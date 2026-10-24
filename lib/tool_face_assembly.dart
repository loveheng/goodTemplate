// 工具面装配收口：把本 app 各领域网关收口为 1 个 [McpToolFace]，供**两条通道共用同一份装配**
// ——HTTP 调试通道（main.dart → McpController.toolFaceFactory）与
// Binder 生产通道（mcp_binder_entrypoint.dart → McpServer.toolFace）。
// 新增能力只改本文件，禁两通道各自装配（防「HTTP 一套工具、Binder 另一套」双写漂移）。
//
// 配置与端口一律**懒读 / 可注入**：装配面是同步的，而设置读取是异步的——推到请求
// 发生时读，顺带让用户补填配置后无需重建工具面即生效。
library;

import 'action/command_gateway.dart';
import 'mcp/category_tool_face.dart';
import 'mcp/sample_provider.dart';
import 'mcp/settings_kv.dart';
import 'mcp/tool_face.dart';
import 'tools/sample_tool_face.dart';

/// 装配本 app 的 MCP 工具面。
///
/// [kv] 供各后端配置懒读；[gateway] 为写门禁端口（缺省新建；调用方也可传入既有
/// 实例复用——main 侧 UI 与 Agent 共用同一网关时，用户侧命令走 registerUser，
/// 与 AI 侧注册表物理分离）；[provider] 等端口桩可注入（单测），缺省走各端口
/// 的 fail-closed 缺省实现。
McpToolFace buildDefaultToolFace({
  required SettingsKv kv,
  CommandGateway? gateway,
  SampleProvider? provider,
}) {
  final gw = gateway ?? CommandGateway();
  // W 档执行体（Actor）登记：唯一写入口。真实 app 的敏感设置/用户数据写走
  // registerUser 用户侧注册表（AI 不可触达）；AI 可达写走本登记面。
  registerSampleNoteActor(gw, kv: kv);
  return CategoryToolFace(<CategoryTool>[
    buildSampleTool(gateway: gw, provider: provider),
    // 新增领域：buildXxxTool(gateway: gw, ...) → 一并加入本列表（只改本文件）。
  ]);
}
