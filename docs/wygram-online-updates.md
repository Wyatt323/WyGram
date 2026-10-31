# WyGram 在线更新

更新来源固定为 [Wyatt323/WyGram Releases](https://github.com/Wyatt323/WyGram/releases)。入口位于应用“设置 → WyGram 在线更新”，也可从“设置 → WyGram”进入。

## 使用流程

1. 首次加入更新功能的版本需要手动签名、覆盖安装一次。当前已经交付的 1.0.11 没有此入口，不能自行获取加入入口的新版本。
2. 在更新页导入签名当前安装版所用的同一份 P12/PFX 证书、密码和描述文件。文件在手机的系统“文件”选择器中导入，密码在手机本地输入。无需发送到聊天或 GitHub。
3. 检查更新、查看说明，下载并签名，再确认系统安装。系统完整接收更新包后回到主屏幕，等待安装完成并重新打开 WyGram 核对版本。打开安装链接仅代表请求已提交，不代表安装成功。
4. 正常覆盖更新保留安装版的 Bundle ID、App Group、钥匙串组、URL Scheme 和显示名称；不退出账号，不清除聊天数据库或本机消息/照片记录。证书或描述文件不符合当前身份时应报错，不能通过更换身份绕过。

自动检查默认开启，跨重启保留最近检查时间，每六小时最多检查一次；手动检查不受此间隔限制。自动下载并签名默认关闭；开启后，在新版提醒中确认更新即可下载，应用回到前台时继续签名，安装仍需确认。下载可由系统后台会话继续，签名包和通过校验的下载在应用重启后可复用。界面显示百分比和已下载字节；本次没有增加灵动岛/锁屏 Live Activity 控件。

## 签名材料和安装服务

证书、密码和描述文件使用独立的本机 Keychain 服务，`AfterFirstUnlockThisDeviceOnly`，不加入账号设置备份或 iCloud 钥匙串。导入时核对证书、有效期、当前主应用及扩展的实际签名和权限；签名前和安装前再次核验。支持一份允许通配标识的描述文件覆盖多个组件，但不能伪造描述文件没有授予的能力。

GitHub 只保存公开参考 IPA。下载时校验资产大小和 GitHub 返回的 SHA-256，限制正式版本、固定仓库和文件路径、可信 HTTPS 重定向及最大大小。签名使用安装版的身份和权限，主应用及扩展均重新签名。

签名包只通过 `127.0.0.1` 的随机路径交给本机系统安装器。LCSign 的 HTTPS 节点接收 Bundle ID、构建号、标题和本机回环 URL，用于生成安装清单；P12、密码、描述文件和 IPA 不上传至节点。下载/签名、生成清单、系统开始读取、系统完整接收和最终安装是不同状态；失败可保留已验证的缓存重试。

## 构建和发布

首个包含更新入口的版本为 **1.0.12 (19)**。后续打包同步主应用、全部扩展、版本文件、文件名、报告及说明，保留旧 IPA。

本机正常构建生成的 unsigned IPA 继续供手动 LCSign 使用；在线更新另生成带有 ad-hoc 签名结构的公开参考包，不能把旧 IPA 原地改写。准备与发布脚本：`scripts/wygram_release.py`。

```sh
python3 scripts/wygram_release.py prepare \
  --ipa /absolute/path/to/unsigned.ipa \
  --output /absolute/path/to/new-release-directory \
  --notes /absolute/path/to/release-notes.md \
  --source-commit FULL_COMMIT_SHA

python3 scripts/wygram_release.py publish /absolute/path/to/new-release-directory
```

`prepare` 检查标识及版本一致性，移除描述文件，给主应用、扩展和框架保留 ad-hoc 签名结构，验证后原子生成独立发布目录。包含 `WyGram <version>.ipa`（GitHub 会把空格改成点，附件显示标签保持原名）、SHA256SUMS、源码补丁和构建基线、说明及元数据；拒绝覆盖已准备的目录，检查源码中误入的本机 API 凭据和签名材料。

`publish` 的目标固定为 `Wyatt323/WyGram`，使用本机 GitHub 安全凭据或 `GH_TOKEN` / `GITHUB_TOKEN` 环境变量。令牌需要该仓库的 Contents 写入权限，不应写进源码、构建报告或聊天。先将完整源码提交到目标仓库，再以 `--source-commit` 指定确切修订。不要向 Swiftgram 上游仓库推送。

发布先建草稿，上传 IPA、源码补丁和校验文件，确认 GitHub 的资产摘要与本机一致后再公开并标为最新。任何上传/校验失败均不公开草稿；已存在的正式 tag 不覆盖。标签格式为 `v<version>-b<build>`，客户端会核对标签、IPA 名称、版本、构建、下载路径和摘要。

## 验证边界与来源

逻辑测试使用虚构 Release、临时缓存、本机回环服务和虚构签名材料；页面测试使用实际 SGSettingsUI/Window1 与模拟网络响应。必须在首次打包后，用用户实际证书覆盖安装并验证“下一版 → 下载 → 本地签名 → 系统安装 → 数据保留”。此前的组件测试不代表此真机流程已完成。

更新与签名模块参考并适配自 [RegramDev/Regram-ios](https://github.com/RegramDev/Regram-ios)，研究树修订 `acb65027922c1f76818309b21ae1996754a29a94`。保留代码来源、zsign MIT 和 OpenSSL 许可，后两者加入主应用资源。签名器使用独立命名空间的 OpenSSL，避免污染 Telegram 的 BoringSSL；新增 arm64 模拟器编译支持。应用设置入口、UIKit 页面、账号解锁后提醒、发布工具和 WyGram 固定来源配置是本项目接入部分。
