-- Relay metadata only. zDNumbers/MSBT own every damage number and display rule.
local B=zBox
local results={DAMAGE=true,MISS=true,DODGE=true,PARRY=true,BLOCK=true,RESIST=true,ABSORB=true,IMMUNE=true,EVADE=true}
local function kind(value)
  if type(value)~="string" then return false end
  if value=="SPELL_DOT" then return true end
  return results[value] or (string.sub(value,1,6)=="SPELL_" and results[string.sub(value,7)])
end
local function guid(value)
  return type(value)=="string" and string.find(value,"^0x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$")
end
local function plain(value,limit)
  return type(value)=="string" and string.len(value)<=limit and not string.find(value,"[%c|]")
end

function B:DamageSource()
  if self.connected and self.db.role=="control" then return self.peerGUID end
end

function B:InstallDamageBridge()
  local z=zDNumbers
  if not z or z.PairedDamageVersion~=1 or type(z.SetOutgoingDamageObserver)~="function" or
      type(z.SetPairedDamageSource)~="function" or type(z.ShowPairedDamage)~="function" then
    self.damageBridge=nil;return
  end
  self.damageBridge=z
  z.SetPairedDamageSource(function() return B:DamageSource() end)
  z.SetOutgoingDamageObserver(function(e) B:RelayDamage(e) end,function() return B.connected and B.db.role=="agent" end)
end

function B:RelayDamage(e)
  if not self.connected or self.db.role~="agent" or type(e)~="table" then return end
  local prefix="MSBT_EVENTTYPE_OUTGOING_"
  if type(e.EventType)~="string" or string.sub(e.EventType,1,string.len(prefix))~=prefix then return end
  local suffix=string.sub(e.EventType,string.len(prefix)+1)
  if not kind(suffix) then return end
  local flags=(e.IsCrit and 1 or 0)+(e.IsGlancing and 2 or 0)+(e.IsBlocked and 4 or 0)+(e.IsParried and 8 or 0)
  local id=self:Send("DAMAGE",{self:GUID("player"),suffix,e.Amount or "",flags,e.TargetGUID or "",
    e.Name or "",e.EffectName or "",e.SpellID or "",e.Texture or "",e.DamageType or ""},false)
  if id then self.damageRelayed=(self.damageRelayed or 0)+1 end
end

function B:AcceptDamage(fields,id)
  if not self.damageBridge or table.getn(fields)~=10 or id<=(self.lastDamageID or 0) or
      not guid(fields[1]) or fields[1]~=self:DamageSource() or not kind(fields[2]) then return end
  local amount=fields[3]~="" and self.Integer(fields[3],0,1000000000) or nil
  local flags=self.Integer(fields[4],0,15)
  local spell=fields[8]~="" and self.Integer(fields[8],1,10000000) or nil
  if not flags or (fields[3]~="" and not amount) or (fields[8]~="" and not spell) or
      (fields[5]~="" and not guid(fields[5])) or not plain(fields[6],160) or
      not plain(fields[7],160) or not plain(fields[9],192) or not plain(fields[10],48) then return end
  if string.find(fields[2],"DAMAGE$",1) or fields[2]=="SPELL_DOT" then if not amount then return end end
  self.lastDamageID=id
  local e={Kind=fields[2],Amount=amount,Name=fields[6]~="" and fields[6] or nil,
    EffectName=fields[7]~="" and fields[7] or nil,TargetGUID=fields[5]~="" and fields[5] or nil,
    SpellID=spell,Texture=fields[9]~="" and fields[9] or nil,DamageType=fields[10]~="" and fields[10] or nil,
    IsCrit=math.mod(flags,2)==1 or nil,IsGlancing=math.mod(math.floor(flags/2),2)==1 or nil,
    IsBlocked=math.mod(math.floor(flags/4),2)==1 or nil,IsParried=math.mod(math.floor(flags/8),2)==1 or nil}
  local ok,shown=pcall(self.damageBridge.ShowPairedDamage,e,fields[1])
  if ok and shown then self.damageReceived=(self.damageReceived or 0)+1 end
end
