"""Quiet failures, continuous instant melee and metadata-only damage relay."""
from test_local_transport import LocalPair, call_count
from test_pet_mode import pet_pair
from pathlib import Path

f=LocalPair();p=f.p
for lua in [p.main,p.alt]:lua.execute('chat={};DEFAULT_CHAT_FRAME.AddMessage=function(self,text) table.insert(chat,text) end')
p.alt.execute('''
for i=1,100 do zBox.lastCommandAt=GetTime();zBox:RelayGameError("Not enough energy") end
assert(zBox.lastGameError=="Not enough energy")
''')
f.fast(3)
p.main.execute('assert(table.getn(chat)==0 and string.find(zBox:Diagnostics(),"Not enough energy",1,true));assert(string.find(zBox.notice,"Not enough energy",1,true))')
errors=[packet for who,packet,_ in f.history if who=='Alt' and '~ERROR~' in packet]
assert len(errors)==1
f.fast(60);p.main.execute('zBox:Slash("feedback verbose");chat={}')
for _ in range(5):
    p.alt.execute('zBox.lastCommandAt=GetTime();zBox:RelayGameError("Out of range.")');f.fast(5)
p.main.execute('assert(table.getn(chat)==1);zBox:Slash("feedback quiet");chat={}')
p.alt.execute('IsUsableAction=function() return nil,true end')
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.bar.rows[1][4],"SELF"})');f.fast(4)
p.main.execute('assert(table.getn(chat)==0 and string.find(zBox.lastRemoteError,"Not enough power",1,true))')

# Instant hits and failures keep the pet chase active through target movement.
p=pet_pair();p.alt.execute('mainCombat=true;ownCombat=true;GetSpellInfo=function() return "Strike","Rank 1","Icon",40,false,3,0 end')
p.main.execute('assert(zBox:AttackCommand())');p.advance(.3,physics=True)
stops=call_count(p.alt,'StopFollow')
for event in ['SPELLCAST_STOP','SPELLCAST_FAILED','SPELLCAST_INTERRUPTED']:
    p.alt.execute('enemies[enemyGUID].x=enemies[enemyGUID].x+3')
    p.main.execute('zBox:Command("ACTION",{1,zBox.cache.bar.rows[1][4],enemyGUID})');p.advance(.2,physics=True)
    p.alt.execute(f'zBox:CastEvent("{event}");assert(not zBox:IsCastHeld(GetTime()) and zBox.petState.guid==enemyGUID)')
    p.advance(.2,physics=True)
assert call_count(p.alt,'StopFollow')==stops and call_count(p.alt,'UseAction')==3
p.alt.execute('GetSpellInfo=function() return "Cast","Rank 1","Icon",40,false,3,3000 end;IsUsableAction=function() return nil,true end')
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.bar.rows[1][4],enemyGUID})');p.advance(.2,physics=True)
assert call_count(p.alt,'StopFollow')==stops and call_count(p.alt,'UseAction')==3
p.alt.execute('IsUsableAction=function() return true end;GetSpellInfo=nil')
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.bar.rows[1][4],enemyGUID})');p.advance(.2,physics=True)
assert call_count(p.alt,'StopFollow')==stops and call_count(p.alt,'UseAction')==4

# Held direction renewal survives instant actions, while true cast-time holds
# pause renewals. An explicitly changed movement input can still cancel a cast.
f=LocalPair();p=f.p
p.alt.execute('GetSpellInfo=function() return "Strike","Rank 1","Icon",40,false,3,0 end')
p.main.execute('zBox:HoldDirection("forward",true,"key")');f.fast(2)
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.bar.rows[1][4],"SELF"})');f.fast(100)
p.alt.execute('assert(axes.MoveForward)')
p.main.execute('assert(zBox.heldMask==1)')
p.alt.execute('GetSpellInfo=function() return "Fireball","Rank 1","Icon",40,false,0,1500 end')
p.main.execute('zBox:Command("ACTION",{1,zBox.cache.bar.rows[1][4],"SELF"})');f.fast(45)
p.alt.execute('assert(not axes.MoveForward and zBox:IsCastHeld(GetTime()));zBox:CastEvent("SPELLCAST_STOP")')
f.fast(70);p.alt.execute('assert(axes.MoveForward)')

# The transport only calls zDNumbers' public adapter; it creates no text/frame.
for lua in [p.main,p.alt]:lua.execute('''
damage={}
zDNumbers={PairedDamageVersion=1,
 SetOutgoingDamageObserver=function(fn,active) observeDamage=fn;observeDamageActive=active end,
 SetPairedDamageSource=function(fn) sourceProvider=fn end,
 ShowPairedDamage=function(e,source) assert(source==sourceProvider());table.insert(damage,{e=e,source=source});return true end}
zBox:InstallDamageBridge()
''')
p.alt.execute('''
assert(observeDamageActive());observeDamage({EventType="MSBT_EVENTTYPE_OUTGOING_SPELL_DAMAGE",Amount=123,IsCrit=true,
 IsGlancing=true,TargetGUID=enemyGUID,Name="Enemy",EffectName="Strike",SpellID=1752,DamageType="Physical"})
observeDamage({EventType="MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE",Amount=50})
''')
f.fast(5)
p.main.execute('assert(table.getn(damage)==1 and damage[1].e.Amount==123 and damage[1].e.IsCrit and damage[1].e.IsGlancing and damage[1].e.SpellID==1752 and damage[1].source==peerGUID)')
# Replayed IDs and malformed/spoofed source/amount/code/session are rejected.
p.main.execute('''
local b=zBox;local fields={peerGUID,"DAMAGE","10","0",enemyGUID,"Enemy","","","","Physical"}
b:AcceptDamage(fields,b.lastDamageID);fields[1]=ownGUID;b:AcceptDamage(fields,999999)
fields[1]=peerGUID;fields[3]="nan";b:AcceptDamage(fields,999999)
assert(table.getn(damage)==1)
''')
p.alt.execute('zBox:Slash("off");assert(not observeDamageActive());observeDamage({EventType="MSBT_EVENTTYPE_OUTGOING_DAMAGE",Amount=5})')
f.fast(5);p.main.execute('assert(table.getn(damage)==1)')
source=(Path(__file__).parents[1]/'Damage.lua').read_text()
assert all(name not in source for name in ['CreateFrame','CreateFontString','DisplayMessage','AddAnimation'])
print('PASS: quiet/coalesced remote errors with opt-in limited logs, moving-target instant melee and failed-resource attempts preserve chase, real casts/held-input renewals pause correctly, and validated/replay-safe damage metadata goes exclusively to zDNumbers')
