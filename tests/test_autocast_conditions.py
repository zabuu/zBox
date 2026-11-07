"""Custom autocast conditions: set per skill in an editor, sent to the owner, checked before casting."""
from test_roster_trade_bars import Team

MAIN, ALT, ENEMY = ('0x' + x.zfill(16) for x in ['1', '2', '99'])
t = Team(independent=True)
for lua in t.clients.values():
    lua.execute('''
names={"Eviscerate","Tranquilizing Shot","Strike"}
GetSpellTabInfo=function() return "General","Icon",0,3 end
GetSpellName=function(i) return names[i],"Rank 1" end
IsPassiveSpell=function() return false end
IsHelpfulSpell=function() return false end
IsHarmfulSpell=function() return true end
SpellHasRange=function() return true end
cd={}
GetSpellCooldown=function(i) local e=cd[i];if e and e>clock then return clock,e-clock,1 end;return 0,0,1 end
IsUsableSpell=function() return true,false end
selectedGUID="0x0000000000000099";combat=false
local exists=UnitExists
UnitExists=function(u)
 if u=="target" then return selectedGUID~=nil,selectedGUID end
 if u=="0x0000000000000099" then return true,u end
 return exists(u)
end
UnitCanAttack=function(_,u) return u=="0x0000000000000099" end
UnitIsDeadOrGhost=function() return false end
cp=0;GetComboPoints=function() return cp end
hp={};UnitHealth=function(u) return hp[u] or 100 end;UnitHealthMax=function() return 100 end
auras={}
TargetUnit=function(u) selectedGUID=u=="player" and ownGUID or u end
casts={}
CastSpell=function(i) table.insert(casts,i);cd[i]=clock+1.5 end
''')
t.alt.execute('''
zBox.SkillText=function() return "an instant strike that causes 50 damage." end
zBox.AuraNames=function(self,unit,harmful) return auras[unit..(harmful and ":d" or ":b")] or {} end
''')

# Parser
t.main.execute('''
local B=zBox
local r=assert(B:ParseAutocastCondition("cp>=4, !tdebuff:Sunder_Armor>=5 tbuff:Frenzy||Enrage"))
assert(table.getn(r)==3 and r[1].key=="cp" and r[1].op==">=" and r[1].value==4)
assert(r[2].negate and r[2].harmful and r[2].names[1]=="sunder armor" and r[2].count==5)
assert(r[3].names[1]=="frenzy" and r[3].names[2]=="enrage" and r[3].unit=="enemy")
local ok,err=B:ParseAutocastCondition("cp>>4");assert(not ok and err)
ok,err=B:ParseAutocastCondition("xyz>4");assert(not ok and string.find(err,"xyz"))
ok,err=B:ParseAutocastCondition("buffs:x");assert(not ok)
assert(table.getn(B:ParseAutocastCondition(""))==0)
''')
print('PASS: condition text parses into rules, and typos are reported instead of saved')

# Editor on the driver
t.main.execute('''
local p=zBox:BarProfile()
for slot,name in ipairs({"Eviscerate","Tranquilizing Shot","Strike"}) do
 p.pages[1][slot]={command="SKILL",name=name,rank="Rank 1",peer="Alt",realm=zBox:Realm(),icon="Icon"}
end
local cell=zBox.UI.dockCells[1]
IsControlKeyDown=function() return true end
this=cell;arg1="RightButton";cell.scripts.OnClick()
local f=assert(zBox.autoEditor and zBox.autoEditor:IsShown(),"ctrl-right-click opens the editor") and zBox.autoEditor
f.box:SetText("cp>>4");assert(not zBox:SaveAutocastEditor() and f:IsShown(),"bad text is refused")
f.box:SetText("cp>=4");assert(zBox:SaveAutocastEditor() and not f:IsShown())
assert(zBox:BarEntry(1).autocastIf=="cp>=4" and zBox:BarEntry(1).autocast,"saving turns autocast on")
this=zBox.UI.dockCells[2];zBox.UI.dockCells[2].scripts.OnClick()
f.box:SetText("tbuff:Frenzy||Enrage");assert(zBox:SaveAutocastEditor())
IsControlKeyDown=function() return false end
''')
t.advance(1)
print('PASS: ctrl-right-click opens a condition editor; valid text saves and turns autocast on, bad text stays open with the error')

def run(seconds=1.0):
    t.alt.execute('casts={}')
    t.advance(seconds)
    a = t.alt.globals().casts
    return [a[i] for i in range(1, len(a) + 1)]

t.main.execute('combat=true')
assert run() == [], 'no combo points, no enrage'
t.alt.execute('cp=4')
r = run(); assert r and r[0] == 1, ('Eviscerate at 4 combo points', r)
t.alt.execute('cp=2')
t.alt.execute(f'auras["{ENEMY}:b"]={{{{name="frenzy",count=1}}}}')
r = run(); assert r and r[0] == 2, ('Tranquilizing Shot on frenzy', r)
t.alt.execute(f'auras["{ENEMY}:b"]=nil')
assert run(2.0) == [], 'nothing to remove'
print('PASS: Eviscerate waits for 4 combo points; Tranquilizing Shot fires only when the enemy has Frenzy or Enrage')

# Stack counts, missing auras, health checks on the third skill.
t.main.execute('zBox:SetAutocastCondition(3,"!tdebuff:sunder>=5 thp<50")')
t.advance(1)
t.alt.execute(f'hp["{ENEMY}"]=40;auras["{ENEMY}:d"]={{{{name="sunder armor",count=5}}}}')
assert run() == [], 'full sunder stack'
t.alt.execute(f'auras["{ENEMY}:d"]={{{{name="sunder armor",count=3}}}}')
r = run(); assert r and r[0] == 3, r
t.alt.execute(f'hp["{ENEMY}"]=80')
assert run(2.0) == [], 'enemy above 50%'
t.main.execute('assert(zBox:SetAutocastCondition(3,""));assert(zBox:BarEntry(3).autocastIf==nil)')
t.advance(1)
r = run(2.0); assert 3 in r, 'clearing the condition lets it fire again'
t.main.execute('assert(zBox:SetAutocastCondition(3,"behind"))')
t.advance(1)
# Enemy at the origin facing +x (facing 0). Owner at -2,0 is behind; at +2,0 is in front.
t.alt.execute('geo={x=0,y=0,z=0,facing=0,px=-2,py=0,pz=0,distance=2,radius=3};zBox.PetGeometry=function(self,guid) return guid=="0x0000000000000099" and geo or nil end')
r = run(2.0); assert 3 in r, ('behind the enemy', r)
t.alt.execute('geo.px=2')
assert run(2.0) == [], 'in front of the enemy'
t.alt.execute('zBox.PetGeometry=function() return nil end')
assert run(2.0) == [], 'unknown position never counts as behind'
t.main.execute('assert(zBox:SetAutocastCondition(3,"!behind"))')
t.advance(1)
t.alt.execute('zBox.PetGeometry=function(self,guid) return guid=="0x0000000000000099" and geo or nil end')
r = run(2.0); assert 3 in r, ('!behind fires in front of the enemy', r)
t.alt.execute('geo.px=-2')
assert run(2.0) == [], '!behind waits while behind'
t.alt.execute('zBox.PetGeometry=function() return nil end')
assert run(2.0) == [], 'unknown position is not "not behind" either'
t.main.execute('assert(zBox:SetAutocastCondition(3,""))')
t.advance(1)
t.main.execute('assert(zBox:SetAutocastCondition(3,"!aggro maggro"))')
t.advance(1)
t.alt.execute('''
victim="";local guid=zBox.GUID;local peer=zBox.PeerUnit
zBox.PeerUnit=function() return "party1" end
zBox.GUID=function(self,u)
 if u=="party1" then return "0x00000000000000A1" end
 if u=="party1target" then return "0x0000000000000099" end
 if u=="party1targettarget" or u=="targettarget" then return victim end
 return guid(self,u)
end
''')
assert run(2.0) == [], 'enemy attacking nobody: maggro fails'
t.alt.execute('victim="0x00000000000000A1"')
r = run(2.0); assert 3 in r, ('enemy on the main, not on the owner', r)
t.alt.execute('victim=zBox:GUID("player")')
assert run(2.0) == [], 'owner has aggro'
t.alt.execute('zBox.PeerUnit=function() return nil end')
assert run(2.0) == [], 'unknown enemy target fails safe'
t.main.execute('assert(zBox:SetAutocastCondition(3,""))')
t.advance(1)
t.main.execute('combat=false')
print('PASS: aggro/maggro read who the enemy is attacking; behind / !behind use the enemy position and facing; unknown geometry fails safe')
print('PASS: stack counts, ! for missing, and enemy health checks work; clearing a condition restores normal autocast')

# The real tooltip reader runs without errors and Escape no longer minimizes the panel.
t.main.execute('''
UnitBuff=function(u,i) if i==1 then return "Icon",2 end end
local list=zBox:AuraNames("player",false);assert(table.getn(list)==1 and list[1].count==2)
for _,name in ipairs(UISpecialFrames) do assert(name~="zBoxPanel","Escape must not hide the zBox panel") end
''')
print('PASS: aura names are read from tooltips; Escape closes zBox popups but leaves the panel open')
