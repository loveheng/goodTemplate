library;

/// 示例领域网关（CategoryTool 聚合模式——真实 app 工具面的主形态）：
/// 把 N 个细粒度子操作聚合为 1 个 MCP 工具 `sample`（action 枚举派发）。
///
/// 两个子操作各示范一条纪律：
/// - `sample_ping`（R 档）：经 [SampleProvider] 端口执行——依赖反转 + 不可空信封；
/// - `sample_note_put`（W 档）：只 [SubAction.buildCommand] 构造命令，**派发归网关层**
///   （G3：子操作禁止自行 dispatch/鉴权）；执行体 Actor 在 tool_face_assembly.dart
///   登记进 CommandGateway（唯一写入口）。
///
/// 机械约束正文 = README「领域网关纪律（G1–G6）」。
import 'dart:convert';

import '../action/command_gateway.dart';
import '../mcp/category_tool_face.dart';
import '../mcp/sample_provider.dart';
import '../mcp/settings_kv.dart';

/// 公开入口：构建 `sample` 领域网关。[gateway] 缺省 null ⇒ W 档物理不可达（fail-closed）。
CategoryTool buildSampleTool({CommandGateway? gateway, SampleProvider? provider}) {
  final cat = CategoryTool(
    'sample',
    '模板示例域（探活 / 备忘写入演示；真实 app 按此模式写自己的领域网关）',
    gateway,
    // visibility 缺省 private（default-deny，漏标即最严）；需要宿主共享时显式
    // 传 ToolVisibility.shared（经 toSchema 下发 _meta.goodhub.visibility）。
  );
  cat.register(_SamplePingSub(provider ?? const NullSampleProvider()));
  cat.register(_SampleNotePutSub());
  return cat;
}

/// 双轨出参：把业务载荷包成单条 text content（JSON），Agent 可直接解析复用。
SubActionResult _jsonSuccess(Map<String, Object?> payload) => SubActionResult.success([
      {'type': 'text', 'text': jsonEncode(payload)}
    ]);

/// R 档：探活 + 端口调用演示。
class _SamplePingSub extends SubAction {
  _SamplePingSub(this._provider);

  final SampleProvider _provider;

  @override
  String get name => 'sample_ping';

  @override
  String get description =>
      '探活并演示端口调用：text 反转回显；未注入真实实现时返 ERR_SAMPLE_NOT_CONFIGURED';

  @override
  String get paramSignature => 'sample_ping(text: string) [必填: text]';

  @override
  Future<SubActionResult> execute(Map<String, Object?> params) async {
    final text = params['text'];
    if (text is! String || text.isEmpty) {
      return SubActionResult.error('MISSING_ARGUMENT', 'sample_ping 需要非空 text');
    }
    final result = await _provider.reverse(text);
    if (!result.success) {
      // 端口错误信封 → 结构化错误（保留 suggestion 自愈字段，G5）。
      return SubActionResult.structuredError(
        result.errorCode!,
        result.errorMessage!,
        <String, Object?>{
          'code': result.errorCode,
          'message': result.errorMessage,
          if (result.suggestion != null) 'suggestion': result.suggestion,
        },
      );
    }
    return _jsonSuccess(<String, Object?>{'success': true, 'reversed': result.value});
  }
}

/// W 档：备忘写入演示——只构造命令，派发/鉴权归网关层（G3）。
class _SampleNotePutSub extends SubAction {
  @override
  String get name => 'sample_note_put';

  @override
  String get description => '写一条备忘（演示唯一写入口：W 档只 buildCommand，网关统一派发）';

  @override
  String get paramSignature =>
      'sample_note_put(key: string, value: string) [必填: key, value]';

  @override
  bool get isWrite => true;

  @override
  SubActionResult? validate(Map<String, Object?> params) {
    final key = params['key'];
    final value = params['value'];
    if (key is! String || key.isEmpty || value is! String) {
      return SubActionResult.error(
          'MISSING_ARGUMENT', 'sample_note_put 需要非空 key 与 string value');
    }
    return null;
  }

  // W 档子操作无 R 执行体：网关对 isWrite=true 只走 validate→buildCommand→派发（G3）。
  @override
  Future<SubActionResult> execute(Map<String, Object?> params) =>
      throw UnsupportedError('W 档子操作无执行体（写路径只经 buildCommand）');

  @override
  Command buildCommand(Map<String, Object?> params) => SampleNotePutCommand(params);
}

/// 示例写命令（**命令名 = action 名**，供网关按名查找 Actor）。
class SampleNotePutCommand extends Command {
  const SampleNotePutCommand(Map<String, Object?> payload)
      : super('sample_note_put', payload);
}

/// W 档执行体（Actor）：由 tool_face_assembly.dart 登记进 CommandGateway。
/// 输出统一 `{'success': …}` JSON 信封——isError 由 [SubActionResult.fromActor] 派生（G6），
/// 业务失败对客户端可见而非只藏在文本里。
Future<List<Map<String, Object?>>> sampleNotePutActor(
  Command cmd, {
  required SettingsKv kv,
}) async {
  final key = cmd.payload['key'];
  final value = cmd.payload['value'];
  if (key is! String || key.isEmpty || value is! String) {
    return <Map<String, Object?>>[
      {
        'type': 'text',
        'text': jsonEncode(<String, Object?>{
          'success': false,
          'error': <String, Object?>{
            'code': 'MISSING_ARGUMENT',
            'message': '需要非空 key 与 string value',
          },
        }),
      }
    ];
  }
  await kv.settingsSet(<String, String>{'sample_note_$key': value});
  return <Map<String, Object?>>[
    {
      'type': 'text',
      'text': jsonEncode(<String, Object?>{
        'success': true,
        'key': key,
        'stored': true,
      }),
    }
  ];
}

/// Actor 登记（装配层调用；命令名与 action 名一致）。
void registerSampleNoteActor(CommandGateway gateway, {required SettingsKv kv}) {
  gateway.register(
    'sample_note_put',
    (cmd) => sampleNotePutActor(cmd, kv: kv),
  );
}
