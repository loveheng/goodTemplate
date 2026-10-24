package com.goodhub.good_template

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 凭证安全存储平台通道：Keystore 持密钥、密文跨 isolate 可见。
        // 生产通道（McpBinderService.initEngine）同款注册——**双引擎纪律**，
        // 漏挂任一侧该引擎内即 MissingPluginException。
        SecretStoreChannel.register(flutterEngine, applicationContext)
    }
}
