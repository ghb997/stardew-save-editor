# 追踪器界面改进 · 本地源码预览

日期：2026-09-09。基线：SheaflightAmberVault-source-delivery-v0.3.3-build8.zip。

状态：界面改动已写入；静态检查通过；原生构建与视觉验收待完成。这不是已验证发行版或可安装 IPA。

## 这次具体改变

追踪首页从独立模块入口列表改为“农场摘要 → 分类筛选 → 可折叠功能组”。采用暖杏色题头、深棕标题、游戏像素图标、浅绿记录行和细进度条；深色模式使用深灰底、暖色选中态与深绿记录行。

- 农场摘要展示真实农场/农夫、游戏日期、四类收藏合计及配方解锁；有草稿时明确显示“未保存”。
- 总览、基础、收藏、农场生活、状态五类筛选；4 个折叠组覆盖原有全部 11 个模块。
- 详情保留只读性质，顶部分类可以直接切换，打开靠后模块时滚动到对应选中项。
- 收藏页区分财富资源、矿洞世界、收藏统计与累计记录；缺失可选数值显示“未提供”。
- 钱包、技能和配方展示各自准确的进度；配方新增已解锁/未解锁筛选，仍支持中文/英文名称搜索。
- 摘要和数据行适配辅助功能字号；按钮提供选中/折叠状态和明确的操作标识。

本轮按 SwiftUI UI Patterns 使用原生状态、可复用小组件、语义主题与自适应布局；没有改成网页 App，没有增加参考应用才有但本项目尚未支持的功能。

## 数据与操作边界

追踪器只预览当前草稿。点击只改变导航、搜索、筛选或折叠状态，不保存、不解锁游戏数据、不写入真实存档，也不上传存档。

收藏合计是出货/鱼类/矿物/古物四类种类计数相加，不去重、不代表游戏完美度；金色核桃是持有余额，不是累计发现的 130 个。技能摘要按已识别技能的 0–10 级计算比例，详情仍展示存档原始等级。状态优先显示兼容性警告，不再用满进度条暗示“存档完全正常”。

原始 IPA、历史源码 ZIP 与旧版可安装产物均未覆盖。仅参考公开 App Store 截图与只读 IPA 信息；未复制参考应用代码或新增其私有资源。

## 主要源码

- PelicanSaveEditor/Views/Home/TrackerView.swift：首页、摘要、分组导航。
- PelicanSaveEditor/Views/Home/TrackerComponents.swift：分组定义、卡片与数据行。
- PelicanSaveEditor/Views/Home/TrackerDetailView.swift：11 类只读详情、配方筛选。
- PelicanSaveEditor/Views/Home/HomeComponents.swift：追踪器专用主题、可配置题头。
- PelicanSaveEditor/Models/TrackerMetrics.swift 与 PelicanSaveEditorTests/TrackerMetricsTests.swift：指标口径及 7 个测试。
- PelicanSaveEditor.xcodeproj/project.pbxproj：新增文件已注册。

## 验证和下一步

已执行：54 文件语法扫描、6 项工程静态检查、113 资源核对。语法扫描不等于 Swift 编译。项目目前共 58 个测试方法声明，未执行 XCTest。

在 Mac 上运行：

    bash scripts/validate-on-macos.sh
    bash scripts/capture-tracker-ui.sh

第二个脚本构建 Debug，在新建的临时模拟器中使用合成农场数据，采集 16 张原生截图，覆盖浅色、深色、大字号、空状态、草稿和重点详情。它不会操作已有模拟器数据，退出只清理自己创建的设备。

完整人工核对步骤见 validation/TRACKER_UI_CHECKLIST.md。在取得真实截图、同状态对照并修复问题前，design-qa.md 的结论保持 blocked。用户已于 2026-09-09 授权独立分支推送与云端验证。当前验证分支为 codex/tracker-ui-validation-20260909，版本 0.3.3（9）；不合并主分支、不发布 Release。验证结果待更新。
