# 构建 15 验证记录

版本：0.7.0（15），源码候选。日期：2026-09-12。

## 当前状态

| 检查 | 状态与证据 |
| --- | --- |
| 静态工程、资源与版本检查 | 6 项通过，88 个 Swift 文件、113 张位图、173 个测试方法声明；结果见 `static-release-results.json` |
| Swift 语法扫描 | 88 个文件无语法错误；tree-sitter 0.26.0 / tree-sitter-swift 0.7.3，结果见 `swift-syntax-results.json` |
| 配置和目录数据检查 | project.yml 及 3 个 workflow YAML 解析通过；博物馆候选数据确认为 95 项，见 `build15-supporting-checks.json` |
| Shell 语法检查 | Git Bash 对 3 个 macOS 验证/构建脚本执行 `bash -n` 通过；未运行脚本中的 Xcode 命令 |
| Swift 编译和类型检查 | Xcode 16.4 / SDK 18.5 的 Release 设备构建与 Debug 模拟器构建通过 |
| XCTest / XCUITest | 两种 iPad 各 8 项 UI 已通过；iPhone 完整 173 项正在执行 |
| 原生截图 | iPad mini 与 13 英寸 iPad Pro 共 10 张已审阅；见 build15-ui 下各设备清单 |
| 构建 15 IPA | 已生成并校验，3,699,789 字节，未签名 |
| 签名真机安装与游戏往返 | 未执行 |

静态结果文件由本轮命令重新生成。语法扫描工具不支持 Swift 6 的 `sending` 返回限定词，扫描时保留位置并跳过这两个限定词，在结果中单独披露；不将其作为已通过类型检查的证据。

## 云端构建与当前结果

GitHub 授权已恢复，原生构建与测试对应提交 `cd325fa4e86f456481d2e03cf463fc861ee2937c`。此后的文档/validation 提交不修改应用和测试代码。

- [Release 设备构建通过](https://github.com/ghb997/stardew-save-editor/actions/runs/34686632136)，元数据见 build15-device-build.json。
- [两种 iPad 各 8 项 UI 通过](https://github.com/ghb997/stardew-save-editor/actions/runs/34686632117)，逐项结果见 build15-tests-mini.json 与 build15-tests-large.json。
- [iPhone 完整测试正在执行](https://github.com/ghb997/stardew-save-editor/actions/runs/34686632113)，尚未发布通过结论。
- 最终 IPA SHA-256：`4228234536f0b2d454c794244dd6e87041083c4264eece275d847e6d540bb736`。与三个参考应用的体积差异见 [大小对照](BUILD15_SIZE_COMPARISON.md)。

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
