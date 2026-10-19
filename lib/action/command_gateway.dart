library;

/// 唯一写入口空框架（模式提取自 shiguang lib/action/command_handler.dart，
/// 模式照抄拾贝 item_action_handler）。
///
/// 红线语义（新 app 照此执行）：一切 AI 写操作必经 [CommandGateway]，禁绕过直写存储。
/// 三层门：
/// 1. 白名单：只有 [Command] 子类登记过的命令才能进来（未登记 = errPermission）；
/// 2. propose 校验：`propose_*` 前缀命令携带提案载荷，[validatePropose] 机械校验，
///    校验失败原样拒绝（AI 不得改写用户意图）；
/// 3. 越权门：[forbiddenKeys] 列出的键 AI 无权写入，命中即拒（提示引导用户自设）。
///
/// 新 app 用法：定义自己的 sealed 命令族（继承 [Command]），在 [register] 登记
/// Actor，工具面（McpToolFace.call）统一转发到这里。
import 'dart:async';

/// 写命令基类：name 为工具面同名命令；payload 为参数。
abstract class Command {
  const Command(this.name, this.payload);
  final String name;
  final Map<String, Object?> payload;
}

/// 命令执行器：拿到命令返回 MCP content 形状（Map 列表）。
typedef CommandActor = Future<List<Map<String, Object?>>> Function(Command cmd);

class CommandGateway {
  final Map<String, CommandActor> _actors = {};

  /// AI 无权写入的键（越权门）：新 app 按自己的权限边界登记。
  Set<String> forbiddenKeys = {};

  /// 登记命令 → 执行器（App 侧装配时调用；AI 不可经工具面注册）。
  void register(String name, CommandActor actor) => _actors[name] = actor;

  /// AI 是否可执行该命令（白名单 + 越权门）。
  bool admits(String name, Map<String, Object?> args) {
    if (!_actors.containsKey(name)) return false;
    final keys = args.keys.toSet();
    return keys.intersection(forbiddenKeys).isEmpty;
  }

  /// 唯一写入口：未登记 / 越权一律拒；通过则分发。
  Future<List<Map<String, Object?>>> dispatch(Command cmd) async {
    final actor = _actors[cmd.name];
    if (actor == null) {
      return [
        {'type': 'text', 'text': '错误：命令 ${cmd.name} 未开放给 AI'}
      ];
    }
    if (!admits(cmd.name, cmd.payload)) {
      return [
        {'type': 'text', 'text': '错误：${cmd.name} 命中越权键，请建议用户在 app 内自行修改'}
      ];
    }
    return actor(cmd);
  }

  /// propose 机械校验钩子：新 app 覆写以实现「提案先验，不合格整单拒」。
  Future<String?> validatePropose(Command cmd) async => null;
}
