"""0.10.3: cast-target dropdown, Mouseover mode for every skill, and blank-view recovery."""
from test_roster_trade_bars import Team

MAIN, ALT, ENEMY, FRIEND, FOE = '0x' + '1'.zfill(16), '0x' + '2'.zfill(16), '0x' + '99'.zfill(16), '0x' + '77'.zfill(16), '0x' + '88'.zfill(16)

t = Team(independent=True)
for lua in t.clients.values():
    lua.execute('''
GetSpellTabInfo=function() return "General","Icon",0,2 end
GetSpellName=function(i) return ({"Heal","Fireball"})[i],"Rank 1" end
IsPassiveSpell=function() return false end
GetSpellCooldown=function() return 0,0,1 end
IsHelpfulSpell=function(i,book) return i==1 end
IsHarmfulSpell=function(i,book) return i==2 end
SpellHasRange=function() return true end
local exists=UnitExists
selectedGUID="0x0000000000000099";hovered=nil;focus=nil
UnitExists=function(u)
 if u=="target" then return selectedGUID~=nil,selectedGUID end
 if u=="mouseover" then return hovered~=nil,hovered end
 if u=="party2" then return true,"0x0000000000000077" end
 if u=="0x0000000000000077" or u=="0x0000000000000088" then return true,u end
 return exists(u)
end
GetMouseFocus=function() return focus end
UnitCanAssist=function(_,u) return u=="0x0000000000000077" or u=="0x0000000000000001" or u=="0x0000000000000002" end
UnitCanAttack=function(_,u) return u=="0x0000000000000088" or u=="0x0000000000000099" end
TargetUnit=function(u) selectedGUID=u=="player" and ownGUID or u;log("TargetUnit",u) end
castTargets={}
CastSpell=function(i) table.insert(castTargets,{i,selectedGUID});log("CastSpell",i) end
''')

t.main.execute('''
local p=zBox:BarProfile()
p.pages[1][1]={command="SKILL",name="Heal",rank="Rank 1",peer="Alt",realm=zBox:Realm(),icon="Icon"}
p.pages[1][2]={command="SKILL",name="Fireball",rank="Rank 1",peer="Alt",realm=zBox:Realm(),icon="Icon"}
p.pages[1][3]={command="SKILL",name="Heal",rank="Rank 1",peer="Main",realm=zBox:Realm(),icon="Icon"}
''')

# Dropdown: the button opens a list of every mode; a choice saves and closes it.
t.main.execute('''
local u=zBox.UI
u:CycleTarget();local m=u.targetMenu
assert(m and m:IsShown() and table.getn(m.rows)==5)
assert(m.rows[1].check:IsShown() and not m.rows[5].check:IsShown(),"current mode is ticked")
this=m.rows[5];m.rows[5].scripts.OnClick()
assert(zBox.targetMode=="MOUSEOVER" and zBox:BarProfile().targetMode=="MOUSEOVER")
assert(not m:IsShown())
zBox:RenderBar();assert(u.targetMode.caption:GetText()=="Mouseover")
u:CycleTarget();assert(m:IsShown() and m.rows[5].check:IsShown());u:CycleTarget();assert(not m:IsShown())
''')
print('PASS: cast target button opens a dropdown of all five modes; choosing one saves it per character and closes the list')

def click(slot, right=False, hover=None, focus=None):
    t.main.globals().hovered = hover
    t.main.execute(f'focus={focus or "nil"}')
    t.main.execute(f'assert(zBox:UseBarSlot({slot},{"true" if right else "false"}))')
    t.advance(.6)

def last(lua):
    rows = lua.globals().castTargets
    return rows[len(rows)][2]

click(1, hover=FRIEND); assert last(t.alt) == FRIEND, 'heal on hovered friend'
click(2, hover=FRIEND); assert last(t.alt) == ENEMY, 'damage ignores hovered friend, uses main target'
click(2, hover=FOE); assert last(t.alt) == FOE, 'damage on hovered enemy'
click(1, hover=FOE); assert last(t.alt) == MAIN, 'heal ignores hovered enemy, uses main'
click(1); assert last(t.alt) == MAIN, 'no hover: heal goes to main'
click(2); assert last(t.alt) == ENEMY, 'no hover: damage goes to main target'
click(1, focus='{label="party",id="2"}'); assert last(t.alt) == FRIEND, 'pfUI-style unit frame hover'
click(1, focus='{unit="party2"}'); assert last(t.alt) == FRIEND, 'Blizzard/notgrid unit frame hover'
click(1, focus='{GetParent=function() return {unit="party2"} end}'); assert last(t.alt) == FRIEND, 'child of a unit frame'
click(1, right=True, hover=FRIEND); assert last(t.alt) == ALT, 'right-click still casts on the owner'
click(3, hover=FRIEND); assert last(t.main) == FRIEND, "driver's own skill on hovered friend"
click(3); assert last(t.main) == MAIN, "driver's own heal with no hover"
t.main.execute('zBox:SetTargetMode("TARGET")')
click(1, hover=FRIEND); assert last(t.alt) == MAIN, 'other modes keep their old behaviour'
t.alt.execute('assert(not zBox:ResolveMouseTarget("MOUSE:junk:",true) and zBox:ResolveMouseTarget("MOUSE::",false)=="")')
print('PASS: Mouseover mode casts every skill on the hovered unit (world or unit frames), with friendly/hostile fallbacks and right-click owner casts intact')

# Blank page recovery: drop the spells snapshot on the wire and check the page still loads.
dropping = {'on': True}
send = t.send
def lossy(src, target, packet):
    if dropping['on'] and src == 'Alt' and 'snapshot' in packet:
        return
    send(src, target, packet)
t.send = lossy
t.main.execute('zBox:Request("spells",1);zBox.cache.view=nil')
t.advance(3)
t.main.execute('assert(not zBox:ViewLoaded(),"snapshot was dropped")')
dropping['on'] = False
t.advance(12)
t.main.execute('assert(zBox:ViewLoaded() and zBox.cache.view.section=="spells","page recovers without user action")')
t.advance(10)
t.main.execute('assert(zBox.viewRetries==0)')
print('PASS: a lost Spells/Actions snapshot is re-requested automatically and the page fills in; retries stop once loaded')

# Queue compaction: a queue that never fully drains no longer hits its cap.
t.alt.execute('''
local b=zBox
b.queueLow={};b.lowIndex=1
for i=1,1000 do
 assert(b:Send("STATE",{"vitals",1,1,1,1,0},false),"send "..i.." refused")
 if math.mod(i,2)==0 then b.lowIndex=b.lowIndex+2 end -- drained as fast as filled, never empty
end
assert(table.getn(b.queueLow)<100)
''')
print('PASS: a continuously busy send queue keeps accepting snapshots instead of silently dropping them')
