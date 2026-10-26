local B = zBox

function B:MovementMode()
  return self.db.mirrorMovement and "mirror" or (self.db.petMovement and "pet" or "follow")
end

function B:SetMovementMode(mode)
  if mode ~= "follow" and mode ~= "mirror" and mode ~= "pet" then return false, "Unknown movement mode" end
  if mode == "pet" and not self:GetBridgeInfo().nativeMove then return false, "Pet controls need zBoxBridge 0.1.6; fully restart both clients after updating the DLL" end
  local ok, reason = self:SetMirrorMode(mode == "mirror", true)
  if not ok then return false, reason end
  self.db.petMovement = mode == "pet"
  self:Notify(mode == "pet" and "Pet controls: Follow, Assist and Attack. Combat ends in Follow." or (mode == "mirror" and "Mirror movement enabled" or "Follow mode selected"))
  return true
end

function B:CycleMovementMode()
  local nextMode = { follow = "mirror", mirror = "pet", pet = "follow" }
  local ok, reason = self:SetMovementMode(nextMode[self:MovementMode()])
  if not ok then self:Notify(reason) end
end

function B:PetOrder(order)
  local guid = (order == "attack" or order == "assist") and self:GUID("target") or ""
  if order == "attack" and guid == "" then return false, "Choose an enemy first" end
  return self:Command("PET", { order, guid, self.db.petStyle or "auto" })
end

function B:FollowCommand()
  if self:MovementMode() == "pet" then return self:PetOrder("follow") end
  return self:Command("FOLLOW")
end

function B:AssistCommand()
  if self:MovementMode() == "pet" then return self:PetOrder("assist") end
  return self:Command("ASSIST")
end

function B:AttackCommand()
  if self:MovementMode() ~= "pet" then
    local ok,reason = self:SetMovementMode("pet")
    if not ok then return false,reason end
  end
  return self:PetOrder("attack")
end

function B:StopPetAttack(state)
  state = state or self.petState
  if not state then return end
  if state.hunterStarted then self:Invoke("SpellStopCasting"); state.hunterStarted = nil end
  if state.meleeStarted then
    if StopAttack then self:Invoke("StopAttack")
    elseif IsCurrentSpell and IsCurrentSpell("Attack") then self:Invoke("AttackTarget") end
    state.meleeStarted = nil
  end
end

function B:CancelPet()
  self:StopPetAttack()
  self.petState = nil
end

function B:PetStyle(style)
  local _, class = UnitClass("player")
  if class == "HUNTER" then return "hunter" end
  if style == "melee" or style == "ranged" then return style end
  return (class == "MAGE" or class == "WARLOCK" or class == "PRIEST") and "ranged" or "melee"
end

function B:PetEnemy(guid)
  return type(guid) == "string" and string.find(guid, "^0x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") and
    UnitExists(guid) and not UnitIsDeadOrGhost(guid) and UnitCanAttack and UnitCanAttack("player", guid)
end

function B:PetGeometry(guid)
  local ok, result, x,y,z,facing,px,py,pz,radius = pcall(zBoxNative, "CombatGeometry", guid)
  if not ok or result ~= 1 then return nil end
  for _, value in ipairs({x,y,z,facing,px,py,pz,radius}) do
    if type(value) ~= "number" or value ~= value or math.abs(value)>100000 then return nil end
  end
  if radius < 1.5 or radius > 15 or (x-px)^2+(y-py)^2 > 120^2 or math.abs(z-pz)>35 then return nil end
  return { x=x, y=y, z=z, facing=facing, px=px, py=py, pz=pz, radius=radius,
    distance=math.sqrt((x-px)^2+(y-py)^2) }
end

function B:PetCanRear(guid, inCombat)
  -- Use the commanded enemy's actual target, never the main's target-of-target
  -- by accident. Unknown victims during combat do not authorize circling.
  if self:GUID("target") ~= guid then return false end
  local victim, player = self:GUID("targettarget"), self:GUID("player")
  if victim == "" then return not inCombat end
  if player ~= "" then return self:Name(victim) ~= self:Name(player) end
  if UnitIsUnit then
    local ok, same = pcall(UnitIsUnit, "targettarget", "player")
    if ok then return not same end
  end
  return false
end

function B:PetFollow(state)
  state = state or self.petState
  local main = self:GroupUnit(self.db.peer)
  if not main then self:StopMovement(); return false, "Main character is unavailable" end
  local ok, reason = self:StopMovement(nil, true, true)
  if not ok then self:CancelPet(); return false, reason end
  self:StopPetAttack(state)
  if state then
    state.guid, state.seenCombat, state.quietAt, state.behind, state.rearBlockedUntil = nil, nil, nil, nil, nil
    state.lastPlan, state.lastAttack, state.lastRear = nil, nil, nil
    state.lastMainTarget = self:GUID(main .. "target")
  end
  ok, reason = self:Invoke("FollowUnit", main)
  self.following = ok
  if not ok then self:CancelPet() end
  return ok, reason or "Following main"
end

function B:ReceivePet(order, guid, style)
  if order ~= "follow" and order ~= "assist" and order ~= "attack" then return false, "Invalid pet order" end
  if style ~= "auto" and style ~= "melee" and style ~= "ranged" then return false, "Invalid pet approach" end
  if not self:GetBridgeInfo().nativeMove then return false, "Pet controls need zBoxBridge 0.1.6; restart both clients after updating" end
  if UnitIsDeadOrGhost("player") then return false, "Account 2 is dead" end
  if order == "attack" and not self:PetEnemy(guid) then return false, "Choose a living attackable enemy loaded by account 2" end
  if order == "attack" and not self:PetGeometry(guid) then return false, "Enemy is out of movement range or geometry is unavailable" end
  local ok, reason = self:StopMovement(nil, true)
  if not ok then return false, reason end
  self.petState = { mode = order == "assist" and "assist" or "follow", style = self:PetStyle(style) }
  local main = self:GroupUnit(self.db.peer)
  self.petState.lastMainTarget = main and self:GUID(main .. "target") or ""
  if order ~= "follow" and self:PetEnemy(guid) then
    self.petState.guid, self.petState.started = guid, GetTime()
  else return self:PetFollow() end
  return true, self.petState.style == "ranged" and "Approaching and facing target; choose your spells" or "Pet attack requested"
end

function B:PetGround(x,y,z, g)
  local ok, hit, gx,gy,gz = pcall(zAPI, "raycast", x,y,z+2,x,y,z-3)
  if not ok or hit ~= 1 or type(gz) ~= "number" or gz ~= gz or math.abs(gz-z)>2.5 or
     type(gx) ~= "number" or type(gy) ~= "number" or gx~=gx or gy~=gy or math.abs(gx)>100000 or math.abs(gy)>100000 then return nil end
  -- Like zPet, validate the floor and the target-to-point corridor. Also check
  -- our straight travel segment: a player has no server-side pet pathfinder.
  local wall, blocked = pcall(zAPI, "raycast", g.x,g.y,g.z+0.8,gx,gy,gz+0.8)
  if not wall or blocked ~= 0 then return nil end
  wall, blocked = pcall(zAPI, "raycast", g.px,g.py,g.pz+0.8,gx,gy,gz+0.8)
  if not wall or blocked ~= 0 then return nil end
  return gx,gy,gz
end

function B:PetApproach(state, g, canRear, now)
  local radius = state.style == "melee" and g.radius or 25
  local dx,dy = g.px-g.x,g.py-g.y
  local length = math.max(0.001,g.distance)
  local x,y = g.x+dx/length*radius,g.y+dy/length*radius
  if state.style ~= "melee" then
    if g.distance <= 26 and (state.style ~= "hunter" or g.distance >= 8) then return true end
  elseif canRear and now >= (state.rearBlockedUntil or 0) then
    local fx,fy = math.cos(g.facing),math.sin(g.facing)
    local behind = g.distance > 0.2 and (dx*fx+dy*fy)/length < (state.behind and -0.1 or -0.3)
    state.behind = behind
    if behind and g.distance <= radius+0.4 and math.abs(g.pz-g.z)<2 then return true end
    x,y = g.x-fx*radius,g.y-fy*radius
    -- Avoid running through the enemy's centre on a frontal approach. One
    -- side waypoint gets us around it before the final rear point.
    if not behind and (dx*fx+dy*fy)/length > 0.25 then
      local side = dx*(-fy)+dy*fx >= 0 and 1 or -1
      x,y = g.x-fy*(radius+1)*side,g.y+fx*(radius+1)*side
    end
  elseif g.distance <= radius+0.3 and math.abs(g.pz-g.z)<2 then state.behind=nil; return true end
  local gx,gy,gz = self:PetGround(x,y,g.z,g)
  if not gx then
    -- A rejected rear point falls back to an ordinary melee approach.
    if state.style == "melee" and canRear then
      state.rearBlockedUntil, state.behind = now+1, nil
      if g.distance <= radius+0.3 and math.abs(g.pz-g.z)<2 then return true end
      gx,gy,gz = self:PetGround(g.x+dx/length*radius,g.y+dy/length*radius,g.z,g)
    end
    if not gx then return false, "No clear ground route to the target" end
  end
  if state.lastRear ~= canRear or now-(state.lastPlan or -10) >= 0.3 then
    local d = self.destination
    local changed = state.lastRear ~= canRear or not d or (d.x-gx)^2+(d.y-gy)^2+(d.z-gz)^2 > 0.6^2
    if changed then
      local ok, reason = self:BeginMove(gx,gy,gz,"pet")
      if not ok then return false, reason end
      state.lastPlan, state.lastRear = now, canRear
    end
  end
  return false
end

function B:PetStartAttack(state, now)
  if state.style == "ranged" then return true end
  if now-(state.lastAttack or -10) < 1 then return true end
  state.lastAttack = now
  if state.style == "hunter" then
    local shotName = GetSpellInfo and GetSpellInfo(75) or "Auto Shot"
    local slot
    for tab = 1, GetNumSpellTabs() do
      local _,_,offset,count = GetSpellTabInfo(tab)
      for i = (offset or 0)+1, (offset or 0)+(count or 0) do if GetSpellName(i,BOOKTYPE_SPELL or "spell") == shotName then slot=i; break end end
      if slot then break end
    end
    if not slot then return false, "Auto Shot is not learned on account 2" end
    local ok, reason
    if CastSpellNoToggle then ok,reason=self:Invoke("CastSpellNoToggle",75)
    elseif not state.hunterStarted then ok,reason=self:Invoke("CastSpell",slot,BOOKTYPE_SPELL or "spell")
    else return true end
    if ok then state.hunterStarted=true end
    return ok,reason
  end
  local ok, reason = true
  if StartAttack then ok,reason=self:Invoke("StartAttack")
  elseif not state.meleeStarted and (not IsCurrentSpell or not IsCurrentSpell("Attack")) then ok,reason=self:Invoke("AttackTarget") end
  if ok then state.meleeStarted=true end
  return ok,reason
end

function B:PetTick(now)
  local state = self.petState
  if not state then return end
  if UnitIsDeadOrGhost("player") then self:StopMovement(); return end
  local main = self:GroupUnit(self.db.peer)
  if not main then self:StopMovement(); return end
  local mainCombat, ownCombat = UnitAffectingCombat(main), UnitAffectingCombat("player")
  local combat = mainCombat or ownCombat
  if state.guid and combat then state.seenCombat = true end
  if self:IsCastHeld(now) then return end
  if state.seenCombat and not combat then
    self:StopPetAttack(state)
    if self.destination then self:StopMovement(nil,true,true) end
    state.quietAt = state.quietAt or now
    if now-state.quietAt >= 0.7 then self:PetFollow(state); return end
    return
  else state.quietAt = nil end
  local mainTarget = self:GUID(main .. "target")
  if (state.mode == "assist" and mainCombat) or (state.guid and mainTarget ~= state.lastMainTarget) then
    if mainTarget ~= state.guid and self:PetEnemy(mainTarget) then
      local ok = self:StopMovement(nil, true, true)
      if not ok then self:CancelPet(); return end
      self:StopPetAttack(state)
      state.guid, state.started, state.behind, state.lastPlan = mainTarget, now, nil, nil
      state.rearBlockedUntil, state.lastRear = nil, nil
      state.seenCombat = combat and true or nil
    end
  end
  state.lastMainTarget = mainTarget
  if not state.guid then return end
  if not state.seenCombat and state.style == "hunter" and now-(state.started or now)>15 then
    self:PetFollow(state); self:Send("ERROR", {"Attack did not start; returned to Follow"},true); return
  end
  if not self:PetEnemy(state.guid) then self:PetFollow(state); return end
  if now-(state.nextCheck or -10) < 0.2 then return end
  state.nextCheck = now
  if self:GUID("target") ~= state.guid then
    local selected, detail = self:ChooseTarget(state.guid)
    if not selected then self:PetFollow(state); self:Send("ERROR", {detail}, true); return end
  end
  local geometry = self:PetGeometry(state.guid)
  if not geometry then self:PetFollow(state); return end
  local ready, reason = self:PetApproach(state, geometry, self:PetCanRear(state.guid, combat), now)
  if reason then self:PetFollow(state); self:Send("ERROR", {reason}, true); return end
  if not ready then return end
  if self.destination or self.following then
    local ok = self:StopMovement(nil,true,true)
    if not ok then self:CancelPet(); return end
  end
  local heading = self:HeadingToUnit(state.guid)
  if heading then
    local ok,result = pcall(zBoxNative,"SetHeading",heading)
    if not ok or result ~= 1 then self:StopMovement(); return end
  end
  local ok, errorText = self:PetStartAttack(state,now)
  if not ok then self:PetFollow(state); self:Send("ERROR", {errorText or "Attack failed"},true) end
end
