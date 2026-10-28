"""Friendly click targeting across the real three-client command pipeline."""
from test_roster_trade_bars import Team

t = Team(independent=True)
for lua in t.clients.values():
    lua.execute('''
GetSpellTabInfo=function() return "General","Icon",0,3 end
GetSpellName=function(i) return ({"Heal","Fireball","Self buff"})[i],"Rank 1" end
IsPassiveSpell=function() return false end
GetSpellCooldown=function() return 0,0,1 end
IsHelpfulSpell=function(i,book) return i==1 or i==3 or (not book and i==1001) end
IsHarmfulSpell=function(i,book) return i==2 end
badRangeCalls=0;bookRangeCalls=0;idRangeCalls=0
SpellHasRange=function(i,book)
 if book~="spell" or i>3 then badRangeCalls=badRangeCalls+1 end
 bookRangeCalls=bookRangeCalls+1;return i~=3
end
C_Spell={SpellHasRange=function(id)
 if id~=1001 then badRangeCalls=badRangeCalls+1 end
 idRangeCalls=idRangeCalls+1;return id==1001
end}
GetActionInfo=function(slot) return slot==2 and "macro" or "spell",slot==2 and 7 or 1001 end
GetMacroSpell=function(i) assert(i==7);return "Heal","Rank 1",1001 end
GetMacroInfo=function() return "Heal macro","Icon","/cast Heal" end
local exists=UnitExists
selectedGUID="0x0000000000000099"
UnitExists=function(u) if u=="target" then return selectedGUID~=nil,selectedGUID end;return exists(u) end
TargetUnit=function(u) selectedGUID=u=="player" and ownGUID or u;log("TargetUnit",u) end
castTargets={};actionTargets={}
CastSpell=function(i) table.insert(castTargets,{i,selectedGUID});log("CastSpell",i) end
UseAction=function(i) table.insert(actionTargets,{i,selectedGUID});log("UseAction",i) end
''')

t.main.execute('''
local p=zBox:BarProfile()
for slot,owner in ipairs({"Alt","Beta","Main"}) do
 p.pages[1][slot]={command="SKILL",name="Heal",rank="Rank 1",peer=owner,realm=zBox:Realm(),icon="Icon"}
end
p.pages[1][4]={command="SKILL",name="Fireball",rank="Rank 1",peer="Alt",realm=zBox:Realm(),icon="Icon"}
p.pages[1][5]={command="SKILL",name="Self buff",rank="Rank 1",peer="Alt",realm=zBox:Realm(),icon="Icon"}
''')

def click(slot, right=False):
    t.main.execute(f'assert(zBox:UseBarSlot({slot},{"true" if right else "false"}))')
    t.advance(.6)

def target(lua, actions=False):
    rows = lua.globals().actionTargets if actions else lua.globals().castTargets
    return rows[len(rows)][2]

main, alt, beta, hostile = (f'0x{i:016x}' for i in [1, 2, 3, 0x99])

for mode in ['TARGET', 'MAIN', 'SELF', 'KEEP', 'MOUSEOVER']:
    t.main.globals().zBox.targetMode = mode
    click(1)
    assert target(t.alt) == main, mode
    click(1, True)
    assert target(t.alt) == alt, mode
    click(2)
    assert target(t.beta) == main, mode
    click(2, True)
    assert target(t.beta) == beta, mode
    click(3)
    assert target(t.main) == main, mode
    click(3, True)
    assert target(t.main) == main, mode
print('PASS: heals left-click the driver and right-click their own caster across every target mode and mixed owners')

# Damage skills keep the chosen target rules, and self-only utilities do not
# suddenly select the driver. Keybound clicks take the same left-click path.
t.main.execute('zBox.targetMode="TARGET";selectedGUID="0x0000000000000099"')
click(4)
assert target(t.alt) == hostile
click(5)
assert target(t.alt) == hostile
t.main.execute('zBox.targetMode="SELF"')
click(4)
assert target(t.alt) == alt
t.main.execute('this=zBoxBarKey1;arg1="LeftButton";this.scripts.OnClick()')
t.advance(.6)
assert target(t.alt) == main
print('PASS: damage and self-only skills retain their target rules; keybound friendly skills use the driver')

# Source action/spell views and previously exported macros share the same
# descriptor. Exercise the real source-view click and legacy proxy handlers.
for command, index in [('SPELL', 1), ('ACTION', 1), ('ACTION', 2)]:
    for right, expected in [(False, main), (True, alt)]:
        stamp = t.alt.eval(f'zBox:{"SpellStamp" if command == "SPELL" else "ActionStamp"}({index})')
        t.main.globals().castStamp = stamp
        section = 'spells' if command == 'SPELL' else 'actions'
        row = f'{{{index},"Icon","Heal",castStamp,castStamp,"0"}}'
        t.main.execute(f'zBox.UI:Click({{section="{section}",row={row}}},"{"RightButton" if right else "LeftButton"}")')
        t.advance(.6)
        assert target(t.alt, command == 'ACTION') == expected, (command, index, right)
        t.main.execute(f'proxy=zBox:RemoteProxy("{command}",{index},castStamp,"Icon","Heal");assert(zBox:UseProxy(proxy,{"true" if right else "false"}))')
        t.advance(.6)
        assert target(t.alt, command == 'ACTION') == expected, ('proxy', command, index, right)
print('PASS: source spell/action casts and spell-backed macros honor friendly left/right targeting using the correct spell ID and book APIs')

# Delayed casts remember the selected friendly target after movement stops.
t.alt.execute('''
GetSpellInfo=function() return "Heal","Rank 1","Icon",0,false,0,1500 end
GetUnitSpeed=function() return 0 end
''')
t.main.execute('zBox.targetMode="TARGET";selectedGUID="0x0000000000000099"')
click(1)
assert target(t.alt) == main
click(1, True)
assert target(t.alt) == alt
t.alt.execute('''
GetSpellInfo=nil
local range=SpellHasRange
SpellHasRange=nil
assert(zBox:IsFriendlyCast("SPELL",1)) -- Do not pass a book slot to the ID-only API.
SpellHasRange=range
IsHelpfulSpell=function() error("classification unavailable") end
assert(not zBox:IsFriendlyCast("SPELL",1))
IsHelpfulSpell=nil
assert(not zBox:IsFriendlyCast("SPELL",1))
''')
click(1)
assert target(t.alt) == hostile
for lua in t.clients.values():
    lua.execute('assert(badRangeCalls==0 and bookRangeCalls>0)')
t.alt.execute('assert(idRangeCalls>0)')
print('PASS: casts with a cast time retain their click target, and absent/failing classification APIs preserve the existing target mode')
