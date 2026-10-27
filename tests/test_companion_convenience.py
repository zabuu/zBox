"""Two-client behavior for activity leases, direct dialogue and shared quests."""
from test_feedback_damage import call_count
from test_zbox import Pair, MACROS
from test_features import QUESTS, NPC
from pathlib import Path

# Lease refreshes neither jump nor touch the main client. A positive AFK flag
# is cleared once, rather than toggled speculatively every heartbeat.
p=Pair()
for lua in (p.main,p.alt):
    lua.execute('''
local native=zBoxNative
zBoxNative=function(name,...)
 if name=="RefreshActivity" then log(name);return 1 end
 return native(name,unpack(arg))
end
zBox.bridgeInfo={ready=true,activity=true,npc=true,label="Native inputs 0.1.9"};zBox.nextActivity=nil
away=true;UnitIsAFK=function() return away end
SendChatMessage=function(text,channel) assert(text=="" and channel=="AFK");away=false;log("ClearAFK") end
''')
p.advance(61)
assert call_count(p.alt,'RefreshActivity')==3 and call_count(p.main,'RefreshActivity')==0
assert call_count(p.alt,'ClearAFK')==1 and call_count(p.main,'ClearAFK')==0
assert call_count(p.alt,'Jump')==0
p.alt.execute('zBox:Slash("awake off")');p.advance(31)
assert call_count(p.alt,'RefreshActivity')==3
p.alt.execute('zBox:Slash("awake on")');p.advance(.2)
assert call_count(p.alt,'RefreshActivity')==4
p.online=False;p.advance(40)
assert call_count(p.alt,'RefreshActivity')==4
p.alt.execute('''
assert(not zBox.connected)
zBox.nextActivity=nil;zBox:ActivityTick(GetTime());assert(Jump==originalNativeJump)
zBox.connected=true;zBox.lastReceive=GetTime();zBox.worldSuspended=true;zBox:ActivityTick(GetTime())
''')
assert call_count(p.alt,'RefreshActivity')==4
print('PASS: background activity is agent-only, leased, rate-limited, revocable and stops on loss/loading; existing AFK clears once without movement')

# Whole quest logs travel independently of the selected panel. The pfQuest
# wrapper keeps the main's lines and adds the paired character's real counts.
p=Pair(ui=True)
for lua in (p.main,p.alt):lua.execute(QUESTS)
p.main.execute('quests[1][3]="Wolves slain: 5/8";quests[2][1]="Main questline";zBox.questCache=nil')
p.advance(8)
p.main.execute('''
assert(zBox.view=="actions" and zBox.cache.quests[1][7]=="Wolves slain: 2/8")
tip=CreateFrame("GameTooltip","PairedTestTooltip",UIParent);tip.lines={}
tip.AddLine=function(self,line)
 table.insert(self.lines,line)
 _G[self.name.."TextLeft"..table.getn(self.lines)]={GetText=function() return line end}
end
tip.NumLines=function(self) return table.getn(self.lines) end
tip.Reset=function(self) self.lines={} end
pfMap={ShowTooltip=function(self,meta,t) t:AddLine("Main: Wolves slain: 5/8");t:Show() end}
zBox:InstallQuestTooltip();local hook=pfMap.ShowTooltip;zBox:InstallQuestTooltip();assert(pfMap.ShowTooltip==hook)
meta={quest="Shared hunt",spawn="Wolves",item={}}
pfMap:ShowTooltip(meta,tip)
assert(tip.lines[1]=="Main: Wolves slain: 5/8" and tip.lines[2]=="Alt - Shared hunt" and tip.lines[3]=="  Wolves slain: 2/8")
pfMap:ShowTooltip(meta,tip);assert(table.getn(tip.lines)==4,"No duplicate remote section")
tip:Reset();pfMap:ShowTooltip({quest="Main questline",spawn="Relic",item={}},tip);assert(table.getn(tip.lines)==1)
tip:Reset();pfMap:ShowTooltip({quest="Alt questline",spawn="Relic",item={}},tip);assert(table.getn(tip.lines)==1)
''')
p.alt.execute('quests[1][3]="Wolves slain: 8/8";zBox.questCache=nil');p.advance(6)
p.main.execute('''
tip:Reset();pfMap:ShowTooltip(meta,tip)
assert(tip.lines[1]=="Main: Wolves slain: 5/8" and tip.lines[3]=="  Wolves slain: 8/8")
local original=zBox.QuestList
zBox.QuestList=function() return {{2,"id:1","Shared hunt",10,"In progress","","Wolves slain: 5/8"}} end
local old=zBox.cache.quests
zBox.cache.quests={{"2","id:2","Shared hunt","10","In progress","","Wolves slain: 0/8"}}
tip:Reset();pfMap:ShowTooltip(meta,tip);assert(table.getn(tip.lines)==1,"Different IDs must not be combined")
zBox.cache.quests=old;zBox.QuestList=original
local before=zBox.lastQuestProgress
zBox:AcceptQuestProgress({"questprogress",tostring(before),"1","1",""});assert(table.getn(zBox.cache.quests)==2)
zBox:AcceptQuestProgress({"questprogress",tostring(before+1),"2","2",""});assert(table.getn(zBox.cache.quests)==2,"Partial update stays invisible")
zBox:AcceptQuestProgress({"questprogress",tostring(before+1),"1","2",""});assert(table.getn(zBox.cache.quests)==0)
''')
p.alt.execute('quests={};zBox.questCache=nil');p.advance(6)
p.main.execute('tip:Reset();pfMap:ShowTooltip(meta,tip);assert(table.getn(tip.lines)==1)')
print('PASS: pfQuest retains main progress and appends independent shared-quest counts only; updates/removal, exact IDs, paging, replay and duplicate guards work')

# Also run the installed pfQuest's real tooltip builder when available. This
# integration check is optional in a standalone zBox checkout.
pf_source=Path(r'G:\Games\OctoWoW\Interface\AddOns\pfQuest\map.lua')
if pf_source.exists():
    p=Pair()
    for lua in (p.main,p.alt):lua.execute(QUESTS)
    p.main.execute('quests[1][3]="Wolves slain: 5/8";questCollapsed=false;zBox.questCache=nil')
    p.advance(6)
    source=pf_source.read_text(encoding='utf-8')
    function=source[source.index('function pfMap:ShowTooltip('):source.index('function pfMap:GetMapNameByID(')]
    p.main.execute('''
pfMap={tooltip={GetColor=function() return 1,1,0 end}}
compat={GetQuestLogTitle=GetQuestLogTitle};strfind=string.find
pfUI={api={SanitizePattern=function() return "(.+) slain: (%d+)/(%d+)" end}}
QUEST_MONSTERS_KILLED="%s slain: %d/%d"
realTip={lines={},AddLine=function(self,line) table.insert(self.lines,line) end,Show=function() end}
''')
    p.main.execute(function)
    p.main.execute('''
zBox:InstallQuestTooltip()
pfMap:ShowTooltip({quest="Shared hunt",spawn="Wolves",item={}},realTip)
assert(string.find(realTip.lines[2],"5/8",1,true))
assert(realTip.lines[3]=="Alt - Shared hunt" and string.find(realTip.lines[4],"2/8",1,true))
''')
    print('PASS: installed pfQuest tooltip function retains its own objective and appends the paired objective below it')

NPC_UNITS='''
local exists,names=UnitExists,UnitName
UnitExists=function(unit) if unit=="npc" then return true,"0x0000000000000099" end;return exists(unit) end
UnitName=function(unit) if unit=="npc" then return "Forest Keeper" end;return names(unit) end
GetGossipText=function() return "Welcome, traveler.\\nHow can I help you?" end
GetObjectiveText=function() return "Recover the relic." end
GetRewardText=function() return "Choose your reward." end
RAID_CLASS_COLORS={MAGE={r=.25,g=.78,b=.92}}
'''
p=Pair(ui=True)
for lua in (p.main,p.alt):lua.execute(NPC);lua.execute(NPC_UNITS)
p.main.execute('''
originalAccept=AcceptQuest;originalComplete=CompleteQuest
zBox.UI:Minimize();assert(zBox.UI.miniTalkButton.shown)
zBox.UI:Talk();assert(not zBox.UI.frame.shown and zBox.view=="actions")
''')
p.advance(3)
assert call_count(p.alt,'InteractNPC')==1
p.main.execute('''
local f=zBox.UI.npcWindow
assert(f.shown and not zBox.UI.frame.shown and zBox.view=="actions")
assert(f.art.template=="GossipFramePanelTemplate" and f.scroll.template=="UIPanelScrollFrameTemplate")
assert(f.art.level<f.chrome.level and f.art.level<f.scroll.level and f.art.level<f.close.level)
assert(f.dialogue.text=="Welcome, traveler.\\nHow can I help you?")
assert(f.classBorder.borderColor[1]==.25 and f.classBorder.borderColor[3]==.92)
this=f.rows[1];this.scripts.OnEnter();this.scripts.OnLeave()
f:Hide();zBox.UI:ReceiveNPC(zBox.cache.npc);assert(not f.shown,"Escape must stay dismissed at the same revision")
zBox.UI:OpenNPC();assert(f.shown)
assert(AcceptQuest==originalAccept and CompleteQuest==originalComplete)
''')
# Match the user's installed pfUI skin through its public API, without touching
# any of the existing dialogue frame's fields, scripts, or controls.
p.main.execute('''
GossipFrame=CreateFrame("Frame","GossipFrame",UIParent);GossipFrame.backdrop=CreateFrame("Frame",nil,GossipFrame)
GossipGreetingText=CreateFrame("FontString",nil,GossipFrame)
GossipGreetingText.GetFont=function() return "Fonts\\\\Test.ttf",14,"" end
GossipFrame.GetScale=function() return .92 end
pfUI={api={}}
pfUI.api.StripTextures=function(frame) frame.stripped=true end
pfUI.api.CreateBackdrop=function(frame,inset,legacy)
 if not legacy then frame.backdrop=CreateFrame("Frame",nil,frame) end
end
pfUI.api.SkinButton=function(frame) frame.pfButton=true end
pfUI.api.SkinCloseButton=function(frame) frame.pfClose=true end
zBox.UI:RenderNPCWindow(zBox.cache.npc)
local f=zBox.UI.npcWindow
assert(f.pfSkinned and f.art.stripped and f.primary.pfButton and f.close.pfClose)
assert(f.scale==.92 and f.paper.texture=="Interface\\\\Stationery\\\\StationeryTest1")
assert(f.backdrop.borderColor[3]==.92 and f.dialogue.fontSize==14)
assert(GossipFrame.backdrop.parent==GossipFrame and AcceptQuest==originalAccept)
''')
p.alt.execute('''
GetNumQuestRewards=function() return 1 end;GetRewardMoney=function() return 150 end
GetQuestItemInfo=function(kind,index) return (kind=="reward" and "Guaranteed reward" or ("Choice "..index)),"RewardIcon",1 end
zBox:NPCEvent("QUEST_COMPLETE")
''');p.advance(3)
p.main.execute('''
local f=zBox.UI.npcWindow
assert(f.shown and f.dialogue.text=="Choose your reward.")
this=f.rows[1];this.scripts.OnClick()
assert(f.primary.row[6]=="reward" and f.primary.shown)
assert(string.find(f.extras[1].label.text,"Guaranteed reward",1,true))
''')
assert call_count(p.alt,'GetQuestReward')==0
p.main.execute('this=zBox.UI.npcWindow.primary;this.scripts.OnClick()');p.advance(.8)
assert call_count(p.alt,'GetQuestReward')==1
p.main.execute('this=zBox.UI.npcWindow.primary;this.scripts.OnClick()');p.advance(.8)
assert call_count(p.alt,'GetQuestReward')==1
p.main.execute('zBox.UI:CloseNPC()');p.advance(.8)
p.main.execute('assert(not zBox.UI.npcWindow.shown,"A pending Close must not reopen from the intermediate action snapshot")')
p.alt.execute('zBox:NPCEvent("QUEST_FINISHED")');p.advance(1)
p.main.execute(MACROS)
p.main.execute('GetMacroIconInfo=function(index) return index==2 and "Interface\\\\Icons\\\\INV_Misc_Note_01" or "Other" end')
p.main.execute('''
assert(zBox:PickupControl("talk"));assert(cursorMacro)
for id,proxy in pairs(zBox.db.proxies) do if proxy.slot=="talk" then assert(proxy.command=="CONTROL");zBox:UseProxy(id) end end
''');p.advance(1)
assert call_count(p.alt,'InteractNPC')==2
print('PASS: one-step Talk/macros work minimized; automatic independent stock/pfUI dialogue, class border, exact text, reward selection, fingerprints, dismissal and Close work')

# Drive the actual quest-scene -> server quest-log change -> command -> remote
# gossip -> detail/progress/reward flow. No main protected API is wrapped.
def quest_pair():
    p=Pair(ui=True)
    for lua in (p.main,p.alt):
        lua.execute(QUESTS);lua.execute(NPC);lua.execute(NPC_UNITS)
        lua.execute('''
GetTitleText=function() return questTitle or "A new quest" end
GetGossipAvailableQuests=function() return "A new quest",10 end
GetGossipActiveQuests=function() return "Shared hunt",10 end
SelectGossipAvailableQuest=function(index) log("SelectGossipAvailableQuest",index);zBox:NPCEvent("QUEST_DETAIL") end
SelectGossipActiveQuest=function(index) log("SelectGossipActiveQuest",index);questTitle="Shared hunt";zBox:NPCEvent("QUEST_PROGRESS") end
CompleteQuest=function() log("CompleteQuest");zBox:NPCEvent("QUEST_COMPLETE") end
AcceptQuest=function() log("AcceptQuest");table.insert(quests,{"A new quest",10,"Relic: 0/1"});zBox.questCache=nil;zBox:NPCEvent("QUEST_FINISHED") end
GetQuestReward=function(index) log("GetQuestReward",index);table.remove(quests,1);zBox.questCache=nil;zBox:NPCEvent("QUEST_FINISHED") end
''')
    return p

p=quest_pair()
p.main.execute('''
mainAccept=AcceptQuest;mainReward=GetQuestReward
event="QUEST_DETAIL";zBoxEvents.scripts.OnEvent()
-- The user accepts locally; only a confirmed addition to the log is relayed.
table.insert(quests,{"A new quest",10,"Relic: 0/1"});zBox.questReadUntil=nil
event="QUEST_LOG_UPDATE";zBoxEvents.scripts.OnEvent()
''');p.advance(5)
assert call_count(p.alt,'InteractNPC')==1 and call_count(p.alt,'SelectGossipAvailableQuest')==1
assert call_count(p.alt,'AcceptQuest')==1
p.advance(3);assert call_count(p.alt,'AcceptQuest')==1
p.main.execute('''
assert(AcceptQuest==mainAccept and GetQuestReward==mainReward)
questTitle="Shared hunt";zBox.questCache=nil
event="QUEST_COMPLETE";zBoxEvents.scripts.OnEvent()
table.remove(quests,1);zBox.questReadUntil=nil
event="QUEST_LOG_UPDATE";zBoxEvents.scripts.OnEvent()
''')
p.alt.execute('completable=true;rewardChoices=0');p.advance(5)
assert call_count(p.alt,'CompleteQuest')==1 and call_count(p.alt,'GetQuestReward')==1
p.alt.execute('assert(not zBox.questIntent)')

# Multiple rewards require the remote player to choose. Ineligible, distant,
# cancelled, disabled and interrupted scenes never auto-accept or spend.
p=quest_pair()
p.main.execute('questTitle="Shared hunt";zBox:ObserveQuestScene("QUEST_COMPLETE");table.remove(quests,1);zBox.questCache=nil;zBox:ObserveQuestChange()')
p.alt.execute('completable=true;rewardChoices=2');p.advance(5)
assert call_count(p.alt,'CompleteQuest')==1 and call_count(p.alt,'GetQuestReward')==0
p.main.execute('assert(zBox.UI.npcWindow.shown and zBox.cache.npc.meta[1]=="reward")')
p.alt.execute('assert(not zBox.questIntent)')
p=quest_pair()
p.main.execute('zBox:ObserveQuestScene("QUEST_DETAIL");zBox:ObserveQuestScene("QUEST_FINISHED")');p.advance(2)
assert call_count(p.alt,'InteractNPC')==0
p.main.execute('zBox:Slash("quests off");zBox:ObserveQuestScene("QUEST_DETAIL");table.insert(quests,{"A new quest",10,"Relic: 0/1"});zBox.questCache=nil;zBox:ObserveQuestChange()');p.advance(2)
assert call_count(p.alt,'InteractNPC')==0
p=quest_pair()
p.alt.execute('local position=zBox.Position;zBox.Position=function(self,u) if u=="target" then return 50,0,0 end;return position(self,u) end')
p.command('zBox:Command("QUESTLINK",{"accept","","A new quest","0x0000000000000099"})');p.advance(2)
assert call_count(p.alt,'InteractNPC')==0 and call_count(p.alt,'AcceptQuest')==0
p=quest_pair()
p.alt.execute('completable=false')
p.command('zBox:Command("QUESTLINK",{"complete","","Shared hunt","0x0000000000000099"})');p.advance(4)
assert call_count(p.alt,'CompleteQuest')==0 and call_count(p.alt,'GetQuestReward')==0
p=quest_pair()
p.command('zBox:Command("QUESTLINK",{"accept","","A new quest","0x0000000000000099"});zBox:Command("STOP")');p.advance(3)
assert call_count(p.alt,'AcceptQuest')==0
print('PASS: main-confirmed linked quest pickup/turn-in validates NPC/range/eligibility, follows real dialogue events, runs once, leaves reward choices visible and respects cancel/off/STOP')
