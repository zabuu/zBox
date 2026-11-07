"""Driver commands refresh the follower's idle timestamp so it never goes AFK while driven."""
from test_zbox import Pair

p = Pair()
p.alt.execute('''
refreshes=0;afk=true;cleared=0
local native=zBoxNative
zBoxNative=function(cmd,a,b,c)
 if cmd=="capabilities" then return 1,"zBoxBridge 0.1.11",3 end
 if cmd=="RefreshActivity" then refreshes=refreshes+1;return 1,"ok" end
 return native(cmd,a,b,c)
end
zBox.bridgeInfo=nil;local i=zBox:GetBridgeInfo();assert(i.activity);i.directWhisper=false;i.localIPC=false -- this fixture routes party addon messages only
UnitIsAFK=function() return afk end
SendChatMessage=function(text,kind) if kind=="AFK" then afk=false;cleared=cleared+1 end end
zBox.nextActivity=clock+1000
''')
p.command('zBox:Command("FOLLOW")')
assert p.alt.globals().refreshes >= 1 and p.alt.globals().cleared == 1
before = p.alt.globals().refreshes
p.command('zBox:Command("FOLLOW")')
p.advance(2.5)
p.command('zBox:Command("FOLLOW")')
assert p.alt.globals().refreshes == before + 1, 'throttled to every 2s'
p.alt.execute('zBox.db.keepAwake=false')
before = p.alt.globals().refreshes
p.advance(3); p.command('zBox:Command("FOLLOW")')
assert p.alt.globals().refreshes == before, '/zbox awake off disables it'
print('PASS: driver commands refresh the follower idle timer (throttled), clear AFK, and honor /zbox awake off; works on bridge 0.1.11 with a failed jump hook')
