"""Mouse binding input routing and actionable external-DLL diagnostics."""
from test_melee_cooldowns import Pair, MACROS, call_count
from pathlib import Path
import xml.etree.ElementTree as ET

p=Pair(ui=True);p.main.execute(MACROS)
p.main.execute('''
local u=zBox.UI
u:ShowKeys();bindings.F="ZBOX_MOVE"
this=u.keyButtons[1];arg1="LeftButton";this.scripts.OnClick()
assert(u.bindingCapture=="ZBOX_MOVE" and u.bindingCover.shown)
assert(u.bindingCover.strata=="FULLSCREEN_DIALOG" and u.bindingCover.level>this.level)
assert(not u.bindingCover.scripts.OnMouseUp and not bindings.BUTTON1)
-- Fresh middle/side-button presses are delivered above child buttons, not
-- only when the pointer happens to rest over the panel's bare background.
this=u.bindingCover;arg1="Button4";this.scripts.OnMouseDown()
assert(bindings.BUTTON4=="ZBOX_MOVE" and not bindings.F and not u.bindingCover.shown)
u:BeginBinding("ZBOX_FOLLOW");altKey=true;ctrlKey=true;shiftKey=true
arg1="Button5";u.bindingCover.scripts.OnMouseDown()
assert(bindings["ALT-CTRL-SHIFT-BUTTON5"]=="ZBOX_FOLLOW")
altKey=false;ctrlKey=false;shiftKey=false
u:BeginBinding("ZBOX_ASSIST");arg1="MiddleButton";u.bindingCover.scripts.OnMouseDown()
assert(bindings.BUTTON3=="ZBOX_ASSIST")
u:BeginBinding("ZBOX_ATTACK");arg1="Button6";u.bindingCover.scripts.OnMouseDown()
assert(bindings.BUTTON6=="ZBOX_ATTACK")
u:BeginBinding("ZBOX_STOP");arg1=-1;u.bindingCover.scripts.OnMouseWheel()
assert(bindings.MOUSEWHEELDOWN=="ZBOX_STOP")
u:BeginBinding("ZBOX_JUMP");ctrlKey=true;arg1=1;u.bindingCover.scripts.OnMouseWheel()
assert(bindings["CTRL-MOUSEWHEELUP"]=="ZBOX_JUMP");ctrlKey=false
u:BeginBinding("ZBOX_JUMP");arg1="LSHIFT";u.bindingCover.scripts.OnKeyDown()
assert(u.bindingCapture and u.bindingCover.shown)
arg1="ESCAPE";u.bindingCover.scripts.OnKeyDown()
assert(not u.bindingCover.shown and bindings["CTRL-MOUSEWHEELUP"]=="ZBOX_JUMP")
-- A client-rejected primary mouse binding preserves the previous key and
-- stays in capture until the player chooses an accepted button or cancels.
local set=SetBinding
SetBinding=function(key,binding) if key=="BUTTON1" or key=="BUTTON2" then return false end;return set(key,binding) end
u:BeginBinding("ZBOX_MOVE");arg1="LeftButton";u.bindingCover.scripts.OnMouseDown()
assert(u.bindingCapture and u.bindingCover.shown and bindings.BUTTON4=="ZBOX_MOVE")
arg1="RightButton";u.bindingCover.scripts.OnMouseDown()
assert(u.bindingCapture and bindings.BUTTON4=="ZBOX_MOVE")
arg1="Button7";u.bindingCover.scripts.OnMouseDown()
assert(bindings.BUTTON7=="ZBOX_MOVE" and not bindings.BUTTON4)
u:BeginBinding("ZBOX_MOVE");arg1="BACKSPACE";u.bindingCover.scripts.OnKeyDown()
assert(not bindings.BUTTON7 and not u.bindingCover.shown)
SetBinding=set
u:BeginBinding("ZBOX_FORWARD");arg1="Button4";u.bindingCover.scripts.OnMouseDown()
assert(bindings.BUTTON4=="ZBOX_FORWARD")
local id=zBox.sendID
zBox:HoldDirection("forward",false)
assert(zBox.sendID==id,"Release of the captured button must not issue a movement command")
u:BeginBinding("ZBOX_MOVE");u.keys:Hide();assert(not u.bindingCover.shown and not u.bindingCapture)
u:ShowKeys();u:BeginBinding("ZBOX_MOVE");zBox:Disconnect()
assert(not u.bindingCover.shown and not u.bindingCapture)
''')
p=Pair(ui=True);p.main.execute(MACROS)
bindings={node.attrib['name']:node for node in ET.parse(Path(__file__).resolve().parents[1]/'Bindings.xml').getroot()}
p.main.execute('zBox.UI:ShowKeys();zBox.UI:BeginBinding("ZBOX_FORWARD");arg1="Button4";zBox.UI.bindingCover.scripts.OnMouseDown();assert(bindings.BUTTON4=="ZBOX_FORWARD")')
p.main.globals().keystate='down';p.main.execute(bindings['ZBOX_FORWARD'].text);p.advance(.4)
p.alt.execute('assert(axes.MoveForward)')
p.main.globals().keystate='up';p.main.execute(bindings['ZBOX_FORWARD'].text);p.advance(.4)
p.alt.execute('assert(not axes.MoveForward)')
assert call_count(p.main,'MoveForwardStart')==0
print('PASS: dedicated mouse capture over controls, middle/side buttons, modifiers/wheel, ignored activating release, rejected-key preservation, cancel/clear/close/disconnect, and actual XML mouse movement press/release without stray commands')

p=Pair()
p.alt.execute('''
local exists=UnitExists
UnitExists=function(unit) if unit==ownGUID then return true,ownGUID end;return exists(unit) end
UnitXP=function() return 1 end
SUPERWOW_VERSION=126;CLASSIC_API_VERSION=10400
GetNampowerVersion=function() return 4,3,0 end
local api=zAPI
zAPI=function(command,...) if command=="version" then return "3.1" end;return api(command,unpack(arg)) end
local report=zBox:Diagnostics()
assert(string.find(report,"UnitXP=loaded",1,true) and string.find(report,"zAPI=3.1",1,true))
assert(string.find(report,"SuperWoW=126",1,true) and string.find(report,"Nampower=4.3.0",1,true))
assert(string.find(report,"ClassicAPI=10400",1,true) and string.find(report,"GUID lookup=ok",1,true))
zAPI=nil;GetPlayerFacing=nil;GetSpellInfo=nil;UnitXP=nil;SUPERWOW_VERSION=nil;CLASSIC_API_VERSION=nil;GetNampowerVersion=nil
UnitExists=function(unit) if string.sub(unit,1,2)=="0x" then error("Unknown unit") end;return exists(unit) end
report=zBox:Diagnostics()
assert(string.find(report,"GUID lookup=FAILED",1,true) and string.find(report,"zAPI=missing",1,true))
assert(string.find(report,"facing=missing",1,true) and string.find(report,"spell info=missing",1,true))
assert(string.find(report,"UnitXP=missing",1,true))
''')
assert call_count(p.alt,'TargetUnit')==0
# Working calls after a failed cast must not erase the error's source. The
# diagnostic probe is read-only and never changes targets to test GUID support.
p=Pair()
p.alt.execute('''
local native=zBoxNative
zBoxNative=function(command,...)
 if command=="UseAction" then
  local beforeEvent,beforeArg=event,arg1
  event="UI_ERROR_MESSAGE";arg1="Unknown unit.";zBox.frame.scripts.OnEvent()
  event,arg1=beforeEvent,beforeArg
  error("fixture cast failure")
 end
 return native(command,unpack(arg))
end
''')
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"KEEP"})');p.advance(.5)
p.alt.execute('''
assert(zBox.lastGameError=="Unknown unit." and zBox.lastGameErrorCall=="UseAction(1)" and not zBox.activeInvoke)
assert(zBox:Invoke("FollowUnit","party1"))
assert(string.find(zBox:Diagnostics(),"Unknown unit. @ UseAction(1)",1,true))
local exists=UnitExists
UnitExists=function(unit)
 if unit==ownGUID then
  local beforeEvent,beforeArg=event,arg1
  event="UI_ERROR_MESSAGE";arg1="Probe error";zBox.frame.scripts.OnEvent()
  event,arg1=beforeEvent,beforeArg
  error("Unsupported GUID")
 end
 return exists(unit)
end
zBox:Diagnostics()
assert(zBox.lastGameError=="Unknown unit." and zBox.lastGameErrorCall=="UseAction(1)" and not zBox.dependencyProbe)
''')
print('PASS: dependency versions/presence and non-mutating GUID lookup probe, missing/unsupported APIs reported without crashing, and the original game-error call survives later successful inputs')
