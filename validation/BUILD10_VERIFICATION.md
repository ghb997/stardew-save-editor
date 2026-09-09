# 0.4.0（10）原生验证记录

2026-09-09，本次应用代码完成设备 Release 编译和模拟器 Debug 编译；实际执行 79 项测试，79 项通过，0 项失败、0 项跳过。

## 构建与测试证据

| 项目 | 实际结果 |
| --- | --- |
| [设备构建](https://github.com/ghb997/stardew-save-editor/actions/runs/34360459510) | Xcode 16.4、iOS SDK 18.5、Release、iPhoneOS arm64 成功 |
| [原生测试](https://github.com/ghb997/stardew-save-editor/actions/runs/34363052838) | Xcode 16.4（16F6）、Debug、iPhone SE 第 3 代、iOS 26.2，79/79 通过 |
| 存档核心 SaveCoreTests | 32/32 通过 |
| 游戏逻辑 GameLogicRegressionTests | 10/10 通过 |
| 新增功能 ReferenceFeatureTests | 14/14 通过 |
| 追踪指标 TrackerMetricsTests | 7/7 通过 |
| 保存事务 TransactionRegressionTests | 9/9 通过 |
| 界面 TrackerSmokeUITests | 7/7 通过，包含 3 项新增编辑流程 |
| 工程、数据和资源静态检查 | 6/6 通过，57 个 Swift 文件，113 张位图 |

逐项结果从下载的 `tests.log` 中实际完成的 XCTest 记录提取，并核对工程中全部测试名称，未发现漏跑或重复结果。机器可读记录：[build10-native-tests.json](build10-native-tests.json)、[build10-device-build.json](build10-device-build.json)、[build10-static-checks.json](build10-static-checks.json)。完整日志、结果包与附件保存在对应 Actions 运行的产物中。

## 源码与 IPA 对应关系

- 设备包来自提交 `a9c21c5db79380ca1601e785659562845d951292`。
- 完整测试来自提交 `20e4fc24e7e7d9e726e14b2c2d8928303531377b`。
- 两个提交之间只修正测试：八种物品的往返测试预先提供八个合法槽位；编辑器界面测试先按几何位置小幅双向滚动，并在预览关闭后检查结果。首轮测试曾因这三处测试问题失败，修正后完整重跑通过。
- 应用代码、资源、Xcode 工程、`project.yml`、构建脚本和工作流的 Git 对象完全一致，因此该设备包对应通过验证的应用代码。详见 [build10-source-equivalence.json](build10-source-equivalence.json)。后续交付提交只增加文档和验证证据。

设备包：`SheaflightAmberVault-v0.4.0-build10-unsigned.ipa`，3,055,842 字节，最低 iOS 17.0。下载后已复核 ZIP CRC、Info.plist 版本、arm64 / iOS 设备平台、`Assets.car` 及构建记录中的 SHA-256。

SHA-256：`c106178eb5b4d5e6ef0764f805465445f25421d9d20d6a5e03e8c808bfdbb1c2`。

这是未签名设备包，需要签名后安装。

## 新增界面证据

以下均为本次 XCUITest 的原生截图，使用合成演示农场。已逐张检查标出的状态；这些截图不覆盖全部页面、设备和无障碍模式。单独的 16 张 Tracker 截图流程本次未运行。

| 截图 | 核对内容 |
| --- | --- |
| [背包扩容](build10-ui/editor-backpack-expanded.png) | 36 格选中、3/36 容量、物品卡片及待保存状态 |
| [背包搜索输入态](build10-ui/editor-backpack-search.png) | Diamond 搜索词与 36 格容量；键盘展开时结果在当前可视区下方，筛选由测试断言确认：钻石槽存在、其他物品槽隐藏 |
| [好感预览](build10-ui/editor-relationship-batch-preview.png) | 仅阿比盖尔一人，1,750 → 2,000 点，可取消或加入草稿 |
| [好感应用](build10-ui/editor-relationship-applied.png) | 搜索范围为 1/3 人，阿比盖尔 2,000 点、8 心、1 项待保存 |
| [送礼预览](build10-ui/editor-gift-reset-preview.png) | 今日 1 → 0、本周 2 → 0，并说明好感和日期保留 |
| [送礼应用](build10-ui/editor-gift-reset-applied.png) | 今日和本周均为 0 次，好感仍为 1,750，2 项待保存 |

截图与测试名称、原始附件名及 SHA-256 的映射见 [截图清单](build10-ui/manifest.json)。

## 尚未覆盖

本次没有执行真机安装、真实《星露谷物语》存档载入和隔日往返，也未覆盖完整 iPad、动态字体、VoiceOver、各类文件提供器及复杂多人/模组存档。模拟器测试和合成 XML 回归只能证明所覆盖的代码路径。

真机验收时可用独立测试副本，先在编辑器保存，再在游戏中载入并睡到下一天后重新读取。自动备份与双文件事务仍按现有实现工作。
