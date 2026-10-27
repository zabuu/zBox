-- zNameplates owns drawing; zBox supplies only authorized, fresh peer state.
local B=zBox
local send=B.SendStatus
function B:SendStatus()
 send(self)
 self:Send("STATE",{"vitals",UnitHealth("player"),UnitHealthMax("player"),UnitMana("player"),UnitManaMax("player"),
  UnitPowerType and UnitPowerType("player") or 0},false)
end
local accept=B.AcceptState
function B:AcceptState(fields,id)
 if fields[1]~="vitals" then return accept(self,fields,id) end
 if table.getn(fields)~=6 or id<=(self.lastVitalsID or 0) then return end
 local v={at=GetTime()}
 for i=2,6 do v[i]=self.Integer(fields[i],0,i==6 and 10 or 1000000000);if not v[i] then return end end
 self.cache.vitals,self.lastVitalsID=v,id
end
function B:PairedVitals(guid)
 if not self.db or self.db.role~="control" or not self.db.enabled or self.worldSuspended then return end
 for _,name in ipairs(self:FollowerNames()) do
  local state=self:FollowerState(name)
  if state and state.connected and state.peerGUID==guid then
   local v=state.cache.vitals
   if v and GetTime()-v.at<=3 then return {health=v[2],maxHealth=v[3],power=v[4],maxPower=v[5],powerType=v[6]} end
  end
 end
end
function B:InstallVitalsProvider()
 if self.vitalsProvider or not zNameplates or type(zNameplates.SetPairedVitalsProvider)~="function" then return end
 self.vitalsProvider=true;zNameplates.SetPairedVitalsProvider(function(guid) return B:PairedVitals(guid) end)
end
