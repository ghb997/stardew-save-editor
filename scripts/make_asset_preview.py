"""Make a contact sheet of bundled game sprites. Requires Pillow; no network.

Usage: python make_asset_preview.py [path-to-CJK-font]
The output is a sprite contact sheet, not an application screenshot.
"""
from pathlib import Path
import json
import sys
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
records = json.loads((root / "GAME_ASSETS_MANIFEST.json").read_text(encoding="utf-8"))
paths = {record["asset"]: root / record["file"] for record in records}
font_candidates = [Path(sys.argv[1])] if len(sys.argv) > 1 else [
    Path("C:/Windows/Fonts/msyh.ttc"), Path("/System/Library/Fonts/PingFang.ttc")]
font_path = next((p for p in font_candidates if p.is_file()), None)
if not font_path:
    raise SystemExit("Provide a Chinese font path as the first argument.")
fonts = {n: ImageFont.truetype(str(font_path), n) for n in (16, 18, 21, 24, 38)}
canvas = Image.new("RGB", (1600, 1220), "#f5f0e3")
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
    value = next(v for v in items if (v["name"] if by_name else v["_key"]) == key
                 and v["_type"] in ("Object", "Tool", "BigCraftable"))
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

def text(x, y, value, size=18, color=ink):
    draw.text((x, y), value, font=fonts[size], fill=color)

def panel(x, y, w, h, title, note):
    draw.rounded_rectangle((x, y, x + w, y + h), radius=18, fill="#fffcf5", outline="#d7ddcf", width=2)
    text(x + 24, y + 17, title, 24)
    text(x + 24, y + h - 28, note, 16, muted)

def sample(sprite, x, y, width, height, title, scale=None):
    if scale is None:
        scale = max(1, min(width // sprite.width, (height - 28) // sprite.height))
    image = sprite.resize((sprite.width * scale, sprite.height * scale), Image.Resampling.NEAREST)
    canvas.paste(image, (x + (width - image.width) // 2, y + (height - 28 - image.height) // 2), image)
    box = draw.textbbox((0, 0), title, font=fonts[18])
    text(x + (width - (box[2] - box[0])) // 2, y + height - 25, title, 18)

draw.rectangle((0, 0, 1600, 116), fill="#284b38")
text(40, 20, "穗光琥珀存档匣 · 游戏素材预览", 38, "#fff7dd")
text(42, 77, "v0.3.2 / build 6     本图仅展示打包的游戏纹理裁切，不是应用运行截图", 18, "#d8e5d2")

panel(40, 144, 740, 378, "人物肖像", "33 位 NPC 原始表情图，本区展示其中 8 位")
for i, (name, zh) in enumerate([("Abigail", "阿比盖尔"), ("Sebastian", "塞巴斯蒂安"), ("Leah", "莉亚"), ("Shane", "谢恩"),
                                 ("Robin", "罗宾"), ("Willy", "威利"), ("Krobus", "科罗布斯"), ("Wizard", "法师")]):
    sample(texture("GamePortrait" + name, (0, 0, 64, 64)), 60 + (i % 4) * 176, 195 + (i // 4) * 144, 170, 140, zh, 1)

panel(820, 144, 740, 378, "1.6 作物与种子", "八种新增安全物品使用原始 Objects_2 图集")
for i, (key, zh) in enumerate([("Carrot", "胡萝卜"), ("SummerSquash", "西葫芦"), ("Broccoli", "西兰花"), ("Powdermelon", "霜瓜"),
                               ("CarrotSeeds", "胡萝卜种子"), ("SummerSquashSeeds", "西葫芦种子"), ("BroccoliSeeds", "西兰花种子"), ("PowdermelonSeeds", "霜瓜种子")]):
    sample(item(key), 840 + (i % 4) * 176, 195 + (i // 4) * 144, 170, 140, zh, 4)

panel(40, 550, 740, 230, "工具菜单图标", "按物品类型和 menuSpriteIndex 选择原图")
for i, (name, zh) in enumerate([("Axe", "斧头"), ("Hoe", "锄头"), ("Pickaxe", "镐子"), ("Watering Can", "喷壶")]):
    sample(item(name, True), 60 + i * 176, 600, 170, 135, zh, 4)

panel(820, 550, 740, 230, "发型与饰品图层", "展示独立原图图层；肤色与完整人物合成尚未覆盖")
for i, index in enumerate([0, 9, 16, 27, 56, 65]):
    second = index >= 56
    local = index - 56 if second else index
    x, y = (local % 8) * 16, (local // 8) * (128 if second else 96)
    sample(texture("GameHair2" if second else "GameHair1", (x, y, x + 16, y + 16)), 836 + i * 90, 610, 88, 118, str(index), 3)
for i, index in enumerate([0, 6]):
    x, y = (index % 8) * 16, (index // 8) * 32
    sample(texture("GameAccessories", (x, y, x + 16, y + 16)), 1376 + i * 82, 610, 80, 118, "饰品 " + str(index), 3)

panel(40, 808, 740, 338, "基础建筑", "展示农舍、畜棚、鸡舍原图；升级版本不套用基础外观")
for i, (asset, box, label) in enumerate([("GameBuildinghouses", (0, 0, 160, 144), "农舍"),
                                        ("GameBuildingBarn", None, "畜棚"), ("GameBuildingCoop", None, "鸡舍")]):
    sample(texture(asset, box), 64 + i * 233, 873, 215, 214, label, 1)

panel(820, 808, 740, 338, "原始墙纸与地板", "直接按游戏编号裁切，保留原始像素与花纹")
for i, style in enumerate([0, 8, 23, 54]):
    x, y = (style % 16) * 16, (style // 16) * 48
    sample(texture("GameWallsAndFloors", (x, y, x + 16, y + 48)), 846 + i * 87, 875, 80, 206, "墙 " + str(style), 3)
for i, style in enumerate([0, 5, 18, 27]):
    x, y = (style % 8) * 32, 336 + (style // 8) * 32
    sample(texture("GameWallsAndFloors", (x, y, x + 32, y + 32)), 1210 + i * 81, 898, 76, 165, "地 " + str(style), 2)

text(42, 1170, "素材来源：colecrouter/stardew-save-editor 等固定提交 · 清单收录 55 张位图及 SHA-256 · 未使用生成图像", 18, muted)
output = root / "游戏素材预览.png"
canvas.save(output)
print(str(output))
