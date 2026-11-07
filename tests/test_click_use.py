"""Click-to-use: Move-mode click on a friendly NPC makes the follower walk up and talk to it."""
import sys
sys.argv = sys.argv[:1]
from test_zbox import Pair

NPC = '0x00000000000000AB'
p = Pair()
for lua in (p.main, p.alt):
    lua.execute('''
npcGUID="0x00000000000000AB";npcX,npcY,npcZ=20,0,0;hovered=nil;selectedGUID=nil;talked={}
local exists=UnitExists
UnitExists=function(u)
 if u=="mouseover" then return hovered~=nil,hovered end
 if u=="target" and selectedGUID then return true,selectedGUID end
 if u==npcGUID then return true,u end
 return exists(u)
end
UnitIsPlayer=function(u) return not (u==npcGUID or ((u=="target" and selectedGUID==npcGUID) or (u=="mouseover" and hovered==npcGUID))) end
UnitCanAttack=function() return false end
UnitIsDeadOrGhost=function() return false end
UnitAffectingCombat=function() return false end
UnitName=function(u) if u=="target" and selectedGUID==npcGUID then return "Innkeeper" end;if u=="player" then return ownName end;return peerName end
TargetUnit=function(u) selectedGUID=u;log("TargetUnit",u) end
InteractNPC=function(g) table.insert(talked,g) end
local api=zAPI
zAPI=function(command,unit,a,b,c,d,e)
 if command=="unitPosition" and unit=="target" and selectedGUID==npcGUID then return npcX,npcY,npcZ end
 return api(command,unit,a,b,c,d,e)
end
''')
p.alt.execute('px,py,pz,facing=0,0,0,0;zBox.bridgeInfo=nil')
p.alt.execute('local g=zBox.GetBridgeInfo;zBox.GetBridgeInfo=function(self) local i=g(self);i.npc=true;i.nativeMove=nil;return i end')

# Hovered NPC: the follower targets it, walks over and talks once in range.
p.main.execute('hovered=npcGUID;local ok,why=zBox:CaptureMoveOrUse();assert(ok,why)')
p.advance(.5)
alt = p.alt.globals()
assert alt.zBox.useTarget and alt.zBox.destination, 'walking to the NPC'
assert len(alt.talked) == 0, 'not yet in range'
p.advance(5, physics=True)
assert len(alt.talked) == 1 and alt.talked[1] == NPC, list(alt.talked.values())
assert not alt.zBox.useTarget and not alt.zBox.destination
print('PASS: clicking a hovered friendly NPC walks the follower over and talks to it on arrival')

# Already in range: talks straight away.
p.alt.execute('talked={}')
p.main.execute('assert(zBox:CaptureMoveOrUse())')
p.advance(.5)
assert len(alt.talked) == 1
print('PASS: an NPC already in range is talked to immediately')

# Another order cancels the pending talk.
p.alt.execute('talked={};px,py=0,0;selectedGUID=nil')
p.main.execute('assert(zBox:CaptureMoveOrUse())')
p.advance(.5)
assert alt.zBox.useTarget
p.main.execute('zBox:Command("STOP")')
p.advance(.5)
assert not alt.zBox.useTarget
p.advance(5, physics=True)
assert len(alt.talked) == 0, 'stopped: no talk'
print('PASS: Stop or a new order cancels the walk-and-talk')

# Hostile or player under the cursor: falls back to a normal ground move.
p.main.execute('hovered=nil;selectedGUID=nil;assert(zBox:PickUseTarget()==nil)')
p.main.execute('UnitCanAttack=function() return true end;hovered=npcGUID;assert(zBox:PickUseTarget()==nil);UnitCanAttack=function() return false end;hovered=nil')
# Targeted NPC plus a ground click right next to it counts as clicking it.
p.main.execute('selectedGUID=npcGUID;assert(zBox:PickUseTarget(21,1,0)==npcGUID);assert(zBox:PickUseTarget(40,0,0)==nil)')
print('PASS: hostile units and players are ignored; a ground click beside your targeted NPC also counts')

# The picker lets the mouse through to the world (so NPC hover still works) and
# reads quick clicks by polling the mouse buttons; drags and UI clicks are ignored.
q = Pair(ui=True)
q.main.execute('''
buttons={};IsMouseButtonDown=function(b) return buttons[b] end
focusFrame=nil;GetMouseFocus=function() return focusFrame end
cx,cy=500,300;GetCursorPosition=function() return cx,cy end
local u=zBox.UI;u:CreateMoveOverlay();local f=u.moveOverlay
assert(not f.mouseEnabled,"pass-through picker must not catch the mouse")
picked=0;zBox.CaptureMoveOrUse=function() picked=picked+1;return true end
local function step(t) clock=clock+t;GetTime=function() return clock end;f.scripts.OnUpdate() end
GetTime=function() return clock end
u:ArmMove();assert(f:IsShown());f.scripts.OnShow()
buttons.LeftButton=true;step(.05);cx=560;step(.3);buttons.LeftButton=false;step(.05)
assert(picked==0 and f:IsShown(),"a camera drag is not a click")
cx=500;focusFrame={};buttons.LeftButton=true;step(.05);buttons.LeftButton=false;step(.05)
assert(picked==0 and f:IsShown(),"clicks on UI frames are ignored")
focusFrame=nil;buttons.LeftButton=true;step(.05);buttons.LeftButton=false;step(.05)
assert(picked==1 and not f:IsShown(),"a quick world click picks and closes")
u:ArmMove();f.scripts.OnShow();buttons.RightButton=true;step(.05);buttons.RightButton=false;step(.05)
assert(picked==1 and not f:IsShown(),"right-click cancels")
''')
print('PASS: the Move picker passes the mouse through to the world; quick clicks pick, drags and UI clicks do not, right-click cancels')

# Ground reticle: drawn on the exact point the click would pick, in perspective.
q.main.execute('''
local u=zBox.UI;local f=u.moveOverlay;local r=assert(u.reticle,"reticle exists")
GetCursorPosition=function() return UIParent.width*UIParent:GetEffectiveScale()*.5,UIParent.height*UIParent:GetEffectiveScale()*.2 end
hovered=nil;UnitExists=function(unit) if unit=="mouseover" then return false end;return true end
u:ArmMove();f.scripts.OnShow();clock=clock+1;f.scripts.OnUpdate()
assert(r.target,"ground point found")
local x,y,z=zBox:PickTerrain()
assert(math.abs(r.target.x-x)<1e-6 and math.abs(r.target.y-y)<1e-6,"reticle sits on the picked point")
local centre=r.dots[table.getn(r.dots)];assert(centre:IsShown())
local shown=0;for _,t in ipairs(r.dots) do if t:IsShown() then shown=shown+1 end end
assert(shown>=15,"ring drawn: "..shown)
GetCursorPosition=function() return -50,-50 end;clock=clock+1;f.scripts.OnUpdate()
assert(not r.target and not centre:IsShown(),"hidden off-screen / no hit")
u:CancelMove()
''')
print('PASS: the Move picker draws a perspective ground ring on the exact point a click would pick, and hides it with no hit')

# Game objects (bridge 0.1.12, contract 11): hovered object -> walk over and right-click it.
OBJ = '0xF11000000000ABCD'
for lua in (p.main, p.alt):
    lua.execute('''
objectHover=nil;objX,objY,objZ=15,5,0;used={}
local native=zBoxNative
zBoxNative=function(name,a,b,c)
 if name=="capabilities" then return 1,"zBoxBridge 0.1.12",11,1 end
 if name=="MouseoverObject" then if objectHover then return 1,objectHover,objX,objY,objZ end;return 0,"No game object under the cursor" end
 if name=="InteractObject" then table.insert(used,a);return 1,"Object use requested" end
 return native(name,a,b,c)
end
zBox.bridgeInfo=nil
local g=zBox.GetBridgeInfo
zBox.GetBridgeInfo=function(self) local i=g(self);i.npc=true;i.nativeMove=nil;i.directWhisper=nil;i.localIPC=nil;i.multiLocal=nil;return i end -- fixture transport is addon messages
''')
p.main.execute('assert(zBox:GetBridgeInfo().objects and zBox:GetBridgeInfo().jumpEvents)')
p.alt.execute('px,py,pz,facing=0,0,0,0;selectedGUID=nil;used={}')
p.main.execute(f'hovered=nil;selectedGUID=nil;objectHover="{OBJ}";local ok,why=zBox:CaptureMoveOrUse();assert(ok,why)')
p.advance(.5)
alt = p.alt.globals()
assert alt.zBox.useTarget and alt.zBox.useTarget.object, 'walking to the object'
p.advance(5, physics=True)
assert len(alt.used) == 1 and alt.used[1] == OBJ, list(alt.used.values())
assert not alt.zBox.destination
print('PASS: a hovered chest/herb (bridge 0.1.12) walks the follower over and right-clicks it once in range')
# A lookup far from the clicked ground point is not trusted.
p.main.execute('objX,objY=90,90;assert(zBox:PickUseObject(15,5,0)==nil);objX,objY=15,5;assert(zBox:PickUseObject(15,5,0))')
# Old bridges: no object support, falls back to a ground move.
p.main.execute('zBox.bridgeInfo=nil;local n=zBoxNative;zBoxNative=function(name,...) if name=="capabilities" then return 1,"zBoxBridge 0.1.11",10 end;return n(name,unpack(arg)) end;assert(not zBox:GetBridgeInfo().objects and zBox:PickUseObject()==nil)')
p.main.execute('zBox.bridgeInfo=nil;zBoxNative=function(name) if name=="capabilities" then return 1,"zBoxBridge 0.1.12",11,0 end end;local i=zBox:GetBridgeInfo();assert(i.objects and not i.jumpEvents and i.jumpObserverFailed and i.trade)')
print('PASS: object lookups far from the click are ignored; older bridges fall back to ground moves; contract 11 reports a failed jump hook without disabling the rest')

# Walking to an NPC opens the Talk window on the main, like the Talk button.
src = open(__import__('pathlib').Path(__file__).resolve().parents[1] / 'Use.lua', encoding='utf-8').read()
q.main.execute(src)
q.main.execute('''
local B=zBox
B.PickUseTarget=function() return "0x00000000000000AB" end
sent=nil;B.Command=function(self,c,f) sent=c;return true end
assert(B:CaptureMoveOrUse());assert(sent=="WALKUSE")
assert(B.UI.npcWindow and B.UI.npcWindow:IsShown(),"Talk window opens")
''')
print('PASS: walking up to an NPC opens the Talk window on the main')

# Bridge 0.1.13: no mouseover object, but a click within 3 yards of one uses the nearest.
p.main.execute('''
zBox.bridgeInfo=nil
zBoxNative=function(name,a,b,c,d)
 if name=="capabilities" then return 1,"zBoxBridge 0.1.13",12,1 end
 if name=="MouseoverObject" then return 0,"No game object under the cursor" end
 if name=="NearestObject" then
  assert(d==3)
  if (a-15)^2+(b-5)^2<=d*d then return 1,"0xF11000000000ABCD",15,5,0 end
  return 0,"No game object near that point"
 end
end
local i=zBox:GetBridgeInfo();assert(i.objects and i.nearestObjects)
assert(zBox:PickUseObject(16,6,0)=="0xF11000000000ABCD","click beside the chest uses it")
assert(zBox:PickUseObject(30,30,0)==nil,"click elsewhere is a plain move")
assert(zBox:PickUseObject()==nil,"no click point, no search")
''')
print('PASS: bridge 0.1.13 picks the game object nearest a ground click (within 3 yards) when the cursor lookup finds nothing')
