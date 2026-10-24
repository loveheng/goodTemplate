library;

/// 组件基座冒烟：BlockCanvas 底座 + 通用组件。
///
/// **模板不带主题骨架**：组件经主题扩展取 token（`tokensOf`），宿主在自建主题里
/// 注册自己的 `AppTokens` 实例——视觉值归宿主，页面设计不受模板约束。
/// 本测试即「宿主注册」的最小示范。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_template/ui/components/app_components.dart';
import 'package:good_template/ui/components/block_canvas.dart';
import 'package:good_template/ui/components/bracket_pair_formatter.dart';
import 'package:good_template/ports.dart';
import 'package:good_template/service/mcp_controller.dart';
import 'package:good_template/tool_face_assembly.dart';
import 'package:good_template/ui/mcp_service_page.dart';
import 'package:good_template/ui/components/readiness_components.dart';
import 'package:good_template/ui/tokens/app_tokens.dart';
import 'package:good_template/ui_ports/readiness.dart';

ThemeData _hostTheme() => ThemeData(
      useMaterial3: true,
      extensions: <ThemeExtension<dynamic>>[AppTokens.of(Brightness.dark)],
    );

Widget _host(Widget child, {bool scroll = true}) => MaterialApp(
      theme: _hostTheme(),
      home: Scaffold(
        body: scroll ? SingleChildScrollView(child: child) : child,
      ),
    );

void main() {
  testWidgets('AppTokens：宿主注册后组件经 tokensOf 可达（视觉值归属宿主）', (tester) async {
    late AppTokens tokens;
    await tester.pumpWidget(_host(Builder(
      builder: (context) {
        tokens = tokensOf(context);
        return const SizedBox.shrink();
      },
    )));
    expect(tokens.palette.hairline, isNotNull);
    expect(tokens.typeScale.body, isNotNull);
  });

  testWidgets('SectionCard / TelemetryText / ErrorLine / EmptyState 渲染', (tester) async {
    await tester.pumpWidget(_host(Column(
      children: const [
        SectionCard(title: 'T', child: Text('body')),
        TelemetryText('127.0.0.1:8765'),
        ErrorLine(code: 'E_X', message: '失败', suggestion: '重试'),
        EmptyState(message: '暂无数据'),
      ],
    )));
    expect(find.text('T'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
    expect(find.text('127.0.0.1:8765'), findsOneWidget);
    expect(find.text('E_X：失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('暂无数据'), findsOneWidget);
  });

  testWidgets('GuidanceCard：动作回调可达', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(GuidanceCard(
      message: '缺 Key',
      actionLabel: '去配置',
      onAction: () => tapped = true,
    )));
    await tester.tap(find.text('去配置'));
    expect(tapped, isTrue);
  });

  testWidgets('BlockCanvas 底座：受控块输入回调（文本单源在宿主）', (tester) async {
    final controller = TextEditingController();
    String? changed;
    await tester.pumpWidget(_host(
      BlockCanvas(
        blockCount: 1,
        controllerAt: (i) => controller,
        outputBuilder: (context, i, sunk) => null,
        onInputChanged: (i, text) => changed = text,
        onBlockRemove: (i) {},
        onPasteFission: (i, lines) {},
      ),
      scroll: false,
    ));
    expect(find.byType(TextField), findsAtLeastNWidgets(1));
    await tester.enterText(find.byType(TextField).first, 'hi');
    await tester.pump();
    expect(changed, 'hi', reason: '输入经 onInputChanged 上报宿主（受控单源）');
  });

  test('applyBracketPair 三件套（纯函数 headless）：补全 / 跳过 / 配对删除', () {
    // 补全：输入 ( → 成对插入 ()，光标落括号对中间
    final insert = applyBracketPair(
      const TextEditingValue(text: '1+2', selection: TextSelection.collapsed(offset: 3)),
      const TextEditingValue(text: '1+2(', selection: TextSelection.collapsed(offset: 4)),
    );
    expect(insert.text, '1+2()');
    expect(insert.selection.baseOffset, 4);
    // 跳过：光标前恰是 ) 再输入 ) → 只右移不重复
    final skip = applyBracketPair(
      const TextEditingValue(text: '1+2()', selection: TextSelection.collapsed(offset: 4)),
      const TextEditingValue(text: '1+2())', selection: TextSelection.collapsed(offset: 5)),
    );
    expect(skip.text, '1+2()');
    expect(skip.selection.baseOffset, 5);
    // 配对删除：删完整 () 的 ( → 连 ) 一起删，光标留删除点
    final del = applyBracketPair(
      const TextEditingValue(text: 'f()', selection: TextSelection.collapsed(offset: 2)),
      const TextEditingValue(text: 'f(', selection: TextSelection.collapsed(offset: 1)),
    );
    expect(del.text, 'f');
    expect(del.selection.baseOffset, 1);
  });

  testWidgets('ReadinessPill：状态点 + 双通道文字（missing → 未就绪）', (tester) async {
    await tester.pumpWidget(_host(ReadinessPill(
      item: const ReadinessItem(label: '定位', state: ReadinessState.missing),
    )));
    expect(find.text('定位'), findsOneWidget);
    expect(find.text('未就绪'), findsOneWidget);
    expect(find.byType(StatusDot), findsOneWidget);
  });

  testWidgets('McpServicePage：内核配套调试页（服务开关/令牌/直连指引）', (tester) async {
    final controller = McpController(
      kv: InMemoryKv(),
      toolFaceFactory: () => buildDefaultToolFace(kv: InMemoryKv()),
    );
    await tester.pumpWidget(_host(McpServicePage(controller: controller), scroll: false));
    expect(find.text('MCP 调试服务'), findsOneWidget);
    expect(find.text('已停止'), findsOneWidget, reason: '调试服务不随启动自启');
    expect(find.text('端口 8765'), findsOneWidget);
    expect(find.text('http://127.0.0.1:8765/mcp'), findsNWidgets(2),
        reason: '状态遥测 + 直连指引同 endpoint');
    expect(find.text('启动'), findsOneWidget);
    await tester.tap(find.text('重生成令牌'));
    await tester.pump();
    expect(find.text('MCP 调试服务'), findsOneWidget, reason: '重生成令牌后页面稳定渲染');
  });
}
