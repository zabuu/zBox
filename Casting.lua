local B = zBox

function B:CaptureCastFacing(replace)
  if self.castActive and not replace then return end
  self.castFacingGUID = nil
  if (self.mirrorInput or self.petState) and UnitCanAttack and UnitCanAttack("player", "target") then
    local guid = self:GUID("target")
    if guid ~= "" then self.castFacingGUID = guid end
  end
end

function B:FaceCastTarget()
  if not self.castFacingGUID then return true end
  local heading = self:HeadingToUnit(self.castFacingGUID)
  if not heading then return false, "Cannot read the cast target's position" end
  local ok, result, detail = pcall(zBoxNative, "SetHeading", heading)
  return ok and result == 1, ok and detail or tostring(result)
end

function B:IsCastHeld(now)
  if self.castActive and self.castEventTimeout and now > self.castEventTimeout then
    self.castActive, self.castFacingGUID, self.stopForCast = nil, nil, nil
  end
  return self.pendingCast or self.castActive or (self.castingUntil and now < self.castingUntil)
end

function B:CastTime(command, index)
  if not GetSpellInfo then return nil end
  local ok, name, rank, icon, cost, funnel, power, milliseconds
  if command == "SPELL" then
    ok, name, rank, icon, cost, funnel, power, milliseconds = pcall(GetSpellInfo, index, BOOKTYPE_SPELL or "spell")
  elseif GetActionInfo then
    local kind, id = GetActionInfo(index)
    if kind ~= "spell" or not id then return nil end
    ok, name, rank, icon, cost, funnel, power, milliseconds = pcall(GetSpellInfo, id)
  end
  if ok and name and not funnel and type(milliseconds) == "number" then return math.max(0, milliseconds / 1000) end
end

function B:PerformCast(request)
  local command, index = request.command, request.index
  if command == "ACTION" then
    if not HasAction(index) or request.stamp ~= self:ActionStamp(index) then return false, "Action bar changed; refresh first" end
  else
    if request.stamp ~= self:SpellStamp(index) then return false, "Spellbook changed; refresh first" end
    if IsPassiveSpell and IsPassiveSpell(index, BOOKTYPE_SPELL or "spell") then return false, "This spell is passive" end
  end
  local ok, reason = self:ChooseTarget(request.target)
  if not ok then return false, reason end
  self:CaptureCastFacing()
  ok, reason = self:FaceCastTarget()
  if not ok then return false, reason end
  self.castRequestAt, self.lastCastSignal = GetTime(), nil
  local hold = request.duration == 0 and 0 or ((request.duration or 2) + 0.6)
  self.castingUntil = math.max(self.castingUntil or 0, GetTime() + hold)
  if command == "ACTION" then return self:Invoke("UseAction", index, 0, request.target == "SELF" and 1 or nil) end
  return self:Invoke("CastSpell", index, BOOKTYPE_SPELL or "spell")
end

function B:RequestCast(command, index, stamp, target)
  local duration = self:CastTime(command, index)
  local request = { command = command, index = index, stamp = stamp, target = target, duration = duration, at = GetTime() }
  if duration == 0 then return self:PerformCast(request) end
  local followed = self.following or self.resumeFollow
  local ok, reason = self:StopMovement(true, true)
  if not ok then return false, reason end
  self.resumeFollow, self.followQuietAt = followed, nil
  self.pendingCast = request
  return true, "Stopping movement before casting"
end

function B:CastEvent(eventName, duration)
  if eventName == "SPELLCAST_START" or eventName == "SPELLCAST_CHANNEL_START" then
    self.castingUntil = GetTime() + (tonumber(duration) or 30000) / 1000 + 0.6
    self.castActive = true
    self.castEventTimeout = math.max(GetTime() + 30, self.castingUntil + 5)
    self:CaptureCastFacing(true)
    -- Events may fire inside a scoped native cast. Defer input calls to Tick.
    if self.petState then self.stopForCast = true
    elseif self.mirrorInput then
      for _, moving in pairs(self.axes or {}) do if moving then self.stopForCast = true end end
    end
  elseif eventName == "SPELLCAST_DELAYED" then
    self.castingUntil = math.max(GetTime(), self.castingUntil or 0) + (tonumber(duration) or 0) / 1000
    self.castEventTimeout = math.max(self.castEventTimeout or 0, self.castingUntil + 5)
  elseif eventName == "SPELLCAST_CHANNEL_UPDATE" then
    self.castingUntil = GetTime() + (tonumber(duration) or 30000) / 1000 + 0.6
    self.castEventTimeout = math.max(GetTime() + 30, self.castingUntil + 5)
  else
    self.castingUntil = GetTime() + 0.35
    self.castActive, self.castFacingGUID, self.stopForCast, self.castEventTimeout = nil, nil, nil, nil
  end
  self.followQuietAt = nil
end

function B:CastingTick(now)
  if UnitIsDeadOrGhost("player") then self:StopMovement(); return end
  if self.stopForCast then
    self.stopForCast = nil
    self:StopMovement(true, true)
  end
  local request = self.pendingCast
  if request then
    local stationary = false
    if GetUnitSpeed then
      local ok, speed = pcall(GetUnitSpeed, "player")
      stationary = ok and type(speed) == "number" and speed < 0.05
    else
      local x, y, z = self:Position()
      stationary = x and request.x and (x-request.x)^2 + (y-request.y)^2 + (z-request.z)^2 < 0.0001
      request.x, request.y, request.z = x, y, z
    end
    if now - request.at >= 0.15 and stationary then
      self.pendingCast = nil
      local ok, reason = self:PerformCast(request)
      if not ok then self.castingUntil, self.castFacingGUID = now + 0.35, nil; self:Send("ERROR", { reason }, true) end
    elseif now - request.at > 2 then
      self.pendingCast, self.castingUntil = nil, now + 0.35
      self:Send("ERROR", { "Account 2 is still moving; cast cancelled" }, true)
    end
  end
  local held = self:IsCastHeld(now)
  if self.castFacingGUID then
    if held then self:FaceCastTarget() else self.castFacingGUID = nil end
  end
  if not self.resumeFollow or held then return end
  local unit = self:PeerUnit()
  if not unit or UnitAffectingCombat("player") or UnitAffectingCombat(unit) then self.followQuietAt = nil; return end
  self.followQuietAt = self.followQuietAt or now
  if now - self.followQuietAt < 0.5 then return end
  self.resumeFollow, self.followQuietAt = nil, nil
  local ok = self:Invoke("FollowUnit", unit)
  self.following = ok
end
