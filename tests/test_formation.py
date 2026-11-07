"""Follow formations: Left/Right/Front/Random spots around the main, Center = normal follow."""
import sys, math
sys.argv = sys.argv[:1]
from test_zbox import Pair

p = Pair(ui=True)
p.alt.execute('''
mx,my,mz,mfacing=0,0,0,0;px,py,pz=0,-10,0;moves={};heads={};followCalls=0
local n=zBoxNative
zBoxNative=function(name,a,b,c)
 if name=="capabilities" then return 1,"zBoxBridge 0.1.6",5 end
 if name=="MoveTo" then table.insert(moves,{a,b});px,py=a,b;return 1,"Native move" end
 if name=="SetHeading" then table.insert(heads,a);facing=a;return 1,"ok" end
 if name=="StopFollow" then return 1,"stopped" end
 if name=="FollowUnit" then followCalls=followCalls+1;return 1,"Requested" end
 return n(name,a,b,c)
end
zBox.bridgeInfo=nil
zBox.PetGeometry=function(self,guid)
 if far then return nil end
 return {x=mx,y=my,z=mz,facing=mfacing,px=px,py=py,pz=pz,radius=3,distance=math.sqrt((mx-px)^2+(my-py)^2)}
end
local guid=zBox.GUID;zBox.GUID=function(self,u) local g=guid(self,u);if g=="" then return "0x0000000000000001" end;return g end
''')
alt = p.alt.globals()

def follow(name):
    p.main.execute(f'zBox.db.formation="{name}";assert(zBox:Command("FOLLOW"))')
    p.advance(.8)

def spot():
    return alt.px, alt.py

# Left: facing +x, so back-left is (-2.5, +2.5) (left of +x is +y).
follow('left')
assert alt.zBox.formation == 'left' and alt.zBox.formationState, 'formation follow active'
x, y = spot(); assert abs(x + 2.5) < .1 and abs(y - 2.5) < .1, (x, y)
follow('right'); x, y = spot(); assert abs(x + 2.5) < .1 and abs(y + 2.5) < .1, (x, y)
follow('front'); x, y = spot(); assert abs(x - 3) < .1 and abs(y) < .1, (x, y)
print('PASS: Left/Right/Front walk to back-left, back-right and in front of the main')

# Turning the main turns the spot; settled followers face the main's way.
p.alt.execute('mfacing=math.pi/2')
p.advance(1)
x, y = spot(); assert abs(x) < .1 and abs(y - 3) < .1, ('front follows facing', x, y)
assert alt.heads[len(alt.heads)] and abs(alt.heads[len(alt.heads)] - math.pi/2) < .01
print('PASS: spots rotate with the main; a settled follower faces the same way')

# Random: a new spot in the box behind each time the main starts moving.
follow('random')
seen = set()
p.alt.execute('mfacing=0')
for i in range(8):
    p.alt.execute('mx=mx+3'); p.advance(.3)  # main moves
    p.advance(1)                              # main stops
    x, y = spot()
    back, side = alt.mx - x, y - alt.my
    assert 1.4 <= back <= 5.1 and abs(side) <= 4.05, (back, side)
    seen.add((round(back, 1), round(side, 1)))
assert len(seen) >= 4, seen
print('PASS: Random picks a new spot 1.5-5 yards behind and up to 4 yards to either side each move')

# Center keeps the game's follow; too far falls back to it too.
p.alt.execute('followCalls=0')
follow('center')
assert not alt.zBox.formationState and alt.followCalls >= 1
follow('left'); p.alt.execute('far=true;followCalls=0'); p.advance(.5)
assert alt.followCalls == 1 and alt.zBox.formationState.native
p.alt.execute('far=nil'); p.advance(.5)
assert not alt.zBox.formationState.native
p.main.execute('zBox:Command("STOP")'); p.advance(.5)
assert not alt.zBox.formationState
print('PASS: Center uses normal follow; out of range falls back to normal follow and back again; Stop ends formation')

# UI: the tab pops out five formation buttons with custom icons; choosing one saves it.
p.main.execute('''
local u=zBox.UI;assert(u.formationTab,"tab exists")
u.formationTab.scripts.OnClick();local f=u.formationFlyout;assert(f:IsShown() and table.getn(f.buttons)==5)
assert(string.find(f.buttons[5].icon.texture or f.buttons[5].icon:GetTexture() or "","formation%-random"))
f.buttons[3].scripts.OnClick();assert(zBox.db.formation=="right" and zBox:Formation()=="right")
assert(f.buttons[3].ring:IsShown() and not f.buttons[1].ring:IsShown())
''')
print('PASS: the Formation tab pops out five icon buttons; choosing one saves it and marks it')
