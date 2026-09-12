# 0.6.0（build 14）原生验证记录

2026-09-12，设备 Release 构建成功，完整 iPhone 回归与两种尺寸 iPad 的新增流程验证全部通过。iPhone 实际执行 138 项，两个 iPad 各执行 4 项，合计 146 次执行通过；没有失败、跳过、漏跑或重复记录。

## 原生构建与测试

| 项目 | 实际结果 |
| --- | --- |
| [设备 Release 构建](https://github.com/ghb997/stardew-save-editor/actions/runs/34675547635) | Xcode 16.4、iOS SDK 18.5、iPhoneOS arm64，通过 |
| [完整 iPhone 回归](https://github.com/ghb997/stardew-save-editor/actions/runs/34675123238) | iPhone SE 第 3 代、iOS 26.2，138/138 通过：117 项单元测试、21 项 UI 测试 |
| [iPad mini (A17 Pro)](https://github.com/ghb997/stardew-save-editor/actions/runs/34675557231) | iOS 26.2，新增 4/4 条 UI 流程通过 |
| [iPad Pro 13-inch (M5)](https://github.com/ghb997/stardew-save-editor/actions/runs/34675557231) | iOS 26.2，新增 4/4 条 UI 流程通过 |
| 静态工程、数据与资源检查 | 6/6 通过，78 个 Swift 文件、113 张位图 |

测试结果由 `tests.log` 中实际完成的 XCTest 记录提取，并与该轮 Git 提交里的测试声明核对。构建成功、静态检查通过和测试通过分别记录。

| iPhone 完整回归分组 | 通过数 |
| --- | ---: |
| ExpandedEditorTests：新增四工具存档回归 | 23 |
| SaveCoreTests：存档核心、后台读取和大存档回归 | 36 |
| GameLogicRegressionTests：游戏逻辑 | 10 |
| ReferenceFeatureTests：背包与关系 | 14 |
| TrackerMetricsTests：追踪指标 | 7 |
| TransactionRegressionTests：备份与保存事务 | 9 |
| WorldEditorTests：地图、外观颜色和房间 | 18 |
| AdaptiveLayoutUITests：导入、横竖屏、窄窗口与字体流程 | 7 |
| TrackerSmokeUITests：已有追踪与编辑 UI 流程 | 10 |
| ExpandedEditorUITests：新增四工具 UI 流程 | 4 |

机器可读证据：[完整测试](build14-native-tests.json)、[iPad mini](build14-ipad-mini-tests.json)、[iPad Pro](build14-ipad-large-tests.json)、[设备包](build14-device-build.json)、[静态检查](build14-static-checks.json)、[Swift 语法扫描](build14-swift-syntax.json)、[源码对应关系](build14-source-equivalence.json)。

本轮大存档回归使用 8,163,552 字节合成数据，记录后台读取与解析总计约 1.10 秒；这不是已签名真机或用户点击到页面可操作的端到端耗时，也不能与其他 runner 上的历史单次计时直接作性能比较。

## 覆盖范围

本轮新增 23 项存档回归，覆盖世界地点和建筑室内的容器发现、36/70 格容量、槽位写入、共享/特殊/未知物品只读边界、未知 XML 与未编辑数值写法保留；山谷天气别名同步、名称/整数编码、重复与冲突字段保留、运气范围和姜岛限制；机器计时与就绪状态、产物身份/数量/品质/额外字段保留；普通/混合收集包定义与进度配对、缺失/重复记录排除、材料补给、空位不足时整次取消、Joja 路线限制；逐项撤销、zlib 往返及后台再解析。

新增四条 UI 流程实际操作了箱子数量输入、加入草稿和检查页；运气预设与恢复、天气选择和差异；机器选择、预览、加入草稿和单台撤销；材料选择、补给预览、背包差异和献祭进度保持不变。

## 应用源码与构建身份

设备包和本轮 iPad 验证使用提交 `40da6c03efb7b2b44e8d1283434deeaaf2b628c7`；完整 iPhone 回归使用 `af83dddc251d968ca7a8b35438ba73977de6ee01`。

两者之间只改了新 UI 测试的启动等待：从查找底部“工具”标签，改为等待 `editor.tools.list` 页面容器，以兼容 iPad 的顶部导航。应用代码、资源、单元测试、Xcode 工程、配置、脚本和工作流保持相同。测试断言未删除，新等待已在两种尺寸 iPad 的四条流程中通过。后续交付提交仅加入文档与证据；每轮报告保留实际源提交 SHA。

设备包文件名为 `SheaflightAmberVault-v0.6.0-build14-unsigned.ipa`，3,559,128 字节，最低 iOS 17.0，支持 iPhone / iPad。已校验 ZIP CRC、Info.plist 版本、设备 arm64 Mach-O 平台、Assets.car 以及构建记录中的 SHA-256；包内无签名目录、描述文件或 LC_CODE_SIGNATURE。

SHA-256：`644f527c22f7f0a905e5d3e2c960f98971d98f9064e329592763ed28ad2740ad`。

## 原生截图审阅

已逐张审阅本轮 iPhone SE、iPad mini 和 iPad Pro 的 24 张新增流程截图。预览弹窗、取消/加入草稿入口、原始/草稿值、材料品质与目标格子、机器计时与撤销，以及占用独立布局空间的底部检查栏显示正常。iPhone 检查页的截图处于顶部滚动位置，差异行位于画面下缘，撤销和保存操作在更下方；这些截图不表示整页内容同时可见。

| 状态 | iPhone SE | iPad mini | iPad Pro 13 英寸 |
| --- | --- | --- | --- |
| 箱子数量 25 | [截图](build14-ui/iphone/build14-storage-quantity.png) | [截图](build14-ui/mini/build14-storage-quantity.png) | [截图](build14-ui/large/build14-storage-quantity.png) |
| 箱子差异检查 | [截图](build14-ui/iphone/build14-storage-review.png) | [截图](build14-ui/mini/build14-storage-review.png) | [截图](build14-ui/large/build14-storage-review.png) |
| 运气预设与原值 | [截图](build14-ui/iphone/build14-weather-luck.png) | [截图](build14-ui/mini/build14-weather-luck.png) | [截图](build14-ui/large/build14-weather-luck.png) |
| 天气差异检查 | [截图](build14-ui/iphone/build14-weather-review.png) | [截图](build14-ui/mini/build14-weather-review.png) | [截图](build14-ui/large/build14-weather-review.png) |
| 机器完成预览 | [截图](build14-ui/iphone/build14-machines-preview.png) | [截图](build14-ui/mini/build14-machines-preview.png) | [截图](build14-ui/large/build14-machines-preview.png) |
| 机器待保存与撤销 | [截图](build14-ui/iphone/build14-machines-applied.png) | [截图](build14-ui/mini/build14-machines-applied.png) | [截图](build14-ui/large/build14-machines-applied.png) |
| 材料补给预览 | [截图](build14-ui/iphone/build14-bundle-supply-preview.png) | [截图](build14-ui/mini/build14-bundle-supply-preview.png) | [截图](build14-ui/large/build14-bundle-supply-preview.png) |
| 补给后的背包差异 | [截图](build14-ui/iphone/build14-bundle-inventory-draft.png) | [截图](build14-ui/mini/build14-bundle-inventory-draft.png) | [截图](build14-ui/large/build14-bundle-inventory-draft.png) |

各设备目录内的 `manifest.json` 记录测试名称、原始附件名、SHA-256 和逐图审阅内容。截图没有重绘或修改。演示农场仅载入主存档，所以检查页显示缺少 `SaveGameInfo` 的提示；这不等同真实文件提供器或双文件保存验收。

## 验证限制

本次使用合成 XML 与模拟器，未执行签名真机安装、真实游戏存档载入并睡到下一天后的往返验证。新增工具的 iPad 测试与截图为默认竖屏；既有横竖屏和较大字体测试属于原有布局流程，不代表新工具的所有方向、动态字体、VoiceOver、窗口尺寸、主题或模组存档都已验收。

社区中心测试确认材料进入背包且原献祭记录不变，实际交付和奖励需在游戏内完成。共享特殊容器、家具与建筑移动、其他联机玩家、直接剧情解锁均不属于本轮功能范围。
