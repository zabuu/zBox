"""Autocast smart checks: heals only hurt targets, buffs/DoTs/debuffs are not reapplied while up."""
from test_roster_trade_bars import Team

MAIN, ALT, ENEMY = ('0x' + x.zfill(16) for x in ['1', '2', '99'])
t = Team(independent=True)
for lua in t.clients.values():
    lua.execute('''
names={"Strike","Corruption","Heal","Fortitude","Rage","Renew","Sunder"}
texts={"an instant strike that causes 50 damage.","corrupts the target, causing 100 shadow damage over 18 sec.",
 "heals a friendly target for 100 to 120.","increases the target's stamina by 10 for 30 min.","generates 10 rage over 10 sec.",
 "heals the target of 200 damage over 15 sec.","sunders the target's armor. can be applied up to 5 times. lasts 10 sec."}
GetSpellTabInfo=function() return "General","Icon",0,7 end
GetSpellName=function(i) return names[i],"Rank 1" end
IsPassiveSpell=function() return false end
IsHelpfulSpell=function(i) return i==3 or i==4 or i==6 end
IsHarmfulSpell=function(i) return i==1 or i==2 or i==7 end
SpellHasRange=function(i) return i~=5 end
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
hp={}
local function key(u) if u=="player" then return ownGUID end;return u end
UnitHealth=function(u) return hp[key(u)] or 100 end
UnitHealthMax=function() return 100 end
buffs={};debuffs={}
UnitBuff=function(u,i) local b=buffs[key(u)];return b and b[i] end
UnitDebuff=function(u,i) local b=debuffs[key(u)];return b and b[i],b and b.count end
TargetUnit=function(u) selectedGUID=u=="player" and ownGUID or u end
casts={}
CastSpell=function(i) table.insert(casts,{i,selectedGUID});cd[i]=clock+1.5 end
''')
t.alt.execute('zBox.SkillText=function(self,command,index) return texts[index] end')

def only(*spells):
    t.main.execute('local p=zBox:BarProfile();for s=1,12 do p.pages[1][s]=nil end')
    for slot, i in enumerate(spells, 1):
        t.main.execute(f'zBox:BarProfile().pages[1][{slot}]={{command="SKILL",name=names[{i}],rank="Rank 1",peer="Alt",realm=zBox:Realm(),icon="Icon",autocast=true}}')
    t.advance(.6)

def run(seconds=2.0):
    t.alt.execute('casts={}')
    t.advance(seconds)
    a = t.alt.globals().casts
    return [(a[i][1], a[i][2]) for i in range(1, len(a) + 1)]

t.main.execute('combat=true')
only(3)
assert run() == [], 'nobody hurt: no heal'
t.alt.execute(f'hp["{MAIN}"]=70')
r = run(); assert r and r[0] == (3, MAIN), r
t.alt.execute(f'hp["{MAIN}"]=80;hp["{ALT}"]=40')
r = run(); assert r and r[0] == (3, ALT), ('most hurt first', r)
t.alt.execute(f'hp["{MAIN}"]=95;hp["{ALT}"]=95')
assert run() == [], 'above 90%: no heal'
print('PASS: heals fire only when main or the owner is below 90% health, on the most hurt one')

only(6)
t.alt.execute(f'hp["{MAIN}"]=60;hp["{ALT}"]=100;buffs["{MAIN}"]={{"SpellIcon6"}}')
r=run(); assert r == [], ('HoT already on the only hurt target', r, t.alt.eval('zBox.autocast and zBox.autocast.list[1].a'))
t.alt.execute(f'buffs["{MAIN}"]=nil')
r = run(); assert r and r[0] == (6, MAIN), r
t.alt.execute(f'hp["{MAIN}"]=100')
print('PASS: heal-over-time skills skip a target that already has them')

only(4)
t.alt.execute(f'buffs["{MAIN}"]={{"SpellIcon4"}}')
r = run(); assert r and r[0] == (4, ALT), ('main buffed, buff self', r)
t.alt.execute(f'buffs["{ALT}"]={{"SpellIcon4"}}')
assert run() == [], 'everyone buffed'
only(5)
t.alt.execute(f'buffs["{ALT}"]={{"SpellIcon5"}}')
assert run() == [], 'self buff already up'
t.alt.execute(f'buffs["{ALT}"]=nil')
r = run(); assert r and r[0][0] == 5, r
print('PASS: buffs go to whoever is missing them, and self-buffs are not recast while active')

only(2, 1)
t.alt.execute(f'debuffs["{ENEMY}"]={{"SpellIcon2"}}')
r = run(1.0); assert r and r[0] == (1, ENEMY), ('DoT up, so the next skill fires', r)
t.alt.execute(f'debuffs["{ENEMY}"]=nil')
r = run(1.0); assert r and r[0] == (2, ENEMY), r
t.alt.execute(f'debuffs["{ENEMY}"]={{"SpellIcon1"}}')
r = run(1.0); assert r and r[0][0] in (1, 2), 'direct damage ignores matching debuff icon'
print('PASS: DoTs are not reapplied while ticking; direct-damage skills keep firing on cooldown')
only(7)
t.alt.execute(f'debuffs["{ENEMY}"]={{"SpellIcon7",count=3}}')
r = run(1.0); assert r and r[0] == (7, ENEMY), ('Sunder keeps stacking below 5', r)
t.alt.execute(f'debuffs["{ENEMY}"]={{"SpellIcon7",count=5}}')
assert run(1.0) == [], 'Sunder stops at 5 stacks'
t.alt.execute('function CastSpell(i) table.insert(casts,{i,selectedGUID});cd[i]=clock+1.5;if i==7 then debuffs["0x0000000000000099"].count=5 end end')
t.alt.execute(f'debuffs["{ENEMY}"]={{"SpellIcon7",count=4}}')
r = run(1.0); assert r and r[0][0] == 7
t.alt.execute('casts={}')
t.advance(4)
assert len(t.alt.globals().casts) == 0, 'full fresh stack is left alone'
t.advance(2.5)
r = [t.alt.globals().casts[i][1] for i in range(1, len(t.alt.globals().casts) + 1)]
assert r and r[0] == 7, ('refreshed ~4s before the 10s duration ends', r)
t.alt.execute('casts={}')
t.advance(3)
assert len(t.alt.globals().casts) == 0, 'refresh restarts the timer'
print('PASS: stacking debuffs build to max stacks, then are refreshed shortly before they expire')
t.main.execute('combat=false')
