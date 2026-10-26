"""Extended two-client regressions; importing the base suite runs its checks too."""
from test_zbox import Pair, call_count, MACROS

p=Pair()
p.alt.execute('''
GetSpellInfo=function() return "Fireball","Rank 1","Icon",1,false,0,3000 end
moving=true;GetUnitSpeed=function() return moving and 7 or 0 end
local normal=UseAction
UseAction=function(a,b,c) assert(not zBox.following and not moving);normal(a,b,c);zBox:CastEvent("SPELLCAST_START",3000) end
''')
p.command('zBox:Command("FOLLOW")')
p.alt.execute('calls={};axes.MoveForward=true;axes.StrafeLeft=true')
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"KEEP"})');p.advance(.3)
assert call_count(p.alt,'UseAction')==0
p.alt.execute('assert(calls[7][1]=="StopFollow" and not nativeFollowing);for _,v in pairs(axes) do assert(not v) end;moving=false')
p.advance(.3)
assert call_count(p.alt,'UseAction')==1
p.alt.execute('combat=true');p.advance(4)
assert not p.alt.globals().zBox.following
p.alt.execute('zBox:CastEvent("SPELLCAST_STOP");combat=false');p.advance(1)
assert p.alt.globals().zBox.following
p.alt.execute('UnitAffectingCombat=function(unit) return unit=="party1" end')
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"KEEP"})');p.advance(5)
assert not p.alt.globals().zBox.following
p.command('zBox:Command("STOP")');p.alt.execute('UnitAffectingCombat=function() return false end');p.advance(2)
assert not p.alt.globals().zBox.following
p.alt.execute('moving=true')
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"KEEP"})');p.advance(3)
assert call_count(p.alt,'UseAction')==2
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"KEEP"});zBox:Command("AXES",{1})');p.advance(1)
p.alt.execute('moving=false');p.advance(1)
assert call_count(p.alt,'UseAction')==2
print("PASS: casts wait for rest, cancel native follow/all axes, resume after both characters leave combat, respect stop/manual overrides")

p=Pair(ui=True);p.main.execute(MACROS)
p.main.execute('zBox:Request("spells",1)');p.advance(3)
p.main.execute('this=zBox.UI.cells[1];arg1="LeftButton";this.scripts.OnDragStart()');p.advance(1)
p.main.execute('this=zBox.UI.cells[1];arg1="LeftButton";this.scripts.OnClick();this.scripts.OnDragStop();this.scripts.OnClick();assert(cursorMacro==19)')
p.advance(1)
assert call_count(p.alt,'CastSpell')==0
p.main.execute('cursorMacro=nil;this=zBox.UI.cells[1];IsShiftKeyDown=function() return true end;zBox.UI:Click(this,"LeftButton");assert(cursorMacro==19);IsShiftKeyDown=function() return false end')
print("PASS: spellbook widget long drag/release and shift-click export a macro without casting")

p=Pair(ui=True)
for scale in [.55,.85,1.25]:
    p.main.globals().testScale=scale
    p.main.execute('''
UIParent.height=900;UIParent.scale=.8
zBox.UI.frame:SetScale(testScale)
local s=zBox.UI.frame:GetEffectiveScale()
zBox.UI.frame.mockTop=890*.8/s;zBox.UI.frame.mockBottom=(890*.8-110*s)/s
zBox.UI:PlacePanels()
for _,f in ipairs({zBox.UI.browser,zBox.UI.setup,zBox.UI.keys}) do
 assert(f.point[1]=="TOPLEFT" or f.point[1]=="TOPRIGHT")
 assert(f.point[3]=="BOTTOMLEFT" or f.point[3]=="BOTTOMRIGHT")
 assert(f:GetFrameLevel()>zBox.UI.frame:GetFrameLevel())
 assert(f:GetHeight()*f:GetEffectiveScale() <= zBox.UI.frame.mockBottom*s)
end
zBox.UI.frame.mockBottom=10;zBox.UI.frame.mockTop=120
zBox.UI:PlacePanels();assert(zBox.UI.browser.point[1]=="BOTTOMLEFT")
''')
print("PASS: scale-aware browser/setup/keys popouts choose below/above without covering the dock")

QUESTS=r'''
questSelection=2;questCollapsed=true
quests={{"Shared hunt",10,"Wolves slain: 2/8"},{"Alt questline",12,"Relic: 0/1"}}
local function entry(index)
 if index==1 then return {"Forest",0,nil,true,questCollapsed} end
 if not questCollapsed and quests[index-1] then local q=quests[index-1];return {q[1],q[2],nil,nil,nil,q[4]} end
end
GetNumQuestLogEntries=function() return questCollapsed and 1 or #quests+1,#quests end
GetQuestLogTitle=function(i) local r=entry(i);if r then return unpack(r,1,6) end end
ExpandQuestHeader=function(i) questCollapsed=false end
CollapseQuestHeader=function(i) assert(i==1);questCollapsed=true end
GetQuestLogSelection=function() return questSelection end
SelectQuestLogEntry=function(i) questSelection=i end
GetNumQuestLeaderBoards=function(i) return 1 end
GetQuestLogLeaderBoard=function(o,i) return quests[i-1][3],"monster",false end
'''
p=Pair(ui=True)
for client in [p.main,p.alt]:client.execute(QUESTS)
p.main.execute('quests[1][3]="Wolves slain: 5/8";quests[2][1]="Main questline";zBox:Request("quests",1)');p.advance(5)
p.main.execute('''
assert(zBox.cache.view.section=="quests" and #zBox.cache.view.rows==2)
local r=zBox.cache.view.rows[1];assert(string.find(r[7],"2/8") and string.find(zBox:QuestComparison(r),"5/8"))
assert(string.find(zBox:QuestComparison(zBox.cache.view.rows[2]),"not in quest log"))
assert(#zBox:MainOnlyQuests()==1 and zBox:MainOnlyQuests()[1][3]=="Main questline")
assert(questCollapsed and questSelection==2)
zBox.UI.questMainOnly=true;zBox.UI:Refresh();assert(string.find(zBox.UI.cells[1].name.text,"Main questline"))
''')
p.alt.execute('assert(questCollapsed and questSelection==2);quests[1][3]="Wolves slain: 8/8";zBox.questCache=nil;zBox.viewDirty=true');p.advance(4)
p.main.execute('assert(string.find(zBox.cache.view.rows[1][7],"8/8"))')
print("PASS: separate questlines/objectives and main-only quests; collapsed headers/selection restored")

NPC=r'''
UnitIsPlayer=function() return false end;UnitCanAttack=function() return false end
GetMoney=function() return money or 100000 end
merchantPrice=250;merchantStock=-1;trainerState="available";trainerPrice=1000
GetGossipOptions=function() return "Browse goods","vendor","Train me","trainer" end
GetGossipAvailableQuests=function() return "A new quest",10 end
GetGossipActiveQuests=function() return "Shared hunt",10 end
GetNumAvailableQuests=function() return 1 end;GetAvailableTitle=function() return "A new quest" end
GetNumActiveQuests=function() return 1 end;GetActiveTitle=function() return "Shared hunt" end
GetTitleText=function() return "A new quest" end
GetQuestText=function() return "Help the forest" end
GetProgressText=function() return "Have you found it?" end
IsQuestCompletable=function() return completable end
GetNumQuestChoices=function() return rewardChoices or 2 end
GetQuestItemInfo=function(kind,index) return "Reward "..index,"RewardIcon",1 end
GetMerchantNumItems=function() return 1 end
GetMerchantItemInfo=function() return "Water","ItemIcon",merchantPrice,5,merchantStock,true end
GetNumTrainerServices=function() return 1 end
GetTrainerServiceInfo=function() return "Fireball","Rank 2",trainerState end
GetTrainerServiceCost=function() return trainerPrice end
GetTrainerServiceIcon=function() return "SpellIcon" end
for _,name in ipairs({"SelectGossipOption","SelectGossipAvailableQuest","SelectGossipActiveQuest","SelectAvailableQuest","SelectActiveQuest",
 "AcceptQuest","CompleteQuest","GetQuestReward","BuyMerchantItem","BuyTrainerService","CloseGossip","CloseQuest","CloseMerchant","CloseTrainer"}) do
 local fn=name;_G[fn]=function(a,b) log(fn,a,b) end
end
InteractNPC=function(guid) log("InteractNPC",guid);zBox:NPCEvent("GOSSIP_SHOW") end
'''
p=Pair(ui=True);p.alt.execute(NPC)
p.main.execute('zBox:Request("npc",1)');p.advance(2)
p.command('zBox:Command("TALK",{"0x0000000000000099"})');p.advance(3)
assert call_count(p.alt,'InteractNPC')==1
p.main.execute('assert(#zBox.cache.view.rows==5)')
p.command('local r=zBox.cache.view.rows[1];zBox:Command("NPC",{r[6],r[1],r[5]})')
assert call_count(p.alt,'SelectGossipOption')==1
for event,op,fn,index in [('GOSSIP_SHOW','gossipAvailable','SelectGossipAvailableQuest',3),('GOSSIP_SHOW','gossipActive','SelectGossipActiveQuest',4),('QUEST_GREETING','available','SelectAvailableQuest',1),('QUEST_GREETING','active','SelectActiveQuest',2),('QUEST_DETAIL','accept','AcceptQuest',1),('QUEST_PROGRESS','complete','CompleteQuest',1),('QUEST_COMPLETE','reward','GetQuestReward',2)]:
    p.alt.execute(f'completable=true;zBox:NPCEvent("{event}")');p.advance(3)
    p.command(f'local r=zBox.cache.view.rows[{index}];assert(r[6]=="{op}");zBox:Command("NPC",{{r[6],r[1],r[5]}})')
    assert call_count(p.alt,fn)==1
p.alt.execute('zBox:NPCEvent("MERCHANT_SHOW")');p.advance(3)
p.main.execute('zBox.UI.frame:Show();zBox.UI:Refresh();zBox.UI:Click(zBox.UI.cells[1],"LeftButton")');p.advance(.5)
assert call_count(p.alt,'BuyMerchantItem')==0
p.main.execute('zBox.UI:Click(zBox.UI.cells[1],"LeftButton")');p.advance(.5)
assert call_count(p.alt,'BuyMerchantItem')==1
p.alt.execute('assert(calls[#calls][1]=="BuyMerchantItem" and calls[#calls][3]==1)')
p.advance(3)
p.main.execute('oldNPCRow=zBox.cache.view.rows[1]')
p.alt.execute('merchantPrice=500')
p.command('local r=oldNPCRow;zBox:Command("NPC",{r[6],r[1],r[5]})')
assert call_count(p.alt,'BuyMerchantItem')==1
p.alt.execute('zBox:NPCEvent("MERCHANT_UPDATE")');p.advance(3)
p.alt.execute('money=0')
p.command('local r=zBox.cache.view.rows[1];zBox:Command("NPC",{r[6],r[1],r[5]})')
assert call_count(p.alt,'BuyMerchantItem')==1
p.alt.execute('money=100000;zBox:NPCEvent("TRAINER_SHOW")');p.advance(3)
p.command('local r=zBox.cache.view.rows[1];zBox:Command("NPC",{r[6],r[1],r[5]});zBox:Command("NPC",{r[6],r[1],r[5]})')
assert call_count(p.alt,'BuyTrainerService')==1
p.advance(3)
p.alt.execute('trainerState="unavailable";zBox:NPCEvent("TRAINER_UPDATE")');p.advance(3)
p.command('local r=zBox.cache.view.rows[1];zBox:Command("NPC",{r[6],r[1],r[5]})')
assert call_count(p.alt,'BuyTrainerService')==1
p.alt.execute('zBox:NPCEvent("TRAINER_CLOSED")');p.advance(3)
p.main.execute('assert(#zBox.cache.view.rows==0)')
print("PASS: nearby NPCs, gossip/quest/rewards, confirmed one-off vendor buys/training; stale prices, duplicate spends, closed/unavailable dialogs reject")

# Read the main's actual movement flags and heading, including camera turns.
p=Pair(ui=True)
p.command('zBox:Command("FOLLOW")')
p.main.execute('assert(zBox:SetMirrorMode(true));MoveForwardStart();facing=1.2')
p.advance(.8)
p.alt.execute('assert(not zBox.following and axes.MoveForward and math.abs(facing-1.2)<.001)')
assert call_count(p.main,'MoveForwardStart')==1
p.main.execute('facing=2.1;StrafeLeftStart();Jump()');p.advance(.5)
p.alt.execute('assert(axes.MoveForward and axes.StrafeLeft and math.abs(facing-2.1)<.001)')
assert call_count(p.main,'Jump')==1 and call_count(p.alt,'Jump')==1
p.main.execute('MoveForwardStop();StrafeLeftStop();facing=.25');p.advance(.5)
p.alt.execute('assert(not axes.MoveForward and not axes.StrafeLeft and math.abs(facing-.25)<.001)')
# Stationary turning is synchronized by absolute headings, not a second turn rate.
p.main.execute('TurnLeftStart();facing=3.4');p.advance(.5)
p.alt.execute('assert(not axes.TurnLeft and math.abs(facing-3.4)<.001)')
p.main.execute('TurnLeftStop();MoveForwardStart()');p.advance(.5)
p.alt.execute('GetSpellInfo=function() return "Fireball","Rank 1","Icon",1,false,0,1500 end')
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"KEEP"})');p.advance(.7)
p.alt.execute('assert(not axes.MoveForward and not zBox.following)')
p.main.execute('facing=4.2;Jump()');p.advance(.4)
assert call_count(p.alt,'Jump')==1
p.advance(2)
p.alt.execute('assert(axes.MoveForward and math.abs(facing-4.2)<.001 and not zBox.following)')
# A stopped stream expires even though both clients remain connected.
p.main.execute('zBox.MirrorTick=function() end');p.advance(1)
p.alt.execute('assert(not axes.MoveForward and not zBox.mirrorInput)')
# STOP pauses the stream until explicitly resumed. Hidden panels still mirror.
p=Pair(ui=True)
p.main.execute('assert(zBox:SetMirrorMode(true));MoveForwardStart();zBox.UI.frame:Hide()');p.advance(.5)
p.alt.execute('assert(axes.MoveForward)')
p.command('zBox:Command("STOP")');p.advance(1)
p.alt.execute('assert(not axes.MoveForward)')
assert p.main.globals().zBox.mirrorPaused
p.main.execute('zBox:ToggleMirrorPause()');p.advance(.5)
p.alt.execute('assert(axes.MoveForward)')
p.main.execute('assert(zBox:SetMirrorMode(false))');p.advance(.5)
p.alt.execute('assert(not axes.MoveForward)')
# Invalid headings, opposing directions, zone differences and older bridges reject.
p.alt.execute('assert(not zBox:AcceptMirror(1,0/0,"Test Zone"));assert(not zBox:AcceptMirror(3,1,"Test Zone"));assert(not zBox:AcceptMirror(1,1,"Other Zone"))')
p.main.execute('zBox.bridgeInfo={ready=true,npc=false,mirror=false};assert(not zBox:SetMirrorMode(true))')
print("PASS: mirror mode copies normal movement/jump/camera heading, pauses during casts, resumes afterward, works hidden, expires lost streams and obeys STOP/mode switches")
print("All extended zBox checks passed.")
