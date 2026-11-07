"""Dock autocast: right-click toggles; the owner casts leftmost-ready skills on cooldown in combat."""
from test_roster_trade_bars import Team

ENEMY = '0x' + '99'.zfill(16)
t = Team(independent=True)
for lua in t.clients.values():
    lua.execute('''
GetSpellTabInfo=function() return "General","Icon",0,4 end
GetSpellName=function(i) return ({"Strike","Bolt","Heal","Rage"})[i],"Rank 1" end
IsPassiveSpell=function() return false end
IsHelpfulSpell=function(i,book) return i==3 end
IsHarmfulSpell=function(i,book) return i==1 or i==2 end
SpellHasRange=function(i) return i~=4 end
cd={} ; usable={true,true,true,true}
GetSpellCooldown=function(i) local e=cd[i];if e and e>clock then return clock,e-clock,1 end;return 0,0,1 end
IsUsableSpell=function(i) return usable[i],false end
selectedGUID=nil;combat=false;enemyDead=false
local exists=UnitExists
UnitExists=function(u)
 if u=="target" then return selectedGUID~=nil,selectedGUID end
 if u=="0x0000000000000099" then return true,u end
 return exists(u)
end
UnitCanAttack=function(_,u) return u=="0x0000000000000099" end
UnitIsDeadOrGhost=function(u) if u=="0x0000000000000099" then return enemyDead end;return false end
TargetUnit=function(u) selectedGUID=u=="player" and ownGUID or u;log("TargetUnit",u) end
casts={}
CastSpell=function(i) table.insert(casts,{i,selectedGUID});cd[i]=clock+({6,0,8,30})[i];log("CastSpell",i) end
''')

t.main.execute('''
local p=zBox:BarProfile()
for slot,name in ipairs({"Strike","Bolt","Heal","Rage"}) do
 p.pages[1][slot]={command="SKILL",name=name,rank="Rank 1",peer="Alt",realm=zBox:Realm(),icon="Icon"}
end
p.pages[1][5]={command="SKILL",name="Strike",rank="Rank 1",peer="Main",realm=zBox:Realm(),icon="Icon"}
local cell=zBox.UI.dockCells[1]
this=cell;arg1="RightButton";cell.scripts.OnClick()
assert(zBox:BarEntry(1).autocast,"right-click turns autocast on")
for _,s in ipairs({2,3,4}) do this=zBox.UI.dockCells[s];zBox.UI.dockCells[s].scripts.OnClick() end
this=zBox.UI.dockCells[5];zBox.UI.dockCells[5].scripts.OnClick()
assert(not zBox:BarEntry(5).autocast,"driver's own skills cannot autocast")
''')
t.advance(1)
alt = t.alt.globals()
assert len(alt.casts) == 0, 'nothing out of combat'
t.main.execute('selectedGUID="0x0000000000000099";combat=true')
t.advance(1.5)
order = [alt.casts[i][1] for i in range(1, len(alt.casts) + 1)]
assert order[:2] == [1, 3] or order[:1] == [1], order
assert alt.casts[1][2] == ENEMY, 'hostile skills use main target'
print('PASS: right-click toggles autocast on linked skills only; nothing casts out of combat; leftmost ready skill fires first on main target')

# Strike is on cooldown, so the next ready one in line fires; heal goes to main.
t.advance(3)
seq = [alt.casts[i][1] for i in range(1, len(alt.casts) + 1)]
assert 1 in seq and 2 in seq and 3 in seq and 4 in seq, seq
heal = [alt.casts[i][2] for i in range(1, len(alt.casts) + 1) if alt.casts[i][1] == 3][0]
assert heal == '0x' + '1'.zfill(16), heal
t.advance(4)
strikes = sum(1 for i in range(1, len(alt.casts) + 1) if alt.casts[i][1] == 1)
assert strikes >= 2, 'Strike recast once its cooldown is back'
print('PASS: skills fire down the line on cooldown; friendly skills target main; self-only skills need no target')

# A skill that fails (out of range) is skipped for a moment instead of blocking the rest.
t.alt.execute('CastSpell=function(i) table.insert(casts,{i,selectedGUID});if i~=1 then cd[i]=clock+({6,0,8,30})[i] end;log("CastSpell",i) end;cd={};casts={}')
t.advance(3)
seq = [alt.casts[i][1] for i in range(1, len(alt.casts) + 1)]
assert seq.count(1) <= 3 and 2 in seq, seq
print('PASS: a skill that does not go off backs off so later skills still cast')

t.main.execute('enemyDead=true;selectedGUID="0x0000000000000099"')
t.alt.execute('enemyDead=true;cd={};casts={}')
t.advance(2)
seq = [alt.casts[i][1] for i in range(1, len(alt.casts) + 1)]
assert 1 not in seq and 2 not in seq, seq
t.alt.execute('enemyDead=false')
t.main.execute('enemyDead=false;for s=1,4 do this=zBox.UI.dockCells[s];zBox.UI.dockCells[s].scripts.OnClick() end')
t.advance(1)
t.alt.execute('casts={};cd={}')
t.advance(2)
assert len(alt.casts) == 0, 'right-click again turns autocast off'
t.main.execute('combat=false')
print('PASS: no hostile casts on a dead target; toggling off stops autocast on the follower')
