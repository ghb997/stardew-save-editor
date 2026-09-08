# 交付验证说明

版本：0.3.3（7）。环境：Windows 与 GitHub Actions，2026-09-08。

## 已执行的检查

- 使用 tree-sitter-swift 解析全部 50 个 Swift 文件，无语法解析错误。该语法库尚未支持两个 `sending` 返回限定符，脚本以等字节空格跳过限定符后解析其余内容，并在 JSON 中明确列出位置。这不等同于 Swift 编译器类型检查或并发隔离验证。
- 静态工程检查：源码引用与 target、版本设置、JSON/plist/XML、素材文件、SHA-256 与图片尺寸。可重复运行 `python3 scripts/verify_release.py`，结果写入 `validation/static-release-results.json`。
- 113 张打包位图均核对清单；其中 58 张来自用户素材库，已对完整 859 张库进行路径、解码、格式、尺寸、动画帧与 SHA-256 审计，并人工检查选中图像。素材预览联系表不作为 iOS 实机截图。
- 最终 ZIP 将按每个文件的 SHA-256 与交付源目录比较；ZIP 的 SHA-256 另附在同目录校验文件中。

机器可读语法检查结果：`validation/swift-syntax-results.json`。检查脚本：`scripts/check_swift_syntax.py`；重跑需要 Python、tree-sitter 0.26.0 和 tree-sitter-swift 0.7.3。

## 尚未执行的验证

当前 Windows 机器没有 Xcode、Swift iOS SDK或 iOS 模拟器。上一版 0.3.2 build 6 已在 GitHub Actions 使用 Xcode 16.4 成功完成设备 Release 编译；本版 0.3.3 build 7 的云端结果以对应构建记录为准。51 个 XCTest、iPhone/iPad UI 检查和《星露谷物语》真实读档仍需单独执行。

## Mac 上执行

1. 安装 Xcode 16 或更新版本，并在 Xcode 设置中安装一个 iOS Simulator runtime。
2. 在工程根目录执行 `bash scripts/validate-on-macos.sh`。脚本选择可用的 iPhone 模拟器，先 build 再 test，失败时返回非零退出码，并保留构建日志与测试结果包。
3. 也可打开 `PelicanSaveEditor.xcodeproj`，选 `PelicanSaveEditor` scheme，运行 Build 和 Test。真机运行需配置自己的 Signing Team。

## 重点人工验收

| 场景 | 预期 |
|---|---|
| 每类字段单独修改 | 检查页显示实际差异，单项撤销后该项不再写回 |
| 盆栽/制造物/模组物品与普通杂草混放 | 只有白名单普通杂物可被批量和单项清理 |
| 两只动物且年龄与饲养天数不同 | 编辑一只动物的单个字段，其他动物与年龄保持不变 |
| 主档与另一农场 SaveGameInfo 配对 | 非零稳定玩家 ID 不一致时阻止导入；缺少 ID 时提示 |
| 中文/emoji/XML BOM/zlib | 正常读取；未知字段在往返中保留 |
| 10 级技能经验降低至 0 | 等级与职业同时更新；无关技能保持原值 |
| 同名农场不同目录、重复复制导入 | 日志与恢复来源隔离 |
| 双文件写入失败或游戏已写入未知新进度 | 已知混合状态可恢复，未知状态先保护备份并提示 |
| 原主档损坏/缺失或摘要缺失 | 冷启动后从备份管理校验并导出有效备份，无需加载原档 |
| 副本保存后导出、取消、下滑关闭导出页 | 已保存副本与导出状态准确，不声称游戏原档已被替换 |
| 正在编辑时取消或打开损坏的新农场 | 原会话保留；正在工作时草稿不再变化 |
| 大存档与慢文件提供器 | 读取/保存期间 UI 有反馈，操作结束后再展示结果 |
| iPhone/iPad 大字体与 VoiceOver | 检查按钮可达，地图对象可通过列表选中 |
| 素材与游戏对照 | 板块入口可区分；NPC、动物、果树、技能、进度字段、地图操作、工具、发型、饰品、墙纸/地板编号正确；缺图显示无预览 |

真实游戏验收请使用独立测试副本：载入修改结果、检查字段、睡到下一天并再次加载。文件提供器权限、云盘同步竞争、完整角色显示和复杂多人/模组存档需要样本覆盖，静态脚本无法证明这些行为。
