"""Local bridge routing, fast frame polling, priority, handoffs and fallbacks."""
from test_ungrouped import direct_pair, call_count
from collections import deque

class LocalPair:
    def __init__(self):
        self.p=direct_pair(ui=True)
        self.enabled=True;self.counter=0;self.state={};self.history=[];self.busy={};self.info_busy={}
        for name,lua,other in [('Main',self.p.main,'Alt'),('Alt',self.p.alt,'Main')]:
            self.state[name]={'open':False,'epoch':0,'queues':[deque(),deque(),deque()]}
            lua.globals().ipcOpen=lambda realm,own,peer,key,role,name=name:self.open(name,(realm,own,peer,key,role))
            lua.globals().ipcClose=lambda name=name:self.close(name)
            lua.globals().ipcInfo=lambda name=name:self.info(name)
            lua.globals().ipcSend=lambda packet,priority,name=name,other=other:self.send(name,other,packet,int(priority))
            lua.globals().ipcRead=lambda name=name,other=other:self.read(name,other)
            lua.globals().ipcDiscard=lambda name=name:self.discard(name)
            lua.execute('''
local native=zBoxNative
zBoxNative=function(command,...)
 if command=="capabilities" then return 1,"zBoxBridge 0.1.8",7 end
 if command=="LocalOpen" then return ipcOpen(unpack(arg)) end
 if command=="LocalClose" then ipcClose();return 1,"Closed" end
 if command=="LocalDiscard" then ipcDiscard();return 1,"Discarded" end
 if command=="LocalInfo" then return ipcInfo() end
 if command=="LocalSend" then return ipcSend(unpack(arg)) end
 if command=="LocalRead" then return ipcRead() end
 return native(command,unpack(arg))
end
zBox.bridgeInfo=nil;zBox:CloseLocalTransport();zBox:Disconnect()
''')
        self.p.advance(1)
        for lua in [self.p.main,self.p.alt]:lua.execute('assert(zBox.connected and zBox.localReady and zBox:Channel()=="LOCAL")')
        self.p.wire=[]
    def open(self,name,profile):
        state=self.state[name]
        if not state['open'] or profile!=state.get('profile'):
            self.counter+=1;state.update(open=True,epoch=self.counter,profile=profile)
            self.discard(name)
        return 1,'Opened'
    def close(self,name):
        self.state[name]['open']=False;self.discard(name)
    def discard(self,name):
        for q in self.state[name]['queues']:q.clear()
    def peer(self,name):
        own=self.state[name];other=self.state['Alt' if name=='Main' else 'Main']
        if not self.enabled or not own['open'] or not other['open']:return None
        a,b=own['profile'],other['profile']
        if a[0]!=b[0] or a[1]!=b[2] or a[2]!=b[1] or a[3]!=b[3] or a[4]==b[4]:return None
        return other
    def info(self,name):
        if self.info_busy.get(name):self.info_busy[name]-=1;return 0,'','Busy'
        peer=self.peer(name)
        return 1,f'{peer["epoch"]:016x}' if peer else '','Local DLL IPC fixture'
    def send(self,name,other,packet,priority):
        if self.busy.get(name):self.busy[name]-=1;return 0,'Busy'
        peer=self.peer(name)
        if not peer:return -1,'Peer unavailable'
        assert len(packet)<=4352 and packet.startswith('2~') and '|' not in packet
        q=peer['queues'][priority]
        if priority==2:self.discard(other)
        elif len(q)>=32:return 0,'Queue full'
        q.append((self.state[name]['epoch'],peer['epoch'],self.p.time,packet))
        self.history.append((name,packet,priority))
        return 1,'Sent'
    def read(self,name,other):
        own=self.state[name]
        for q in reversed(own['queues']):
            while q:
                src,dst,at,packet=q.popleft()
                if src==self.state[other]['epoch'] and dst==own['epoch'] and self.p.time-at<=1:
                    return 1,packet
        return 0,''
    def fast(self,steps=1,delta=.01):
        for _ in range(steps):
            self.p.time+=delta
            for lua in [self.p.main,self.p.alt]:
                lua.globals().clock=self.p.time;lua.globals().arg1=delta
                lua.globals().zBox.frame.scripts.OnUpdate()
            self.p.deliver()

f=LocalPair();p=f.p
p.main.execute('assert(zBox.UI.connection.text=="Alt  /  Local DLL")')
before=call_count(p.alt,'Jump')
p.main.execute('zBox.tokens=0;assert(zBox:Command("JUMP"))')
assert f.history[-1][0]=='Main' and '~CMD~JUMP' in f.history[-1][1]
f.fast(2)
assert call_count(p.alt,'Jump')==before+1 and not p.wire
p.main.execute('assert(zBox.lastRoundTrip and zBox.lastRoundTrip<.05);assert(string.find(zBox:Diagnostics(),"command ack=",1,true))')

# Large snapshots use a handful of frames, and all existing readers still work.
p.main.execute('local frames=zBox:Packets("CHECK",{string.rep("x",8000)});assert(table.getn(frames)==2)')
for section in ['spells','bags','gear','talents','quests','npc']:
    p.main.execute(f'zBox:Request("{section}",1)');p.advance(1)
    p.main.execute(f'assert(zBox.cache.view.section=="{section}")')
p.main.execute('zBox:Request("actions",1)');p.advance(1)
before=call_count(p.alt,'UseAction')
p.main.execute('assert(zBox:Command("ACTION",{1,zBox.cache.bar.rows[1][4],"SELF"}))')
f.fast(2);p.alt.execute('assert(zBox.pendingCast)')
f.fast(22);assert call_count(p.alt,'UseAction')==before+1

# Backlogged UI frames cannot consume the dedicated command lane. Full lanes
# retry the exact packet, including its ID, instead of dropping or duplicating.
p.main.execute('for i=1,80 do zBox:Send("NOOP",{string.rep("x",2000)},false) end')
before=call_count(p.alt,'Jump')
p.main.execute('assert(zBox:Command("JUMP"))');f.fast(2)
assert call_count(p.alt,'Jump')==before+1
f.busy['Main']=2
before=call_count(p.alt,'Jump')
p.main.execute('assert(zBox:Command("JUMP"))')
f.fast(5)
assert call_count(p.alt,'Jump')==before+1

# A contended emergency Stop stays reserved until the next frame.
p.main.execute('assert(zBox:Command("AXES",{1}))');f.fast(2)
p.alt.execute('assert(axes.MoveForward)')
f.busy['Main']=1
p.main.execute('assert(zBox:Command("STOP"));assert(zBox.localStopPacket)')
f.fast(3)
p.alt.execute('assert(not axes.MoveForward)')
p.main.execute('assert(not zBox.localStopPacket)')

# A busy mutex cannot trigger an unnecessary route change. Local pairing also
# keeps working with the game-message fixture disabled: no whisper dependency.
session=p.main.globals().zBox.session
f.info_busy['Main']=1;f.fast(2)
assert p.main.globals().zBox.session==session
p.online=False
before=call_count(p.alt,'Jump');p.main.execute('zBox:Command("JUMP")');f.fast(3)
assert call_count(p.alt,'Jump')==before+1 and p.main.globals().zBox.connected
p.online=True

# Reconnect with a fresh session after peer restarts; old commands/channel,
# name, key and session mismatches never issue an input.
old_session=p.main.globals().zBox.session
p.alt.execute('zBox.localOpened=nil;zBox:CloseLocalTransport(true);zBox:Disconnect()');p.advance(1)
assert p.main.globals().zBox.connected and p.main.globals().zBox.session!=old_session
before=call_count(p.alt,'Jump')
p.alt.globals().oldSession=old_session
p.alt.execute('''
local b=zBox;local frame="2~"..b.db.key.."~"..b.session.."~999999~1~1~CMD~JUMP"
b:Receive(b.prefix,frame,"WHISPER","Main");b:Receive(b.prefix,frame,"UNKNOWN","Main")
b:Receive(b.prefix,frame,"LOCAL","Intruder")
b:Receive(b.prefix,"2~wrongcode~"..b.session.."~999999~1~1~CMD~JUMP","LOCAL","Main")
b:Receive(b.prefix,"2~"..b.db.key.."~"..oldSession.."~999999~1~1~CMD~JUMP","LOCAL","Main")
''')
assert call_count(p.alt,'Jump')==before

# Separate-computer/no-local-peer and explicit whisper mode keep the existing
# directed pairing. A route change stops movement and clears queued inputs.
p.main.execute('assert(zBox:Command("AXES",{1}))');f.fast(2)
f.enabled=False;p.advance(3)
for lua in [p.main,p.alt]:lua.execute('assert(zBox.connected and not zBox.localReady and zBox:Channel()=="WHISPER")')
p.alt.execute('assert(not axes.MoveForward)')
before=call_count(p.alt,'Jump');p.main.execute('zBox:Command("JUMP")');p.advance(.4)
assert call_count(p.alt,'Jump')==before+1
f.enabled=True;p.advance(1)
p.main.execute('zBox:Slash("transport whisper")');p.advance(3)
for lua in [p.main,p.alt]:lua.execute('assert(zBox.connected and zBox:Channel()=="WHISPER")')
p.main.execute('zBox:Slash("transport auto")');p.advance(1)
for lua in [p.main,p.alt]:lua.execute('assert(zBox.connected and zBox:Channel()=="LOCAL")')
p.main.execute('zBox:Slash("off");assert(not zBox.localOpened and not zBox.connected)');p.advance(4.5)
p.alt.execute('assert(not zBox.connected and not axes.MoveForward)')
f=LocalPair();p=f.p
f.state['Alt']['open']=False
p.main.execute('local ok=zBox:Command("JUMP");assert(not ok and not zBox.connected and string.find(zBox.notice,"Local send failed",1,true))')
print('PASS: automatic local pairing, 10ms frame polling/immediate commands, larger snapshots/all views/casts, priority/backpressure/reserved Stop, no whisper dependence, transient contention, peer generations/replay rejection, mode changes, remote whisper fallback and revoke cleanup')
