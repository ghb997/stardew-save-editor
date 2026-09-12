# 构建 15 验证记录

版本：0.7.0（15）。日期：2026-09-12。当前结果：设备构建和两种 iPad 测试通过，iPhone 全量回归正在执行。

## 当前修订

设备构建、两种 iPad 和完整 iPhone 任务对应提交 `a0a0a7e0422adfd5d5e15dd1cc122a4f8cab0b34`，位于分支 `codex/complete-repair-build15`。应用源码、资源及工程保持一致；随后增强 RepairEditorUITests 的可见性和具体差异断言，并给现有脚本/workflow 增加只运行这 4 项 UI 流程的入口。这组增强后的测试将另行执行并保存截图。

| 项目 | 当前结果 | 证据 |
| --- | --- | --- |
| Release arm64 IPA | 构建成功，版本、架构、签名状态与文件摘要已核对 | [构建任务](https://github.com/ghb997/stardew-save-editor/actions/runs/34688577632)、[元数据](build15-device-build.json) |
| iPad mini（A17 Pro） | 实际执行 8 项 UI 测试，全部通过；5 张原生截图已审阅 | [逐项结果](build15-tests-mini.json)、[截图清单](build15-ui/mini/manifest.json) |
| 13 英寸 iPad Pro（M5） | 实际执行 8 项 UI 测试，全部通过；5 张原生截图已审阅 | [逐项结果](build15-tests-large.json)、[截图清单](build15-ui/large/manifest.json) |
| iPhone 完整回归 | 正在执行，范围为 148 项单元和 25 项 UI 测试，尚未获得本轮完整通过结果 | [测试任务](https://github.com/ghb997/stardew-save-editor/actions/runs/34688653688) |
| 静态工程与资源检查 | 6 项通过，88 个 Swift 文件、113 张位图、173 个测试方法声明 | [静态结果](static-release-results.json) |
| Swift 语法扫描 | 无语法错误；两个 Swift 6 sending 限定词的跳过在报告中披露 | [语法结果](swift-syntax-results.json) |
| 配置及目录数据 | project.yml、3 个 workflow YAML 和 95 项博物馆候选数据通过检查 | [辅助检查](build15-supporting-checks.json) |
| 签名真机安装、真实游戏往返 | 未执行 | 见下文覆盖边界 |

两种 iPad 的任务位于 [同一工作流运行](https://github.com/ghb997/stardew-save-editor/actions/runs/34688577619)，每台执行 ExpandedEditorUITests 的 4 项和 RepairEditorUITests 的 4 项。已逐项核对 XCTest 完成记录与方法声明，无缺测、跳过、重复或失败。

## 安装包

- 文件：`SheaflightAmberVault-v0.7.0-build15-unsigned.ipa`
- 大小：3,701,134 字节，约 3.53 MiB；展开总量约 12.13 MiB。
- SHA-256：`c52c20523639eb91e8fc3bd9ee3c78b819967bdd1f7e500006b9a51f3bd52080`
- Xcode 16.4 / iPhoneOS SDK 18.5；Release，arm64，最低 iOS 17.0。
- IPA 未签名，没有 provisioning profile；需要签名后安装。
- [IPA 静态检查](build15-ipa-inspection.json)、[与参考 IPA 的大小对照](BUILD15_SIZE_COMPARISON.md)。

设备构建元数据中的 `testsRun: false` 表示 Release 打包脚本不运行测试；模拟器测试由上述独立任务执行。

## 回归发现与修正

此前原生回归修复了装备/收藏整行点击区域、系统组合的收藏记录标签及小屏搜索键盘操作。上一轮 `cd325fa` 的 iPhone 实际执行 173 项，其中 148 项单元测试全部通过，25 项 UI 中 2 项失败：收藏补给明细位于检查页下方，背包搜索未提交时键盘遮住结果。

当前测试会滚动核对“槽位 3”及“矮人卷轴 II ×1（普通）”，背包搜索提交后核对钻石槽位及筛选结果。背包页也补充了滚动收起键盘支持。当前完整 iPhone 任务保留全部 173 项测试和测试内原生截图；通过手动参数省略测试结束后的独立 Tracker 展示截图步骤。

此前失败或取消的任务用于诊断，不计为当前修订的通过结果。

截图检查还发现旧 iPhone 截图中的装备升级差异和取消结果位于可视区域下方。增强后的测试会先滚动到完整单元格，核对工具等级 1 → 4、空槽位变为矮人卷轴 II，并让“没有待保存的更改”提示位于屏幕内再截图。这次调整不改变应用代码和 IPA。

## 覆盖边界

测试使用合成存档和模拟器。生成 XML 后重新解析并核对草稿，可验证序列化结果是否符合本次修改意图；尚未完成签名真机安装、真实存档在游戏中加载、睡觉保存及二次载入。文件提供器、云同步、多人和 Mod 存档仍需要相应环境与样本验证。

本轮未实现完整地形/人物渲染、高级事件预测或完整锻造编辑，也不宣称与参考应用全面等价。安装与使用步骤见 [START_HERE.md](../START_HERE.md)，修复范围见 [COMPLETE_REPAIR.md](../COMPLETE_REPAIR.md)。
