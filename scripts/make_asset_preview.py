"""Make a contact sheet of bundled game sprites. Requires Pillow; no network.

Usage: python make_asset_preview.py [path-to-CJK-font]
The output is a sprite contact sheet, not an application screenshot.
"""
from pathlib import Path
import json
import math
import sys

from PIL import Image, ImageDraw, ImageFont


root = Path(__file__).resolve().parents[1]
records = json.loads((root / "GAME_ASSETS_MANIFEST.json").read_text(encoding="utf-8"))
paths = {record["asset"]: root / record["file"] for record in records}
font_candidates = [Path(sys.argv[1])] if len(sys.argv) > 1 else [
    Path("C:/Windows/Fonts/msyh.ttc"), Path("/System/Library/Fonts/PingFang.ttc")]
font_path = next((path for path in font_candidates if path.is_file()), None)
if not font_path:
    raise SystemExit("Provide a Chinese font path as the first argument.")

fonts = {size: ImageFont.truetype(str(font_path), size) for size in (15, 17, 20, 23, 38)}
canvas = Image.new("RGB", (1800, 1640), "#f5f0e3")
draw = ImageDraw.Draw(canvas)
ink = "#283e31"
muted = "#647064"
rows = json.loads((root / "PelicanSaveEditor/Resources/iteminfo.json").read_text(encoding="utf-8"))
items = [row[1] for row in rows]


def texture(asset, box=None):
    image = Image.open(paths[asset]).convert("RGBA")
    if box:
        assert 0 <= box[0] < box[2] <= image.width and 0 <= box[1] < box[3] <= image.height, (asset, box)
        image = image.crop(box)
    return image


def item(key, by_name=False):
    value = next(value for value in items if (value["name"] if by_name else value["_key"]) == key
                 and value["_type"] in ("Object", "Tool", "BigCraftable"))
    kind = value["_type"]
    height = 32 if kind == "BigCraftable" else 16
    if kind == "Tool":
        asset = "GameTools"
        index = value.get("menuSpriteIndex", value.get("spriteIndex"))
    elif kind == "BigCraftable":
        asset = "GameCraftables"
        index = value["spriteIndex"]
    else:
        asset = "GameObjects2" if value.get("texture", "").lower() == "objects_2.png" else "GameSpringObjects"
        index = value.get("spriteIndex", int(value["_key"]) if value["_key"].isdigit() else -1)
    width = texture(asset).width
    x, y = (index % (width // 16)) * 16, (index // (width // 16)) * height
    return texture(asset, (x, y, x + 16, y + height))


def text(x, y, value, size=17, color=ink):
    draw.text((x, y), value, font=fonts[size], fill=color)


def panel(x, y, width, height, title, note):
    draw.rounded_rectangle((x, y, x + width, y + height), radius=18,
                           fill="#fffcf5", outline="#d7ddcf", width=2)
    text(x + 22, y + 16, title, 23)
    text(x + 22, y + height - 26, note, 15, muted)


def sample(sprite, x, y, width, height, title):
    image_height = height - 30
    ratio = min((width - 12) / sprite.width, (image_height - 8) / sprite.height, 4)
    if ratio >= 1:
        ratio = max(1, math.floor(ratio))
    display = sprite.resize((max(1, round(sprite.width * ratio)), max(1, round(sprite.height * ratio))),
                            Image.Resampling.NEAREST)
    canvas.paste(display, (x + (width - display.width) // 2,
                           y + (image_height - display.height) // 2), display)
    box = draw.textbbox((0, 0), title, font=fonts[17])
    text(x + (width - (box[2] - box[0])) // 2, y + height - 25, title, 17)


def asset_grid(x, y, width, height, values, columns):
    grid_rows = math.ceil(len(values) / columns)
    cell_width = (width - 36) // columns
    cell_height = (height - 92) // grid_rows
    for index, (asset, label) in enumerate(values):
        sample(texture(asset), x + 18 + (index % columns) * cell_width,
               y + 52 + (index // columns) * cell_height, cell_width, cell_height, label)


draw.rectangle((0, 0, 1800, 116), fill="#284b38")
text(40, 20, "穗光琥珀存档匣 · 游戏素材预览", 38, "#fff7dd")
text(42, 77, "v0.3.3 / build 8     板块入口、字段行与实体预览均使用打包的游戏像素素材", 17, "#d8e5d2")

panel(40, 142, 840, 322, "编辑板块识别", "每个入口使用独立素材；进入编辑器后顶栏会继续显示当前板块")
asset_grid(40, 142, 840, 322, [
    ("GameUIFarmhouse", "房屋"), ("GameUIBackpack", "背包"),
    ("GameUIProgress", "进度"), ("GameUIRelationships", "关系"),
    ("GameUIWallet", "钱包"), ("GameUIRecipes", "配方"),
    ("GameUIReview", "检查保存"), ("GameUIBackup", "备份"),
    ("GameUIFarmComputer", "魔法地图"), ("GameUICropPlanner", "作物计算"),
], 5)

panel(920, 142, 840, 322, "技能与进度字段", "技能、货币、收藏和统计行使用与字段含义对应的原图")
asset_grid(920, 142, 840, 322, [
    ("GameUISkillFarming", "耕种"), ("GameUISkillFishing", "钓鱼"),
    ("GameUISkillForaging", "采集"), ("GameUISkillMining", "采矿"),
    ("GameUISkillCombat", "战斗"), ("GameUIGoldBar", "收入"),
    ("GameUIDiamond", "齐钻/矿物"), ("GameUIGoldenWalnut", "金色核桃"),
    ("GameUIArtifact", "古物"), ("GameUIFish", "鱼类"),
], 5)

panel(40, 492, 840, 342, "农场动物", "十一种标准动物用物种与颜色示意；幼年鸡图不表示存档年龄")
asset_grid(40, 492, 840, 342, [
    ("GameAnimalWhiteChicken", "白鸡"), ("GameAnimalBrownChicken", "棕鸡"),
    ("GameAnimalBlueChicken", "蓝鸡"), ("GameAnimalWhiteCow", "白牛"),
    ("GameAnimalBrownCow", "棕牛"), ("GameAnimalDuck", "鸭"),
    ("GameAnimalGoat", "山羊"), ("GameAnimalSheep", "绵羊"),
    ("GameAnimalPig", "猪"), ("GameAnimalRabbit", "兔"),
    ("GameAnimalOstrich", "鸵鸟"),
], 6)

panel(920, 492, 840, 342, "果树与农场操作", "果树显示成熟树种；批量工具使用喷壶、石块、纤维与木材原图")
asset_grid(920, 492, 840, 342, [
    ("GameFruitTreeCherry", "樱桃"), ("GameFruitTreeApricot", "杏"),
    ("GameFruitTreeOrange", "橙子"), ("GameFruitTreePeach", "桃子"),
    ("GameFruitTreePomegranate", "石榴"), ("GameFruitTreeApple", "苹果"),
    ("GameFruitTreeMango", "芒果"), ("GameFruitTreeBanana", "香蕉"),
    ("GameUIWateringCan", "浇水"), ("GameUIStone", "石块"),
    ("GameUIWeeds", "杂草"), ("GameUITwig", "树枝"),
], 6)

panel(40, 862, 840, 326, "人物关系头像", "关系列表按存档 NPC 名称匹配完整头像；本区展示新增和既有示例")
portrait_values = [
    (texture("GamePortraitGunther"), "冈瑟"), (texture("GamePortraitGovernor"), "州长"),
    (texture("GamePortraitMorris"), "莫里斯"), (texture("GamePortraitProfessorSnail"), "蜗牛教授"),
    (texture("GamePortraitLeo"), "雷欧"), (texture("GamePortraitMarlon"), "马龙"),
    (texture("GamePortraitMrQi"), "齐先生"), (texture("GamePortraitAbigail", (0, 0, 64, 64)), "阿比盖尔"),
    (texture("GamePortraitSebastian", (0, 0, 64, 64)), "塞巴斯蒂安"),
    (texture("GamePortraitLeah", (0, 0, 64, 64)), "莉亚"),
]
portrait_cell_w = (840 - 36) // 5
portrait_cell_h = (326 - 92) // 2
for index, (sprite, label) in enumerate(portrait_values):
    sample(sprite, 58 + (index % 5) * portrait_cell_w,
           914 + (index // 5) * portrait_cell_h, portrait_cell_w, portrait_cell_h, label)

panel(920, 862, 840, 326, "背包与配方物品", "按物品 ID、类型和图集索引裁切原始像素图，未知项明确显示无预览")
item_values = [("Carrot", "胡萝卜"), ("SummerSquash", "西葫芦"),
               ("Broccoli", "西兰花"), ("Powdermelon", "霜瓜"),
               ("Axe", "斧头"), ("Hoe", "锄头"),
               ("Pickaxe", "镐子"), ("Watering Can", "喷壶")]
cell_w, cell_h = 196, 112
for index, (key, label) in enumerate(item_values):
    sample(item(key, by_name=key in {"Axe", "Hoe", "Pickaxe", "Watering Can"}),
           940 + (index % 4) * cell_w, 916 + (index // 4) * cell_h,
           cell_w, cell_h, label)

panel(40, 1216, 840, 334, "建筑、备份与钱包", "建筑按存档类型匹配；钱包条幅用于提示当前正在编辑特殊物品标记")
asset_grid(40, 1216, 840, 334, [
    ("GameUIFarmhouse", "农舍"), ("GameBuildingBarn", "畜棚"),
    ("GameBuildingCoop", "鸡舍"), ("GameBuildingSilo", "筒仓"),
    ("GameBuildingFishPond", "鱼塘"), ("GameUIBackup", "备份箱"),
    ("GameUIWalletStrip", "钱包条幅"),
], 4)

panel(920, 1216, 840, 334, "发型、饰品、墙纸与地板", "直接按游戏编号裁切独立图层；不把单个图层伪装成完整角色")
style_samples = []
for index in (0, 9, 27, 56):
    second = index >= 56
    local = index - 56 if second else index
    x, y = (local % 8) * 16, (local // 8) * (128 if second else 96)
    style_samples.append((texture("GameHair2" if second else "GameHair1", (x, y, x + 16, y + 16)), f"发型 {index}"))
for style in (0, 23):
    x, y = (style % 16) * 16, (style // 16) * 48
    style_samples.append((texture("GameWallsAndFloors", (x, y, x + 16, y + 48)), f"墙纸 {style}"))
for style in (0, 18):
    x, y = (style % 8) * 32, 336 + (style // 8) * 32
    style_samples.append((texture("GameWallsAndFloors", (x, y, x + 32, y + 32)), f"地板 {style}"))
for index, (sprite, label) in enumerate(style_samples):
    sample(sprite, 938 + (index % 4) * 200, 1272 + (index // 4) * 112, 196, 108, label)

text(42, 1592, "素材清单：113 张位图（用户素材库精选 58 张）· 每张记录来源、尺寸与 SHA-256 · 未使用生成图像", 17, muted)
output = root / "游戏素材预览.png"
canvas.save(output)
print(str(output))
