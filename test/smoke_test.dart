library;

/// 模板冒烟测试：KV 端口 + 凭证分流 + CommandGateway 门禁 + 工具面链路
/// + 装配收口（CategoryTool 示例域 R/W 双档）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/action/command_gateway.dart';
import 'package:good_template/mcp/mcp_server.dart';
import 'package:good_template/mcp/sample_provider.dart';
import 'package:good_template/mcp/tool_face.dart';
import 'package:good_template/ports.dart';
import 'package:good_template/service/in_memory_secret_store.dart';
import 'package:good_template/service/persistent_kv.dart';
import 'package:good_template/tool_face_assembly.dart';

class _PongFace implements McpToolFace {
  @override
  List<Map<String, Object?>> schemas() => const [];

  @override
  Future<Map<String, Object?>> call(String name, Map<String, Object?> args) async => const {
        'content': [
          {'type': 'text', 'text': 'pong'}
        ],
        'isError': false,
      };
}

/// 可断言的假端口实现（单测注入；生产注入真实实现）。
class _EchoReverseProvider implements SampleProvider {
  @override
  Future<SampleResult> reverse(String text) async => SampleResult.ok(text.split('').reversed.join());
}

Map<String, Object?> _decodeContent(Map<String, Object?> result) =>
    jsonDecode((result['content'] as List).first['text'] as String)
        as Map<String, Object?>;

void main() {
  test('InMemoryKv 读回写值', () async {
    final kv = InMemoryKv();
    await kv.settingsSet({'a': '1'});
    expect(await kv.settingsGet('a'), '1');
    expect(await kv.settingsGet('b'), isNull);
  });

  test('SecretAwareKv：凭证键分流安全存储，普通键走 plain；空值写=删除', () async {
    final plain = InMemoryKv();
    final secrets = InMemorySecretStore();
    final kv = SecretAwareKv(
      plain: plain,
      secrets: secrets,
      secretKeys: const ['api_key'],
    );
    await kv.settingsSet({'api_key': 'S3CR3T', 'theme': 'dark'});
    expect(await secrets.read('api_key'), 'S3CR3T');
    expect(await plain.settingsGet('api_key'), isNull, reason: '凭证禁入明文 KV');
    expect(await plain.settingsGet('theme'), 'dark');
    await kv.settingsSet({'api_key': ''});
    expect(await secrets.read('api_key'), isNull, reason: '空值写 = 删除凭证');
  });

  test('CommandGateway：未登记拒绝 / 已登记分发', () async {
    final gw = CommandGateway();
    final unregistered = await gw.dispatch(_Dummy('nope'));
    expect(unregistered.first['text'], contains('未开放'));
    gw.register('ok', (_) async => const [
          {'type': 'text', 'text': 'done'}
        ]);
    final ok = await gw.dispatch(_Dummy('ok'));
    expect(ok.first['text'], 'done');
  });

  test('McpServer.handleJsonRpc：initialize + tools/call 全链路（纯 Dart 内核）', () async {
    final server = McpServer(toolFace: _PongFace(), tokenProvider: () => null);
    final init = await server.handleJsonRpc(jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': '2025-03-26'},
    }));
    final initMap = jsonDecode(init) as Map<String, Object?>;
    expect(initMap['result'], isNotNull);
    final call = await server.handleJsonRpc(jsonEncode({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/call',
      'params': {'name': 'ping', 'arguments': {}},
    }));
    expect(jsonDecode(call)['result'], isNotNull);
  });

  test('装配收口：单一 sample 工具 + private 可见性 + action 枚举', () async {
    final face = buildDefaultToolFace(kv: InMemoryKv());
    final schemas = face.schemas();
    expect(schemas, hasLength(1));
    expect(schemas.first['name'], 'sample');
    final meta = (schemas.first['_meta'] as Map)['goodhub'] as Map;
    expect(meta['visibility'], 'private', reason: 'default-deny：漏标即最严');
    final actionEnum =
        ((((schemas.first['inputSchema'] as Map)['properties'] as Map)['action'] as Map)['enum'])
            as List;
    expect(actionEnum, containsAll(['sample_ping', 'sample_note_put']));
  });

  test('sample_ping（R 档）：端口注入反转 + 缺参带前缀错误 + 未注入 fail-closed', () async {
    final face = buildDefaultToolFace(
      kv: InMemoryKv(),
      provider: _EchoReverseProvider(),
    );
    final ok = await face.call('sample', {
      'action': 'sample_ping',
      'params': {'text': 'abc'},
    });
    expect(ok['isError'], false);
    expect(_decodeContent(ok)['reversed'], 'cba');

    final missing = await face.call('sample', {
      'action': 'sample_ping',
      'params': <String, Object?>{},
    });
    expect(missing['isError'], true);
    expect((missing['content'] as List).first['text'],
        contains('[sample.sample_ping: MISSING_ARGUMENT]'));

    // 未注入真实 provider（装配缺省 NullSampleProvider）→ 结构化错误带 suggestion。
    final bare = buildDefaultToolFace(kv: InMemoryKv());
    final nullish = await bare.call('sample', {
      'action': 'sample_ping',
      'params': {'text': 'x'},
    });
    expect(nullish['isError'], true);
    final err = _decodeContent(nullish)['error'] as Map;
    expect(err['code'], 'sample.sample_ping: ERR_SAMPLE_NOT_CONFIGURED');
    expect(err['suggestion'], isNotNull, reason: '自愈字段保真（G5）');
  });

  test('sample_note_put（W 档）：经网关派发落 KV + 缺参前置校验 + 未知 action', () async {
    final kv = InMemoryKv();
    final face = buildDefaultToolFace(kv: kv);
    final ok = await face.call('sample', {
      'action': 'sample_note_put',
      'params': {'key': 'k1', 'value': 'v1'},
    });
    expect(ok['isError'], false, reason: 'Actor 成功信封派生 isError=false（G6）');
    expect(_decodeContent(ok)['success'], true);
    expect(await kv.settingsGet('sample_note_k1'), 'v1');

    final missing = await face.call('sample', {
      'action': 'sample_note_put',
      'params': {'key': ''},
    });
    expect(missing['isError'], true);
    expect((missing['content'] as List).first['text'],
        contains('sample.sample_note_put: MISSING_ARGUMENT'));

    final unknown = await face.call('sample', {
      'action': 'nope',
      'params': <String, Object?>{},
    });
    expect(unknown['isError'], true);
    expect((unknown['content'] as List).first['text'], contains('sample.nope: UNKNOWN_ACTION'));
  });
}

class _Dummy extends Command {
  const _Dummy(String name) : super(name, const {});
}
