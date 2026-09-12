# 构建 15 验证记录

版本：0.7.0（15），源码候选。日期：2026-09-12。

## 当前状态

| 检查 | 状态与证据 |
| --- | --- |
| 静态工程、资源与版本检查 | 6 项通过，88 个 Swift 文件、113 张位图、173 个测试方法声明；结果见 `static-release-results.json` |
| Swift 语法扫描 | 88 个文件无语法错误；tree-sitter 0.26.0 / tree-sitter-swift 0.7.3，结果见 `swift-syntax-results.json` |
| 配置和目录数据检查 | project.yml 及 3 个 workflow YAML 解析通过；博物馆候选数据确认为 95 项，见 `build15-supporting-checks.json` |
| Shell 语法检查 | Git Bash 对 3 个 macOS 验证/构建脚本执行 `bash -n` 通过；未运行脚本中的 Xcode 命令 |
| Swift 编译和类型检查 | 未执行；本机 Windows 没有 Xcode，`xcrun` 不可用 |
| XCTest / XCUITest | 未执行；新增 31 个单元方法、4 个 UI 方法仅为待运行用例 |
| 构建 15 IPA | 未生成 |
| 签名真机安装与游戏往返 | 未执行 |

静态结果文件由本轮命令重新生成。语法扫描工具不支持 Swift 6 的 `sending` 返回限定词，扫描时保留位置并跳过这两个限定词，在结果中单独披露；不将其作为已通过类型检查的证据。

## 云端构建阻挡

既有工程通过 GitHub Actions 的 macOS runner 构建。当前 `gh api user --jq .login` 返回 HTTP 401，Codex GitHub 连接器也处于未登录状态，因此本轮尚未推送或运行云端任务。恢复 GitHub 登录后，需要在当前修复分支运行完整测试与构建；旧版通过记录不能替代这一步。

## 可重复验证

```text
python3 scripts/verify_release.py
python3 scripts/check_swift_syntax.py
```

以下步骤需要 macOS / Xcode 16.x：

```sh
bash scripts/validate-on-macos.sh
LAYOUT_DEVICE=mini LAYOUT_SCOPE=repair bash scripts/validate-layout-on-macos.sh
LAYOUT_DEVICE=large LAYOUT_SCOPE=repair bash scripts/validate-layout-on-macos.sh
bash scripts/build-unsigned-ipa.sh
```

本分支的 push 会触发现有 device build、完整 iPhone suite、两种 iPad 尺寸的 repair/expanded UI suite。构建成功后仍需审阅 xcresult、原生截图和包内版本/架构，并保存新 IPA 的 SHA-256。游戏验收还需使用真实 1.6 存档，在游戏关闭时编辑，载入检查并睡觉保存，再次加载确认字段保留。

## 历史记录

构建 14 的设备构建和测试数字保留在 `BUILD14_VERIFICATION.md`；其他旧版本报告同样只适用于各自版本。本文件未复用任何旧 IPA 作为新构建产物。
