"""Production independent bar UI, mixed owners, isolated bindings and targeting."""
from test_roster_trade_bars import Team
from test_zbox import call_count

t=Team(independent=True)
for lua in t.clients.values():lua.execute('GetSpellCooldown=function() return 0,0,1 end')
t.main.execute('''
nativeBindings={F8="ACTIONBUTTON1"};overrides={};bindingWrites=0
SetBinding=function() bindingWrites=bindingWrites+1;error("must not change WoW bindings") end
SaveBindings=function() bindingWrites=bindingWrites+1;error("must not save WoW bindings") end
GetBindingAction=function(key) return nativeBindings[key] or "" end
ClearOverrideBindings=function(owner) overrides={} end
SetOverrideBindingClick=function(owner,priority,key,button,mouse) overrides[key]={button,mouse} end
assert(zBox.independentBars.ready)
assert(zBox.view=="spells")
for i=1,12 do assert(zBox:BarEntry(i)==nil and zBox.UI.dockCells[i].row==nil) end
zBox:Request("spells",1)
''');t.advance(2)
t.main.execute('assert(zBox:PickupRemote("spells",zBox.cache.view.rows[1]));assert(zBox:DropBarSlot(1));assert(zBox:BarEntry(1).peer=="Alt")')
t.main.execute('zBox:SelectFollower("Beta");zBox:Request("spells",1)');t.advance(2)
t.main.execute('''
local row=zBox.cache.view.rows[1]
assert(zBox:PickupRemote("spells",row));assert(zBox:SelectFollower("Alt"));assert(zBox:DropBarSlot(2))
assert(zBox:BarEntry(2).peer=="Beta")
cursorSpell=true
GetCursorInfo=function() if cursorSpell then return "spell",1,"spell",123 end end
CursorHasSpell=function() return cursorSpell end
ClearCursor=function() cursorSpell=nil end
assert(zBox:DropBarSlot(3));assert(not cursorSpell and zBox:BarEntry(3).peer=="Main")
assert(zBox:UseBarSlot(1));assert(zBox:UseBarSlot(2));assert(zBox:UseBarSlot(3))
''');t.advance(.7)
assert call_count(t.alt,'CastSpell')==1 and call_count(t.beta,'CastSpell')==1 and call_count(t.main,'CastSpell')==1
t.main.execute('''
assert(zBox:SelectFollower("Beta"));assert(not zBox:BarEntry(1))
assert(zBox:SelectFollower("Alt"));assert(zBox:BarEntry(1).peer=="Alt" and zBox:BarEntry(2).peer=="Beta")
for i=1,9 do zBox.UI:BarPage(1) end
local p=zBox:BarProfile();assert(p.page==10);zBox.UI:BarPage(1);assert(p.page==1)
zBox.UI:BarPage(-1);assert(p.page==10);zBox.UI:BarPage(1)
zBox:Request("actions",10);zBox.UI:Page(1);assert(zBox.page==1);zBox.UI:Page(-1);assert(zBox.page==10)
local p,key=zBox:BarProfile();assert(zBox:StartBarDrag(p.pages[1][1],{key=key,page=1,slot=1}));assert(zBox:DropBarSlot(2))
assert(zBox:BarEntry(1).peer=="Beta" and zBox:BarEntry(2).peer=="Alt")
''')
print('PASS: bar starts blank, mixes driver/two followers without WoW slots or macros, keeps separate saved profiles, swaps entries and wraps both page controls in both directions')

t.main.execute('''
zBox:ToggleBarBinding();zBox:HoverBarSlot(1);zBox:CaptureBarKey("F8")
assert(zBox:BarProfile().bindings[1]=="F8" and not overrides.F8)
zBox:CaptureBarKey("ESCAPE");assert(overrides.F8[1]=="zBoxBarKey1")
assert(nativeBindings.F8=="ACTIONBUTTON1" and bindingWrites==0)
this=zBoxBarKey1;arg1="LeftButton";this.scripts.OnClick()
zBox.UI:Minimize();assert(overrides.F8 and zBox:BarProfile().bindings[1]=="F8")
zBox.UI:Restore();zBox:SelectFollower("Beta");assert(not overrides.F8)
zBox:SelectFollower("Alt");assert(overrides.F8)
zBox:ToggleBarBinding();zBox:HoverBarSlot(2)
IsControlKeyDown=function() return true end
zBox:CaptureBarKey("BUTTON4");IsControlKeyDown=function() return false end
assert(zBox:BarProfile().bindings[2]=="CTRL-BUTTON4")
zBox:EndBarBinding();assert(overrides["CTRL-BUTTON4"])
''');t.advance(.5)
assert call_count(t.beta,'CastSpell')==2
t.main.execute('''
zBox:ToggleBarBinding();zBox:HoverBarSlot(2);zBox:CaptureBarKey("BACKSPACE");zBox:EndBarBinding()
assert(not overrides["CTRL-BUTTON4"] and bindingWrites==0)
''')
t.alt.execute('GetSpellCooldown=function() return clock-2,10,1 end')
t.beta.execute('GetSpellCooldown=function() return clock-1,20,1 end')
t.advance(2)
t.main.execute('assert(zBox.UI.dockCells[1].zBoxCooldown:IsShown() and zBox.UI.dockCells[2].zBoxCooldown:IsShown())')
# Spells are saved by name/rank, independently of future spellbook indices.
t.alt.execute('GetSpellName=function(i) return i==2 and "Spell 1" or "Moved spell","Rank 1" end;IsPassiveSpell=function() return false end;zBox.skillIndices=nil')
t.main.execute('assert(zBox:UseBarSlot(2))');t.advance(.5)
casts=[row for _,row in t.alt.globals().calls.items() if row[1]=='CastSpell']
assert casts[-1][2]==2
t.main.execute('''
local p=zBox:BarProfile();local entry=p.pages[1][2]
zBox:Slash("off");assert(not next(overrides) and nativeBindings.F8=="ACTIONBUTTON1" and bindingWrites==0)
assert(p.pages[1][2]==entry and p.bindings[1]=="F8")
assert(zBox:ConfigureRoster({"Alt","Beta"},"testcode123"))
''');t.advance(6)
t.main.execute('assert(zBox:BarEntry(2).peer=="Alt" and overrides.F8);assert(bindingWrites==0)')
print('PASS: hover binds use only temporary overrides, support modifiers/side buttons/clearing, survive minimization and reconnect, restore native keys on profile/off, track both owners cooldowns and resolve moved spellbook indices')

# Macro metadata is identified locally on the owning client; no macro body is
# sent for evaluation. A temporary mouseover is restored after the one action.
t=Team(independent=True)
for lua in t.clients.values():lua.execute('GetSpellCooldown=function() return 0,0,1 end')
t.alt.execute('''
local action=GetActionInfo
GetActionInfo=function(i) if i==1 then return "macro",7 end;return action(i) end
GetMacroInfo=function(i) if i==7 then return "Heal mouse","MacroIcon","/cast [@mouseover,help] Heal" end end
local exists=UnitExists
UnitExists=function(u)
 if u=="mouseover" then return mouseoverGUID~=nil,mouseoverGUID end
 if u=="target" and selectedGUID then return true,selectedGUID end
 return exists(u)
end
SetMouseoverUnit=function(guid) mouseoverGUID=guid~="" and guid or nil end
TargetUnit=function(unit) selectedGUID=unit=="player" and ownGUID or unit;log("TargetUnit",unit) end
UseAction=function(i) assert(mouseoverGUID==expectedMouseover);log("UseAction",i) end
IsUsableAction=function() return nil,false end -- No native mouseover before the scoped action.
mouseoverGUID=ownGUID;CleveRoids={mouseoverUnit=ownGUID}
''')
t.main.execute('zBox:Request("actions",1)');t.advance(3)
t.main.execute('''
local row=zBox.cache.view.rows[1];assert(row[11]=="macro" and row[14]=="1")
assert(zBox:PickupRemote("actions",row));assert(zBox:DropBarSlot(1));assert(zBox:BarEntry(1).mouseover)
local exists=UnitExists
UnitExists=function(u) if u=="mouseover" then return true,"0x0000000000000004" end;return exists(u) end
''')
t.alt.execute('expectedMouseover="0x0000000000000004"')
t.main.execute('assert(zBox:UseBarSlot(1))');t.advance(.5)
assert call_count(t.alt,'UseAction')==1
t.alt.execute('assert(mouseoverGUID==ownGUID and CleveRoids.mouseoverUnit==ownGUID)')
t.main.execute('zBox.targetMode="SELF"')
t.alt.execute('expectedMouseover=ownGUID')
t.main.execute('assert(zBox:UseBarSlot(1))');t.advance(.5)
assert call_count(t.alt,'UseAction')==2
t.alt.execute('assert(mouseoverGUID==ownGUID)')
# Repeated invalid-unit lookups from background code must not be relayed as
# spell errors; raw GUID-target concatenation is never queried at all.
t.alt.execute('''
local exists=UnitExists
UnitExists=function(u)
 if u==peerGUID.."target" then error("Unknown unit: invalid GUID suffix") end
 if u=="bad-token" then event="UI_ERROR_MESSAGE";arg1="Unknown unit.";zBox.frame.scripts.OnEvent();error("Unknown unit") end
 return exists(u)
end
zBox.mainTargetGUID="0x0000000000000099";assert(zBox:GUID(peerGUID.."target")==zBox.mainTargetGUID)
zBox.lastCommandAt=GetTime();zBox.lastErrorRelayText=nil
for i=1,40 do assert(zBox:GUID("bad-token")=="") end
assert(not zBox.lastErrorRelayText)
''')
print('PASS: mouseover macros are detected, use the driver/chosen target and restore follower mouseover; invalid passive token lookups are contained instead of flooding relayed chat')
