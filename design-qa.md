# 轻量农场手账：设计检查

- Source visual truth: `design/selected-journal-reference.png`，853 × 1844 px。
- Native implementation: SwiftUI，首轮提交 `266e468c3ef1b9b4c688c3ef981c02d4915b8377`；iPhone 16e 与 iPad mini 的浅色/深色预览各 2 项均通过。
- Target state: 工具页，浅色，已载入演示存档并有待保存草稿。
- Planned additional states: 深色、空状态、导入、iPad、横屏、375pt 大字号、编辑及搜索。
- Full-view evidence: `../build20-validation/design/initial-reference-vs-native.png`，参考 853×1844 与 iPhone 1170×2532 均按宽 390 归一化；iPhone 保留系统状态栏与安全区，不能将这些差异当成界面缺陷。
- Findings: [P2] 工具底栏图标未渲染；[P2] 首屏备份行说明部分被固定底部区域截住；[P2] 紫红背包和蓝羽毛入口图标偏离参考的棕色背包、礼物盒。
- Applied fixes: 改用有效的系统工具符号；缩短非交互空隙和工具行高度；补齐参考风格的背包和关系图标。点击目标仍不少于 44pt。
- Capture issue: 第一轮浅色设置截图包含 TabView 切换中的混合帧；深色设置及 iPad 同页正常。调整截图时机，在切换完成后重新采集。
- Comparison history: 首轮对照有上述 P2 项，保留原始截图；已实施修正，等待同尺寸、同状态的复拍和对照。
- final result: blocked

阻塞条件为修正后的原生截图与对应构建尚未返回；复拍与图像对照完成后更新此记录。第一轮完整测试已因这些确定需要修正的视觉问题主动停止，不能记为完整回归通过。
