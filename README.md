# WyGram 1.0.0

WyGram 的 iOS 客户端构建仓库。基于 [Swiftgram/Telegram-iOS](https://github.com/Swiftgram/Telegram-iOS) 的固定提交 `cf8b23beaaac4126a396337ac2d5be13f9f76b66`，构建时应用本仓库的源码补丁。

在仓库 Settings → Secrets and variables → Actions 添加 `TG_API_ID` 和 `TG_API_HASH`，然后在 Actions → Build WyGram IPA → Run workflow 启动。API 信息仅从 Secrets 写入临时构建配置，不应提交到源码。

成功后在该次运行的 Artifacts 下载 `WyGram-1.0.0-unsigned`，里面包含 IPA 和 SHA-256 校验值。IPA 使用 arm64 真机架构，安装前需要自行签名。仓库使用标准 macOS 26 runner 与 Xcode 26.2，不自动发布 Release。

本地 Pro 功能免费可用，沿用上游图标。已移除启动时的订阅状态查询并增加相关请求超时；后台恢复后持续加载的问题仍需真机测试确认。Telegram 服务端会员功能不受客户端修改影响。
