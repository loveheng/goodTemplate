import 'dart:async';
import 'dart:convert';

import 'jsonrpc.dart';
import 'tool_face.dart';

/// 工具调用事件（内核侧吐；UI 侧经 `lib/ui_ports` 订阅，守 R4）。
///
/// 字段：`name` 工具名、`ts` 毫秒时间戳（epoch）、`elapsedMs` 耗时、`ok` 成功与否。
/// `ok` 由工具面结果的 `isError` **唯一派生**（G4）——不另设判定
/// 口径，避免「内核说成功、客户端说失败」。
///
/// 本类是**类型化对象**而非 MCP 文本信封：UI 消费它不触 R2。
class McpCallEvent {
  const McpCallEvent({
    required this.name,
    required this.ts,
    required this.elapsedMs,
    required this.ok,
  });

  /// 被调用的工具名（领域网关的域工具名）。
  final String name;

  /// 毫秒时间戳（epoch）。
  final int ts;

  /// 耗时（毫秒）。
  final int elapsedMs;

  /// 是否成功（由工具面结果的 `isError` 唯一派生）。
  final bool ok;
}

/// 内嵌 MCP 服务：Streamable HTTP（POST /mcp，application/json 单响应）。
/// v1 不做服务端主动推送：GET/DELETE 返回 405；也不签发会话 id（规范允许 MAY，
/// 无状态更简单，桌面桥与直连客户端都不依赖会话）。
/// 内核纯 Dart：业务依赖经 [McpToolFace] 端口注入，不沾 Repository / 业务模型。
class McpServer {
  McpServer({
    required this.toolFace,
    required this.tokenProvider,
    this.instructionsProvider,
  });

  /// 工具面端口（宿主注入；本 app = tool_face_assembly.dart 装配的领域网关）。
  final McpToolFace toolFace;

  /// 返回当前生效 token；为空表示关闭鉴权。
  final String? Function() tokenProvider;

  /// initialize 返回的 instructions；非空时覆盖内置文案（配置热更入口）。
  final Future<String?> Function()? instructionsProvider;

  /// 对外标识（MCP `serverInfo`）：init-app 起底改名时随本 app 包名同步替换。
  static const String serverName = 'good_template';
  static const String serverVersion = '0.1.0';

  /// 工具调用事件（内核侧吐；UI 侧经 `lib/ui_ports` 订阅，守 R4）。
  ///
  /// 字段：`name` 工具名、`ts` 毫秒时间戳（epoch）、`elapsedMs` 耗时、`ok` 成功与否。
  /// `ok` 由工具面结果的 `isError` **唯一派生**（G4）——不另设
  /// 判定口径，避免「内核说成功、客户端说失败」。
  ///
  /// 本类是**类型化对象**而非 MCP 文本信封：UI 消费它不触 R2。
  final StreamController<McpCallEvent> _callEvents =
      StreamController<McpCallEvent>.broadcast();

  /// 工具调用事件流（广播；内核侧吐事件，UI 侧 `StreamBuilder` 接）。
  ///
  /// 生命周期：随 [close] 释放。
  Stream<McpCallEvent> get onCall => _callEvents.stream;

  void _emitCall(String name, int elapsedMs, {required bool ok}) {
    if (_callEvents.isClosed) return;
    _callEvents.add(
      McpCallEvent(
        name: name,
        ts: DateTime.now().millisecondsSinceEpoch,
        elapsedMs: elapsedMs,
        ok: ok,
      ),
    );
  }

  /// 内置占位 instructions（中性模板文案）：每次 initialize 必读。
  /// 真实 app 经远程配置 `mcpInstructions`（RemoteConfigStore）或注入
  /// [instructionsProvider] 下发领域提示词，整体覆盖本占位。
  static const _builtinInstructions =
      '你是本 app 的领域助手。可用能力以 tools/list 为准，调用前先读各工具的 '
      'description 与参数签名；写操作统一经写门禁派发，越权或未登记的动作会返回'
      '机器码错误（若带 suggestion 字段，按其提示重试）。超出工具面能力的请求，'
      '如实说明不可为，不要虚构结果。';

  /// 内置 instructions 只读出口：MCP 控制层注入用户身份画像时复用此基准文案，
  /// 与其拼接后整体覆盖（instructionsProvider 非空时生效）。
  static String get builtinInstructions => _builtinInstructions;

  /// 传输无关：输入 JSON-RPC 请求体，输出响应体字符串。
  /// 通知（id==null）返回空串，由传输层决定回 202。
  ///
  /// 由 [HttpTransport] 等传输层调用，使内核可脱离 dart:io / Flutter 被嵌入
  /// （内核纯 Dart：HTTP 与 Binder 双通道共用同一份）。
  Future<String> handleJsonRpc(String rawBody) async {
    Object? msg;
    try {
      msg = jsonDecode(rawBody);
    } catch (_) {
      return jsonEncode(_rpcError(null, errParse, 'JSON 解析失败'));
    }
    if (msg is! Map<String, Object?>) {
      return jsonEncode(_rpcError(null, errInvalidRequest, '仅支持单条 JSON-RPC 消息'));
    }
    final method = msg['method'];
    final id = msg['id'];
    if (id == null) return ''; // 通知：无需应答
    if (method is! String) {
      return jsonEncode(_rpcError(id, errInvalidRequest, '缺少 method'));
    }
    try {
      final result = await _dispatch(method, msg['params']);
      return jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result});
    } on McpRpcError catch (e) {
      return jsonEncode({'jsonrpc': '2.0', 'id': id, 'error': e.toMap()});
    } catch (e) {
      return jsonEncode(_rpcError(id, errInternal, '工具执行失败: $e'));
    }
  }

  Future<Object?> _dispatch(String method, Object? params) async {
    switch (method) {
      case 'initialize':
        final p = params is Map<String, Object?> ? params : const {};
        return {
          'protocolVersion': McpProtocol.negotiate(p['protocolVersion']),
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': serverName, 'version': serverVersion},
          'instructions': instructionsProvider == null
              ? _builtinInstructions
              : (await instructionsProvider!() ?? _builtinInstructions),
        };
      case 'ping':
        return <String, Object?>{};
      case 'tools/list':
        return {'tools': toolFace.schemas()};
      case 'tools/call':
        final p = params is Map<String, Object?> ? params : const <String, Object?>{};
        final name = p['name'];
        if (name is! String) throw McpRpcError(errInvalidParams, '缺少 tool name');
        final args = p['arguments'] is Map<String, Object?>
            ? p['arguments'] as Map<String, Object?>
            : <String, Object?>{};
        // 透传工具面产出的完整 result（含 isError）——内核不再硬编码 false，
        // 否则含"错误"字样的失败文本会被客户端当作成功（G4）。
        // 内核**不按工具名做业务特例**：任何业务语义由工具面自行承载。
        final sw = Stopwatch()..start();
        try {
          final result = await toolFace.call(name, args);
          sw.stop();
          _emitCall(name, sw.elapsedMilliseconds,
              ok: result['isError'] != true);
          return result;
        } catch (_) {
          sw.stop();
          _emitCall(name, sw.elapsedMilliseconds, ok: false);
          rethrow;
        }
      case 'resources/list':
        return {'resources': <Map<String, Object?>>[]};
      case 'prompts/list':
        // prompts 先空实现：宿主需要 SOP 流程时随 playbook 内容实装。
        return {'prompts': <Map<String, Object?>>[]};
      default:
        throw McpRpcError(errMethodNotFound, '未知方法: $method');
    }
  }

  Map<String, Object?> _rpcError(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  /// 释放内核持有的资源（调用事件流控制器）。
  ///
  /// **幂等**：重复调用不抛；释放唯一入口 = owner 调本方法。
  void close() {
    if (!_callEvents.isClosed) _callEvents.close();
  }
}
