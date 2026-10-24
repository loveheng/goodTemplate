library;

/// goodhub 服务端模板 · 最小壳：装配端口 → 工具面装配（单点收口）→ MCP HTTP 起服 → 前台常驻。
///
/// 新 app 起底三步：
/// 1. 写自己的领域网关（参照 lib/tools/sample_tool_face.dart 的 CategoryTool 模式）
///    与领域端口（参照 lib/mcp/sample_provider.dart），在 lib/tool_face_assembly.dart 收口；
/// 2. 需要凭证的键在装配处登记 SecretAwareKv.secretKeys（本壳默认无凭证键）；
/// 3. 通知文案 / SERVER_ID / 应用名等改名点由 `init-app` 一键代做。
///
/// 验收：`node tool/mcp-bridge/e2e-check.mjs`（token 见控制台日志）。
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Binder 后台 entrypoint 纳入编译根（import 闭包）：它不被 UI 引用，若不 import
// 则 kernel_blob 不含该库，headless 引擎 executeDartEntrypoint 报
// Dart_LookupLibrary not found → "Dart entrypoint 超时"（真机实证）。
// ignore: unused_import
import 'mcp_binder_entrypoint.dart';
import 'service/keystore_secret_store.dart';
import 'service/mcp_controller.dart';
import 'service/persistent_kv.dart';
import 'tool_face_assembly.dart';

void main() {
  runApp(const _TemplateApp());
}

class _TemplateApp extends StatelessWidget {
  const _TemplateApp();

  @override
  Widget build(BuildContext context) {
    // 前台服务就绪后由回调装配 MCP 总控（UI 仅承载生命周期，无业务页面）
    return WithForegroundTask(
      child: MaterialApp(
        title: 'good_template',
        theme: ThemeData(useMaterial3: true),
        home: const _BootPage(),
      ),
    );
  }
}

class _BootPage extends StatefulWidget {
  const _BootPage();

  @override
  State<_BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<_BootPage> {
  String _status = '装配中…';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // ① 存储：普通设置持久化 + 凭证分流安全存储（Keystore 持密钥、密文跨 isolate 可见）。
    //    真实 app 在此登记自己的凭证键（secretKeys），未登记键走普通持久化。
    final kv = SecretAwareKv(
      plain: await SharedPrefsKv.open(),
      secrets: const KeystoreSecretStore(),
    );

    // ② MCP 总控：工具面经装配单点收口——与 Binder 生产通道共用同一份（禁双写）。
    final controller = McpController(
      kv: kv,
      toolFaceFactory: () => buildDefaultToolFace(kv: kv),
    );
    await controller.regenerateToken();

    // ③ HTTP 回环起服（前台保活由 enable() 内非阻塞补启）。
    final error = await controller.enable();
    debugPrint('[good_template] MCP endpoint: ${controller.endpoint}');
    debugPrint('[good_template] token: ${controller.token}');
    setState(() {
      _status = error == null
          ? 'MCP 已起服：${controller.endpoint}\ntoken: ${controller.token}'
          : '起服失败: $error';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_status, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
