# 构建 20 装饰资产来源

工具页采用用户选定的第 2 套图像参考：[selected-journal-reference.png](selected-journal-reference.png)。图像由内置 `image_gen` 生成，作为设计方向；实际界面使用 SwiftUI 原生布局、文字和交互。

## JournalFarmBanner

- 生成工具：内置 `image_gen`，`transparent_background=true`。
- 输入参考：上述已选模板。
- 提示词规格：仅重绘参考顶部细长农场插画；真实透明背景；淡绿远山、橙棕农舍与红棕屋顶、矮木栅栏、树、右侧奶油色小鸡与爱心气泡；主体完整、草地底缘平直细窄；无文字、图标、界面、外框、大片天空或附加场景。
- 实际输出：2188 × 718，RGBA；可见插画范围 x=0…2187、y=215…505。保留生成工具的完整文件，未二次绘制或栅格修改。SwiftUI 按原始比例显示，仅在页面容器中隐藏上下透明留白。
- 这是生成的装饰插画，不是官方游戏纹理，也不代表读取到的真实农场布局。
- 文件哈希和尺寸纳入 `GAME_ASSETS_MANIFEST.json`；运行 `scripts/verify_release.py` 可校验。

## JournalFarmerIcon / JournalWeatherIcon / JournalMapIcon

- 生成工具：内置 `image_gen`，均设置 `transparent_background=true`，参照同一已选模板。
- 共用提示词规格：单个完整像素风 UI 图标，独立透明方形 PNG；风格及朝向贴近参考，主体尽量占画布 75%–85%，34pt 时可辨，不含文字或 UI。
- 农夫：正面草帽、蓝色背带裤的完整小农夫。
- 天气：太阳在左上、小白云在右下。
- 地图：带绿色农场地块的浅色卷轴地图。
- 这些图标为工具入口装饰，不是角色实时外观、真实天气值或真实农场地图截图。
- 保留工具原始输出，未重绘。实际尺寸和 SHA-256 由清单校验；透明边缘与原生显示尺寸会在设计截图检查中核对。

原有 `Game…` 内容图标、物品和 NPC 图片仍使用其原始清单记录的游戏素材来源。系统搜索、箭头、关闭、导航与状态控件采用 SF Symbols。
