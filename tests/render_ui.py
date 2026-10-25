"""Render production Lua widget positions for layout QA, using placeholder icons.

This is a fixture preview, not an in-game screenshot. No game assets are copied.
"""
import ast
from pathlib import Path
from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
nodes = ast.parse((HERE / "test_zbox.py").read_text()).body
env = {"__file__": str(HERE / "test_zbox.py"), "Path": Path, "LuaRuntime": LuaRuntime}
for node in nodes:
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id in {"ROOT", "FILES", "BOOT"} for t in node.targets):
        exec(compile(ast.Module(body=[node], type_ignores=[]), "fixture", "exec"), env)
    elif isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in {"endpoint", "Pair"}:
        exec(compile(ast.Module(body=[node], type_ignores=[]), "fixture", "exec"), env)

pair = env["Pair"](ui=True)
lua = pair.main
lua.execute('''
UIParent.width=1280;UIParent.height=800
zBox.UI.frame:Show();zBox.UI.setup:Hide()
zBox.db.peer="Zablink"
zBox.cache.status={"status","Zablink","30","MAGE","1240","1500","1860","2200","Forest Spider","0","0","0","Idle","Native inputs 0.1.3"}
local names={"Fireball","Frostbolt","Frost Nova","Frost Armor","Blink","Counterspell","Arcane Missiles","Cone of Cold","Polymorph","Evocation","Conjure Food","Conjure Water"}
for i=1,12 do
 zBox.cache.bar.rows[i]={tostring(i),"Interface\\\\Icons\\\\Spell_Frost_FrostBolt02",names[i],"stamp","0","1","0","0","0","0"}
end
zBox.notice="Drag a skill onto your bars. Keys sets movement bindings."
zBox.UI:Refresh()
zBox.UI.toast:Hide()
''')

SCALE = 2
FONT = Path("C:/Windows/Fonts/segoeui.ttf")
canvas = Image.new("RGB", (1280 * SCALE, 800 * SCALE), "#182024")
draw = ImageDraw.Draw(canvas)
rects = {}


def font(size):
    return ImageFont.truetype(str(FONT), round(size * SCALE))


def color(value, fallback):
    return tuple(round(float(value[i]) * 255) for i in [1, 2, 3]) if value else fallback


def anchor(rect, name):
    x, y, w, h = rect
    return x + (0 if "LEFT" in name else w if "RIGHT" in name else w / 2), y + (0 if "TOP" in name else h if "BOTTOM" in name else h / 2)


def rect(frame):
    key = frame.mockid
    if key in rects:
        return rects[key]
    if frame.name in {"UIParent", "WorldFrame"}:
        result = (0, 0, 1280, 800)
    else:
        size = frame.fontSize or 10
        w = frame.width or 0
        h = frame.height or 0
        if frame.kind == "FontString":
            w = w or draw.textlength(frame.text or "", font=font(size)) / SCALE
            h = h or size + 3
        parent = frame.parent or lua.globals().UIParent
        points = list(frame.points.values())
        def reference(point):
            target = point[2] if point[2] is not None else parent
            target_name = point[3] or point[1]
            ax, ay = anchor(rect(target), target_name)
            return ax + (point[4] or 0), ay - (point[5] or 0)
        if len(points) >= 2 and points[0][1] == "TOPLEFT" and points[1][1] == "BOTTOMRIGHT":
            x, y = reference(points[0]); right, bottom = reference(points[1]);w, h = right-x, bottom-y
        elif points:
            point = points[-1]; ax, ay = reference(point)
            ox, oy = anchor((0, 0, w, h), point[1]);x, y = ax-ox, ay-oy
        else:
            x, y, _, _ = rect(parent)
        result = (x, y, w, h)
    rects[key] = result
    return result


def paint(frame):
    if not frame.shown:
        return
    x, y, w, h = rect(frame)
    box = tuple(round(n * SCALE) for n in (x, y, x+w, y+h))
    if frame.backdrop:
        draw.rounded_rectangle(box, radius=3*SCALE, fill=color(frame.background, (15, 23, 28)), outline=(44, 65, 71), width=SCALE)
    if frame.kind == "Texture":
        if frame.color:
            draw.rectangle(box, fill=color(frame.color, (35, 48, 55)))
        elif frame.texture:
            row = frame.parent.row
            if row and row[2] != "":
                index = int(row[1]); palette = [(111,53,32),(34,83,111),(43,96,101),(55,79,111),(76,56,105)]
                draw.rectangle(box, fill=palette[(index-1) % len(palette)])
                title = "".join(word[0] for word in row[3].split())[:2]
                draw.text((box[0]+6*SCALE, box[1]+6*SCALE), title, font=font(11), fill=(235,235,225))
            else:
                draw.rectangle(box, fill=(25,34,40))
    if frame.kind == "FontString" and frame.text:
        text = str(frame.text)
        lines = []
        words = text.split()
        line = ""
        for word in words:
            next_line = (line + " " + word).strip()
            if line and draw.textlength(next_line, font=font(frame.fontSize or 10)) > w*SCALE:
                lines.append(line);line=word
            else:
                line=next_line
        if line:
            lines.append(line)
        for i, line in enumerate(lines[:max(1, int(h/(frame.fontSize or 10)))]):
            tx = box[0]
            if frame.justify == "RIGHT": tx = box[2]-draw.textlength(line,font=font(frame.fontSize or 10))
            elif frame.justify == "CENTER" or not frame.justify: tx = (box[0]+box[2]-draw.textlength(line,font=font(frame.fontSize or 10)))/2
            draw.text((tx,box[1]+i*(frame.fontSize or 10)*SCALE),line,font=font(frame.fontSize or 10),fill=color(frame.textColor,(214,224,226)))
    children = list(frame.children.values())
    layers = {"BACKGROUND": 0, "ARTWORK": 1, "OVERLAY": 3}
    children.sort(key=lambda child: layers.get(child.layer, 2))
    for child in children:
        paint(child)


out = HERE / "build"
out.mkdir(exist_ok=True)
paint(lua.globals().UIParent)
fx,fy,fw,fh = rect(lua.globals().zBox.UI.frame)
crop = lambda image, x,y,w,h: image.crop(tuple(round(n*SCALE) for n in (x-8,y-8,x+w+8,y+h+8)))
panel_scale = lua.globals().zBox.db.uiScale
def scaled_crop(x,y,w,h):
    image = crop(canvas,x,y,w,h)
    return image.resize((round(image.width*panel_scale),round(image.height*panel_scale)),Image.Resampling.LANCZOS)
scaled_crop(fx,fy,fw,fh).save(out / "compact-preview.png")
lua.execute('zBox.UI:ToggleBrowser()')
rects.clear();canvas.paste("#182024",(0,0,canvas.width,canvas.height));paint(lua.globals().UIParent)
bx,by,bw,bh = rect(lua.globals().zBox.UI.browser)
scaled_crop(bx,by,bw,bh+fh+5).save(out / "browser-preview.png")
print("Saved fixture layout previews (placeholder icons):", out)
