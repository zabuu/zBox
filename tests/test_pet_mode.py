"""Native point movement and explicitly commanded pet-style account control."""
from test_linked_controls import Pair, call_count
from test_zbox import MACROS
import math

WORLD = r'''
enemyGUID="0x0000000000000099";otherGUID="0x0000000000000098"
enemies={[enemyGUID]={x=12,y=0,z=0,facing=0},[otherGUID]={x=22,y=0,z=0,facing=0}}
mainTarget=enemyGUID;selectedGUID=enemyGUID
mainCombat=false;ownCombat=false
local exists=UnitExists
UnitExists=function(unit)
 if unit=="target" then return enemies[selectedGUID] and true,selectedGUID end
 if unit=="party1target" then return enemies[mainTarget] and true,mainTarget end
 if enemies[unit] then return true,unit end
 return exists(unit)
end
UnitCanAttack=function(player,unit)
 local e=enemies[unit=="target" and selectedGUID or unit]
 return e and not e.friendly and not e.dead
end
UnitIsDeadOrGhost=function(unit)
 if unit=="player" then return not alive end
 local e=enemies[unit=="target" and selectedGUID or unit]
 return e and e.dead or false
end
UnitAffectingCombat=function(unit) return unit=="player" and ownCombat or (unit=="party1" and mainCombat or false) end
TargetUnit=function(unit) if enemies[unit] then selectedGUID=unit end;log("TargetUnit",unit) end
StartAttack=function() attacking=true;log("StartAttack") end
StopAttack=function() attacking=false;log("StopAttack") end
CastSpellNoToggle=function(id) assert(id==75);shooting=true;log("AutoShot",id) end
GetSpellInfo=function(id) if id==75 then return "Auto Shot" end;return "Fireball","Rank 1","Icon",1,false,0,3000 end
local stopCast=SpellStopCasting
SpellStopCasting=function() shooting=false;stopCast() end
local api=zAPI
zAPI=function(command,unit,y,z,ex,ey,ez)
 if command=="unitPosition" then
  if unit=="player" then return px,py,pz end
  if unit=="party1" then return -5,0,0 end
  local e=enemies[unit=="target" and selectedGUID or unit]
  if e then return e.x,e.y,e.z end
 end
 if command=="raycast" then
  if z>0 and ez<=0 then
   local t=-z/(ez-z);return 1,unit+(ex-unit)*t,y+(ey-y)*t,0,t
  end
  return blocked and 1 or 0
 end
 return api(command,unit,y,z,ex,ey,ez)
end
local native=zBoxNative
zBoxNative=function(command,a,b,c)
 if command=="capabilities" then return 1,"zBoxBridge 0.1.6",5 end
 if command=="MoveTo" then
  log("MoveTo",a,b,c)
  if rejectMove then return 0,"Rejected" end
  nativePoint={x=a,y=b,z=c};nativeMoveState=4;return 1,"Native move"
 end
 if command=="MoveState" then return 1,nativeMoveState or 12 end
 if command=="StopFollow" then nativePoint=nil;nativeMoveState=12 end
 if command=="CombatGeometry" then
  local e=enemies[a]
  if not e or e.missing then return 0,"Missing geometry" end
  return 1,e.x,e.y,e.z,e.facing,px,py,pz,3
 end
 return native(command,a,b,c)
end
zBox.bridgeInfo=nil
local normalPhysics=physics
physics=function(dt)
 if nativePoint then
  if stalledNative then return end
  local dx,dy=nativePoint.x-px,nativePoint.y-py
  local distance=math.sqrt(dx*dx+dy*dy)
  if distance<=1.25 then nativePoint=nil;nativeMoveState=12
  else
   local travel=math.min(7*dt,distance-1.25)
   px=px+dx/distance*travel;py=py+dy/distance*travel
  end
 else normalPhysics(dt) end
end
'''

def pet_pair(ui=False, kind='WARRIOR'):
    p=Pair(ui=ui)
    for client in (p.main,p.alt): client.execute(WORLD)
    p.alt.execute(f'UnitClass=function() return "{kind}","{kind}" end')
    return p

# The native ground cursor wins only when the actual projected hit matches the
# UI/OS cursor. Missing/misaligned native hits retain the calibrated ray path.
p=pet_pair()
p.main.execute('''
local api=zAPI
zAPI=function(command,...)
 if command=="cursorProjection" then return 3257869999,.5,.2,.5,.2,12,34,0,15 end
 return api(command,unpack(arg))
end
local x,y,z=zBox:PickTerrain();assert(x==12 and y==34 and z==0 and zBox.lastPickMethod=="Native ground cursor")
zAPI=function(command,...)
 if command=="cursorProjection" then return 123,.7,.8,.7,.8,99,99,0,15 end
 return api(command,unpack(arg))
end
local x,y,z=zBox:PickTerrain();assert(x~=99 and zBox.lastPickMethod=="Calibrated terrain ray")
''')
p.command('zBox:Command("MOVETO",{10,0,0,"Test Zone"})')
p.advance(2,physics=True)
p.alt.execute('assert(math.abs(px-10)<.4 and not zBox.destination and not nativePoint and not axes.MoveForward)')
assert call_count(p.alt,'MoveTo')==1
# A native engine that never starts (including old high-FPS behavior) yields to
# precise input steering without changing framerate/CVars/client constants.
p=pet_pair()
p.alt.execute('stalledNative=true')
p.command('zBox:Command("MOVETO",{10,0,0,"Test Zone"})')
p.advance(3.5,physics=True)
p.alt.execute('assert(math.abs(px-10)<.4 and not zBox.destination and not nativePoint)')

# Precombat melee attack goes around the front to the rear before starting.
p=pet_pair(ui=True)
p.alt.execute('enemies[enemyGUID].facing=math.pi')
p.main.execute('assert(zBox:SetMovementMode("pet"));assert(zBox.UI.petAttack.shown and zBox.UI.petAssist.shown);assert(zBox:AttackCommand())')
p.advance(3.8,physics=True)
p.alt.execute('assert(attacking and px>enemies[enemyGUID].x+1 and zBox.petState.guid==enemyGUID)')
assert call_count(p.alt,'MoveTo')>=2
assert call_count(p.main,'StartAttack')==0
p.alt.execute('mainCombat=true;ownCombat=true');p.advance(.3)
p.alt.execute('mainCombat=false;ownCombat=false');p.advance(1)
p.alt.execute('assert(zBox.following and zBox.petState and not zBox.petState.guid and not attacking)')

# Assist stays armed but cannot pick a fresh idle target. It switches to the
# main's target during combat, then returns to Follow after both leave combat.
p=pet_pair()
p.main.execute('assert(zBox:SetMovementMode("pet"));ClearTarget();selectedGUID="";assert(zBox:PetOrder("assist"))')
p.advance(.8)
p.alt.execute('assert(zBox.petState.mode=="assist" and not zBox.petState.guid and zBox.following);mainCombat=true')
p.advance(3,physics=True)
p.alt.execute('assert(zBox.petState.guid==enemyGUID and attacking);mainTarget=otherGUID')
p.advance(2,physics=True)
p.alt.execute('assert(zBox.petState.guid==otherGUID and attacking);mainCombat=false;ownCombat=false')
p.advance(1)
p.alt.execute('assert(zBox.following and zBox.petState.mode=="assist" and not zBox.petState.guid and not attacking)')
p.main.execute('assert(zBox:PetOrder("follow"))');p.advance(.7)
p.alt.execute('mainCombat=true');p.advance(1)
p.alt.execute('assert(zBox.petState.mode=="follow" and not zBox.petState.guid)')

# Casters hold range, face the target, and never choose a spell automatically.
p=pet_pair(kind='MAGE')
p.alt.execute('enemies[enemyGUID].x=40')
p.main.execute('assert(zBox:AttackCommand())');p.advance(3.5,physics=True)
p.alt.execute('assert(zBox.petState.style=="ranged" and enemies[enemyGUID].x-px<=26 and enemies[enemyGUID].x-px>=23)')
assert call_count(p.alt,'UseAction')==0 and call_count(p.alt,'CastSpell')==0 and call_count(p.alt,'StartAttack')==0
# A remote cast stops pet movement and owns facing until the real end event.
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],enemyGUID})');p.advance(.4)
p.alt.execute('zBox:CastEvent("SPELLCAST_START",3000);mainCombat=true;ownCombat=true;assert(not zBox.destination)')
p.advance(4)
p.alt.execute('assert(zBox.castActive and zBox.petState);zBox:CastEvent("SPELLCAST_STOP")')
p.advance(.5)
p.alt.execute('mainCombat=false;ownCombat=false');p.advance(1)
p.alt.execute('assert(zBox.following and not zBox.petState.guid)')

# Hunters start the native non-toggling Auto Shot and stop it on explicit recall.
p=pet_pair(kind='HUNTER')
p.alt.execute('GetSpellName=function(i) return i==1 and "Auto Shot" or "Other", "" end')
p.main.execute('assert(zBox:AttackCommand())');p.advance(1)
p.alt.execute('assert(shooting and zBox.petState.style=="hunter")')
assert call_count(p.alt,'AutoShot')>=1 and call_count(p.alt,'StartAttack')==0
p.main.execute('assert(zBox:PetOrder("follow"))');p.advance(.8)
p.alt.execute('assert(not shooting and zBox.following and not zBox.petState.guid)')

# STOP/manual movement disconnects autonomous movement. Invalid/friendly targets
# and blocked ground cannot authorize an attack or leave a running move behind.
for command in ('zBox:Command("STOP")','zBox:Command("AXES",{1})'):
    p=pet_pair();p.main.execute('assert(zBox:AttackCommand())');p.advance(.5)
    p.main.execute(command);p.advance(.4)
    p.alt.execute('assert(not zBox.petState)')
p=pet_pair();p.alt.execute('enemies[enemyGUID].friendly=true')
p.main.execute('assert(zBox:AttackCommand())');p.advance(1)
p.alt.execute('assert(not zBox.petState and not nativePoint and not attacking)')
p=pet_pair();p.alt.execute('blocked=true')
p.main.execute('assert(zBox:AttackCommand())');p.advance(1)
p.alt.execute('assert(zBox.following and not zBox.petState.guid and not nativePoint and not attacking)')
p=pet_pair();p.main.execute('assert(zBox:AttackCommand())');p.advance(.5)
p.alt.execute('zBox:Disconnect();assert(not zBox.petState and not nativePoint)')
print('PASS: native cursor validation, native movement/final correction/stall fallback, precombat rear melee attack, armed Assist/target switching, combat-end follow, manual caster control, hunter Auto Shot and emergency/manual/disconnect/geometry safeguards')

# Export each control without issuing an order. The generated macro remains
# paired to its character/realm; pet macros select Pet even after a mode change.
p=pet_pair(ui=True);p.main.execute(MACROS)
p.main.execute(r'''
C_Macro={CreateMacro=function(name,texture,body,character)
 assert(character and string.find(texture,"Interface\\Icons\\"))
 for i=19,36 do
  if not macros[i] then macros[i]={name=name,icon=texture,body=body};log("CreateMacro",i);return i end
 end
end}
assert(zBox:SetMovementMode("pet"))
''');p.advance(.5)
p.main.execute(r'''
local u=zBox.UI
for _,control in ipairs({u.followButton,u.petAssist,u.petAttack,u.moveButton,u.stopButton}) do
 this=control;arg1="LeftButton";this.scripts.OnDragStart();this.scripts.OnClick()
 assert(cursorMacro);cursorMacro=nil
 this.scripts.OnDragStop();this.scripts.OnClick()
end
assert(zBoxDB.proxies["1"].slot=="petfollow" and zBoxDB.proxies["2"].slot=="petassist")
assert(zBoxDB.proxies["3"].slot=="petattack" and zBoxDB.proxies["4"].slot=="move" and zBoxDB.proxies["5"].slot=="stop")
assert(not u.moveOverlay.shown)
''');p.advance(.5)
p.alt.execute('assert(not zBox.petState and not zBox.following and not attacking)')
assert call_count(p.main,'CreateMacro')==5
p.main.execute('this=zBox.UI.petAttack;arg1="LeftButton";shiftKey=true;this.scripts.OnClick();assert(cursorMacro==21);cursorMacro=nil;shiftKey=false')
assert call_count(p.main,'CreateMacro')==5
p.main.execute('assert(zBox:SetMovementMode("follow"));zBox:UseProxy("3")');p.advance(3.5,physics=True)
p.main.execute('assert(zBox:MovementMode()=="pet")')
p.alt.execute('assert(attacking and zBox.petState.guid==enemyGUID)')
p.main.execute('zBox:UseProxy("1")');p.advance(.6)
p.alt.execute('assert(zBox.following and not attacking and zBox.petState.mode=="follow")')
p.main.execute('ClearTarget();selectedGUID="";zBox:UseProxy("2")');p.advance(.6)
p.alt.execute('assert(zBox.petState.mode=="assist" and zBox.following)')
p.main.execute('zBox:UseProxy("4");assert(zBox.UI.moveOverlay.shown);zBox.UI:CancelMove();zBox:UseProxy("5")');p.advance(.5)
p.alt.execute('assert(not zBox.petState and not zBox.following and not nativePoint)')
p.main.execute('zBox.db.peer="Different";zBox:UseProxy("1");assert(string.find(zBox.notice,"different paired character"));zBox.db.peer="Alt"')
p.main.execute('zBox.db.proxies["1"].realm="Other realm";zBox:UseProxy("1");assert(string.find(zBox.notice,"different paired character"))')
p=pet_pair();p.main.execute('zBox:Slash("pet follow")');p.advance(.5)
p.alt.execute('assert(zBox.following and zBox.petState.mode=="follow")')
p.main.execute('zBox:Slash("pet assist")');p.advance(.5)
p.alt.execute('assert(zBox.petState.mode=="assist" and zBox.petState.guid==enemyGUID)')
p.main.execute('zBox:Slash("pet attack")');p.advance(.5)
p.alt.execute('assert(zBox.petState.mode=="follow" and zBox.petState.guid==enemyGUID)')
# A held manual input also cancels a stationary ranged order, not just a move.
p=pet_pair(kind='MAGE');p.main.execute('assert(zBox:AttackCommand())');p.advance(1)
p.alt.execute('assert(zBox.petState and not zBox.destination and not zBox.following)')
p.main.execute('zBox:Command("AXES",{1})');p.advance(.4)
p.alt.execute('assert(not zBox.petState)')
print('PASS: draggable/Shift-click pet Follow/Assist/Attack, Move and STOP macros do not issue commands while exporting; macros reuse slots, select Pet, enforce pairing, and work through slash commands; stationary manual override cancels Pet')
