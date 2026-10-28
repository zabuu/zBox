"""Paired periodic centering, real mirrored inputs, casting and cancellation."""
from test_companion_convenience import call_count
from test_local_transport import LocalPair
from test_zbox import Pair, MACROS
import math

WORLD=r'''
local api=zAPI
zAPI=function(command,unit,...)
 if command=="unitPosition" and unit=="player" then return px,py,pz end
 if command=="raycast" then return stackBlocked and 1 or 0 end
 return api(command,unit,unpack(arg))
end
physics=function(dt)
 if freezePhysics then return end
 local forward=(axes.MoveForward and 1 or 0)-(axes.MoveBackward and 1 or 0)
 local left=(axes.StrafeLeft and 1 or 0)-(axes.StrafeRight and 1 or 0)
 local length=math.sqrt(forward*forward+left*left)
 if length>0 then
  local speed=forward<0 and 4.5 or 7
  local f,l=forward/length*speed,left/length*speed
  px=px+(math.cos(facing)*f-math.sin(facing)*l)*dt
  py=py+(math.sin(facing)*f+math.cos(facing)*l)*dt
 end
end
GetUnitSpeed=function() return 7 end
'''

def setup(local=True):
    f=LocalPair() if local else None
    p=f.p if f else Pair(ui=True)
    for lua in (p.main,p.alt):lua.execute(WORLD)
    p.main.execute('zBox.UI.frame:Show();px=3;py=-2;pz=0;facing=.7;assert(zBox:SetMirrorMode(true));assert(zBox:SetMirrorStack(true))')
    p.alt.execute('px=-1;py=1;pz=0')
    return f,p

def run(f,p,seconds,fps=60):
    dt=1/fps
    for _ in range(round(seconds*fps)):
        if f:f.fast(1,dt)
        else:
            p.time+=dt
            for lua in (p.main,p.alt):
                lua.globals().clock=p.time;lua.globals().arg1=dt
                lua.globals().zBox.frame.scripts.OnUpdate()
            p.deliver()
        for lua in (p.main,p.alt):lua.globals().physics(dt)

def distance(p):
    return math.hypot(p.main.globals().px-p.alt.globals().px,p.main.globals().py-p.alt.globals().py)

# Normal movement, rather than a position setter, converges from all quadrants.
for local,fps in [(True,60),(True,30),(True,20),(False,60)]:
    for heading in [0,.7,math.pi/2,math.pi,5.7]:
        f,p=setup(local)
        p.main.globals().facing=heading
        run(f,p,5,fps)
        assert distance(p)<(.13 if fps==60 else .3),(local,fps,heading,distance(p))
        assert abs(p.alt.globals().facing-heading)<.00001
        assert p.main.globals().px==3 and p.main.globals().py==-2
        assert call_count(p.alt,'FollowUnit')==0 and call_count(p.alt,'MoveTo')==0
        p.alt.execute('for _,active in pairs(axes) do assert(not active) end')
print('PASS: periodic Stack settles toward the main at varied headings/FPS over local IPC and addon messages, keeps heading and never moves account 1')

f,p=setup()
run(f,p,5)
p.main.execute('''
local u=zBox.UI
u:Refresh();assert(u.stackButton.shown and u.stackButton.caption.text=="Stack ON")
local previous=0
for _,b in ipairs({u.targetMode,u.followButton,u.stackButton,u.moveButton,u.stopButton}) do
 assert(b.point[4]>=previous and b.point[4]+b.width<=484)
 previous=b.point[4]+b.width
end
''')
# A fresh drift waits for the next pulse; it does not turn into continuous follow.
baseline=call_count(p.alt,'StrafeLeftStart')+call_count(p.alt,'StrafeRightStart')+call_count(p.alt,'MoveForwardStart')+call_count(p.alt,'MoveBackwardStart')
run(f,p,5)
assert baseline==sum(call_count(p.alt,name) for name in ['StrafeLeftStart','StrafeRightStart','MoveForwardStart','MoveBackwardStart'])
p.alt.execute('zBox.mirrorStack.nextPulse=GetTime()+1.5;px=px+2')
run(f,p,.7)
assert distance(p)>1.9
run(f,p,2)
assert distance(p)<.13
# Inputs and current coordinates keep updating while the main moves and turns.
p.main.execute('MoveForwardStart();facing=2.4')
run(f,p,.6)
p.alt.execute('assert(zBox.mirrorInput.stack and math.abs(zBox.mirrorInput.heading-2.4)<.00001)')
assert p.main.globals().px!=3
p.main.execute('assert(zBox:SetMirrorStack(false))')
run(f,p,.2)
p.alt.execute('assert(not zBox.mirrorStack and not zBox.mirrorInput.stack and axes.MoveForward and not axes.StrafeLeft and not axes.StrafeRight)')
p.main.execute('MoveForwardStop();assert(zBox:SetMirrorStack(true))')
run(f,p,5)
assert distance(p)<.13
# Cast holds acquire normal movement stops and retain enemy facing. Pulses never
# issue a heading/movement change until the cast hold has ended.
p.alt.execute('px=px+2;zBox.mirrorStack.nextPulse=0')
run(f,p,.1)
p.alt.execute('zBox:CastEvent("SPELLCAST_START",2000);zBox:CastingTick(GetTime());heldX=px;heldY=py;heldFacing=facing')
starts=sum(call_count(p.alt,name) for name in ['StrafeLeftStart','StrafeRightStart','MoveForwardStart','MoveBackwardStart'])
run(f,p,1.5)
p.alt.execute('assert(px==heldX and py==heldY and facing==heldFacing)')
assert starts==sum(call_count(p.alt,name) for name in ['StrafeLeftStart','StrafeRightStart','MoveForwardStart','MoveBackwardStart'])
p.alt.execute('zBox:CastEvent("SPELLCAST_STOP")')
run(f,p,3)
assert distance(p)<.13
print('PASS: Stack is pulsed rather than continuous; live positions/turns update, OFF restores held Mirror inputs and real casts suspend correction/facing')

for heading in [0,.8,math.pi,5.7]:
    f,p=setup()
    p.main.globals().facing=heading
    p.alt.globals().px=3+4*math.cos(heading);p.alt.globals().py=-2+4*math.sin(heading)
    run(f,p,.1)
    p.alt.execute('assert(axes.MoveForward and not axes.MoveBackward and not axes.StrafeLeft and not axes.StrafeRight)')
    expected=(heading+math.pi)%(2*math.pi)
    assert abs(p.alt.globals().facing-expected)<.001
    assert distance(p)<3.5  # Closes at forward speed, rather than backpedalling.
    run(f,p,2.5)
    assert distance(p)<.13 and abs(p.alt.globals().facing-heading)<.00001
print('PASS: a follower ahead immediately faces the main, closes at forward speed and restores the main heading after stacking at varied headings')

# Invalid geometry and obstructions do not authorize extra movement. A blocked
# client releases the correction after its short progress watchdog.
for condition in ['stackBlocked=true','px=100','pz=8','zBox.Position=function() return nil end','zBox.PeerUnit=function() return nil end']:
    f,p=setup();p.alt.execute(condition);run(f,p,1.5)
    p.alt.execute('for _,active in pairs(axes) do assert(not active) end;assert(not zBox.mirrorStack.active)')
f,p=setup();p.alt.execute('freezePhysics=true');run(f,p,1.2)
p.alt.execute('assert(not zBox.mirrorStack.active and zBox.lastStackStatus=="no closing progress");for _,active in pairs(axes) do assert(not active) end')

# Pause, STOP, manual movement, mode changes, disconnect and reload all preserve
# the user's authority. The saved toggle never starts a paused mirror stream.
for command in ['zBox:Command("STOP")','zBox:ToggleMirrorPause()','zBox:SetMovementMode("follow")','zBox:Command("AXES",{1})']:
    f,p=setup();run(f,p,.15);p.main.execute(command);run(f,p,.3)
    p.alt.execute('assert(not zBox.mirrorStack and not zBox.mirrorInput)')
f,p=setup();run(f,p,.15)
p.main.execute('zBox:Command("STOP")');run(f,p,.2)
p.main.execute('assert(zBox:SetMirrorStack(false));assert(zBox:SetMirrorStack(true));assert(zBox.mirrorPaused)');run(f,p,2)
p.alt.execute('assert(not zBox.mirrorInput and not zBox.mirrorStack)')
p.main.execute('zBox:ToggleMirrorPause()');run(f,p,4)
assert distance(p)<.13
f,p=setup();run(f,p,.15);f.enabled=False;p.online=False;run(f,p,4)
p.alt.execute('assert(not zBox.mirrorInput and not zBox.mirrorStack);for _,active in pairs(axes) do assert(not active) end')
p.main.execute('assert(zBox.db.mirrorStack);zBox:Initialize();assert(zBox.db.mirrorStack and zBox.mirrorPaused)')
print('PASS: blocked/unavailable/distant/wrong-floor geometry and stalled corrections stay bounded; pause/STOP/manual orders/mode/loss/reload suspend Stack safely')

f,p=setup();run(f,p,.1)
p.alt.execute('''
local before=zBox.mirrorInput
for _,args in ipairs({{"bad",1,2,3},{"1",0/0,0,0},{"1",100001,0,0},{"1",0,0},{"1","text",0,0}}) do
 assert(not zBox:AcceptMirror(0,0,"Test Zone",unpack(args)))
 assert(zBox.mirrorInput==before)
end
assert(zBox:AcceptMirror(0,0,"Test Zone"));assert(not zBox.mirrorStack)
''')
p.main.execute('zBox.peerVersion="0.8.0";local ok,why=zBox:SetMirrorStack(true);assert(not ok and string.find(why,"0.8.1",1,true))')
# The toggle exports/reuses a normal paired macro without issuing movement.
p.main.execute('zBox.peerVersion="0.8.1";assert(zBox:SetMirrorStack(false))')
p.main.execute(MACROS)
p.main.execute(r'''
C_Macro={CreateMacro=function(name,texture,body,character)
 assert(character)
 for i=19,36 do if not macros[i] then macros[i]={name=name,icon=texture,body=body};return i end end
end}
zBox.UI:Refresh();this=zBox.UI.stackButton;arg1="LeftButton";this.scripts.OnDragStart();assert(cursorMacro)
assert(not zBox.db.mirrorStack)
this.scripts.OnClick();this.scripts.OnDragStop();this.scripts.OnClick();assert(not zBox.db.mirrorStack)
local id;for key,proxy in pairs(zBox.db.proxies) do if proxy.slot=="stack" then id=key end end
assert(id);zBox:UseProxy(id);assert(zBox.db.mirrorStack)
zBox:Slash("stack off");assert(not zBox.db.mirrorStack)
zBox:Slash("stack");assert(zBox.db.mirrorStack)
zBox:SetMovementMode("follow");zBox.UI:Refresh();assert(not zBox.UI.stackButton.shown)
''')
print('PASS: malformed Stack metadata and old peers reject without movement mutation; compact mode-specific toggle, drag suppression, paired macro and explicit slash on/off work')
