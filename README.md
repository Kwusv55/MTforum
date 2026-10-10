# MT论坛 Flutter 客户端

MT管理器论坛 (bbs.binmt.cc) 第三方客户端，基于 Flutter + Material Design 3。

原开发者已停更，本仓库为接手后的维护版本。

## 快速开始

```bash
flutter pub get
flutter run
```

## 编译 APK

```bash
flutter build apk --release
```

> Release 签名读取仓库根目录的 `key.properties`。该文件**不应提交到仓库**。
> 构建环境没有正式 keystore 时，`android/app/build.gradle.kts` 会回落到
> debug 签名并打印警告，构建不会失败——但这种包只能用于本地验证，
> **不能用于正式发布**。

## 发布新版本

1. 改 `pubspec.yaml` 的 `version:`（如 `2.48.0+174`）；
2. 在 `CHANGELOG.md` 里写一节对应版本的更新内容；
3. 构建 APK（或推送 `v*` tag，由 GitHub Actions 构建并上传到 Release）。

CI 的正式签名来自仓库 Secrets（`ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` /
`ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`），密钥文件不入库。

> 应用内自动检查更新已移除，新版本通过仓库 Release 分发。

## 外观

- **液态玻璃**：顶栏、悬浮底栏、评论区弹层与输入栏使用背景模糊 + 饱和度增强 +
  边缘高光的玻璃材质（`lib/core/widgets/liquid_glass.dart`），可在
  设置 → 外观 中关闭。
- **背景壁纸**：设置 → 外观 → 背景壁纸，可选内置渐变壁纸或从相册导入图片，
  并调节遮罩强度保证文字可读（`lib/core/theme/wallpapers.dart`）。

## 文档

- [开发进度](开发进度.md) - 功能清单、已知问题、代码结构
- [接口文档](binmt_api_doc.md) - 34个论坛API接口完整说明

## 技术栈

- Flutter 3.27.0 + Dart 3.6.0
- Material Design 3（`lib/core/theme/`，中性灰 + 单一低饱和强调色，自动深浅色）
- Dio (HTTP) + CookieJar（核心登录态 / 防护 Cookie 分流）
- html (HTML解析)
- photo_view (图片缩放)
- cached_network_image (图片缓存)
- Android 原生不可见 WebView（无感人机验证）

## 目录结构

```
lib/
  core/            主题 token、网络层、无感验证、工具、通用组件
    theme/         ColorScheme / Typography / Spacing / Radius / Motion
    network/       HttpClient 工厂、Cookie 管理
      waf/         拦截页识别、验证守门器、不可见 WebView 桥、重放拦截器
  features/<域>/   auth forum thread messages profile social mall
    data/          该域的网络调用（api_service 的 part）
    models/        该域的模型（models.dart 的 part）
    widgets/       该域的页面部件
  data/parsers/    HTML 解析器（forum_parser / user_center_parser 的 part）
  pages/           页面入口（部分为兼容转发）
  services/        ApiService 门面 + 业务服务
```
