"""Render production Lua widget positions for layout QA, using placeholder icons.

This is a fixture preview, not an in-game screenshot. No game assets are copied.
"""
import ast
import re
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
        if parent.kind == "ScrollFrame":
            y -= parent.verticalScroll or 0
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
    if frame.kind in {"EditBox", "Button"} and frame.template and frame.text:
        draw.rounded_rectangle(box,radius=3*SCALE,fill=(23,32,38),outline=(57,77,82),width=SCALE)
        draw.text((box[0]+7*SCALE,box[1]+4*SCALE),str(frame.text),font=font(10),fill=(223,213,175))
    if frame.kind == "Texture":
        if frame.texture and "UI-QuestGreeting-TopLeft" in str(frame.texture) and (HERE / "build/quest-bg.blp").exists():
            paper = Image.open(HERE / "build/quest-bg.blp").convert("RGB")
            coord = frame.texcoord
            if coord:
                paper = paper.crop((coord[1]*paper.width, coord[3]*paper.height, coord[2]*paper.width, coord[4]*paper.height))
            canvas.paste(paper.resize((max(1,box[2]-box[0]),max(1,box[3]-box[1]))),box[:2])
        elif frame.color:
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
    if frame.kind == "PlayerModel":
        cx=(box[0]+box[2])/2;cy=box[1]+45*SCALE
        draw.ellipse((cx-20*SCALE,cy,cx+20*SCALE,cy+40*SCALE),fill=(79,88,93))
        draw.polygon([(cx-17*SCALE,cy+40*SCALE),(cx-43*SCALE,cy+140*SCALE),(cx+43*SCALE,cy+140*SCALE),(cx+17*SCALE,cy+40*SCALE)],fill=(63,72,78))
        draw.text((cx-58*SCALE,cy+150*SCALE),"Character model in game",font=font(10),fill=(160,165,160))
    if frame.kind == "FontString" and frame.text:
        text = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(frame.text))
        lines = []
        for paragraph in text.split("\n"):
            line = ""
            for word in paragraph.split():
                next_line = (line + " " + word).strip()
                if line and draw.textlength(next_line, font=font(frame.fontSize or 10)) > w*SCALE:
                    lines.append(line);line=word
                else:
                    line=next_line
            lines.append(line)
        for i, line in enumerate(lines[:max(1, int(h/(frame.fontSize or 10)))]):
            tx = box[0]
            if frame.justify == "RIGHT": tx = box[2]-draw.textlength(line,font=font(frame.fontSize or 10))
            elif frame.justify == "CENTER" or not frame.justify: tx = (box[0]+box[2]-draw.textlength(line,font=font(frame.fontSize or 10)))/2
            draw.text((tx,box[1]+i*(frame.fontSize or 10)*SCALE),line,font=font(frame.fontSize or 10),fill=color(frame.textColor,(214,224,226)))
    children = list(frame.children.values())
    layers = {"BACKGROUND": 0, "ARTWORK": 1, "OVERLAY": 3}
    children.sort(key=lambda child: layers.get(child.layer, 2))
    before = canvas.copy() if frame.kind == "ScrollFrame" else None
    for child in children:
        paint(child)
    if before is not None:
        inside=canvas.crop(box);canvas.paste(before);canvas.paste(inside,box[:2])


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
lua.execute('zBox.db.petMovement=true;zBox.UI:Refresh();zBox.UI.toast:Hide()')
rects.clear();canvas.paste("#182024",(0,0,canvas.width,canvas.height));paint(lua.globals().UIParent)
scaled_crop(fx,fy,fw,fh).save(out / "pet-controls-preview.png")
lua.execute('zBox.db.petMovement=false;zBox.UI:Refresh()')
lua.execute('zBox.UI:ToggleBrowser()')
rects.clear();canvas.paste("#182024",(0,0,canvas.width,canvas.height));paint(lua.globals().UIParent)
bx,by,bw,bh = rect(lua.globals().zBox.UI.browser)
scaled_crop(bx,by,bw,bh+fh+5).save(out / "browser-preview.png")
print("Saved fixture layout previews (placeholder icons):", out)

# The larger quest/NPC rows and downward popouts use the production UI too.
features = ast.parse((HERE / "test_features.py").read_text()).body
for node in features:
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id in {"QUESTS", "NPC"} for t in node.targets):
        exec(compile(ast.Module(body=[node], type_ignores=[]), "fixture", "exec"), env)
lua.execute('zBox.db.peer="Alt"')
pair.main.execute(env["QUESTS"])
pair.alt.execute(env["QUESTS"])
pair.main.execute('quests[1][3]="Wolves slain: 5/8";quests[2][1]="Main questline";zBox:Request("quests",1)')
pair.advance(4)
lua.execute('''
zBox.UI.frame:ClearAllPoints();zBox.UI.frame:SetPoint("TOP",UIParent,"TOP",0,-10)
zBox.UI.frame.mockTop=900;zBox.UI.frame.mockBottom=790
zBox.UI.browser:Show();zBox.UI:Refresh();zBox.UI.toast:Hide()
''')
def full_preview(name):
    rects.clear();canvas.paste("#182024",(0,0,canvas.width,canvas.height));paint(lua.globals().UIParent)
    canvas.resize((1280,800),Image.Resampling.LANCZOS).save(out / name)
full_preview("quests-below-preview.png")
pair.alt.execute(env["NPC"])
pair.alt.execute('zBox:NPCEvent("MERCHANT_SHOW")')
lua.execute('zBox:Request("npc",1)');pair.advance(4)
lua.execute('zBox.db.mirrorMovement=true;zBox.mirrorPaused=false;zBox.UI:Refresh();zBox.UI.toast:Hide()')
full_preview("npc-mirror-preview.png")

# A contact sheet for all character views. Models/icons are fixture placeholders;
# the parchment is sampled from the installed client only when available locally.
lua.execute('zBox.UI.frame:ClearAllPoints();zBox.UI.frame:SetPoint("BOTTOM",UIParent,"BOTTOM",0,110);zBox.UI.frame.mockTop=220;zBox.UI.frame.mockBottom=110')
pair.alt.execute(r'''
GetGossipText=function() return "Welcome, traveler.\n\nThe forest grows restless. We need someone brave enough to find out why. Will you lend us your aid?" end
GetBagName=function(bag) return bag==0 and "Backpack" or "Runecloth Bag" end
GetContainerNumSlots=function() return 16 end
GetNumSpellTabs=function() return 1 end
GetSpellTabInfo=function() return "Frost","Icon",0,24 end
GetSpellName=function(i) local names={"Fireball","Frostbolt","Frost Nova","Frost Armor","Blink","Counterspell","Arcane Missiles","Cone of Cold","Polymorph","Evocation","Conjure Food","Conjure Water"};return names[(i-1)%12+1],"Rank "..math.ceil(i/12) end
GetNumTalents=function() return 28 end
GetTalentInfo=function(tab,i) return "Talent "..i,"TalentIcon",math.ceil(i/4),(i-1)%4+1,(i%3==0 and 5 or 0),5,nil,true end
''')
previews=[]
for section in ["gear","bags","spells","talents","quests","npc"]:
    if section=="npc": pair.alt.execute('zBox:NPCEvent("GOSSIP_SHOW")')
    lua.execute(f'zBox:Request("{section}",1)');pair.advance(6)
    if section=="bags":
        lua.execute('zBox.UI:ToggleBag(2)');pair.advance(4)
    lua.execute('zBox.UI.browser:Show();zBox.UI:Refresh();zBox.UI.toast:Hide()')
    rects.clear();canvas.paste("#182024",(0,0,canvas.width,canvas.height));paint(lua.globals().UIParent)
    bx,by,bw,bh=rect(lua.globals().zBox.UI.browser)
    preview=crop(canvas,bx,by,bw,bh).resize((504,round(bh+16)),Image.Resampling.LANCZOS)
    preview.save(out/f'{section}-character-preview.png')
    previews.append((section,preview))
sheet=Image.new('RGB',(3*524,2*560),'#182024')
for i,(section,preview) in enumerate(previews):
    sheet.paste(preview,(10+(i%3)*524,32+(i//3)*560))
    ImageDraw.Draw(sheet).text((18+(i%3)*524,8+(i//3)*560),section.title(),font=ImageFont.truetype(str(FONT),16),fill='#d6ccac')
sheet.save(out/'character-views-preview.png')
print('Saved character-view contact sheet:',out/'character-views-preview.png')
lua.execute('zBox.UI:Minimize()')
rects.clear();canvas.paste("#182024",(0,0,canvas.width,canvas.height));paint(lua.globals().UIParent)
mx,my,mw,mh=rect(lua.globals().zBox.UI.restoreButton)
scaled_crop(mx,my,mw,mh).save(out/'minimized-preview.png')

# Production roster and trade widgets; icons/dialogue skins are placeholders.
lua.execute('''
zBox.UI:Restore();zBox.UI:ShowSetup();zBox.UI:SetFollowerRows({"Zablink","Fridgey","Zabmage"});zBox.UI.npcWindow:Hide()
''')
rects.clear();canvas.paste("#182024",(0,0,canvas.width,canvas.height));paint(lua.globals().UIParent)
sx,sy,sw,sh=rect(lua.globals().zBox.UI.setup)
crop(canvas,sx,sy,sw,sh).resize((466,round(sh+16)),Image.Resampling.LANCZOS).save(out/'roster-setup-preview.png')
lua.execute('''
zBox.UI.setup:Hide();zBox:CreateTradePreview()
zBox.cache.trade={fields={"trade","preview","0x0000000000000004","Fridgey",12345,5000,"0","1","","preview"},rows={},at=GetTime()}
for i=1,14 do zBox.cache.trade.rows[i]={i<=7 and "1" or "2",tostring((i-1)%7+1),i==1 and "Runecloth" or (i==8 and "Greater Healing Potion" or ""),"ItemIcon",i==1 and "20" or "1","",""} end
zBox:TradeTick(GetTime())
''')
rects.clear();canvas.paste("#182024",(0,0,canvas.width,canvas.height));paint(lua.globals().UIParent)
tx,ty,tw,th=rect(lua.globals().zBox.tradeUI)
crop(canvas,tx,ty,tw,th).resize((386,426),Image.Resampling.LANCZOS).save(out/'trade-preview.png')
