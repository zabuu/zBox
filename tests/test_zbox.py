"""Run two isolated Lua clients through the real zBox transport and handlers.

These are offline behavioral fixtures, not a claim of live-server validation.
Run: python zBox/tests/test_zbox.py
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime
import re
import math
import random
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FILES = ["Core.lua", "NPCGuard.lua", "Protocol.lua", "Damage.lua", "Activity.lua", "Movement.lua", "Casting.lua", "Controls.lua", "Cooldowns.lua", "Mirror.lua", "Stack.lua", "Pet.lua", "Quests.lua", "QuestProgress.lua", "NPC.lua", "QuestTogether.lua", "Agent.lua", "UI.lua", "Views.lua", "NPCWindow.lua"]
BOOT = r'''
clock=10; realm="Private Test"; grouped=true; alive=true; combat=false
getglobal=function(n) return _G[n] end
GetTime=function() return clock end
GetRealmName=function() return realm end
GetNumRaidMembers=function() return 0 end
GetNumPartyMembers=function() return grouped and 1 or 0 end
GetRealZoneText=function() return "Test Zone" end
DEFAULT_CHAT_FRAME={AddMessage=function(self,t) end}
SlashCmdList={}; UISpecialFrames={}; BOOKTYPE_SPELL="spell"
local Frame={}
Frame.__index=function(self,key)
 if Frame[key] then return Frame[key] end
 if string.find(key,"^[A-Z]") then return function() end end
end
function CreateFrame(kind,name,parent,template)
 local f=setmetatable({scripts={},shown=true,text="",width=100,height=100,level=parent and parent.level+1 or 1,parent=parent,name=name,kind=kind,template=template,children={},points={}},Frame)
 if parent then table.insert(parent.children,f) end
 mockSerial=(mockSerial or 0)+1;f.mockid=mockSerial
 if name then _G[name]=f end
 return f
end
function Frame:SetScript(k,fn) self.scripts[k]=fn end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:SetText(t) self.text=tostring(t or "") end
function Frame:GetText() return self.text end
function Frame:GetName() return self.name end
function Frame:SetWidth(n) self.width=n end
function Frame:GetWidth() return self.width end
function Frame:SetHeight(n) self.height=n end
function Frame:GetHeight() return self.height end
function Frame:GetEffectiveScale() return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Frame:GetTop() return self.mockTop end
function Frame:GetBottom() return self.mockBottom end
function Frame:SetScale(value) self.scale=value end
function Frame:GetFrameLevel() return self.level end
function Frame:SetFrameLevel(n) self.level=n end
function Frame:SetParent(parent)
 if self.parent==parent then return end
 if self.parent then for i,child in ipairs(self.parent.children) do if child==self then table.remove(self.parent.children,i);break end end end
 self.parent=parent;table.insert(parent.children,self)
end
function Frame:SetTexCoord(...) self.texcoord={...} end
function Frame:SetVerticalScroll(value) self.verticalScroll=value end
function Frame:GetVerticalScroll() return self.verticalScroll or 0 end
function Frame:SetScrollChild(child) self.scrollChild=child end
function Frame:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
function Frame:SetFrameStrata(value) self.strata=value end
function Frame:EnableMouse(value) self.mouseEnabled=value end
function Frame:Show()
 local change=not self.shown; self.shown=true
 if change and self.scripts.OnShow then local old=this;this=self;self.scripts.OnShow();this=old end
end
function Frame:Hide()
 local change=self.shown; self.shown=false
 if change and self.scripts.OnHide then local old=this;this=self;self.scripts.OnHide();this=old end
end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown end
function Frame:CreateFontString(name,layer) local f=CreateFrame("FontString",name,self);f.width=0;f.height=0;f.layer=layer;return f end
function Frame:CreateTexture(name,layer) local f=CreateFrame("Texture",name,self);f.layer=layer;return f end
function Frame:SetTexture(value,g,b,a) self.texture=value;if type(value)=="number" then self.color={value,g,b,a} end end
function Frame:SetPoint(a,b,c,x,y) self.point={a,b,c,x,y};table.insert(self.points,self.point) end
function Frame:ClearAllPoints() self.points={} end
function Frame:SetFont(path,size) self.fontSize=size end
function Frame:SetBackdrop(value) self.backdrop=value end
function Frame:SetBackdropBorderColor(r,g,b,a) self.borderColor={r,g,b,a} end
function Frame:SetBackdropColor(r,g,b,a) self.background={r,g,b,a} end
function Frame:SetTextColor(r,g,b,a) self.textColor={r,g,b,a or 1} end
function Frame:SetJustifyH(value) self.justify=value end
UIParent=CreateFrame("Frame","UIParent"); WorldFrame=CreateFrame("Frame","WorldFrame")
GetCursorPosition=function() return UIParent.width*UIParent:GetEffectiveScale()*.5,UIParent.height*UIParent:GetEffectiveScale()*.2 end
GameTooltip=CreateFrame("GameTooltip","GameTooltip")
UnitName=function(u) if u=="player" then return ownName elseif u=="party1" then return peerName elseif u=="target" then return "Training Dummy" end end
UnitExists=function(u)
 if u=="player" or u=="party1" then return true,u=="player" and ownGUID or peerGUID end
 if u=="target" or u=="0x0000000000000099" then return true,"0x0000000000000099" end
 return false
end
UnitClass=function() return "Mage","MAGE" end
UnitLevel=function() return 60 end
UnitHealth=function() return 1200 end
UnitHealthMax=function() return 2000 end
UnitMana=function() return 900 end
UnitManaMax=function() return 1500 end
UnitAffectingCombat=function() return combat end
UnitIsDeadOrGhost=function() return not alive end
IsShiftKeyDown=function() return shift or false end
points=5; ranks={[1]=0,[2]=0}
UnitCharacterPoints=function() return points end
GetNumTalentTabs=function() return 3 end
GetNumTalents=function(tab) return 2 end
GetTalentTabInfo=function(tab) return "Tree "..tab,"Icon",0,"Background" end
GetTalentInfo=function(tab,index) return "Talent "..index,"TalentIcon",1,index,ranks[index],5,nil,true end
GetActionInfo=function(slot) return actions and actions[slot] and "spell" or nil,slot end
LearnTalent=function(tab,index) calls[#calls+1]={"LearnTalent",tab,index};ranks[index]=ranks[index]+1;points=points-1 end
GetNumSpellTabs=function() return 1 end
GetSpellTabInfo=function() return "General","Icon",0,2 end
GetSpellName=function(index) if index<=2 then return "Spell "..index,"Rank 1" end end
GetSpellTexture=function(index) return "SpellIcon"..index end
IsPassiveSpell=function(index) return index==2 end
actionText="Test macro"; actions={[1]=true,[2]=true}
GetActionTexture=function(slot) return actions[slot] and "Interface\\Icons\\Spell_Frost_FrostBolt02" or nil end
GetActionText=function(slot) return slot==1 and actionText or nil end
HasAction=function(slot) return actions[slot] end
GetActionCount=function(slot) return 0 end
GetActionCooldown=function(slot) return 0,0,1 end
IsUsableAction=function(slot) return true,false end
IsCurrentAction=function(slot) return false end
IsCurrentSpell=function() return false end
function link(key) return "|cff0070dd|H"..key.."|h[Fixture item]|h|r" end
bags={[0]={[1]="item:100:0:0:0",[2]="item:200:0:0:0"},[1]={},[2]={},[3]={},[4]={}}
gear={[16]="item:300:0:0:0"}; cursor=nil
GetContainerNumSlots=function(bag) return 8 end
GetContainerItemLink=function(bag,slot) return bags[bag][slot] and link(bags[bag][slot]) end
GetContainerItemInfo=function(bag,slot) return bags[bag][slot] and "ItemIcon",1,false,3 end
GetInventoryItemLink=function(u,slot) return gear[slot] and link(gear[slot]) end
GetInventoryItemTexture=function(u,slot) return gear[slot] and "GearIcon" end
CursorHasItem=function() return cursor~=nil end
CursorHasSpell=function() return false end
CursorHasMoney=function() return false end
calls={}; axes={}; px=0;py=0;pz=0;facing=0
function log(name,a,b,c) calls[#calls+1]={name,a,b,c} end
UseAction=function(a,b,c) log("UseAction",a,b,c) end
CastSpell=function(a,b) log("CastSpell",a,b) end
TargetUnit=function(unit) log("TargetUnit",unit) end
ClearTarget=function() log("ClearTarget") end
FollowUnit=function(unit) if unit~="player" then nativeFollowing=true end;log("FollowUnit",unit) end
AssistUnit=function(unit) log("AssistUnit",unit) end
AttackTarget=function() log("AttackTarget") end
nativePostHooks={}
nativeJumpSequence=0
Jump=function(a,b,c)
 log("Jump",a,b,c)
 if not jumpBlocked then nativeJumpSequence=(nativeJumpSequence+1)%4294967296 end
 if nativePostHooks.Jump then nativePostHooks.Jump(a,b,c) end
end
originalNativeJump=Jump
-- Model ClassicAPI's native post-hook: the normal protected path executes
-- first, followed by an isolated observer; the addon never calls Jump itself.
hooksecurefunc=function(name,callback)
 assert(name=="Jump");nativePostHooks[name]=callback
end
SpellStopCasting=function() log("SpellStopCasting") end
SpellStopTargeting=function() log("SpellStopTargeting") end
PickupContainerItem=function(bag,slot) cursor,bags[bag][slot]=bags[bag][slot],cursor;log("PickupContainerItem",bag,slot) end
PickupInventoryItem=function(slot) cursor,gear[slot]=gear[slot],cursor;log("PickupInventoryItem",slot) end
EquipCursorItem=function(slot) cursor,gear[slot]=gear[slot],cursor;log("EquipCursorItem",slot) end
UseContainerItem=function(bag,slot) log("UseContainerItem",bag,slot) end
for _,axis in ipairs({"MoveForward","MoveBackward","TurnLeft","TurnRight","StrafeLeft","StrafeRight"}) do
 local key=axis
 _G[axis.."Start"]=function() axes[key]=true;log(key.."Start") end
 _G[axis.."Stop"]=function() axes[key]=false;log(key.."Stop") end
end
GetPlayerFacing=function() return facing end
zApiTargetCalls=0
zAPI=function(command,unit,y,z,ex,ey,ez)
 if command=="unitPosition" then return px,py,pz end
 if command=="cursorProjection" then return nil end
 if command=="camera" then return 0,0,10,1,0,0,0,-1,0,0,0,1,1.5,1.5 end
 if command=="worldToScreen" then return .5-y/unit*.3,.5+(z-10)/unit*.3,unit end
 if command=="raycast" then
  local t=-z/(ez-z)
  if t>=0 and t<=1 then return 1,unit+(ex-unit)*t,y+(ey-y)*t,0,t end
  return 0
 end
 if command=="setTarget" then zApiTargetCalls=zApiTargetCalls+1;TargetUnit(unit);return 1 end
end
zBoxNative=function(name,a,b,c)
 if name=="capabilities" then return 1,"zBoxBridge 0.1.5",4 end
 if name=="status" then return 1,"Fixture bridge 0.1.5" end
 if name=="StopFollow" then nativeFollowing=false;log("StopFollow");return 1,"Native follow cancelled" end
 if name=="inputs" then
  local mask=0
  for i,axis in ipairs({"MoveForward","MoveBackward","TurnLeft","TurnRight","StrafeLeft","StrafeRight"}) do if axes[axis] then mask=mask+2^(i-1) end end
  return 1,mask,facing,nativeJumpSequence
 end
 if name=="SetHeading" then facing=a;log("SetHeading",a);return 1,"Heading matched" end
 _G[name](a,b,c);return 1,"Requested"
end
function physics(dt)
 if axes.TurnLeft then facing=facing+2.25*dt end
 if axes.TurnRight then facing=facing-2.25*dt end
 if axes.MoveForward then px=px+math.cos(facing)*7*dt;py=py+math.sin(facing)*7*dt end
end
'''


def endpoint(name, peer, ui=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(BOOT)
    lua.globals().ownName = name
    lua.globals().peerName = peer
    lua.globals().ownGUID = "0x0000000000000001" if name == "Main" else "0x0000000000000002"
    lua.globals().peerGUID = "0x0000000000000002" if name == "Main" else "0x0000000000000001"
    for name in FILES if ui else [f for f in FILES if f not in {"UI.lua", "Views.lua", "NPCWindow.lua"}]:
        source = (ROOT / name).read_text(encoding="utf-8")
        lua.compile(source)
        lua.execute(source)
    lua.execute("zBox:Initialize()")
    return lua


class Pair:
    def __init__(self, ui=False):
        self.main = endpoint("Main", "Alt", ui)
        self.alt = endpoint("Alt", "Main", ui)
        self.wire = []
        self.history = []
        self.online = True
        self.time = 10.0
        for src, dst, name in [(self.main, self.alt, "Main"), (self.alt, self.main, "Alt")]:
            def send(prefix, message, channel, src=src, dst=dst, name=name):
                assert len(message.encode()) + len(prefix.encode()) <= 254
                # WoW validates chat escapes even on the addon-message path.
                # A raw packet delimiter such as |t or |k is parsed as markup,
                # so the transport must carry no pipes or raw control bytes.
                assert "|" not in prefix + message, "Invalid escape code in chat message"
                assert all(ord(c) >= 32 and ord(c) != 127 for c in prefix + message), "Raw control byte on the wire"
                self.wire.append((dst, prefix, message, channel, name))
                self.history.append((dst, prefix, message, channel, name))
            src.globals().SendAddonMessage = send
        self.alt.execute('assert(zBox:Configure("agent","Main","testcode123"))')
        self.main.execute('assert(zBox:Configure("control","Alt","testcode123"))')
        self.advance(6)
        assert self.main.globals().zBox.connected and self.alt.globals().zBox.connected

    def deliver(self):
        pending, self.wire = self.wire, []
        for dst, prefix, message, channel, sender in pending:
            if self.online:
                dst.globals().zBox.Receive(dst.globals().zBox, prefix, message, channel, sender)

    def advance(self, seconds, physics=False):
        for _ in range(round(seconds / .05)):
            self.time += .05
            for lua in [self.main, self.alt]:
                lua.globals().clock = self.time
                lua.globals().zBox.Tick(lua.globals().zBox, self.time, .05)
            self.deliver()
            if physics:
                self.alt.globals().physics(.05)

    def command(self, text):
        self.main.execute(text)
        self.advance(.8)


def call_count(lua, name):
    return sum(row[1] == name for _, row in lua.globals().calls.items())


for name in FILES:
    source = (ROOT / name).read_text()
    # Lua 5.0 syntax/API guard in addition to compiling/executing in Lua 5.1.
    assert not re.search(r"(?<!-)\#|\bgoto\b|\bstring\.gmatch\b|\bstring\.match\b|\btable\.unpack\b|\bselect\s*\(", source), name
    assert "loadstring" not in source and "RunScript" not in source, name
print("PASS: all runtime modules compile and avoid newer Lua syntax/APIs and received-code execution")

p = Pair()
p.main.execute('assert(zBox.cache.view and zBox.cache.view.section=="actions" and table.getn(zBox.cache.view.rows)==12)')
assert p.main.globals().zBox.cache.status[2] == "Alt"
print("PASS: isolated clients pair, fragment/reassemble the action bar, and exchange health/power status")

p.main.execute(r'''
-- Encoding must preserve empty fields, markup, percent/caret/tilde text,
-- raw control bytes and nested records without exposing them to chat parsing.
local values={"", "name^with%and~separators", "|cff0070dd|Hitem:100:0:0:0|h[Item]|h|r",
 "tab\tnew\nreturn\r", string.char(0,1,31,127)}
local encoded=zBox:Encode(values)
assert(not string.find(encoded,"[|%c]"))
local decoded=zBox:Decode(encoded)
for i=1,table.getn(values) do assert(decoded[i]==values[i]) end
local nested={zBox:Encode(values),zBox:Encode({"", "nested^|text", "100%"})}
local decodedNested=zBox:Decode(zBox:Encode(nested))
for i=1,table.getn(nested) do assert(decodedNested[i]==nested[i]) end
local packets=zBox:Packets("CHECK",values)
local received=nil
local originalMessage=zBox.Message
zBox.Message=function(self,kind,fields) assert(kind=="CHECK");received=fields end
for i=table.getn(packets),1,-1 do
 assert(not string.find(packets[i],"[|%c]"))
 zBox:Receive(zBox.prefix,packets[i],"PARTY","Alt")
end
zBox.Message=originalMessage
assert(received and table.getn(received)==table.getn(values))
for i=1,table.getn(values) do assert(received[i]==values[i]) end
''')
print("PASS: pipe-free/control-free packets preserve item links, empty fields, nested rows, separators and raw control bytes")

p.command('zBox:Command("ACTION", {1,zBox.cache.view.rows[1][4],zBox:TargetDescriptor()})')
assert call_count(p.alt, "UseAction") == 1
assert call_count(p.main, "UseAction") == 0
assert call_count(p.alt, "TargetUnit") == 1
assert p.alt.globals().zApiTargetCalls == 0, "Casting must not enter zAPI's unsafe GUID target setter"
packet = [x for x in p.history if "~CMD~" in x[2]][-1]
dst, prefix, message, channel, sender = packet
dst.globals().zBox.Receive(dst.globals().zBox, prefix, message, channel, sender)
assert call_count(p.alt, "UseAction") == 1
for spoofed_sender, spoofed_channel, spoofed_message in [
    ("Stranger", channel, message), (sender, "GUILD", message),
    (sender, channel, message.replace("testcode123", "wrongcode12")),
    (sender, channel, "garbage"),
]:
    dst.globals().zBox.Receive(dst.globals().zBox, prefix, spoofed_message, spoofed_channel, spoofed_sender)
assert call_count(p.alt, "UseAction") == 1
p.alt.execute('actionText="Changed"')
p.command('zBox:Command("ACTION", {1,zBox.cache.view.rows[1][4],"KEEP"})')
assert call_count(p.alt, "UseAction") == 1
print("PASS: actions execute only on account 2; spoofed peer/key/channel, replay and stale action slots are rejected")

# Acknowledging a Lua call is not enough: casting must wait for the intended
# GUID to become the actual selected target, and never use zAPI.setTarget.
target_pair = Pair()
target_pair.alt.execute('''
local originalExists=UnitExists
UnitExists=function(unit)
 if unit=="0x0000000000000098" then return true,unit end
 return originalExists(unit)
end
''')
target_pair.command('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"0x0000000000000098"})')
assert call_count(target_pair.alt, "UseAction") == 0
assert "could not select" in target_pair.main.globals().zBox.notice
target_pair.main.execute('zBox:Request("spells",1)')
target_pair.advance(4)
target_pair.command('zBox:Command("SPELL",{1,zBox.cache.view.rows[1][5],"0x0000000000000099"})')
assert call_count(target_pair.alt, "CastSpell") == 1
assert target_pair.alt.globals().zApiTargetCalls == 0
target_pair.alt.execute('TargetUnit=function() error("Fixture: target API failed") end')
target_pair.command('zBox:Command("SPELL",{1,zBox.cache.view.rows[1][5],"0x0000000000000099"})')
assert call_count(target_pair.alt, "CastSpell") == 1
assert "target API failed" in target_pair.main.globals().zBox.notice
print("PASS: action/spell GUID targeting avoids the crash-prone native setter; failed or unconfirmed target switches cannot cast")

# No enemy selection must not block an armor buff before it reaches the client.
buff_pair = Pair()
buff_pair.command('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],""})')
assert call_count(buff_pair.alt, "UseAction") == 1
assert call_count(buff_pair.alt, "ClearTarget") == 1
buff_pair.command('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"SELF"})')
assert call_count(buff_pair.alt, "UseAction") == 2
buff_pair.alt.execute('''
zBox.bridgeInfo=nil
zBoxNative=function(name,a,b,c)
 if name=="capabilities" then return 0,"API or arguments are not allowed" end
 _G[name](a,b,c);return 1,"Requested"
end
''')
buff_pair.command('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"KEEP"})')
buff_pair.command('zBox:Command("AXIS",{"forward","1"})')
assert call_count(buff_pair.alt, "UseAction") == 2
assert call_count(buff_pair.alt, "MoveForwardStart") == 0
assert "restart both clients" in buff_pair.main.globals().zBox.notice
buff_pair.command('zBox:Command("FOLLOW")')
assert buff_pair.alt.eval('calls[#calls][1]=="FollowUnit" and calls[#calls][2]=="party1"')
buff_pair.main.execute('zBox:Slash("diag")')
buff_pair.advance(2)
assert "Bridge update required" in buff_pair.main.globals().zBox.notice
print("PASS: self/untargeted spells reach the client; old bridges reject protected inputs with restart instructions; follow/remote diagnostics remain available")

feedback_pair = Pair()
feedback_pair.alt.execute('''
local originalUse=UseAction
UseAction=function(a,b,c)
 originalUse(a,b,c)
 local savedEvent,savedArg=event,arg1
 event,arg1="SPELLCAST_START","Fireball"
 zBox.frame.scripts.OnEvent()
 event,arg1=savedEvent,savedArg
end
''')
feedback_pair.command('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"KEEP"})')
assert "Casting Fireball" in feedback_pair.main.globals().zBox.notice
feedback_pair.main.execute('zBox:Slash("diag")')
feedback_pair.advance(2)
assert "SPELLCAST_START: Fireball" in feedback_pair.main.globals().zBox.notice
print("PASS: actual client cast events reach the main panel and diagnostics; generic request acknowledgement cannot overwrite newer cast confirmation")

p.main.execute('zBox:Request("bags",1)')
p.advance(5)
p.main.execute('assert(zBox.cache.view.section=="bags");assert(zBox.cache.view.rows[1][8]=="item:100:0:0:0")')
p.command('zBox:Command("EQUIP",{0,1,"item:100:0:0:0",16,"item:300:0:0:0"})')
p.alt.execute('assert(gear[16]=="item:100:0:0:0" and bags[0][1]=="item:300:0:0:0" and not cursor)')
p.command('zBox:Command("EQUIP",{0,1,"item:100:0:0:0",16,"item:100:0:0:0"})')
assert call_count(p.alt, "EquipCursorItem") == 1
p.command('zBox:Command("UNEQUIP",{16,"item:100:0:0:0"})')
p.alt.execute('assert(not gear[16] and bags[0][3]=="item:100:0:0:0" and not cursor)')
p.alt.execute('cursor="item:999:0:0:0"')
p.command('zBox:Command("USEITEM",{0,2,"item:200:0:0:0"})')
assert call_count(p.alt, "UseContainerItem") == 0
p.alt.execute('cursor=nil')
p.command('zBox:Command("USEITEM",{0,2,"item:200:0:0:0"})')
assert call_count(p.alt, "UseContainerItem") == 1
print("PASS: bags round-trip item links; equip swaps old gear back, stale items/cursor conflicts reject, unequip finds an empty backpack slot")

p.main.execute('zBox:Request("talents",1)')
p.advance(5)
p.main.execute('assert(zBox.cache.view.section=="talents" and table.getn(zBox.cache.view.rows)==2)')
p.command('zBox:Command("TALENT",{1,1,0})')
assert p.alt.globals().ranks[1] == 1
p.command('zBox:Command("TALENT",{1,1,0})')
assert p.alt.globals().ranks[1] == 1
p.alt.execute('points=0')
p.command('zBox:Command("TALENT",{1,2,0})')
assert p.alt.globals().ranks[2] == 0
p.main.execute('zBox:Request("spells",1)')
p.advance(4)
p.command('zBox:Command("SPELL",{1,zBox.cache.view.rows[1][5],"SELF"})')
p.command('zBox:Command("SPELL",{2,zBox.cache.view.rows[2][5],"SELF"})')
assert call_count(p.alt, "CastSpell") == 1
print("PASS: talent clicks spend once, stale ranks/no points reject, spellbook supports casting and rejects passive spells")

p = Pair()
p.command('zBox:Command("MOVETO",{10,0,0,"Test Zone"})')
p.advance(4, physics=True)
p.alt.execute('assert(not zBox.destination and px>9 and px<11 and not axes.MoveForward)')
p.alt.execute('px=0;py=0;facing=0')
p.command('zBox:Command("MOVETO",{0,10,0,"Test Zone"})')
p.advance(6, physics=True)
p.alt.execute('assert(not zBox.destination and py>9 and math.abs(px)<1 and not axes.TurnLeft and not axes.TurnRight)')
print("PASS: click-to-move converges on forward and turning destinations and stops its movement axes")

p.alt.execute('px=0;py=0;facing=0')
p.command('zBox:Command("MOVETO",{10,0,0,"Test Zone"})')
p.advance(4)
p.alt.execute('assert(not zBox.destination and not axes.MoveForward)')
p.command('zBox:Command("AXIS",{"forward","1"})')
p.advance(1)
p.alt.execute('assert(not axes.MoveForward)')
p.command('zBox:Command("FOLLOW")')
assert p.alt.globals().zBox.following
p.online = False
p.advance(5)
p.alt.execute('assert(not zBox.connected and not zBox.following and not axes.MoveForward)')
print("PASS: stuck movement, expired held-input lease and lost connection stop the second character")

p = Pair()
p.command('zBox:Command("AXIS",{"forward","1"})')
p.main.execute('for i=1,20 do zBox:Command("JUMP") end;zBox:Command("STOP")')
p.deliver()
p.alt.execute('assert(not axes.MoveForward)')
p.advance(3)
assert call_count(p.alt, "Jump") == 0
print("PASS: emergency stop overtakes queued commands and invalidates older delayed inputs")

p = Pair(ui=True)
p.main.execute('zBox.UI.frame:Show();zBox.UI:Refresh();assert(zBox.UI.cells[1].row)')
p.main.execute('assert(zBox.UI.browser:GetHeight()==193);assert(zBox.UI.frame:GetWidth()==496 and zBox.UI.frame:GetHeight()==110 and zBox.UI.frame.scale==.85)')
p.main.execute('zBox:Request("bags",1)')
p.advance(5)
p.main.execute('zBox.UI:Refresh();zBox.UI:Click(zBox.UI.bagWindows[1].cells[1],"LeftButton");assert(zBox.bagSelection)')
p.main.execute('zBox:Request("gear",1)')
p.advance(5)
p.main.execute('zBox.UI:Refresh();assert(zBox.bagSelection);zBox.UI:Click(zBox.UI.cells[17],"LeftButton")')
p.advance(2)
p.alt.execute('assert(gear[16]=="item:100:0:0:0")')
p.main.execute('zBox.UI:ArmMove();assert(zBox.UI.moveOverlay:IsShown());assert(zBox:CaptureMove());zBox.UI:CancelMove()')
p.advance(1)
assert p.alt.globals().zBox.destination
for section in ["actions", "spells", "bags", "gear", "talents"]:
    p.main.globals().section = section
    p.main.execute('zBox:Request(section,1)')
    p.advance(5)
    p.main.execute('zBox.UI:Refresh();assert(zBox.cache.view.section==section)')
    p.main.execute('''
local contentHeight=zBox.UI.content:GetHeight()
for _,cell in ipairs(zBox.UI.cells) do
 if cell:IsShown() and cell.row then
  assert(-cell.point[5]+cell:GetHeight()<=contentHeight,section.." extends below the browser")
  assert(cell.point[4]+cell:GetWidth()<=472,section.." extends past the browser")
 end
end
''')
print("PASS: all five UI tabs render; bag selection survives the gear-tab switch; click picking sends a world destination")

p.alt.execute('realm="Another Realm"')
before = call_count(p.alt, "Jump")
p.main.execute('zBox:Command("JUMP")')
p.advance(1)
assert call_count(p.alt, "Jump") == before
p.alt.execute('zBox:Slash("off");assert(not zBox.db.enabled and not zBox.connected)')
print("PASS: realm mismatch and explicit revocation reject remote operations")

# A realistic full tree must reassemble while heartbeats/cooldowns are flowing.
p = Pair()
p.alt.execute('''
GetNumTalents=function() return 30 end
GetTalentInfo=function(tab,index)
 return "A full-tree talent "..index,"Interface\\\\Icons\\\\Spell_Frost_FrostBolt02",
 math.floor((index-1)/4)+1,math.mod(index-1,4)+1,0,5,nil,true
end
''')
p.main.execute('zBox:Request("talents",1)')
p.advance(12)
p.main.execute('assert(zBox.connected and zBox.cache.view.section=="talents" and table.getn(zBox.cache.view.rows)==30)')
# Reverse packet delivery and repeat a fragment: a multi-packet request is still one command.
packets, _ = p.main.globals().zBox.Packets(p.main.globals().zBox, "CMD", p.main.table_from(["BOGUS", "x" * 900]))
for _, message in reversed(list(packets.items())):
    p.alt.globals().zBox.Receive(p.alt.globals().zBox, "zBox2", message, "PARTY", "Main")
p.alt.globals().zBox.Receive(p.alt.globals().zBox, "zBox2", packets[1], "PARTY", "Main")
assert p.alt.globals().zBox.connected
# Wrong sessions, invalid sizes, unsupported commands and malformed snapshot rows stay inert.
p.main.execute('''
local before=zBox.cache.view
zBox:AcceptState({"snapshot","talents",1,"bad","bad",3,"bad"})
assert(zBox.cache.view==before)
local ok=zBox:Command("RunScript",{"BAD_REMOTE_CODE"})
assert(ok)
''')
p.advance(1)
assert p.alt.globals().BAD_REMOTE_CODE is None
# A reconnect after both clocks time out negotiates a fresh session.
old_session = p.main.globals().zBox.session
p.online = False
p.advance(5)
p.online = True
p.advance(8)
assert p.main.globals().zBox.connected and p.alt.globals().zBox.connected
assert p.main.globals().zBox.session != old_session
print("PASS: full talent tree, reordered/duplicate fragments, malformed state, rejected code commands and fresh-session reconnection")


# Terrain picking must succeed when the original cursorProjection reports nil.
p = Pair(ui=True)
p.main.execute("zBox.UI.frame:Show(); assert(not zBox.UI.browser:IsShown()); assert(not zBox.UI.pad:IsShown())")
p.main.execute(r"""
local original=zAPI
zAPI=function(command,...)
 if command=="cursorProjection" then error("Cached cursor picking must not run") end
 return original(command,unpack(arg))
end
UIParent.scale=.64; UIParent.width=1920/.64; UIParent.height=1080/.64
local x,y,z=zBox:PickTerrain(); assert(math.abs(x-10)<.001 and math.abs(y)<.001 and z==0)
""")
# A separate projector with skew, cropped viewport, camera yaw/pitch and scaling
# catches sign/FOV/normalization errors rather than copying the inverse formula.
p.main.execute(r"""
function configureTerrain(x,y,z,yaw,pitch,left,bottom,width,height,hf,vf,scale)
 UIParent.width=1920/scale;UIParent.height=1080/scale;UIParent.scale=scale
 local f={math.cos(pitch)*math.cos(yaw),math.cos(pitch)*math.sin(yaw),math.sin(pitch)}
 local r={math.sin(yaw),-math.cos(yaw),0}
 local u={-math.sin(pitch)*math.cos(yaw),-math.sin(pitch)*math.sin(yaw),math.cos(pitch)}
 zAPI=function(command,a,b,c,ex,ey,ez)
  if command=="camera" then return x,y,z,f[1],f[2],f[3],r[1],r[2],r[3],u[1],u[2],u[3],2,1 end
  if command=="worldToScreen" then
   local dx,dy,dz=a-x,b-y,c-z
   local depth=dx*f[1]+dy*f[2]+dz*f[3]
   if depth<=0 then return nil end
   local h=(dx*r[1]+dy*r[2]+dz*r[3])/depth
   local v=(dx*u[1]+dy*u[2]+dz*u[3])/depth
   return left+width*(.5+h*hf+v*.07),bottom+height*(.5+v*vf+h*.03),depth
  end
  if command=="raycast" then
   assert(math.sqrt((ex-a)^2+(ey-b)^2+(ez-c)^2)<250)
   local t=-c/(ez-c)
   if t>=0 and t<=1 then return 1,a+(ex-a)*t,b+(ey-b)*t,0,t end
   return 0
  end
 end
end
""")
rng=random.Random(529)
for i in range(160):
    x,y,z=rng.uniform(-5000,5000),rng.uniform(-5000,5000),rng.uniform(3,25)
    yaw,pitch=rng.uniform(-math.pi,math.pi),rng.uniform(-.7,-.2)
    args=[x,y,z,yaw,pitch,.07,.09,.83,.79,rng.uniform(.25,.6),rng.uniform(.3,.7),rng.uniform(.5,1.5)]
    p.main.globals().configureTerrain(*args)
    distance=rng.uniform(12,55)
    tx=x+math.cos(yaw)*distance+math.sin(yaw)*2
    ty=y+math.sin(yaw)*distance-math.cos(yaw)*2
    sx,sy,_=p.main.globals().zAPI('worldToScreen',tx,ty,0)
    p.main.globals().screenX=sx;p.main.globals().screenY=sy
    p.main.execute('GetCursorPosition=function() return screenX*1920,screenY*1080 end')
    result=p.main.globals().zBox.PickTerrain(p.main.globals().zBox)
    if not (0<=sx<=1 and 0<=sy<=1):
        assert result[0] is None
        continue
    assert len(result)==3,(i,result,sx,sy)
    wx,wy,wz=result
    assert math.dist((wx,wy,wz),(tx,ty,0))<.002,(i,wx,wy,tx,ty)
p.main.execute(r"""
local original=zAPI
zAPI=function(command,...)
 if command=="raycast" then return 0 end
 return original(command,unpack(arg))
end
zBox.UI:ArmMove();this=zBox.UI.moveOverlay;arg1="LeftButton"
zBox.UI.moveOverlay.scripts.OnMouseDown()
assert(zBox.UI.moveOverlay:IsShown() and string.find(zBox.notice,"No ground hit"))
arg1="RightButton";zBox.UI.moveOverlay.scripts.OnMouseDown();assert(not zBox.UI.moveOverlay:IsShown())
zAPI=function() return 0/0 end
local ok,reason=zBox:CaptureMove();assert(not ok and string.find(reason,"Camera picking"))
""")
print("PASS: terrain traces survive a missing cached hit across 160 camera/viewport/UI-scale cases; misses retry without sending a movement command")

# Execute the actual XML bindings, including key-up, with the panel hidden.
p=Pair(ui=True)
bindings={node.attrib['name']:node for node in ET.parse(ROOT/'Bindings.xml').getroot()}
for action,axis in [('FORWARD','MoveForward'),('BACKWARD','MoveBackward'),('LEFT','TurnLeft'),('RIGHT','TurnRight'),('STRAFELEFT','StrafeLeft'),('STRAFERIGHT','StrafeRight')]:
    binding=bindings['ZBOX_'+action]
    assert binding.attrib['runOnUp']=='true'
    p.main.globals().keystate='down';p.main.execute(binding.text);p.advance(.8)
    assert p.alt.globals().axes[axis]
    p.main.globals().keystate='up';p.main.execute(binding.text);p.advance(.3)
    assert not p.alt.globals().axes[axis]
p.main.execute('zBox:HoldDirection("forward",true);zBox:HoldDirection("left",true)')
p.advance(2)
p.alt.execute('assert(axes.MoveForward and axes.TurnLeft)')
p.main.execute('zBox:HoldDirection("left",false)');p.advance(.3)
p.alt.execute('assert(axes.MoveForward and not axes.TurnLeft)')
p.main.execute('zBox:HoldDirection("backward",true)');p.advance(.4)
p.alt.execute('assert(not axes.MoveForward and axes.MoveBackward)')
p.main.execute('zBox:HoldDirection("backward",false)');p.advance(.4)
p.alt.execute('assert(not axes.MoveBackward)')
p.main.execute('zBox:HoldDirection("forward",true)');p.advance(.5)
p.main.execute('zBox.ControlTick=function() end');p.advance(1)
p.alt.execute('assert(not axes.MoveForward)')
print("PASS: real XML key-up bindings, hidden-panel movement, diagonal inputs, opposite-key replacement and abandoned-input leases")

# Follow is cancelled on the controlled client before either cast API runs;
# the controller never calls local movement stop APIs for these requests.
for command in ['ACTION','SPELL']:
    p=Pair()
    p.command('zBox:Command("FOLLOW")')
    assert p.alt.globals().zBox.following
    p.alt.execute('calls={};GetActionInfo=function() return "spell",1 end;GetSpellInfo=function() return "Fireball","Rank 1","Icon",1,false,0,3000 end')
    if command=='ACTION':
        p.command('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"KEEP"})')
    else:
        p.main.execute('zBox:Request("spells",1)');p.advance(3)
        p.command('zBox:Command("SPELL",{1,zBox.cache.view.rows[1][5],"SELF"})')
    names=[row[1] for _,row in p.alt.globals().calls.items()]
    assert names.index('MoveForwardStop')<names.index('UseAction' if command=='ACTION' else 'CastSpell')
    assert not p.alt.globals().zBox.following
    assert call_count(p.main,'MoveForwardStop')==0
print("PASS: action and spell casts stop account 2's follow first, without stopping account 1 or resuming follow during the cast delay")

MACROS=r"""
macros={};cursorMacro=nil;altKey=false;ctrlKey=false;shiftKey=false;bindings={}
IsAltKeyDown=function() return altKey end
IsControlKeyDown=function() return ctrlKey end
IsShiftKeyDown=function() return shiftKey end
GetMacroInfo=function(index) local m=macros[index];if m then return m.name,m.icon,m.body end end
GetMacroIndexByName=function(name) for i,m in pairs(macros) do if m.name==name then return i end end;return 0 end
GetNumMacroIcons=function() return 3 end
GetMacroIconInfo=function(i) return i==2 and "Interface\\Icons\\Spell_Frost_FrostBolt02" or (i==3 and "SpellIcon1" or "Other") end
CreateMacro=function(name,icon,body,localflag,character)
 assert(localflag==nil and character==true and (icon==2 or icon==3))
 for i=19,36 do if not macros[i] then macros[i]={name=name,icon=GetMacroIconInfo(icon),body=body};log("CreateMacro",i);return i end end
 return nil
end
PickupMacro=function(index) cursorMacro=index;log("PickupMacro",index) end
GetCursorInfo=function() if cursorMacro then return "macro",cursorMacro end end
GetBindingKey=function(binding)
 local a,b;for key,value in pairs(bindings) do if value==binding then if not a then a=key else b=key end end end
 return a,b
end
SetBinding=function(key,binding) bindings[key]=binding;return true end
SaveBindings=function(set) assert(set==2);log("SaveBindings") end
GetCurrentBindingSet=function() return 2 end
"""
p=Pair(ui=True);p.main.execute(MACROS)
p.main.execute(r"""
zBox.UI.frame:Show();zBox.UI:Refresh()
this=zBox.UI.dockCells[1];arg1="LeftButton"
this.scripts.OnDragStart();this.scripts.OnClick()
assert(cursorMacro==19 and macros[19].icon==GetActionTexture(1))
assert(macros[19].body=='/script zBox:UseProxy("1")')
assert(zBoxDB.proxies["1"].peer=="Alt")
""")
p.advance(.5)
assert call_count(p.alt,'UseAction')==0
p.main.execute('cursorMacro=nil;zBox:UseProxy("1")');p.advance(.5)
assert call_count(p.alt,'UseAction')==1 and call_count(p.main,'UseAction')==0
p.main.execute('cursorMacro=nil;assert(zBox:PickupRemote("actions",zBox.cache.bar.rows[1]))')
assert call_count(p.main,'CreateMacro')==1
p.alt.execute('actionText="Changed macro"')
p.main.execute('cursorMacro=nil;zBox:UseProxy("1")');p.advance(.5)
assert call_count(p.alt,'UseAction')==1
p.main.execute('zBox:Request("actions",1)');p.advance(3)
p.main.execute('assert(zBox:PickupRemote("actions",zBox.cache.bar.rows[1]));cursorMacro=nil;zBox:UseProxy("1")');p.advance(.5)
assert call_count(p.alt,'UseAction')==2 and call_count(p.main,'CreateMacro')==1
p.main.execute('zBox.db.peer="Different";zBox:UseProxy("1")')
assert 'different paired character' in p.main.globals().zBox.notice
p.main.execute('zBox.db.peer="Alt";cursor="item:999";local ok=zBox:PickupRemote("actions",zBox.cache.bar.rows[1]);assert(not ok);cursor=nil')
p.main.execute('zBox:Initialize()');p.advance(7)
p.main.execute('zBox:UseProxy("1")');p.advance(.5)
assert call_count(p.alt,'UseAction')==3
# Export a spell, reject a passive, and use Alt-self without casting locally.
p.main.execute('zBox:Request("spells",1)');p.advance(3)
p.main.execute('cursorMacro=nil;assert(zBox:PickupRemote("spells",zBox.cache.view.rows[1]));cursorMacro=nil;altKey=true;zBox:UseProxy("2")');p.advance(.5)
assert call_count(p.alt,'CastSpell')==1 and call_count(p.main,'CastSpell')==0
p.main.execute('local ok=zBox:PickupRemote("spells",zBox.cache.view.rows[2]);assert(not ok);altKey=false')
# A full macro bank never edits/deletes an existing macro or picks one up.
full=Pair();full.main.execute(MACROS)
full.main.execute('for i=19,36 do macros[i]={name="Mine"..i,body="/say mine",icon="Other"} end;local ok,why=zBox:PickupRemote("actions",zBox.cache.view.rows[1]);assert(not ok and string.find(why,"macro slot"))')
assert call_count(full.main,'PickupMacro')==0
# Current ClassicAPI's texture-based constructor is also supported.
modern=Pair();modern.main.execute(MACROS)
modern.main.execute(r"""
C_Macro={CreateMacro=function(name,texture,body,character)
 assert(texture==GetActionTexture(1) and character)
 macros[19]={name=name,icon=texture,body=body};return 19
end}
assert(zBox:PickupRemote("actions",zBox.cache.view.rows[1]));assert(cursorMacro==19)
""")
print("PASS: remote macro drag does not cast; legacy and ClassicAPI creation, icon/reuse/persistence, stale-action and peer checks, full banks and occupied cursors")

# Compact strip retains its own live subscription while the browser shows bags.
p=Pair(ui=True)
p.main.execute('zBox.UI.frame:Show();zBox.UI:ToggleBrowser();zBox:Request("bags",1)');p.advance(4)
p.main.execute('assert(zBox.cache.view.section=="bags" and zBox.cache.bar.section=="actions");assert(zBox.UI.dockCells[1].row)')
p.main.execute('zBox.UI:BarPage(1)');p.advance(3)
p.main.execute('assert(zBox.cache.bar.page==2 and zBox.cache.cooldowns.page==2);assert(zBox.cache.view.section=="bags")')
# Bind a modified key, replace a former assignment, cancel, and clear.
p.main.execute(MACROS)
p.main.execute(r"""
bindings.F="ZBOX_FORWARD";bindings.G="ZBOX_FORWARD";bindings["CTRL-H"]="JUMP"
zBox.UI:ShowKeys();zBox.UI.bindingCapture="ZBOX_FORWARD";ctrlKey=true
zBox.UI:CaptureBinding("H");assert(bindings["CTRL-H"]=="ZBOX_FORWARD" and not bindings.F and not bindings.G)
zBox.UI.bindingCapture="ZBOX_FORWARD";zBox.UI:CaptureBinding("ESCAPE");assert(bindings["CTRL-H"]=="ZBOX_FORWARD")
zBox.UI.bindingCapture="ZBOX_FORWARD";zBox.UI:CaptureBinding("BACKSPACE");assert(not bindings["CTRL-H"])
""")
assert call_count(p.main,'SaveBindings')==2
p.main.execute('ctrlKey=true;zBox:HoldDirection("forward",true)');p.advance(.6)
p.alt.execute('assert(axes.MoveForward)')
p.main.execute('ctrlKey=false');p.advance(.4)
p.alt.execute('assert(not axes.MoveForward)')
print("PASS: compact dock, optional browser, independent bar paging/cooldowns and keybinding capture/save/cancel/clear")
