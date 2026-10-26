"""Regressions for the 0.3.0 jump security and panel hit-testing failures."""
from test_features import Pair, call_count

p=Pair(ui=True)
p.main.execute('assert(Jump==originalNativeJump,"zBox replaced the protected Jump global before Mirror was enabled")')
assert p.main.eval('nativePostHooks.Jump') is None
p.main.execute('Jump()')
assert call_count(p.main,'Jump')==1 and call_count(p.alt,'Jump')==0
p.main.execute('assert(zBox:SetMirrorMode(true));assert(Jump==originalNativeJump);Jump()');p.advance(.5)
assert p.main.eval('nativePostHooks.Jump') is None
assert call_count(p.main,'Jump')==2 and call_count(p.alt,'Jump')==1
p.main.execute('assert(zBox:SetMirrorMode(false));Jump()');p.advance(.5)
assert call_count(p.main,'Jump')==3 and call_count(p.alt,'Jump')==1
# No Lua hook is needed, and an older bridge gives a concrete update error.
legacy=Pair()
legacy.main.execute('hooksecurefunc=nil;local before=Jump;assert(zBox:SetMirrorMode(true));assert(Jump==before);Jump()');legacy.advance(.5)
assert call_count(legacy.main,'Jump')==1
assert call_count(legacy.alt,'Jump')==1
legacy.main.execute('zBox.bridgeInfo={ready=true,mirror=true};local ok,why=zBox:SetMirrorMode(true);assert(not ok and string.find(why,"0.1.5"))')
# Only completed native jump events mirror. Repeated polls, failed/blocked jumps
# and heading updates do not manufacture another jump.
p=Pair()
p.main.execute('hooksecurefunc=function() error("zBox must not hook the protected Jump global") end;assert(zBox:SetMirrorMode(true));jumpBlocked=true;Jump()');p.advance(.5)
assert call_count(p.main,'Jump')==1 and call_count(p.alt,'Jump')==0
p.main.execute('jumpBlocked=false;Jump()');p.advance(.5)
assert call_count(p.alt,'Jump')==1
p.advance(2)
assert call_count(p.alt,'Jump')==1
p.main.execute('facing=1.1');p.advance(.5)
assert call_count(p.alt,'Jump')==1
# Jumps before enabling/resuming are baselined, not replayed. Counter wrap works.
p.main.execute('zBox:ToggleMirrorPause();Jump();Jump()');p.advance(.5)
p.main.execute('zBox:ToggleMirrorPause()');p.advance(.5)
assert call_count(p.alt,'Jump')==1
p.main.execute('nativeJumpSequence=4294967295;zBox.lastMirrorJump=4294967295;Jump()');p.advance(.5)
assert call_count(p.alt,'Jump')==2
print('PASS: normal Jump is never hooked; only completed jumps mirror once; blocked jumps, paused events and heading updates do not mirror; counter wrap and old-bridge rejection work')

p=Pair(ui=True)
p.main.execute('''
UIParent.height=900;zBox.UI.frame:Show()
zBox.UI.frame.mockTop=1050;zBox.UI.frame.mockBottom=940
zBox.UI:ShowSetup();zBox.UI:PlacePanels()
local function interactive(frame)
 if frame.kind=="Button" or frame.kind=="EditBox" then
  local parent=frame.parent
  while parent and parent~=UIParent do
   assert(frame.level>parent.level,"Panel background covers "..tostring(frame.kind))
   parent=parent.parent
  end
 end
 for _,child in ipairs(frame.children) do
  if child.kind~="FontString" and child.kind~="Texture" then interactive(child) end
 end
end
for _,panel in ipairs({zBox.UI.browser,zBox.UI.setup,zBox.UI.keys}) do interactive(panel) end
local function collect(frame,levels)
 if frame.kind~="FontString" and frame.kind~="Texture" then levels[frame.mockid]=frame.level end
 for _,child in ipairs(frame.children) do collect(child,levels) end
end
local before={};collect(zBox.UI.frame,before)
for i=1,40 do
 zBox.UI.frame.mockTop=i%2==0 and 1050 or 120
 zBox.UI.frame.mockBottom=i%2==0 and 940 or 10
 zBox.UI:PlacePanels()
end
local after={};collect(zBox.UI.frame,after)
for id,level in pairs(before) do assert(after[id]==level,"Repositioning changed a frame level") end
for _,panel in ipairs({zBox.UI.browser,zBox.UI.setup,zBox.UI.keys}) do interactive(panel) end
''')
print('PASS: setup/browser/keys controls stay above every panel background; top/bottom repositioning preserves descendant frame levels')
