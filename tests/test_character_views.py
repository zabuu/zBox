"""Interaction regressions for the remote character views and bag snapshots."""
from test_cast_facing import Pair, call_count
from test_features import QUESTS, NPC

p = Pair(ui=True)
p.main.execute('zBox.UI.frame:Show();zBox.UI.browser:Show();zBox:Request("gear",1)')
p.advance(3)
p.main.execute('''
local u=zBox.UI
assert(u.gearView.shown and u.gearModel.shown)
assert(u.cells[2].point[4] < u.cells[11].point[4],"Head and hands must flank the character")
assert(u.cells[17].point[5] < u.cells[2].point[5],"Weapons belong below the character")
assert(not u.cells[2].name.shown and u.cells[2].icon.shown)
''')
# Quest selection changes the detail pane and survives polling. Switching away
# restores icons that the compact quest list intentionally hides.
for client in (p.main, p.alt):
    client.execute(QUESTS)
p.main.execute('zBox:Request("quests",1)')
p.advance(4)
p.main.execute('''
local u=zBox.UI
u:Click(u.cells[2],"LeftButton")
assert(u.questDetailTitle.text=="Alt questline")
assert(string.find(u.questDetailText.text,"Relic: 0/1"))
assert(string.find(u.questDetailText.text,"Main:"))
''')
p.advance(3)
p.main.execute('assert(zBox.UI.questDetailTitle.text=="Alt questline");zBox:Request("spells",1)')
p.advance(3)
p.main.execute('assert(zBox.UI.bookView.shown and zBox.UI.cells[1].icon.shown and zBox.UI.cells[1].name.shown)')

# Multiple bags keep their own rows. Polling another bag must not replace the
# selected tab, and stale snapshots cannot overwrite a newer bag view.
p.alt.execute('GetBagName=function(bag) return bag==0 and "Backpack" or "Runecloth Bag" end;bags[1][1]="item:500:0:0:0"')
p.main.execute('zBox:Request("bags",1)')
p.advance(3)
p.main.execute('zBox.UI:ToggleBag(2)')
p.advance(4)
p.main.execute('''
local u=zBox.UI
assert(u.bagWindows[1].shown and u.bagWindows[2].shown)
assert(u.bagWindows[1].cells[1].row[1]=="0")
assert(u.bagWindows[2].cells[1].row[1]=="1")
assert(u.bagWindows[2].title.text=="Runecloth Bag")
local hidden=0
u.bagWindows[1]:SetScript("OnHide",function() hidden=hidden+1 end)
u:Refresh();u:Refresh();assert(hidden==0,"Refreshing bags must not hide an actively dragged window")
u:Click(u.bagWindows[2].cells[1],"LeftButton")
assert(zBox.bagSelection.bag=="1" and zBox.bagSelection.key=="item:500:0:0:0")
local old=zBox.cache.bags[1]
zBox:AcceptState({"snapshot","bags","1",tostring(old.id-1),"Stale","5","", ""})
assert(zBox.cache.bags[1]==old)
''')
p.alt.execute('bags[0][1]="item:600:0:0:0"')
p.advance(6)
p.main.execute('''
assert(zBox.page==2 and zBox.cache.view.page==2)
assert(zBox.UI.bagWindows[1].cells[1].row[8]=="item:600:0:0:0")
local f=zBox.UI.bagWindows[2]
f.GetPoint=function() return "TOPLEFT",UIParent,"TOPLEFT",123,-234 end
this=f;f.scripts.OnDragStop()
assert(zBox.db.bagPositions[2][3]==123 and zBox.db.bagPositions[2][4]==-234)
zBox:Request("gear",1)
''')
p.advance(3)
p.main.execute('assert(not zBox.UI.bagWindows[1].shown and zBox.bagSelection)')

# The exact gossip / quest text is carried separately from operation captions.
# Long text scrolls, and purchase confirmation still uses the existing handler.
p.alt.execute(NPC)
p.alt.execute(r'''
GetGossipText=function() return "Welcome, traveler.\n\nHow can I help you?" end
GetRewardText=function() return "You have done well. Choose your reward." end
GetObjectiveText=function() return "Bring back the lost relic." end
zBox:NPCEvent("GOSSIP_SHOW")
''')
p.main.execute('zBox:Request("npc",1)')
p.advance(4)
p.main.execute(r'''
assert(zBox.UI.npcDialogue.text=="Welcome, traveler.\n\nHow can I help you?")
assert(zBox.UI.cells[1].row[6]=="gossip")
''')
p.alt.execute('GetQuestText=function() return string.rep("The forest needs your help. ",80) end;zBox:NPCEvent("QUEST_DETAIL")')
p.advance(5)
p.main.execute('''
local u=zBox.UI
assert(string.find(u.npcDialogue.text,"Bring back the lost relic.",1,true))
assert(u.npcScroll.maxScroll>0 and u.cells[1].name.text=="Accept quest")
this=u.npcScroll;arg1=-1;this.scripts.OnMouseWheel()
assert(u.npcScroll:GetVerticalScroll()>0)
u:Refresh();assert(u.npcScroll:GetVerticalScroll()>0)
''')
p.alt.execute('zBox:NPCEvent("QUEST_COMPLETE")')
p.advance(4)
p.main.execute('assert(zBox.UI.npcDialogue.text=="You have done well. Choose your reward.");assert(zBox.UI.npcScroll:GetVerticalScroll()==0)')
p.alt.execute('zBox:NPCEvent("MERCHANT_SHOW")')
p.advance(4)
p.main.execute('zBox.UI:Click(zBox.UI.cells[1],"LeftButton")')
p.advance(.5)
assert call_count(p.alt, 'BuyMerchantItem') == 0
p.main.execute('zBox.UI:Click(zBox.UI.cells[1],"LeftButton")')
p.advance(.5)
assert call_count(p.alt, 'BuyMerchantItem') == 1
print('PASS: paper-doll slots, quest selection, spell icon restoration, independently cached/movable bags, stale-bag rejection, exact NPC dialogue/scrolling and confirmed vendor actions')
