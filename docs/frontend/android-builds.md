# Android 签名与升级

Android 编译使用 SDK 37、AGP 9.2.1、Gradle 9.4.1 和 Kotlin 2.4.0，与 `receive_sharing_intent` 1.9 的原生构建要求一致。最低系统版本及目标系统版本继续跟随 Flutter SDK。

所有 Android 构建模式（Debug、Profile、Release）使用同一正式签名。Gradle 要求 `frontend/android/app/release.jks` 和 `ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`；缺少任一项直接失败，不再使用默认调试签名。密钥文件不得提交 Git。

GitHub 手动构建 `build.yml` 与标签发布 `release.yml` 共用 `scripts/prepare_android_signing.sh`，从现有四项 Android Secrets 恢复密钥。手动构建可选 `platform=android`，不触发 Web/Linux；可选的 Debug APK 也使用正式签名。

两条工作流以准备签名时距 2020-01-01 UTC 的秒数作为 `versionCode`，替代固定的 `+1` 和各工作流独立计数。Gradle 禁用 Flutter 的 ABI 版本号偏移，同一次构建的各架构和模式使用相同版本号。安装时使用比已安装包更新的构建；本地打包也须通过 `--build-number` 指定更大的版本号。

上传 APK 前，`scripts/verify_android_apks.sh` 验证实际 APK 签名证书与密钥库证书一致、包名为 `com.vaultstream.frontend`、版本号符合本次构建。密钥或签名验证失败时不上传产物。

过去使用临时调试密钥的安装无法直接升级到正式签名包；需要保留所需本地数据后重新安装。正式签名的历史包可按 Android 的签名与版本规则升级。构建验证不等同于真实设备覆盖安装验收。
