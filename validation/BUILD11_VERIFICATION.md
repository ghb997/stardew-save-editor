# 0.5.0（11）原生验证记录

2026-09-10，本次应用代码完成 iOS 设备 Release 编译和模拟器 Debug 编译。实际执行 100 项测试，100 项通过，0 项失败、0 项跳过。

## 构建与测试证据

| 项目 | 实际结果 |
| --- | --- |
| [设备构建](https://github.com/ghb997/stardew-save-editor/actions/runs/34432584841) | Xcode 16.4、iOS SDK 18.5、Release、iPhoneOS arm64 成功 |
| [原生测试](https://github.com/ghb997/stardew-save-editor/actions/runs/34432594494) | Debug、iPhone SE 第 3 代、iOS 26.2，100/100 通过 |
| 存档核心 SaveCoreTests | 32/32 通过 |
| 游戏逻辑 GameLogicRegressionTests | 10/10 通过 |
| 背包与关系 ReferenceFeatureTests | 14/14 通过 |
| 追踪指标 TrackerMetricsTests | 7/7 通过 |
| 保存事务 TransactionRegressionTests | 9/9 通过 |
| 地图、颜色与房间 WorldEditorTests | 18/18 通过 |
| 界面 TrackerSmokeUITests | 10/10 通过，包含 3 项新增编辑流程 |
| 工程、数据和资源静态检查 | 6/6 通过，63 个 Swift 文件、113 张位图 |

逐项结果从下载的 tests.log 中实际完成的 XCTest 记录提取，并与源码中的全部测试名称核对，没有漏跑、跳过或重复结果。静态检查仅验证工程、数据和资源，不代替原生编译或测试。

机器可读记录：[测试结果](build11-native-tests.json)、[设备包验证](build11-device-build.json)、[静态检查](build11-static-checks.json)。完整日志、结果包及附件在对应 Actions 运行的产物中。

## 本次覆盖

新增的 18 项单元回归覆盖颜色通道与 PackedValue 往返、透明度和未知 XML 保留、无效与缺失字段拒绝写入、房间筛选与同类表面批量修改、单房间恢复、未修改 XML 数值写法保留、地图搜索与范围、单株浇水及操作键校验。既有背包、关系、备份、事务和压缩存档回归一并执行。

新增界面流程实际完成颜色预设、清空输入、六位色值应用及恢复；房间样式搜索、批量预览取消与应用、单房间和全部恢复；地图坐标搜索、浇水预览取消与应用、待处理筛选、定位和撤销。

原生验证发现颜色页滚到底后，恢复按钮仍被外层检查栏遮挡。本次将编辑器和地图的检查栏改为占用独立布局空间，完整重跑后，恢复按钮的可见性、点击和恢复原色断言均通过。测试以稳定的页面标识查找滚动区域，避免页面切换期间失效的列表索引。

## 源码与 IPA 对应关系

设备构建和完整测试均来自提交 02c080cd9d5decbd5152f0b10290aae4702917aa。应用代码、资源、Xcode 工程、project.yml、构建脚本及工作流的 Git 对象已逐项核对；后续交付提交只包含文档和验证证据。详见 [源码对应记录](build11-source-equivalence.json)。

设备包为 SheaflightAmberVault-v0.5.0-build11-unsigned.ipa，3,213,245 字节，最低 iOS 17.0。已复核 ZIP CRC、Info.plist 版本、iPhoneOS arm64 Mach-O、Assets.car 和构建记录中的 SHA-256；包内没有签名目录、描述文件或 LC_CODE_SIGNATURE。

SHA-256：b17bfebfdffbde6e7b4cc5836ed231237a21fda5ed0e94fe9366e9287da408bc。

这是未签名设备包，需要使用自己的签名后安装。

## 界面截图检查

以下七张均来自本轮通过的 XCUITest，使用合成演示农场，已逐张检查表中所列状态。页面处于测试指定的滚动位置；这组截图不覆盖全部页面、尺寸、主题和辅助功能。单独的 16 张 Tracker 截图流程本轮没有运行。

| 截图 | 已核对内容 |
| --- | --- |
| [颜色输入与对照](build11-ui/editor-appearance-color-hex.png) | 原始 #B77C43、当前 #123456 的完整色块与文本，RGB 18 / 52 / 86、清空按钮、应用按钮和 1 项待保存 |
| [房间样式库](build11-ui/editor-room-style-library.png) | 搜索词 5、卧室地板 #5、选中边框及匹配编号的贴图网格 |
| [房间批量预览](build11-ui/editor-room-style-batch-preview.png) | 将修改 4 个房间，逐项原始编号 → #5，勾选控件、取消和加入草稿入口 |
| [恢复单个房间](build11-ui/editor-room-restored-with-other-drafts.png) | 卧室原始与当前地板均为 11，直接输入编号为 11，其他房间仍有 4 项待保存 |
| [范围浇水预览](build11-ui/editor-map-scoped-water-preview.png) | 仅 1 个对象：防风草 X 14、Y 29，取消和确认加入草稿入口 |
| [待处理搜索](build11-ui/editor-map-pending-search.png) | X 14 搜索词、待处理筛选、匹配 1 个与全图待处理 1 个、撤销及定位按钮 |
| [定位作物](build11-ui/editor-map-located-crop.png) | 主地图显示防风草 X 14、Y 29 的详情、撤销操作及 1 项待保存；此滚动位置展示对象详情，坐标画布在上方 |

截图对应测试、原始附件名与 SHA-256 见 [截图清单](build11-ui/manifest.json)。恢复颜色和撤销地图操作的最终状态由同一轮界面测试断言确认。

## 尚未覆盖

本次未执行签名后的真机安装、真实游戏存档载入与睡到下一天后重新加载，也未完成 iPad、动态字体、VoiceOver、各类文件提供器以及复杂多人或模组存档的完整验收。模拟器与合成 XML 测试只能证明已经覆盖的代码路径。

真机与游戏验收可使用独立测试副本：在编辑器保存，再在游戏载入，睡到下一天后重新读取并核对修改结果。此版本的家具拖拽、建筑移动、室内物件和其他联机玩家编辑仍不在本次范围内。
