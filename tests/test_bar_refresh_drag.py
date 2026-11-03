"""Refreshes must not clear saved slots or interrupt a live spell drag."""
from test_roster_trade_bars import Team
from test_zbox import call_count
from test_zbox import endpoint
from lupa.lua51 import lua_type
import json

t=Team(independent=True)
for lua in t.clients.values():
    lua.execute('GetSpellCooldown=function() return 0,0,1 end')
t.main.execute('zBox.UI:Restore();zBox.UI.browser:Show();zBox:Request("spells",1)')
t.advance(2)
t.main.execute('''
local b,u=zBox,zBox.UI
assert(b:PickupRemote("spells",b.cache.view.rows[1]));assert(b:DropBarSlot(1))
savedEntry=b:BarEntry(1)
emptyWrites=0
local icon=u.dockCells[1].icon;local set=icon.SetTexture
icon.SetTexture=function(self,texture,...)
 if texture=="Interface\\\\PaperDoll\\\\UI-Backpack-EmptySlot" then emptyWrites=emptyWrites+1 end
 return set(self,texture,unpack(arg))
end
for i=1,5 do u:Refresh() end
assert(emptyWrites==0,"Legacy refresh must never clear an independent slot")
assert(b:BarEntry(1)==savedEntry and u.dockCells[1].entry==savedEntry)
''')
print('PASS: status/UI refresh never clears an assigned independent bar slot')

# Model the source-side effects that the simple frame mock does not simulate:
# hiding/reparenting a held button cancels the native drag before release.
t.main.execute('''
source=zBox.UI.cells[1];sourceHides=0;sourceMoves=0;mouseHeld=true
local hide,parent=source.Hide,source.SetParent
source.Hide=function(self) sourceHides=sourceHides+1;return hide(self) end
source.SetParent=function(self,p) if p~=self.parent then sourceMoves=sourceMoves+1 end;return parent(self,p) end
IsMouseButtonDown=function(button) assert(button=="LeftButton");return mouseHeld end
this=source;arg1="LeftButton"
if source.scripts.OnMouseDown then source.scripts.OnMouseDown() end
sourceRow=source.row
''')
t.advance(.7)
t.main.execute('''
assert(sourceHides==0 and sourceMoves==0 and source.row==sourceRow,"A pressed source must survive incoming status updates")
this=source;arg1="LeftButton";source.scripts.OnDragStart()
assert(zBox.independentBars.cursor and zBox.independentBars.cursor.entry.name==sourceRow[3])
assert(sourceHides==0,"The pickup notice must not rebuild its own drag source")
''')
t.advance(1)
t.main.execute('''
assert(sourceHides==0 and sourceMoves==0 and source.row==sourceRow)
local cell=zBox.UI.dockCells[2]
cell.GetLeft=function() return 100 end;cell.GetRight=function() return 132 end
cell.GetTop=function() return 100 end;cell.GetBottom=function() return 68 end
GetCursorPosition=function() local s=cell:GetEffectiveScale();return 116*s,84*s end
mouseHeld=false;this=source;arg1="LeftButton";source.scripts.OnDragStop()
assert(not zBox.UI.skillPress and not zBox.independentBars.cursor)
assert(zBox:BarEntry(2).name==sourceRow[3] and zBox:BarEntry(2).peer=="Alt")
source.scripts.OnClick() -- Drag release must not also cast the source spell.
this=cell;cell.scripts.OnClick() -- Nor should the destination cast on release.
''')
t.advance(.7)
assert call_count(t.alt,'CastSpell')==0
t.main.execute('assert(sourceHides>0 and zBox.UI.skillPress==nil);assert(zBox:BarEntry(1)==savedEntry)')
print('PASS: mouse-down, pickup notice, live status updates and drag release preserve the source and place the skill without casting')

# A missed native release callback must not freeze the browser. Shift-click
# pickup remains active after the physical button is released, until placement.
t.main.execute('''
source=zBox.UI.cells[1];mouseHeld=true;this=source;arg1="LeftButton";source.scripts.OnMouseDown()
mouseHeld=false
''')
t.advance(.3)
t.main.execute('''
assert(not zBox.UI.skillPress)
this=source;arg1="LeftButton";IsShiftKeyDown=function() return true end
source.scripts.OnClick();IsShiftKeyDown=function() return false end
assert(zBox.independentBars.cursor)
''')
t.advance(.7)
t.main.execute('''
assert(zBox.independentBars.cursor);assert(zBox:DropBarSlot(3))
source=zBox.UI.cells[1];mouseHeld=true;this=source;arg1="LeftButton";source.scripts.OnMouseDown();source.scripts.OnDragStart()
local cell=zBox.UI.dockCells[4]
cell.GetLeft=function() return 200 end;cell.GetRight=function() return 232 end
cell.GetTop=function() return 100 end;cell.GetBottom=function() return 68 end
GetCursorPosition=function() local s=cell:GetEffectiveScale();return 216*s,84*s end
mouseHeld=false
''')
t.advance(.7)
t.main.execute('''
assert(not zBox.UI.skillPress and not zBox.independentBars.cursor and zBox:BarEntry(4))
source=zBox.UI.cells[1];mouseHeld=true;this=source;arg1="LeftButton";source.scripts.OnMouseDown();source.scripts.OnDragStart()
zBox.UI:Minimize();assert(not zBox.UI.skillPress and not zBox.independentBars.cursor)
zBox.UI:Restore();mouseHeld=false
assert(string.find(zBox:Diagnostics(),"bar page=1/10, slots=4/4",1,true))
''')
print('PASS: missed mouse release recovers, Shift-click pickup persists, minimization cancels safely, and diagnostics report saved slot counts')

# Reconnecting/reloading the same character must retain the saved layout;
# switching follower profiles must not replace that layout with an empty one.
t.main.execute('assert(zBox:SelectFollower("Beta"));assert(not zBox:BarEntry(1));assert(zBox:SelectFollower("Alt"));assert(zBox:BarEntry(1)==savedEntry);zBox:Initialize()')
t.advance(7)
t.main.execute('assert(zBox.connected and zBox:BarEntry(1)==savedEntry and zBox:BarEntry(3));assert(zBox.UI.dockCells[1].icon.texture==savedEntry.icon)')
print('PASS: saved slots survive follower selection, reconnect and Lua reinitialization')

# Exercise an actual fresh Lua runtime with serialized per-character settings.
def saved(value):
    if lua_type(value)=='table':
        return '{'+','.join('['+saved(k)+']='+saved(v) for k,v in value.items())+'}'
    if isinstance(value,str):return json.dumps(value,ensure_ascii=False)
    if isinstance(value,bool):return 'true' if value else 'false'
    if value is None:return 'nil'
    return str(value)

fresh=endpoint('Main','Alt',True,independent=True)
fresh.execute('zBoxDB='+saved(t.main.globals().zBoxDB)+';zBox:Initialize()')
fresh.execute('assert(zBox:BarEntry(1).peer=="Alt" and zBox:BarEntry(2) and zBox:BarEntry(3));assert(zBox.UI.dockCells[1].icon.texture==zBox:BarEntry(1).icon)')
print('PASS: serialized saved bar profiles restore in a fresh Lua client')
