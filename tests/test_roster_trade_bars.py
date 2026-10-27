"""Three isolated clients, real protocol routing and guarded item/UI actions."""
from test_zbox import endpoint, call_count, MACROS
from pathlib import Path

class Team:
    def __init__(self):
        self.clients={n:endpoint(n,'Alt' if n=='Main' else 'Main',True) for n in ['Main','Alt','Beta']}
        self.time=10;self.wire=[];self.history=[];self.off=set()
        for n,lua in self.clients.items():
            lua.globals().ownGUID=f'0x{list(self.clients).index(n)+1:016x}'
            lua.globals().sendPeer=lambda target,packet,n=n:self.send(n,target,packet)
            lua.execute(r'''
local old=zBoxNative
zBoxNative=function(cmd,...)
 if cmd=="capabilities" then return 1,"zBoxBridge 0.1.10",9 end
 if cmd=="LocalSelect" or cmd=="LocalCloseAll" then return 1 end
 if cmd=="Whisper" then sendPeer(unpack(arg));return 1 end
 return old(cmd,unpack(arg))
end
local exists,name=UnitExists,UnitName
UnitExists=function(u)
 if u=="NPC" or u=="npc" then return tradePartner~=nil,tradePartner end
 if u=="0x0000000000000001" or u=="0x0000000000000002" or u=="0x0000000000000003" or u=="0x0000000000000004" then return true,u end
 return exists(u)
end
UnitName=function(u)
 if u=="NPC" or u=="npc" then u=tradePartner end
 local names={["0x0000000000000001"]="Main",["0x0000000000000002"]="Alt",["0x0000000000000003"]="Beta",["0x0000000000000004"]="Friend"}
 return names[u] or name(u)
end
UnitIsPlayer=function(u) return u=="target" or (u and string.find(u,"^0x")) end
UnitCanAttack=function() return false end
UnitPowerType=function() return 3 end
grouped=false;zBox.db.localTransport=false;zBox.bridgeInfo=nil
''')
        self.main=self.clients['Main'];self.alt=self.clients['Alt'];self.beta=self.clients['Beta']
        for n in ['Alt','Beta']: self.clients[n].execute('assert(zBox:Configure("agent","Main","testcode123"))')
        self.main.execute('assert(zBox:ConfigureRoster({"Alt","Beta"},"testcode123"))')
        self.advance(7)
        self.main.execute('assert(zBox.connected and zBox:FollowerState("Beta").connected)')
    def send(self,src,target,packet):
        assert target in self.clients
        self.wire.append((src,target,packet));self.history.append((src,target,packet))
    def advance(self,seconds):
        for _ in range(round(seconds/.05)):
            self.time+=.05
            for n,lua in self.clients.items():
                if n in self.off: continue
                lua.globals().clock=self.time;lua.globals().zBox.Tick(lua.globals().zBox,self.time,.05)
            wire,self.wire=self.wire,[]
            for src,dst,packet in wire:
                if src not in self.off and dst not in self.off:
                    lua=self.clients[dst];lua.globals().zBox.Receive(lua.globals().zBox,'zBox2',packet,'UNKNOWN',src)

t=Team()
t.main.execute('assert(zBox.cache.status[2]=="Alt");assert(zBox:FollowerState("Beta").cache.status[2]=="Beta");assert(zBox.session~=zBox:FollowerState("Beta").session)')
t.main.execute('assert(zBox:Command("FOLLOW"))');t.advance(1)
assert call_count(t.alt,'FollowUnit')==1 and call_count(t.beta,'FollowUnit')==1
t.main.execute(MACROS)
t.main.execute(r'zBox.macroIcons={ [string.lower("Interface\\Icons\\Ability_Tracking")]=2 }')
t.main.execute('assert(zBox:PickupControl("follow"));cursorMacro=nil;assert(zBox:SelectFollower("Beta"));zBox:UseProxy("1");assert(zBox:SelectFollower("Alt"))');t.advance(.5)
assert call_count(t.alt,'FollowUnit')==2 and call_count(t.beta,'FollowUnit')==2
t.main.execute('assert(zBox:Command("ACTION",{1,zBox.cache.bar.rows[1][4],"SELF"}))');t.advance(1)
assert call_count(t.alt,'UseAction')==1 and call_count(t.beta,'UseAction')==0
t.main.execute('assert(zBox:SelectFollower("Beta"));assert(zBox.cache.status[2]=="Beta");assert(zBox:Command("SPELL",{1,zBox:SpellStamp(1),"SELF"}))');t.advance(1)
assert call_count(t.beta,'CastSpell')==1 and call_count(t.alt,'CastSpell')==0
t.main.execute('assert(zBox:Command("AXES",{1}));assert(zBox:Command("STOP"))');t.advance(.5)
for lua in [t.alt,t.beta]:lua.execute('for _,v in pairs(axes) do assert(not v) end')
t.main.execute('zBox.UI:ShowSetup();assert(table.getn(zBox.UI.peerRows)==2);zBox.UI:AddFollowerRow("Third");assert(zBox.UI.setup:GetHeight()==438);zBox.UI.peerRows[3].remove.scripts.OnClick();assert(table.getn(zBox.UI.peerRows)==2);assert(zBox:SelectFollower("Alt"))')
assert t.main.globals().zBox.db.peer=='Alt'
t.off.add('Beta');t.advance(5)
t.main.execute('assert(zBox.connected and not zBox:FollowerState("Beta").connected);assert(zBox.db.peer=="Alt")')
t.off.clear();t.advance(6)
t.main.execute('assert(zBox:FollowerState("Beta").connected);assert(zBox.cache.status[2]=="Alt")')
print('PASS: three-client ungrouped pairing, independent sessions/caches, shared Follow/inputs/Stop, selected casts, selector/setup rows, isolated loss and reconnect')

# Changing a shared code retires all peers; invalid input leaves the roster intact.
t.main.execute('local ok=zBox:ConfigureRoster({"Alt","alt"},"testcode123");assert(not ok and zBox.connected)')

# pfUI buttons receive the same Click dispatch from mouse and pfActionButton.
t.main.execute(MACROS)
t.main.execute(r'''
pfUI={bars={UpdateGrid=function(self,state) assert(self==pfUI.bars);grid=state end}}
local button=CreateFrame("Button","pfActionBarMainButton3",UIParent);button.id=3
button:SetScript("OnClick",function() normalClicks=(normalClicks or 0)+1 end)
button.mockTop,button.mockBottom=100,60
button.GetLeft=function() return 100 end;button.GetRight=function() return 140 end
assert(zBox:PickupRemote("actions",zBox.cache.bar.rows[1]));assert(not macros[19])
assert(zBox.freeCursor);assert(zBox:PlaceFreeProxy(button));assert(zBox.db.barSlots[3]);assert(not zBox.freeCursor)
this=button;arg1="LeftButton";button.scripts.OnClick()
''');t.advance(.7)
assert call_count(t.alt,'UseAction')==2 and call_count(t.beta,'UseAction')==0
t.main.execute('zBox:SelectFollower("Beta");this=pfActionBarMainButton3;arg1="LeftButton";this.scripts.OnClick()');t.advance(.7)
assert call_count(t.alt,'UseAction')==3 and call_count(t.beta,'UseAction')==0
# Direct slots subscribe even when their owner's page/selection is elsewhere.
t.alt.execute('GetActionCooldown=function() return clock-2,10,1 end')
t.advance(1.5)
t.main.execute('local owner=zBox:FollowerState("Alt");assert(owner.cache.proxyCooldowns[zBox.db.barSlots[3]]);assert(pfActionBarMainButton3.zBoxCooldown:IsShown());assert(zBox.db.peer=="Beta")')

t.main.execute('assert(zBox.db.peer=="Beta");assert(zBox:Command("SPELL",{1,zBox:SpellStamp(1),"SELF"}))');t.advance(.7)
assert call_count(t.beta,'CastSpell')==2
t.main.execute(r'''
actions[3]=true;zBox:FreeBarTick(GetTime()+1,true);assert(not zBox.db.barSlots[3]);this=pfActionBarMainButton3;arg1="LeftButton";this.scripts.OnClick();assert(normalClicks==1)
assert(zBox:SelectFollower("Alt"));zBox:Request("spells",1)
''');t.advance(2)
t.main.execute(r'''
assert(zBox:PickupRemote("spells",zBox.cache.view.rows[1]));zBox:CancelFreeDrag();assert(not macros[19]);assert(not zBox.freeCursor)
''')
print('PASS: pfUI direct skills use zero macro slots, remain pinned to the original peer across selection, restore native actions and support spellbook/cancel')

TRADE=r'''
tradePlayer,tradeTarget={},{}
playerMoney,targetMoney=0,0
TradeFrame=CreateFrame("Frame","TradeFrame",UIParent);TradeFrame:Hide()
GetTradePlayerItemLink=function(i) return tradePlayer[i] and link(tradePlayer[i]) end
GetTradeTargetItemLink=function(i) return tradeTarget[i] and link(tradeTarget[i]) end
GetTradePlayerItemInfo=function(i) return tradePlayer[i] and "Offer", "ItemIcon",tradePlayer[i] and 1 or 0,true,"" end
GetTradeTargetItemInfo=function(i) return tradeTarget[i] and "Offer", "ItemIcon",tradeTarget[i] and 1 or 0,3,true,"" end
GetPlayerTradeMoney=function() return playerMoney end
GetTargetTradeMoney=function() return targetMoney end
AcceptTrade=function() log("AcceptTrade") end
CloseTrade=function() log("CloseTrade");tradePartner=nil;event="TRADE_CLOSED";zBox.tradeEvents.scripts.OnEvent() end
InitiateTrade=function(guid) log("InitiateTrade",guid);tradePartner=guid;TradeFrame:Show();event="TRADE_SHOW";zBox.tradeEvents.scripts.OnEvent() end
ClickTradeButton=function(i) log("ClickTradeButton",i);tradePlayer[i],cursor=cursor,tradePlayer[i];event="TRADE_PLAYER_ITEM_CHANGED";zBox.tradeEvents.scripts.OnEvent() end
DeleteCursorItem=function() log("DeleteCursorItem",cursor);cursor=nil end
StaticPopup_Show=function(which,item,owner) popup={which,item,owner} end
StaticPopup_Hide=function() popup=nil end
'''
for lua in t.clients.values():lua.execute(TRADE)
t.main.execute('zBox:Request("bags",1)');t.advance(3)
t.main.execute('local row=zBox.cache.view.rows[1];zBox:ShowBagMenu(row,zBox.UI.cells[1]);assert(zBox.bagMenu:IsShown());assert(zBox:Command("TRADEITEM",{0,1,"item:100:0:0:0",1,zBox:GUID("player")}))');t.advance(2)
t.alt.execute('assert(tradePlayer[1]=="item:100:0:0:0" and bags[0][1]==nil and cursor==nil)')
t.main.execute('tradePartner="0x0000000000000002";TradeFrame:Show();event="TRADE_SHOW";zBox.tradeEvents.scripts.OnEvent()');t.advance(.5)
t.main.execute('assert(zBox.tradeButton:IsShown());zBox.tradeButton.scripts.OnClick()');t.advance(.5)
assert call_count(t.alt,'AcceptTrade')==1 and call_count(t.beta,'AcceptTrade')==0
# Change the live offer without allowing a new snapshot through first.
t.alt.execute('targetMoney=123')
t.main.execute('zBox.tradeButton.scripts.OnClick()');t.advance(.4)
assert call_count(t.alt,'AcceptTrade')==1
t.main.execute('tradePartner="0x0000000000000004"');t.advance(.2)
t.main.execute('assert(not zBox.tradeButton:IsShown())')
t.alt.execute('tradePartner="0x0000000000000004";event="TRADE_SHOW";zBox.tradeEvents.scripts.OnEvent()');t.advance(1)
t.main.execute('assert(zBox.tradeUI:IsShown() and zBox.tradeUI.owner=="Alt");assert(zBox.tradeUI.snapshot.fields[4]=="Friend")')
t.main.execute('assert(zBox:Command("DESTROYPREP",{0,2,"item:200:0:0:0",1}))');t.advance(1)
t.main.execute('assert(popup and popup[3]=="Alt");assert(zBox:SelectFollower("Beta"));StaticPopupDialogs.ZBOX_DESTROY.OnAccept()');t.advance(.5)
assert call_count(t.alt,'DeleteCursorItem')==1 and call_count(t.beta,'DeleteCursorItem')==0
t.alt.execute('assert(bags[0][2]==nil and cursor==nil)')
# A moved item invalidates the confirmed slot. A duplicate confirmation is inert.
t.main.execute('StaticPopupDialogs.ZBOX_DESTROY.OnAccept()');t.advance(.5)
assert call_count(t.alt,'DeleteCursorItem')==1
t.beta.execute('bags[0][2]="item:200:0:0:0"')
t.main.execute('assert(zBox:Command("DESTROYPREP",{0,2,"item:200:0:0:0",1}))');t.advance(.8)
t.beta.execute('bags[0][2]="item:999:0:0:0"')
t.main.execute('StaticPopupDialogs.ZBOX_DESTROY.OnAccept()');t.advance(.5)
assert call_count(t.beta,'DeleteCursorItem')==0
print('PASS: trade item placement, exact partner-only acceptance, changed-offer rejection, third-party preview, peer-pinned destroy confirmation, replay/stale-item rejection')

# Run the actual zNameplates adapter against the same UI fixture.
znp=Path(__file__).parents[2]/'z_Nameplates'/'paired.lua'
if znp.is_file():
    t.main.execute('zNameplates={}');t.main.execute((Path(__file__).parents[2]/'z_Nameplates'/'paired.lua').read_text())
    t.main.execute(r'''
    zBox.vitalsProvider=nil;zBox:InstallVitalsProvider()
    plate=CreateFrame("Frame",nil,UIParent);plate.name=plate:CreateFontString(nil,"OVERLAY");plate.name.GetStringWidth=function() return 60 end
    plate.isFriendly=true;plate.cachedGuid="0x0000000000000002"
    parent={nameplate=plate}
    for _,scale in ipairs({.55,.85,1,1.25}) do
     plate:SetScale(scale);zNameplates.UpdatePairedVitals({[parent]=true});assert(plate.pairedVitals:IsShown())
     assert(math.abs(plate.pairedVitals.health:GetHeight()*plate.pairedVitals.health:GetEffectiveScale()-2)<.00001)
     assert(math.abs(plate.pairedVitals.power:GetHeight()*plate.pairedVitals.power:GetEffectiveScale()-2)<.00001)
    end
    plate.cachedGuid="0x0000000000000004";zNameplates.UpdatePairedVitals({[parent]=true});assert(not plate.pairedVitals:IsShown())
    plate.cachedGuid="0x0000000000000003";zNameplates.UpdatePairedVitals({[parent]=true});assert(plate.pairedVitals:IsShown())
    zNameplates.UpdatePairedVitals({});assert(not plate.pairedVitals:IsShown())
    zBox.db.enabled=false;zNameplates.UpdatePairedVitals({[parent]=true});assert(not plate.pairedVitals:IsShown())
    ''')
    print('PASS: zNameplates draws exactly two physical pixel bars at varied scales, for each fresh authorized GUID only; recycling/removal/revocation hide them')
    
else:
    print('SKIP: optional zNameplates integration fixture (sibling checkout not installed)')

# The same three clients now use independent DLL endpoints; no whisper packets
# may be emitted after the handoff, including after selecting a different peer.
from collections import deque
t=Team();channels={};selected={};epochs=[0]
def bank(own,cmd,*args):
    if cmd=='LocalSelect': selected[own]=args[0];return 1,'Selected'
    if cmd=='LocalCloseAll':
        for key in list(channels):
            if key[0]==own:del channels[key]
        return 1,'Closed'
    if cmd=='LocalOpen':
        realm,name,peer,code,role=args;selected[own]=peer;key=(own,peer)
        if key not in channels:
            epochs[0]+=1;channels[key]={'epoch':str(epochs[0]),'queue':deque(),'code':code,'role':role}
        return 1,'Open'
    key=(own,selected.get(own));state=channels.get(key);peer=channels.get((key[1],own))
    if cmd=='LocalClose':channels.pop(key,None);return 1,'Closed'
    if cmd=='LocalDiscard':
        if state:state['queue'].clear()
        return 1,'Discarded'
    if cmd=='LocalInfo':return 1,peer['epoch'] if peer else '','Fixture bank'
    if cmd=='LocalSend':
        if not peer:return -1,'Unavailable'
        packet,priority=args
        if priority==2:peer['queue'].clear()
        peer['queue'].append(packet);return 1,'Sent'
    if cmd=='LocalRead':return (1,state['queue'].popleft()) if state and state['queue'] else (0,'')
    raise AssertionError(cmd)
for name,lua in t.clients.items():
    lua.globals().bankCommand=lambda cmd,*args,name=name:bank(name,cmd,*args)
    lua.execute('''
local previous=zBoxNative
zBoxNative=function(cmd,...)
 if string.sub(cmd,1,5)=="Local" then return bankCommand(cmd,unpack(arg)) end
 return previous(cmd,unpack(arg))
end
zBox.db.localTransport=true;zBox.bridgeInfo=nil
''')
t.advance(4)
t.main.execute('assert(zBox.localReady and zBox.connected);assert(zBox:FollowerState("Beta").localReady and zBox:FollowerState("Beta").connected)')
whispers=len(t.history)
t.main.execute('assert(zBox:Command("FOLLOW"));assert(zBox:SelectFollower("Beta"));assert(zBox:Command("ACTION",{1,zBox.cache.bar.rows[1][4],"SELF"}))');t.advance(1)
assert call_count(t.alt,'FollowUnit')==1 and call_count(t.beta,'FollowUnit')==1
assert call_count(t.alt,'UseAction')==0 and call_count(t.beta,'UseAction')==1
assert len(t.history)==whispers
t.main.execute('assert(zBox:SetMirrorMode(true));axes.MoveForward=true;facing=1.25');t.advance(.6)
for lua in [t.alt,t.beta]:lua.execute('assert(axes.MoveForward and math.abs(facing-1.25)<.00001)')
t.main.execute('assert(zBox:Command("STOP"))');t.advance(.3)
for lua in [t.alt,t.beta]:lua.execute('assert(not axes.MoveForward)')
t.main.execute('assert(zBox.db.peer=="Beta");zBox:Slash("off");assert(not zBox.roster)');t.advance(5)
assert not channels.get(('Main','Alt')) and not channels.get(('Main','Beta'))
for lua in [t.alt,t.beta]:lua.execute('assert(not zBox.connected)')
print('PASS: multi-endpoint Lua transport switches contexts correctly, avoids whispers, broadcasts Mirror heading/inputs and Stop, routes selected casts and retires all channels')

