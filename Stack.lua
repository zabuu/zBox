local B=zBox

local function coordinate(value)
  value=tonumber(value)
  if value and value==value and math.abs(value)<=100000 then return value end
end

function B:SetMirrorStack(enabled)
  if not self.db.mirrorMovement then return false,"Select Mirror mode first" end
  if enabled then
    local _,_,major,minor,patch=string.find(self.peerVersion or "","^(%d+)%.(%d+)%.(%d+)$")
    major,minor,patch=tonumber(major),tonumber(minor),tonumber(patch)
    if not self.connected or self.db.role~="control" then return false,"Connect the second character first" end
    if not major or (major==0 and (minor<8 or (minor==8 and patch<1))) then return false,"Update zBox to 0.8.1 on account 2 for Stack" end
    if not self:Position("player") then return false,"Stack needs the zAPI position API on both clients" end
  end
  self.db.mirrorStack=enabled and true or false
  self.lastMirrorAt,self.lastMirrorMask=nil,nil
  self:MirrorTick(GetTime())
  if self.UI then self.UI.dirty=true end
  return true,enabled and "Stack ON: periodic centering while Mirror is running" or "Stack OFF"
end

function B:StackTarget(enabled,x,y,z)
  if enabled==nil or enabled=="0" then return false end
  if enabled~="1" then return nil,"Invalid Stack setting" end
  x,y,z=coordinate(x),coordinate(y),coordinate(z)
  if not x or not y or not z then return nil,"Invalid Stack position" end
  return {x=x,y=y,z=z}
end

-- Face the main and run forward during a correction, then restore its heading.
-- No position writes, follow offset, speed changes or camera turns.
-- A pulse lasts at most a second and starts no more than once every two seconds.
function B:MirrorStackMask(input,now)
  local target=input.stack
  if not target then self.mirrorStack=nil;return input.mask end
  local state=self.mirrorStack or {nextPulse=0}
  self.mirrorStack=state
  local dt=math.max(.01,math.min(.1,now-(state.lastStep or (now-.05))))
  state.lastStep=now
  if not state.active and now<state.nextPulse then return input.mask end
  if state.active and now>=state.untilAt then state.active=nil;self.lastStackStatus="pulse complete";return input.mask end
  local x,y,z=self:Position("player")
  if not x or not coordinate(x) or not coordinate(y) or not coordinate(z) then
    state.active,state.nextPulse=nil,now+2;self.lastStackStatus="position unavailable";return input.mask
  end
  local dx,dy=target.x-x,target.y-y
  local distance=math.sqrt(dx*dx+dy*dy)
  local speed=GetUnitSpeed and GetUnitSpeed("player") or 7
  if type(speed)~="number" or speed~=speed or speed<=0 then speed=7 end
  -- Allow for one real input frame, rather than oscillating past a zero-sized
  -- goal on low-FPS clients. At normal frame rates this settles within ~0.1 yd.
  local tolerance=math.max(.08,math.min(speed,14)*dt*.6)
  if distance<=tolerance then
    state.active,state.nextPulse=nil,now+2;self.lastStackStatus="aligned";return input.mask
  end
  if distance>40 or math.abs(target.z-z)>2 or not self:PeerUnit() then
    state.active,state.nextPulse=nil,now+2;self.lastStackStatus="main unavailable / too far / different floor";return input.mask
  end
  if not state.active or now>=(state.nextTrace or 0) then
    state.nextTrace=now+.25
    local ok,hit=pcall(zAPI,"raycast",x,y,z+.8,target.x,target.y,target.z+.8)
    if not ok or hit~=0 then
      state.active,state.nextPulse=nil,now+2;self.lastStackStatus="route blocked";return input.mask
    end
  end
  if not state.active then
    state.active,state.untilAt,state.nextPulse=true,now+1,now+2
    state.distance,state.progressAt=distance,now
  elseif distance<state.distance-.05 then state.distance,state.progressAt=distance,now end
  if now-state.progressAt>.65 then
    state.active=nil;self.lastStackStatus="no closing progress";return input.mask
  end
  local heading=math.mod(math.atan2(dy,dx)+math.pi*2,math.pi*2)
  self.lastStackStatus="centering"
  return 1,heading
end
