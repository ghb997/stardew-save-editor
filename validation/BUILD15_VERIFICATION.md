# 构建 15 验证记录

版本：0.7.0（15）。日期：2026-09-12。

## 当前结果

Release arm64 IPA 已构建并校验。iPhone 的 173 个测试方法分两轮覆盖通过：全量轮次中的 169 项未变测试通过，修正测试滚动导航后，4 项装备/收藏 UI 流程整组复验通过。原全量轮次仍记录为 170 通过、3 失败，不计为全量成功。两种 iPad 各 8 项 UI 流程通过，15 张本轮原生截图已审阅。 IPA 为未签名产物，需要签名后安装；没有执行真实游戏往返。

| 证据轮次 | 实际执行结果 | 最终采用的覆盖 | 逐项记录 |
| --- | --- | --- | --- |
| iPhone SE（第 3 代）全量 | 173 项：170 通过、3 失败 | 未变的 148 单元 + 21 UI，共 169 项 | [原始失败轮次](build15-tests-iphone-full.json) |
| iPhone SE（第 3 代）修复 UI 复验 | 4 项全部通过 | 完整替换 RepairEditorUITests 4 项 | [复验](build15-tests-iphone-repair.json) |
| iPad mini（A17 Pro） | 8 项 UI 全部通过 | 8 项 | [结果](build15-tests-mini.json) |
| 13 英寸 iPad Pro（M5） | 8 项 UI 全部通过 | 8 项 | [结果](build15-tests-large.json) |

最终覆盖 **173 个不同测试方法**，含 iPad 重复验证为 **189 个设备/方法组合**。用于这一结论的四份原始日志合计 **193 次执行：190 通过、3 失败**。全量失败状态保持不变；其中 RepairEditorUITests 的 1 项旧通过与 3 项旧失败统一由后续整组 4 项结果替换。没有遗漏、跳过或把同一设备的复验重复计入覆盖。

- [iPhone 全量任务（失败状态保留）](https://github.com/ghb997/stardew-save-editor/actions/runs/34688653688)
- [iPhone 修复 UI 整组复验](https://github.com/ghb997/stardew-save-editor/actions/runs/34690602507)
- [两种 iPad 扩展/修复 UI 任务](https://github.com/ghb997/stardew-save-editor/actions/runs/34688577619)
- [Release IPA 构建](https://github.com/ghb997/stardew-save-editor/actions/runs/34688577632)
- [机器可读覆盖与来源对应](build15-tests-iphone.json)

## 失败原因与复验范围

原全量的三个失败均发生在进入装备页面之前。测试连续整屏上滑，滑过“工具与装备”后仍向同一方向滚动。失败层级显示按钮在可视区域上方；不是装备保存断言失败。测试改为在工具列表的实际可视范围内，根据目标坐标短距离双向滚动，避开底部标签栏。增强后的检查页断言还核对完整差异单元格及 1 → 4、空 → 矮人卷轴 II 的实际值。

后续整组四项在同一 iPhone 型号上成功执行。其余 169 项的测试文件、应用源码、资源和 Xcode 工程完全一致，沿用已通过的全量结果。两种 iPad 各 8 项覆盖 ExpandedEditorUITests 和 RepairEditorUITests，应用源码同样一致。此前中间诊断任务（包括 332aef3 的 3 通过、1 导航失败）不混入最终覆盖数量。

## 编译、测试与交付源码

- 应用 Release 编译、iPhone 全量与两种 iPad 测试源码：`a0a0a7e0422adfd5d5e15dd1cc122a4f8cab0b34`。
- iPhone 修复 UI 复验源码：`7453365bdb06f95676ae788b54742e0808c0cf2c`。改动限于 RepairEditorUITests、按范围运行测试的脚本/workflow，以及文档和证据。
- 交付分支：`codex/complete-repair-build15`。最终提交增加验证报告、原图和证据检查脚本；应用、资源及工程和已编译提交逐文件一致，其他测试与全量提交一致，RepairEditorUITests 与成功复验提交一致。

`scripts/verify_build15_evidence.py` 会检查 Git 源码一致性、173 个方法的声明和实际结果、整组替换规则、原失败状态以及 15 张原图的摘要和审阅标记。提供原始 artifact 目录时还逐项核对 XCTest 日志，不能把失败轮次改写成通过。

交付中的 `BUILD15-DELIVERY.json` 记录最终提交、编译提交和复验提交；源码 ZIP 逐文件对照 Git blob，二进制补丁执行反向应用检查。`SHA256SUMS.txt` 覆盖交付文件。`validation/native-logs/` 保留 iPhone 全量、iPhone 复验、两种 iPad 共四份原始日志，并核对各自报告的 SHA-256。

## 安装包检查

- 文件：`SheaflightAmberVault-v0.7.0-build15-unsigned.ipa`。
- 大小：3,701,134 字节（3.53 MiB），展开约 12.13 MiB。
- SHA-256：`c52c20523639eb91e8fc3bd9ee3c78b819967bdd1f7e500006b9a51f3bd52080`。
- Release / arm64，iPhone 与 iPad，最低 iOS 17.0；Xcode 16.4 / iPhoneOS SDK 18.5。
- ZIP CRC、Info.plist 版本、Mach-O 架构、无签名与无 provisioning profile 已核对；摘要与构建记录、工作流校验文件一致。
- [设备构建元数据](build15-device-build.json)、[IPA 检查](build15-ipa-inspection.json)、[参考 IPA 大小对照](BUILD15_SIZE_COMPARISON.md)。

设备构建元数据的 `testsRun: false` 表示 Release 打包脚本不执行测试；原生测试由独立模拟器任务完成。

## 原生截图

三台设备各保留以下 5 张未经修改的 XCTest 原图，均已逐张审阅：

| 截图 | 可见内容 |
| --- | --- |
| build15-equipment-review | 工具升级等级 1 → 4 及撤销按钮 |
| build15-equipment-cancel | 取消后没有待保存的更改 |
| build15-equipment-invalid-damage | 最低伤害 90、最高伤害 80 的错误提示及恢复按钮 |
| build15-collection-supply | 缺少记录状态与加入背包草稿的反馈 |
| build15-collection-review | 槽位 3 从空变为矮人卷轴 II ×1（普通） |

原图及来源、摘要、审阅记录：[iPhone](build15-ui/iphone/manifest.json)、[iPad mini](build15-ui/mini/manifest.json)、[13 英寸 iPad Pro](build15-ui/large/manifest.json)。

## 可重复验证

静态工程/资源检查 6 项通过，88 个 Swift 文件、173 个测试方法、113 张位图。Swift 语法扫描无错误；两个 Swift 6 sending 限定词的跳过在语法报告中披露，实际 Swift 编译已由上述 Xcode 任务另行验证。配置 YAML、95 项博物馆候选数据和 macOS 脚本 Bash 语法也已检查。

```sh
python3 scripts/verify_release.py
python3 scripts/check_swift_syntax.py
# 以下检查需要包含相关提交的 Git 仓库：
python3 scripts/verify_build15_evidence.py
# macOS / Xcode 16.x：
bash scripts/validate-on-macos.sh
VALIDATION_TEST_SCOPE=repair bash scripts/validate-on-macos.sh
LAYOUT_DEVICE=mini LAYOUT_SCOPE=repair bash scripts/validate-layout-on-macos.sh
LAYOUT_DEVICE=large LAYOUT_SCOPE=repair bash scripts/validate-layout-on-macos.sh
bash scripts/build-unsigned-ipa.sh
```

## 覆盖边界

测试使用合成存档和模拟器。生成 XML 后重新解析、核对草稿可验证序列化结果，不能替代游戏实际回读。尚未完成签名真机安装、真实存档加载、睡觉保存与二次载入，也未全面覆盖文件提供器、云同步、多人和 Mod 存档。

本轮未实现完整地形/人物渲染、高级事件预测或完整锻造编辑。安装与使用见 [START_HERE.md](../START_HERE.md)，修复范围见 [COMPLETE_REPAIR.md](../COMPLETE_REPAIR.md)。
