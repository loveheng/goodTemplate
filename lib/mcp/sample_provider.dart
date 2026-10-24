library;

/// 示例领域端口（依赖反转接缝样板）：内核与工具面只依赖本抽象，不碰具体实现。
/// 真实 app 照此形状定义自己的端口（如天气/地理），实现落 lib/service/。
///
/// **口径红线（weather.md 判定的反模式）**：失败**不得返回 null 静默降级**——
/// 一律返回不可空信封（成功载荷或带机器码的错误），调用方据此 fail-closed，
/// 不编造数据。缺省实现同样走错误信封（见 [NullSampleProvider]），不假装成功。
abstract class SampleProvider {
  /// 反转文本。空输入/失败一律走错误信封，不吐 null。
  Future<SampleResult> reverse(String text);
}

/// 不可空结果信封：成功带载荷，失败带裸机器码 + 人话说明 + 自愈指引。
class SampleResult {
  const SampleResult.ok(this.value)
      : errorCode = null,
        errorMessage = null,
        suggestion = null;

  const SampleResult.error(this.errorCode, this.errorMessage, {this.suggestion})
      : value = null;

  final String? value;
  final String? errorCode;
  final String? errorMessage;
  final String? suggestion;

  bool get success => errorCode == null;
}

/// 缺省实现：未注入真实实现时 fail-closed 返机器码（不返 null、不编造数据）。
class NullSampleProvider implements SampleProvider {
  const NullSampleProvider();

  @override
  Future<SampleResult> reverse(String text) async => const SampleResult.error(
    'ERR_SAMPLE_NOT_CONFIGURED',
    'SampleProvider 未注入真实实现',
    suggestion: '在 tool_face_assembly.dart 装配处注入真实实现',
  );
}
