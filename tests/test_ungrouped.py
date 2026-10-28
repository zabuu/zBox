"""Directed addon whispers between isolated, ungrouped client fixtures."""
from test_mouse_dependencies import Pair, MACROS, call_count
from test_pet_mode import pet_pair

DIRECT=r'''
local native=zBoxNative
zBoxNative=function(command,a,b,c)
 if command=="capabilities" then return 1,"zBoxBridge 0.1.7",6 end
 if command=="Whisper" then
  if rejectWhisper then return 0,"Fixture transport failure" end
  addonWhisper(a,b);return 1,"Requested"
 end
 return native(command,a,b,c)
end
local exists,name,combat,api=UnitExists,UnitName,UnitAffectingCombat,zAPI
UnitExists=function(unit)
 if unit==ownGUID then return true,ownGUID end
 if unit==peerGUID then return not peerUnloaded,peerGUID end
 if unit==peerGUID.."target" then return not peerUnloaded and enemies[mainTarget] and true,mainTarget end
 return exists(unit)
end
UnitName=function(unit)
 if unit==ownGUID then return ownName end
 if unit==peerGUID then return wrongPeerName or peerName end
 return name(unit)
end
UnitAffectingCombat=function(unit) if unit==peerGUID then return mainCombat end;return combat(unit) end
zAPI=function(command,unit,...)
 if command=="unitPosition" and unit==peerGUID then return -5,0,0 end
 return api(command,unit,unpack(arg))
end
grouped=false;zBox.bridgeInfo=nil;zBox:Disconnect()
'''

def direct_pair(ui=False):
    p=pet_pair(ui=ui)
    p.wire=[]
    for src,dst,sender,peer in [(p.main,p.alt,'Main','Alt'),(p.alt,p.main,'Alt','Main')]:
        def send(target,packet,dst=dst,sender=sender,peer=peer):
            assert target==peer
            assert len(packet.encode())+6<=255 and '|' not in packet
            assert all(32<=ord(c)<=126 for c in packet)
            # Stock 1.12's addon-event mapper labels whisper type 6 UNKNOWN.
            item=(dst,'zBox2',packet,'UNKNOWN',sender)
            p.wire.append(item);p.history.append(item)
        src.globals().addonWhisper=send
        src.execute(DIRECT)
    p.advance(3)
    assert p.main.globals().zBox.connected and p.alt.globals().zBox.connected
    p.main.execute('assert(zBox:Channel()=="WHISPER" and not zBox:GroupUnit(zBox.db.peer) and zBox:PeerUnit()==peerGUID)')
    p.alt.execute('assert(zBox:Channel()=="WHISPER" and zBox:PeerUnit()==peerGUID)')
    return p

p=direct_pair(ui=True)
p.main.execute(r'''
local fields={string.char(195,169,226,128,153,240,159,144,136),"|cffaabbcc^%"}
local encoded=zBox:Encode(fields)
assert(not string.find(encoded,"[^ -~]"))
local restored=zBox:Decode(encoded)
assert(restored[1]==fields[1] and restored[2]==fields[2])
local frame=zBox:Packets("CHECK",{string.rep(fields[1],40)})
for i=1,table.getn(frame) do assert(string.len(frame[i])<=248 and not string.find(frame[i],"[^ -~]")) end
''')
p.main.execute('assert(zBox:FollowCommand())');p.advance(.6)
p.alt.execute('assert(zBox.following)')
assert [row[2] for _,row in p.alt.globals().calls.items() if row[1]=='FollowUnit'][-1]==p.alt.globals().peerGUID
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"SELF"})');p.advance(.6)
assert call_count(p.alt,'UseAction')==1 and call_count(p.main,'UseAction')==0
p.main.execute('assert(zBox:AttackCommand())');p.advance(3,physics=True)
p.alt.execute('assert(attacking and zBox.petState.guid==enemyGUID);mainCombat=true;ownCombat=true;enemies[enemyGUID].victim=peerGUID;mainTarget=otherGUID')
p.main.execute('selectedGUID=otherGUID;zBox:SendMainTarget()')
p.advance(2,physics=True)
p.alt.execute('assert(zBox.petState.guid==otherGUID and attacking);mainCombat=false;ownCombat=false')
p.advance(1)
p.alt.execute('assert(zBox.following and not zBox.petState.guid)')
# Joining/leaving a party does not replace the direct route or reconnect.
session=p.main.globals().zBox.session
p.main.execute('grouped=true;event="PARTY_MEMBERS_CHANGED";zBox.frame.scripts.OnEvent();grouped=false;zBox.frame.scripts.OnEvent()')
p.advance(.3)
assert p.main.globals().zBox.session==session and p.main.globals().zBox.connected

# Wrong sender, code, session, or group channel cannot issue a direct command.
old=call_count(p.alt,'Jump')
for channel,sender in [('UNKNOWN','Intruder'),('PARTY','Main'),('RAID','Main'),('GUILD','Main'),('SAY','Main')]:
    p.alt.globals().testChannel=channel;p.alt.globals().testSender=sender
    p.alt.execute('local b=zBox;local msg="2~"..b.db.key.."~"..b.session.."~99999~1~1~CMD~JUMP";b:Receive(b.prefix,msg,testChannel,testSender)')
p.alt.execute('local b=zBox;b:Receive(b.prefix,"2~wrongkey~"..b.session.."~99999~1~1~CMD~JUMP","UNKNOWN","Main");b:Receive(b.prefix,"2~"..b.db.key.."~oldsession~99999~1~1~CMD~JUMP","UNKNOWN","Main")')
assert call_count(p.alt,'Jump')==old
# The peer's GUID must resolve to the configured name before Follow may use it.
p.alt.execute('wrongPeerName="SomeoneElse";assert(not zBox:PeerUnit())')
old=call_count(p.alt,'FollowUnit')
p.main.execute('assert(zBox:FollowCommand())');p.advance(.4)
assert call_count(p.alt,'FollowUnit')==old
p.alt.execute('wrongPeerName=nil;peerUnloaded=true;assert(not zBox:PeerUnit())')
p.main.execute('assert(zBox:FollowCommand())');p.advance(.4)
assert call_count(p.alt,'FollowUnit')==old
p.alt.execute('assert(zBox.connected);peerUnloaded=false')
p.main.execute('assert(zBox:FollowCommand())');p.advance(.4)
assert call_count(p.alt,'FollowUnit')==old+1
# Cooldown watch/snapshot traffic follows the same directed channel.
p.main.execute(MACROS)
p.main.execute('assert(zBox:PickupRemote("actions",zBox.cache.bar.rows[1]));cursorMacro=nil')
p.advance(.8)
p.alt.execute('GetActionCooldown=function() return clock-1,10,1 end')
p.advance(.5)
p.main.execute('assert(zBox.cache.proxyCooldowns["1"].duration==10)')
# STOP outranks commands already waiting in the outgoing queue.
p.main.execute('zBox:Command("AXES",{1});zBox:Command("STOP")');p.advance(.5)
p.alt.execute('assert(not axes.MoveForward and not zBox.petState)')
p.main.execute('zBox:Command("AXES",{1})');p.advance(.4)
p.alt.execute('assert(axes.MoveForward)')
p.online=False;p.advance(4.5)
p.alt.execute('assert(not zBox.connected and not axes.MoveForward and not nativePoint)')
p=direct_pair();p.main.execute('rejectWhisper=true;zBox:Command("STOP");assert(not zBox.connected and string.find(zBox.notice,"whisper failed"))')
# Old bridges retain their existing grouped fallback, with a clear diagnostic
# instead of pretending they can use the unavailable native whisper route.
p=Pair();p.main.execute('assert(zBox:Channel()=="PARTY");grouped=false')
p.advance(.1)
p.main.execute('assert(not zBox.connected and not zBox:Channel());assert(string.find(zBox:Diagnostics(),"ungrouped pairing needs bridge 0.1.7",1,true))')
print('PASS: directed ungrouped pairing with peer GUID/name checks, Follow/casts/Pet/target switching, party membership independence, sender/code/session/channel rejection, unavailable-peer refusal, cooldowns, STOP priority, lost/failed transport and legacy grouped fallback')
