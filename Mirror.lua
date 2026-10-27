local B = zBox

function B:SetMirrorMode(enabled, quiet)
  if enabled then
    local ok, reason = self:ResetMirrorJump()
    if not ok then return false, reason end
  end
  if self.connected and self.db.role == "control" then self:Command("STOP") end
  self.db.mirrorMovement = enabled and true or false
  self.db.petMovement = false
  self.mirrorPaused, self.lastMirrorAt = not enabled, nil
  if not enabled then self.lastMirrorJump = nil end
  if not quiet then self:Notify(enabled and "Mirror movement enabled: heading, movement and jump" or "Follow mode selected") end
  return true
end

function B:ToggleMirrorPause()
  if not self.db.mirrorMovement then return end
  if self.mirrorPaused then
    local ok, reason = self:ResetMirrorJump()
    if not ok then self:Notify(reason); return end
    self.mirrorPaused, self.lastMirrorAt = false, nil
  else self:Command("STOP") end
  if self.UI then self.UI.dirty = true end
end

function B:MirrorTick(now)
  if not self.connected or self.db.role ~= "control" or not self.db.mirrorMovement or self.mirrorPaused then return end
  local ok, result, mask, heading, jumps = pcall(zBoxNative, "inputs")
  if not ok or result ~= 1 or type(mask) ~= "number" or type(heading) ~= "number" or not self.Integer(jumps, 0, 4294967295) then
    self:Command("STOP"); self:Notify("Mirror paused: update zBoxBridge on both clients"); return
  end
  local jumped = self.lastMirrorJump ~= nil and jumps ~= self.lastMirrorJump
  self.lastMirrorJump = jumps
  if not jumped and now - (self.lastMirrorAt or -10) < (self.localReady and 0.03 or 0.12) then return end
  local x,y,z
  if self.db.mirrorStack then x,y,z=self:Position("player") end
  local stack=self.db.mirrorStack and x~=nil
  local positionChanged=stack and (not self.lastStackX or (x-self.lastStackX)^2+(y-self.lastStackY)^2+(z-self.lastStackZ)^2>.05^2)
  local changed = positionChanged or stack~=self.lastStackEnabled or mask ~= self.lastMirrorMask or not self.lastMirrorHeading or math.abs(heading-self.lastMirrorHeading) > 0.008
  if not jumped and not changed and now - (self.lastMirrorAt or -10) < 0.25 then return end
  self.lastMirrorAt, self.lastMirrorMask, self.lastMirrorHeading = now, mask, heading
  self.lastStackX,self.lastStackY,self.lastStackZ,self.lastStackEnabled=x,y,z,stack
  heading = math.mod(heading, math.pi*2)
  if heading > math.pi*2 - 0.000001 then heading = 0 end
  local fields={mask,string.format("%.6f",heading),(GetRealZoneText and GetRealZoneText()) or ""}
  if stack then
    table.insert(fields,"1");table.insert(fields,string.format("%.4f",x));table.insert(fields,string.format("%.4f",y));table.insert(fields,string.format("%.4f",z))
  else table.insert(fields,"0") end
  self:Command("MIRROR",fields)
  if jumped then self:Command("JUMP", { "mirror" }) end
end

function B:AcceptMirror(mask, heading, zone, stack, x, y, z)
  mask, heading = self.Integer(mask, 0, 63), tonumber(heading)
  if not mask or not heading or heading ~= heading or heading < 0 or heading >= math.pi*2 then return false, "Invalid mirrored inputs" end
  if not self:GetBridgeInfo().mirror then return false, "Mirror mode needs zBoxBridge 0.1.4" end
  if zone ~= ((GetRealZoneText and GetRealZoneText()) or "") then return false, "Mirror movement requires the same zone" end
  local target,reason=self:StackTarget(stack,x,y,z)
  if target==nil then return false,reason end
  -- Heading is authoritative. Turn keys affect the main's heading, so account 2
  -- receives the measured result instead of integrating a second turn rate.
  local forward, backward = math.mod(mask,2), math.mod(math.floor(mask/2),2)
  local strafe = math.floor(mask/16)
  if forward+backward > 1 or strafe == 3 then return false, "Opposite mirrored inputs" end
  local travelMask = forward + backward*2 + strafe*16
  if self.following or self.destination then self:StopMovement() end
  self.mirrorInput = { mask = travelMask, heading = heading, at = GetTime(),stack=target or nil }
  if not target then self.mirrorStack=nil end
  self.resumeFollow = nil
  self:MirrorAgentTick(GetTime())
  return true, "Mirroring movement"
end

function B:MirrorAgentTick(now)
  local input = self.mirrorInput
  if not input then return end
  if now - input.at > 0.8 or UnitIsDeadOrGhost("player") then self:StopMovement(); return end
  if self:IsCastHeld(now) then
    if self.mirrorStack then self.mirrorStack.active,self.mirrorStack.nextPulse=nil,now+.25 end
    return
  end
  local ok, result = pcall(zBoxNative, "SetHeading", input.heading)
  if not ok or result ~= 1 then
    self:StopMovement(); self:Send("ERROR", { "Mirror heading failed; movement stopped" }, true); return
  end
  -- ManualAxes handles the normal lease and opposing-key checks. Preserve the
  -- stream so it can renew input without invoking follow.
  self:ManualAxes(self:MirrorStackMask(input,now),true)
end

function B:ResetMirrorJump()
  local info = self:GetBridgeInfo()
  if not info.jumpEvents then
    if info.version == "zBoxBridge 0.1.5" or info.version == "zBoxBridge 0.1.6" or info.version == "zBoxBridge 0.1.7" or info.version == "zBoxBridge 0.1.8" or info.version == "zBoxBridge 0.1.9" then return false, "Native jump observer did not load; /zbox diag reports its status" end
    return false, "Mirror jumping needs zBoxBridge 0.1.5. Fully restart both clients after updating the DLL."
  end
  local ok, result, mask, heading, jumps = pcall(zBoxNative, "inputs")
  if not ok or result ~= 1 or not self.Integer(jumps, 0, 4294967295) then return false, "Native jump observation is unavailable" end
  -- Baseline on enable/resume so jumps made while paused cannot be replayed.
  self.lastMirrorJump = jumps
  return true
end
