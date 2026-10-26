"""Moving melee enemies, aggro transitions, and real remote macro cooldowns."""
from test_pet_mode import pet_pair, Pair, MACROS, call_count
import math

# Rear positioning works during combat, including after a target rotates.
p=pet_pair()
p.alt.execute('mainCombat=true;ownCombat=true;enemies[enemyGUID].facing=math.pi;enemies[enemyGUID].victim=peerGUID')
p.main.execute('assert(zBox:AttackCommand())');p.advance(4,physics=True)
p.alt.execute('assert(attacking and px>13 and zBox.petState.guid==enemyGUID);enemies[enemyGUID].facing=0')
p.advance(3.5,physics=True)
p.alt.execute('assert(attacking and px<11 and not zBox.destination)')
# Translation and rotation require a fresh rear point, not the old arrival.
p.alt.execute('enemies[enemyGUID].x=19;enemies[enemyGUID].y=4;enemies[enemyGUID].facing=math.pi/2')
p.advance(4,physics=True)
p.alt.execute('local e=enemies[enemyGUID];local d=math.sqrt((px-e.x)^2+(py-e.y)^2);assert(d<3.5 and py<e.y-1 and attacking)')

# Gaining aggro cancels a rear goal immediately, before the replan interval.
p=pet_pair()
p.alt.execute('mainCombat=true;ownCombat=true;enemies[enemyGUID].victim=peerGUID;enemies[enemyGUID].facing=math.pi')
p.main.execute('assert(zBox:AttackCommand())');p.advance(.25)
p.alt.execute('assert(zBox.destination and math.abs(zBox.destination.y)>1);enemies[enemyGUID].victim=ownGUID')
p.advance(.25)
p.alt.execute('assert(zBox.destination and math.abs(zBox.destination.y)<.1 and zBox.destination.x<enemies[enemyGUID].x)')
p.advance(2,physics=True)
p.alt.execute('assert(attacking and not zBox.destination and px<12);enemies[enemyGUID].facing=0')
before=call_count(p.alt,'MoveTo');p.advance(1,physics=True)
assert call_count(p.alt,'MoveTo')==before
# Losing aggro permits a rear correction again, with no new Attack command.
p.alt.execute('enemies[enemyGUID].facing=math.pi;enemies[enemyGUID].victim=peerGUID')
p.advance(3.5,physics=True)
p.alt.execute('assert(attacking and px>13)')
# A missing victim during combat does not authorize circling the enemy.
p=pet_pair();p.alt.execute('px=9;mainCombat=true;ownCombat=true;enemies[enemyGUID].facing=math.pi')
p.main.execute('assert(zBox:AttackCommand())');p.advance(.8,physics=True)
p.alt.execute('assert(attacking and not zBox.destination and px<12)')

# Refresh a long chase without braking at each destination update. Moving for
# more than 35 seconds remains valid; the physical no-progress lease still wins.
p=pet_pair();p.alt.execute('mainCombat=true;ownCombat=true;enemies[enemyGUID].x=60;enemies[enemyGUID].victim=peerGUID')
p.main.execute('assert(zBox:AttackCommand())');p.advance(.3,physics=True)
stops=call_count(p.alt,'StopFollow')
for _ in range(60):
    p.alt.execute('enemies[enemyGUID].x=enemies[enemyGUID].x+.3')
    p.advance(.1,physics=True)
assert call_count(p.alt,'MoveTo')>10 and call_count(p.alt,'StopFollow')==stops
p.advance(12,physics=True)
p.alt.execute('assert(attacking and zBox.petState.guid==enemyGUID)')
for _ in range(400):
    p.alt.execute('enemies[enemyGUID].x=enemies[enemyGUID].x+.2')
    p.advance(.1,physics=True)
p.alt.execute('local e=enemies[enemyGUID];assert(attacking and zBox.petState.guid==enemyGUID and e.x-px<5)')
# A new main target changes an active Pet Attack as well as armed Assist.
p.alt.execute('enemies[otherGUID].x=px+8;enemies[otherGUID].victim=peerGUID;mainTarget=otherGUID')
p.advance(2,physics=True)
p.alt.execute('assert(zBox.petState.guid==otherGUID and selectedGUID==otherGUID and attacking);enemies[otherGUID].dead=true')
p.advance(.4)
p.alt.execute('assert(zBox.following and not zBox.petState.guid and not attacking)')
p=pet_pair();p.alt.execute('mainCombat=true;ownCombat=true;enemies[enemyGUID].x=40;enemies[enemyGUID].victim=peerGUID')
p.main.execute('assert(zBox:AttackCommand())');p.advance(.3,physics=True)
for _ in range(400):
    p.alt.execute('enemies[enemyGUID].x=enemies[enemyGUID].x+.65')
    p.advance(.1,physics=True)
p.alt.execute('assert(zBox.petState.guid==enemyGUID and zBox.destination and clock-zBox.destination.started>35 and px>200)')
# A new explicit order is not undone by the old party-target snapshot arriving
# before the main's new target becomes visible to account 2.
p=pet_pair();p.main.execute('selectedGUID=otherGUID;assert(zBox:AttackCommand())');p.advance(.7)
p.alt.execute('assert(zBox.petState.guid==otherGUID);mainTarget=otherGUID');p.advance(.4)
p.alt.execute('assert(zBox.petState.guid==otherGUID)')
p=pet_pair();p.alt.execute('mainCombat=true;enemies[enemyGUID].x=45;enemies[enemyGUID].victim=peerGUID;physics=function() end')
p.main.execute('assert(zBox:AttackCommand())')
for _ in range(45):
    p.alt.execute('enemies[enemyGUID].x=enemies[enemyGUID].x+.1')
    p.advance(.1,physics=True)
p.alt.execute('assert(not zBox.petState and not nativePoint)')
# Remote casts retain their facing/movement lock while the enemy moves.
p=pet_pair();p.alt.execute('mainCombat=true;enemies[enemyGUID].victim=peerGUID')
p.main.execute('assert(zBox:AttackCommand())');p.advance(.5,physics=True)
p.alt.execute('zBox:CastEvent("SPELLCAST_START",3000)');p.advance(.1)
before=call_count(p.alt,'MoveTo')
p.alt.execute('enemies[enemyGUID].x=25');p.advance(2,physics=True)
assert call_count(p.alt,'MoveTo')==before
p.alt.execute('zBox:CastEvent("SPELLCAST_STOP")');p.advance(1,physics=True)
assert call_count(p.alt,'MoveTo')>before
p.main.execute('zBox:PetOrder("follow")');p.advance(.5)
p.alt.execute('assert(zBox.following and not zBox.petState.guid and not nativePoint)')
print('PASS: continuous melee range/rear chase through movement and turns, aggro gain/loss/unknown victim, long chase without repeated brakes, main-target switch/death/recall, physical stuck detection and cast locks')

# Cooldowns come from account 2, including off-page actions and spellbook
# exports, and show on pfUI/stock macro buttons while the zBox dock is hidden.
p=Pair(ui=True);p.main.execute(MACROS)
p.alt.execute('''
actions[25]=true
remoteActionCD={};remoteSpellCD={}
GetActionCooldown=function(slot) local cd=remoteActionCD[slot];if cd then return cd.start,cd.duration,cd.enabled or 1 end;return 0,0,1 end
GetSpellCooldown=function(slot,book) assert(book=="spell");local cd=remoteSpellCD[slot];if cd then return cd.start,cd.duration,cd.enabled or 1 end;return 0,0,1 end
''')
stamp=p.alt.eval('zBox:ActionStamp(25)')
spellstamp=p.alt.eval('zBox:SpellStamp(1)')
p.main.globals().remoteStamp=stamp;p.main.globals().remoteSpellStamp=spellstamp
p.main.execute(r'''
C_Macro={CreateMacro=function(name,texture,body,character)
 for i=19,36 do if not macros[i] then macros[i]={name=name,icon=texture,body=body};return i end end
end}
assert(zBox:PickupRemote("actions",{"25","RemoteIcon","Remote action",remoteStamp}));cursorMacro=nil
assert(zBox:PickupRemote("spells",{"1","SpellIcon1","Remote spell","Rank 1",remoteSpellStamp,"0"}));cursorMacro=nil
local original=GetActionInfo
barMacros={[5]=19,[61]=20,[18]=19}
GetActionInfo=function(slot) if barMacros[slot] then return "macro",barMacros[slot] end;return original(slot) end
pfActionBarMainButton1=CreateFrame("Button","pfActionBarMainButton1",UIParent);pfActionBarMainButton1.id=5
pfActionBarMainButton1:SetWidth(32);pfActionBarMainButton1:SetHeight(32)
ActionButton1=CreateFrame("Button","ActionButton1",UIParent);ActionButton1.pageSlot=18
ActionButton_GetPagedID=function(button) return button.pageSlot end
MultiBarBottomLeftButton1=CreateFrame("Button","MultiBarBottomLeftButton1",UIParent)
GetActionCooldown=function() return clock,99,1 end -- must never supply the remote timer
originalLocalCD=GetActionCooldown;originalLocalAction=GetActionInfo
CooldownFrame_SetTimer=function(frame,start,duration,enabled) frame.remoteTimer={start,duration,enabled};log("DrawCooldown",duration) end
zBox.UI:Minimize()
''')
p.advance(1)
p.alt.execute('assert(zBox.agentCooldownWatches["1"].slot==25 and zBox.agentCooldownWatches["2"].command=="SPELL");remoteActionCD[25]={start=clock,duration=12};remoteSpellCD[1]={start=clock,duration=90}')
p.advance(.5)
p.main.execute('''
assert(not zBox.UI.frame.shown and zBox.cache.proxyCooldowns["1"].duration==12)
assert(pfActionBarMainButton1.zBoxCooldown.shown and ActionButton1.zBoxCooldown.shown and MultiBarBottomLeftButton1.zBoxCooldown.shown)
assert(pfActionBarMainButton1.zBoxCooldown.text.text=="12" and MultiBarBottomLeftButton1.zBoxCooldown.text.text=="2m")
assert(pfActionBarMainButton1.zBoxCooldown.swipe.remoteTimer[2]==12)
assert(not pfActionBarMainButton1.zBoxCooldown.mouseEnabled)
assert(GetActionCooldown==originalLocalCD and GetActionInfo==originalLocalAction)
''')
p.advance(3)
p.main.execute('assert(tonumber(pfActionBarMainButton1.zBoxCooldown.text.text)<10)')
# Resets and cooldowns started directly on account 2 update the bar as well.
p.alt.execute('remoteActionCD[25]=nil');p.advance(.4)
p.main.execute('assert(not pfActionBarMainButton1.zBoxCooldown.shown)')
p.alt.execute('remoteActionCD[25]={start=clock,duration=5}');p.advance(.4)
p.main.execute('assert(pfActionBarMainButton1.zBoxCooldown.shown)')
# Macro swaps / changing the displayed pfUI action page remove old overlays.
p.main.execute('pfActionBarMainButton1.id=6;barMacros[61]=19');p.advance(.3)
p.main.execute('assert(not pfActionBarMainButton1.zBoxCooldown.shown and MultiBarBottomLeftButton1.zBoxCooldown.duration==5)')
p.main.execute('pfActionBarMainButton1.id=5');p.advance(.3)
# Invalid stamps, old/duplicate snapshots, invalid values and old watch lists
# cannot overwrite a valid current cooldown.
p.main.execute('''
local token=zBox.cooldownWatchToken;local id=zBox.lastProxyCooldownID
local cache=zBox.cache.proxyCooldowns
zBox:AcceptProxyCooldowns({"proxycd",token,"1^99999999^1^1"},id+1);assert(zBox.cache.proxyCooldowns==cache)
zBox:AcceptProxyCooldowns({"proxycd","oldtoken","1^0^0^1"},id+1);assert(zBox.cache.proxyCooldowns==cache)
zBox:AcceptProxyCooldowns({"proxycd",token,"1^0^0^1"},id);assert(zBox.cache.proxyCooldowns==cache)
''')
p.alt.execute('actions[25]=nil');p.advance(.4)
p.main.execute('assert(not zBox.cache.proxyCooldowns["1"].valid and not pfActionBarMainButton1.zBoxCooldown.shown)')
# Removing a macro unsubscribes it. Re-exporting after slot changes updates its
# stamp; a new pairing never inherits another character's timers.
p.main.execute('macros[19]=nil;zBox.nextWatchScan=nil');p.advance(.5)
p.main.execute('assert(not zBox.cooldownWatches["1"] and not ActionButton1.zBoxCooldown.shown)')
p.main.execute('barMacros[61]=20')
p.alt.execute('remoteSpellCD[1]={start=clock,duration=1}');p.advance(.3)
p.main.execute('assert(MultiBarBottomLeftButton1.zBoxCooldown.shown)')
p.advance(1.2)
p.main.execute('assert(not MultiBarBottomLeftButton1.zBoxCooldown.shown)')
p.alt.execute('''
local watches=zBox.agentCooldownWatches
zBox:AcceptCooldownWatches({"badtoken","1^INVOKE^1^0"},zBox.lastWatchID+1);assert(zBox.agentCooldownWatches==watches)
zBox:AcceptCooldownWatches({"badtoken",""},zBox.lastWatchID);assert(zBox.agentCooldownWatches==watches)
remoteSpellCD[1]={start=clock,duration=20}
''')
p.main.execute('zBox:Disconnect();assert(not ActionButton1.zBoxCooldown.shown and not zBox.cooldownWatchToken)')
p.advance(8)
p.main.execute('assert(zBox.connected and zBox.cooldownWatches["2"] and MultiBarBottomLeftButton1.zBoxCooldown.shown)')
print('PASS: remote action/spellbook cooldown subscriptions independent of pages/dock, direct remote casts/reset/expiry, pfUI/stock/paged macro timers, unchanged game APIs, macro swaps/removal, stale stamps/replayed/invalid snapshots and disconnect cleanup')
