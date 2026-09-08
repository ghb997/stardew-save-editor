# 游戏素材与开源实现参考

版本 0.3.3 build 8。工程打包的 113 张位图来自《星露谷物语》素材、用户提供的素材库及以下项目镜像；应用图标由游戏图像进行最近邻缩放，不使用图像生成模型。底部系统标签栏使用系统规定尺寸的导航符号；页面题头、入口、字段和实体继续使用游戏像素素材。素材接入参考：

- [`colecrouter/stardew-save-editor`](https://github.com/colecrouter/stardew-save-editor/tree/1ae326c685f46c1b8c603864ad796fac3c648ce2)：物品贴图表导出、按 `spriteIndex` 裁切与保存编辑器页面组织。
- [`adiquet/stardew-companion-save-editor`](https://github.com/adiquet/stardew-companion-save-editor/tree/fbfa33abcb470c1e289764171518e82bfe0ce97c)：从游戏 `Content` 读取贴图并按 16×16 单元格显示。
- [`AzimMuradov/stardew-valley-designer`](https://github.com/AzimMuradov/stardew-valley-designer/tree/21e1fe7d4d5aa472e7aeb321b943b991d4fb58b9)：农场、建筑与室内资源的图集裁切方式。
- [`overscore-media/stardew-valley-character-preview`](https://github.com/overscore-media/stardew-valley-character-preview/tree/17a0a90c6b80ab4dffcd3cae85c0081e79eb8f63)：按存档外观字段组合游戏人物图层的实现方式。
- [`hpeinar/stardewplanner`](https://github.com/hpeinar/stardewplanner/tree/f6c8dd5fba513d78b95d491a8aa77d6532c55ee6)：单棵橡树游戏预览素材。

用户提供的 [stardewvalley.site 画布](https://stardewvalley.site/zh/canvas/) 在此前尝试中连接超时，未从该站直接取得素材。v0.3.2 新增素材来自已核对的 GitHub 固定提交；v0.3.3 的补充素材来自用户提供的本地压缩包。

## v0.3.3 用户素材库

来源文件：`星露谷素材800+.zip`，完整压缩包 SHA-256：

`4caed66f090c1ff18bf220f08718a73afe4da2b3e1564f6a5f88352cc5c8f79b`

素材库包含 859 张可解码图片（803 PNG、27 GIF、29 JPEG），按人物、动物、房子、植物、物品等分类。本版接入 58 张 PNG：实体预览要求能由存档类型、名称或 ID 准确映射；界面识别图要求与板块或字段含义直接对应，并且不会被描述成存档的实际持有状态。

| 用途 | 数量 | 接入内容 |
|---|---:|---|
| 农场动物 | 11 | 白/棕/蓝鸡、白/棕牛、鸭、山羊、绵羊、猪、兔、鸵鸟 |
| 果树 | 8 | 樱桃、杏、橙子、桃子、石榴、苹果、芒果、香蕉树 |
| 人物头像 | 7 | 冈瑟、州长、莫里斯、蜗牛教授、雷欧、马龙、齐先生 |
| 建筑 | 1 | 鱼塘 |
| 界面识别 | 31 | 板块入口、五项技能、财富/收藏字段、钱包条幅、地图操作、备份与空状态素材 |

`GAME_ASSETS_MANIFEST.json` 对每张新增图片记录压缩包名称与哈希、包内路径、文件哈希、尺寸和使用说明。应用运行不需要原压缩包。素材库没有提供来源 URL 或独立授权文件，因此不虚构上游地址；游戏画面版权仍归 ConcernedApe / 相应权利人所有。

白/棕/蓝鸡使用游戏内幼年图，只表示物种和颜色；果树使用成熟图，只表示树种。虚空鸡、金鸡、恐龙和肤色色板没有可靠对应图，继续显示无预览。界面识别图用于说明当前板块、字段或操作对象，不表示存档已经获得对应物品。GIF、放大场景和没有明确界面用途的装饰图不加入应用。

## v0.3.2 新增素材

逐文件记录在 [GAME_ASSETS_MANIFEST.json](GAME_ASSETS_MANIFEST.json)，含素材名、工程路径、固定提交源 URL、本地 SHA-256、宽高及必要的变换说明。清单覆盖 50 张新增位图及原有的 5 张位图（包括应用图标），不依赖运行时网络。

| 类别 | 数量 | 固定来源与使用方式 |
|---|---:|---|
| NPC 肖像 | 33 | colecrouter 固定提交的 `static/assets/portraits/`；裁切左上 64×64 表情帧 |
| 发型、饰品、人物基础、工具、制造物 | 6 | 同一提交的原始游戏图集；按类型与原图布局裁切 |
| 建筑 | 6 | 同一提交的 Barn、Coop、Silo、Greenhouse、houses、Shipping Bin；准确匹配基础外观，部分作为后续资源保留 |
| 墙纸与地板、作物条带、路径、普通物品 | 4 | AzimMuradov/stardew-valley-designer 固定提交 `21e1fe7d4d5aa472e7aeb321b943b991d4fb58b9` |
| 橡树预览 | 1 | hpeinar/stardewplanner 固定提交 `f6c8dd5fba513d78b95d491a8aa77d6532c55ee6` |

新增下载均核对来源记录及 SHA-256，补充素材和 Wizard 肖像还与 Git Blob SHA-1 逐字节一致。下载不完整的 Cursors 图集未纳入工程。清单中不声称第三方镜像的游戏图片因仓库开源许可证而获得额外授权；《星露谷物语》的游戏素材版权归 ConcernedApe / 相应权利人所有。

## 当前打包素材

固定来源快照：`colecrouter/stardew-save-editor@1ae326c685f46c1b8c603864ad796fac3c648ce2`。

| 工程素材 | 来源文件 | SHA-256 |
|---|---|---|
| `GameFarmBackdrop` | `static/img/wallpaper.jpg` | `04d608ce50c1ffe4033777d11f1a3e38912cd0b818c37642adee2ef53eb3d4e3` |
| `GameSaveSummary` | `static/img/summary.png` | `aad57e39a00bf973d62007a889025dd92c5c5b5031c3dfc7f3ed3dcfafbaa9e3` |
| `GameSpringObjects` | `static/assets/springobjects.png` | `7782f4558756c111cefdd56d7306b8eb148e5ffa847528f0f19721ee8837d09e` |
| `GameObjects2` | `static/assets/Objects_2.png` | `daf740514e063decdc9bf767d24f8b0e427ab3ecbfb611045a86533846186894` |

`AppIcon-1024.png` 由 `summary.png` 通过固定的 4 倍最近邻缩放得到；输出 SHA-256 为
`dc36e3b97d44059d81c574d2f22bad0ea1e3c13a49e8f8924b8a93946475ea94`。

## 渲染规则

- `springobjects.png`：单格 16×16，24 列。
- `Objects_2.png`：单格 16×16，8 列。
- `ItemCatalog` 保留数据中的 `texture` 与 `spriteIndex`。
- 背包与安全物品目录按图集坐标裁切，并使用最近邻插值保持原始像素边缘。
- NPC 肖像取第一表情帧；发型 0–55 使用 96 像素行步长，56–73 使用第二张图集的 128 像素行步长；饰品每行 32 像素，均显示 16×16 正面图层。
- 墙纸按 16×48 裁切、每行 16 项；地板从 y=336 按 32×32 裁切、每行 8 项。越界样式显示无预览，不通过色相生成假样式。
- 基础农舍取 houses 图集 `(0,0,160,144)`，完整温室取 `(0,160,112,160)`；升级畜棚等未匹配的建筑不借用基础建筑外观。
- `GameCrops` 为 32×768 的整理后条带，不按原生游戏 Data/Crops 索引直接裁切；`GameOakTree` 是带地面的 48×48 缩略图，不是生长阶段动画。
- 地图物品按存档中的准确 ID 与类型选图，避免同名变体误配；作物按种子 ID 对应产物图标，47 种作物均有产物映射，产物图标不表示当前生长阶段。
- 未知模组纹理、未匹配内容或越界索引显示无预览/问号；不制造替代图片。

## 尚未覆盖的外观

本包已补齐 11 种常见动物预览，虚空鸡、金鸡和恐龙仍无可靠图；肤色色板仍显示无预览，发型和饰品分别显示真实图层，尚未合成完整人物。地图是存档实体坐标视图，不是游戏地图截图，仍未渲染完整地形、各生长阶段作物与所有升级建筑。

`游戏素材预览.png` 是从本包已存在纹理裁切排版而成的联系表，仅用于核对素材，不代表应用实际运行截图。

## 已移除素材

`PixelFarmHero`、`PixelRoomHero`、`PixelMagicTools`、`PixelFarmer` 及原生成记录已从资源目录移除；代码与编译产物不再引用这些名称。
