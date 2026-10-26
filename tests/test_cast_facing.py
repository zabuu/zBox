"""Mirrored hostile casts own their heading until the real cast end event."""
from test_hotfix import Pair, call_count
import math

p=Pair()
p.alt.execute('''
enemyX=0;enemyY=10
UnitCanAttack=function(player,unit) return unit=="target" or unit=="0x0000000000000099" end
local api=zAPI
zAPI=function(command,unit,...)
 if command=="unitPosition" and (unit=="target" or unit=="0x0000000000000099") then return enemyX,enemyY,0 end
 return api(command,unit,unpack(arg))
end
GetSpellInfo=function() return "Fireball","Rank 1","Icon",1,false,0,3000 end
local native=zBoxNative
zBoxNative=function(name,a,b,c)
 if name=="SetHeading" then assert(not fixtureNativeBusy,"Input reentered during a cast event") end
 if name=="UseAction" then
  fixtureNativeBusy=true
  local result,detail=native(name,a,b,c)
  fixtureNativeBusy=false
  return result,detail
 end
 return native(name,a,b,c)
end
UseAction=function(a,b,c)
 assert(not axes.MoveForward and math.abs(facing-math.pi/2)<.001,"Did not stop and face enemy before casting")
 log("UseAction",a,b,c)
 zBox:CastEvent("SPELLCAST_START",3000)
end
''')
p.main.execute('assert(zBox:SetMirrorMode(true));MoveForwardStart();facing=3.5');p.advance(.5)
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.view.rows[1][4],"KEEP"})');p.advance(.6)
assert call_count(p.alt,'UseAction')==1
p.alt.execute('assert(zBox.castActive and zBox.castFacingGUID=="0x0000000000000099" and not axes.MoveForward)')
p.main.execute('facing=4.4;Jump()');p.advance(.4)
p.alt.execute('assert(math.abs(facing-math.pi/2)<.001 and not axes.MoveForward)')
assert call_count(p.alt,'Jump')==0
# Track the original enemy even if the alt's selected target changes mid-cast.
p.alt.execute('''
enemyX=10;enemyY=0
local exists=UnitExists
UnitExists=function(unit) if unit=="target" then return true,"0x0000000000000098" end;return exists(unit) end
''')
p.advance(.5)
p.alt.execute('assert(math.abs(facing)<.001 and zBox.castFacingGUID=="0x0000000000000099")')
# The estimate alone cannot release the facing lock; delayed/end events own it.
p.advance(4)
p.alt.execute('assert(zBox.castActive and math.abs(facing)<.001 and not axes.MoveForward);zBox:CastEvent("SPELLCAST_DELAYED",1000)')
p.advance(.5)
p.alt.execute('assert(math.abs(facing)<.001 and not axes.MoveForward);zBox:CastEvent("SPELLCAST_STOP")')
p.advance(.7)
p.alt.execute('assert(not zBox.castActive and not zBox.castFacingGUID and axes.MoveForward and math.abs(facing-4.4)<.001)')

# Channel callbacks only record intent while a native cast may still be on the
# stack; facing/movement input is deferred to the next Tick.
p.alt.execute('''
local exists=UnitExists
UnitExists=function(unit) if unit=="target" then return true,"0x0000000000000099" end;return exists(unit) end
enemyX=-10;enemyY=0
fixtureNativeBusy=true
zBox:CastEvent("SPELLCAST_CHANNEL_START",5000)
fixtureNativeBusy=false
''')
p.advance(.3)
p.alt.execute('assert(not axes.MoveForward and math.abs(facing-math.pi)<.001);zBox:CastEvent("SPELLCAST_CHANNEL_UPDATE",2000)')
p.main.execute('facing=.8');p.advance(.4)
p.alt.execute('assert(not axes.MoveForward and math.abs(facing-math.pi)<.001);zBox:CastEvent("SPELLCAST_CHANNEL_STOP")')
p.advance(.6)
p.alt.execute('assert(axes.MoveForward and math.abs(facing-.8)<.001)')

# Friendly/self casts do not adopt an enemy heading, and explicit STOP clears it.
p.alt.execute('''
UnitCanAttack=function() return false end
zBox:CastEvent("SPELLCAST_START",3000)
assert(not zBox.castFacingGUID)
UnitCanAttack=function() return true end
zBox:CastEvent("SPELLCAST_START",3000)
assert(zBox.castFacingGUID)
''')
p.command('zBox:Command("STOP")')
p.alt.execute('assert(not zBox.castActive and not zBox.castFacingGUID and not zBox.mirrorInput)')
print('PASS: hostile mirror casts stop and face the enemy before casting, retain its GUID through target/heading changes and delays, release on cast/channel end, and clear on STOP without native reentry')
