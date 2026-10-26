"""Linked panel recovery, paper-doll clicks and addon automation isolation."""
from test_character_views import Pair, call_count
from test_features import NPC

p = Pair(ui=True)
p.main.execute('''
local u=zBox.UI
u:Minimize()
assert(not u.frame.shown and u.restoreButton.shown and u.closeButton.caption.text=="-")
u:Restore();u.browser:Show()
assert(u.frame.shown and not u.restoreButton.shown)
this=u.closeButton;this.scripts.OnClick()
assert(not u.frame.shown and not u.browser.shown and u.restoreButton.shown)
this=u.restoreButton;this.scripts.OnClick()
assert(u.frame.shown and not u.restoreButton.shown)
u.frame:Hide() -- Escape / another UI closes the full dock.
assert(u.restoreButton.shown)
u.restoreButton:Hide()
''')
p.advance(.2)
p.main.execute('''
assert(zBox.UI.restoreButton.shown,"A linked panel must remain recoverable")
zBox.UI:Toggle();assert(zBox.UI.frame.shown and not zBox.UI.restoreButton.shown)
zBox.UI:Toggle();assert(zBox.UI.restoreButton.shown)
zBox:Slash("off")
assert(not zBox.UI.restoreButton.shown and zBox.UI.closeButton.caption.text=="x")
''')

p = Pair(ui=True)
p.main.execute('zBox.UI:Restore();zBox:Request("gear",1)')
p.advance(3)
p.main.execute('zBox.UI:Click(zBox.UI.cells[17],"RightButton")')
p.advance(1)
p.alt.execute('assert(not gear[16] and bags[0][3]=="item:300:0:0:0" and not cursor)')
before = call_count(p.alt, 'PickupInventoryItem')
p.main.execute('zBox.UI:Click(zBox.UI.cells[2],"RightButton")')
p.advance(.5)
assert call_count(p.alt, 'PickupInventoryItem') == before

# Matches the installed LazyPig event/update entry points. The fixture keeps its
# saved flags enabled so the guard must stop the routines themselves.
AUTOMODS = r'''
LPCONFIG={GOSSIP=true,AUTOSELL=true,AUTOREPAIR=true}
QuestHaste=nil
altHeld=false
IsAltKeyDown=function() return altHeld end
QuestFrameDetailPanel=CreateFrame("Frame",nil,UIParent)
LazyPig_OnEvent=function(name)
 log("LP-event",name)
 if name=="GOSSIP_SHOW" and LPCONFIG.GOSSIP then SelectGossipOption(1) end
end
LazyPig_ReplyQuest=function(name) log("LP-reply",name);AcceptQuest() end
LazyPig_RecordQuest=function(name) log("LP-record",name) end
LazyPig_FixQuest=function(name) log("LP-fix",name) end
LazyPig_GreySell=function() log("LP-sell") end
LazyPig_Repair=function() log("LP-repair") end
LazyPig_OnUpdate=function(elapsed)
 log("LP-update",elapsed)
 if not QuestHaste and IsAltKeyDown() and QuestFrameDetailPanel:IsVisible() then AcceptQuest() end
 return 17,"unchanged"
end
nativeAccept=AcceptQuest;nativeGossip=SelectGossipOption;nativeJump=Jump
originalLPEvent=LazyPig_OnEvent
zBox:InstallNPCGuards()
assert(nativeAccept==AcceptQuest and nativeGossip==SelectGossipOption and nativeJump==Jump)
if zBox.db.role=="control" then assert(LazyPig_OnEvent==originalLPEvent) end
'''
p = Pair()
for client in (p.main, p.alt):
    client.execute(NPC)
    client.execute(AUTOMODS)
p.alt.execute('''
LazyPig_OnEvent("GOSSIP_SHOW");LazyPig_OnEvent("QUEST_GREETING");LazyPig_OnEvent("QUEST_COMPLETE")
LazyPig_ReplyQuest("QUEST_PROGRESS");LazyPig_RecordQuest("A quest");LazyPig_FixQuest("A quest")
LazyPig_GreySell();LazyPig_Repair()
altHeld=true;LazyPig_OnUpdate(.1)
assert(LPCONFIG.GOSSIP and LPCONFIG.AUTOSELL and LPCONFIG.AUTOREPAIR and QuestHaste==nil)
assert(string.find(zBox:NPCGuardStatus(),"paused"))
altHeld=false
local a,b=LazyPig_OnUpdate(.2);assert(a==17 and b=="unchanged")
LazyPig_OnEvent("CHAT_MSG_SYSTEM")
''')
assert call_count(p.alt, 'SelectGossipOption') == 0
assert call_count(p.alt, 'AcceptQuest') == 0
for name in ('LP-reply', 'LP-record', 'LP-fix', 'LP-sell', 'LP-repair'):
    assert call_count(p.alt, name) == 0, name
assert call_count(p.alt, 'LP-update') == 1
assert call_count(p.alt, 'LP-event') == 1
# Controller automation and explicit remote NPC choices remain available.
p.main.execute('LazyPig_OnEvent("GOSSIP_SHOW");altHeld=true;LazyPig_OnUpdate(.1)')
assert call_count(p.main, 'SelectGossipOption') == 1
assert call_count(p.main, 'AcceptQuest') == 1
p.main.execute('zBox:Request("npc",1)')
p.alt.execute('zBox:NPCEvent("GOSSIP_SHOW")')
p.advance(3)
p.command('local row=zBox.cache.view.rows[1];zBox:Command("NPC",{row[6],row[1],row[5]})')
assert call_count(p.alt, 'SelectGossipOption') == 1
# Late addon replacements are guarded on the next tick; unlink is pass-through.
p.alt.execute('LazyPig_ReplyQuest=function(name) log("LP-new",name) end')
p.advance(1.2)
p.alt.execute('''
LazyPig_ReplyQuest("blocked");assert(LPCONFIG.GOSSIP)
zBox:Disconnect()
assert(LazyPig_OnEvent==originalLPEvent)
LazyPig_OnEvent("GOSSIP_SHOW");LazyPig_ReplyQuest("restored")
LazyPig_GreySell();LazyPig_Repair();altHeld=true;LazyPig_OnUpdate(.1)
assert(zBox:NPCGuardStatus()=="normal")
assert(nativeAccept==AcceptQuest and nativeGossip==SelectGossipOption and nativeJump==Jump)
''')
assert call_count(p.alt, 'LP-new') == 1
assert call_count(p.alt, 'SelectGossipOption') == 2
assert call_count(p.alt, 'AcceptQuest') == 1
assert call_count(p.alt, 'LP-sell') == 1 and call_count(p.alt, 'LP-repair') == 1
print('PASS: linked minimize/restore survives close/Escape; right-click unequips; LazyPig auto-gossip/quests/spending pause only on the linked agent without changing settings or protected APIs, and resume on unlink')
