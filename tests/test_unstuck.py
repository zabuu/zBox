"""Fixed Stuck() recovery on the driver and authenticated connected followers."""
from test_roster_trade_bars import Team
from test_local_transport import LocalPair
from test_zbox import call_count

SETUP='''
Stuck=function() log("Stuck",clock) end
SendChatMessage=function() error("Unstuck must not send chat text") end
SlashCmdList.GM=function() error("Unstuck must not open the GM help frame") end
'''
t=Team()
for lua in t.clients.values():lua.execute(SETUP)
t.main.execute('assert(zBox:SetMirrorMode(true));axes.MoveForward=true;facing=1.4')
t.advance(.3)
t.main.execute('assert(zBox:SelectFollower("Beta"));assert(SLASH_ZBOX_UNSTUCK1=="/unstuck");SlashCmdList.ZBOX_UNSTUCK("")')
# Dispatch bypasses the normal action queue, even on the whisper route.
assert any(src=='Main' and dst=='Alt' and '~CMD~UNSTUCK' in p for src,dst,p in t.wire)
assert any(src=='Main' and dst=='Beta' and '~CMD~UNSTUCK' in p for src,dst,p in t.wire)
assert call_count(t.main,'Stuck')==1
t.advance(.4)
for lua in t.clients.values():
    assert call_count(lua,'Stuck')==1
    lua.execute('assert(not axes.MoveForward);assert(not zBox.following and not zBox.pendingCast and not zBox.petState)')
t.main.execute('assert(zBox.db.peer=="Beta" and zBox.mirrorPaused and zBox.heldMask==0)')
# Replayed commands, another sender and extra script text never run again.
packet=next(p for src,dst,p in t.history if src=='Main' and dst=='Alt' and '~CMD~UNSTUCK' in p)
t.alt.globals().replay=packet
t.alt.execute('zBox:Receive(zBox.prefix,replay,"UNKNOWN","Main");zBox:Receive(zBox.prefix,replay,"UNKNOWN","Stranger");local ok=zBox:Execute({"UNSTUCK","Stuck();"});assert(not ok)')
assert call_count(t.alt,'Stuck')==1
t.main.execute('SlashCmdList.ZBOX_UNSTUCK("extra")');t.advance(.2)
assert call_count(t.main,'Stuck')==1
t.main.execute('assert(zBox:Command("FOLLOW"))');t.advance(.3)
t.main.execute('zBox:Slash("unstuck")');t.advance(.4)
for lua in t.clients.values():assert call_count(lua,'Stuck')==2
print('PASS: /unstuck and /zbox unstuck invoke the fixed API once on driver/all followers, bypass backlog, preserve selection, pause Mirror/follow and reject replay/spoof/script arguments')

# A disconnected selection must not prevent recovery on another linked peer.
t.off.add('Beta');t.advance(5)
t.main.execute('assert(not zBox.connected and zBox:FollowerState("Alt").connected);SlashCmdList.ZBOX_UNSTUCK("")');t.advance(.3)
assert call_count(t.main,'Stuck')==3 and call_count(t.alt,'Stuck')==3 and call_count(t.beta,'Stuck')==2
t.off.clear();t.advance(5)
assert call_count(t.beta,'Stuck')==2  # Never run a delayed unstuck after reconnect.
t.main.execute('zBox.worldSuspended=true;SlashCmdList.ZBOX_UNSTUCK("")')
assert call_count(t.main,'Stuck')==3
t.main.execute('zBox.worldSuspended=false;zBox:Slash("off");SlashCmdList.ZBOX_UNSTUCK("")');t.advance(.3)
assert call_count(t.main,'Stuck')==4 and call_count(t.alt,'Stuck')==3
print('PASS: disconnected peers skip recovery without blocking linked peers, reconnect does not replay it, loading rejects it and an unlinked command recovers only the local character')

f=LocalPair();p=f.p
for lua in (p.main,p.alt):lua.execute(SETUP)
p.main.execute('for i=1,50 do zBox:Send("NOOP",{"backlog"},false) end;SlashCmdList.ZBOX_UNSTUCK("")')
f.fast(2)
assert call_count(p.main,'Stuck')==1 and call_count(p.alt,'Stuck')==1
# Fixed API missing/errors report a failure instead of trying chat or script eval.
p.alt.execute('Stuck=nil;local ok,why=zBox:Execute({"UNSTUCK"});assert(not ok and string.find(why,"unavailable"))')
p.alt.execute('Stuck=function() error("fixture failure") end;local ok,why=zBox:Execute({"UNSTUCK"});assert(not ok and string.find(why,"fixture failure"))')
print('PASS: local IPC recovery reaches both clients without draining background queues; missing/failed Stuck APIs fail clearly with no alternative chat/eval path')
