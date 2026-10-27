local B = zBox
local axes = {
  forward = { "MoveForwardStart", "MoveForwardStop" }, backward = { "MoveBackwardStart", "MoveBackwardStop" },
  left = { "TurnLeftStart", "TurnLeftStop" }, right = { "TurnRightStart", "TurnRightStop" },
  strafeleft = { "StrafeLeftStart", "StrafeLeftStop" }, straferight = { "StrafeRightStart", "StrafeRightStop" }
}

function B:SetAxis(axis, enabled)
  self.axes = self.axes or {}
  if self.axes[axis] == enabled then return true end
  if not axes[axis] then return false, "Invalid movement axis" end
  local ok, reason = self:Invoke(axes[axis][enabled and 1 or 2])
  if ok then self.axes[axis] = enabled end
  return ok, reason
end

function B:StopMovement(preserveCast, force, preservePet)
  local nativeMove = self.destination and self.destination.native
  if not preserveCast and not preservePet and self.CancelPet then self:CancelPet() end
  if not preserveCast then
    self.pendingCast, self.resumeFollow, self.castingUntil, self.followQuietAt = nil, nil, nil, nil
    self.castActive, self.castEventTimeout, self.castFacingGUID, self.stopForCast = nil, nil, nil, nil
    self.mirrorInput = nil
    self.mirrorStack=nil
  end
  self.destination, self.manualMove, self.manualUntil = nil, nil, nil
  self.axes = self.axes or {}
  -- Also stop native follow/autorun, including after a panel reload or lost key-up.
  for axis, functions in pairs(axes) do
    if force or self.axes[axis] then self:Invoke(functions[2]) end
    self.axes[axis] = false
  end
  if self.following or force or nativeMove then
    -- 1.12 rejects FollowUnit("player"). Clear the actual follow generator.
    if self:GetBridgeInfo().npc then
      local ok, result, reason = pcall(zBoxNative, "StopFollow")
      if not ok or result ~= 1 then return false, ok and reason or tostring(result) end
    else
      -- The older bridge can still use the ordinary movement-key path, whose
      -- press transition cancels follow before its immediate release.
      local ok, reason = self:Invoke("MoveForwardStart")
      self:Invoke("MoveForwardStop")
      if not ok then return false, reason end
    end
    self.following = nil
  end
  return true
end

function B:Position(unit)
  if type(zAPI) ~= "function" then return nil end
  local ok, x, y, z = pcall(zAPI, "unitPosition", unit or "player")
  if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then return x, y, z end
end

function B:BeginMove(x, y, z, owner)
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  if not x or not y or not z or x ~= x or y ~= y or z ~= z or
     math.abs(x) > 100000 or math.abs(y) > 100000 or math.abs(z) > 100000 then
    return false, "Invalid destination"
  end
  local px, py, pz = self:Position()
  if not px or type(GetPlayerFacing) ~= "function" then return false, "Movement requires zAPI and GetPlayerFacing (ClassicAPI)" end
  local distance = math.sqrt((x - px)^2 + (y - py)^2)
  if distance > 120 or math.abs(z - pz) > 35 then return false, "Choose a point within 120 yards and 35 yards vertically" end
  local previous = owner == "pet" and self.destination
  if previous and previous.owner == "pet" and previous.zone == (GetRealZoneText and GetRealZoneText() or "") then
    -- Refresh a moving enemy's goal without braking or renewing the no-progress
    -- watchdog. A stalled native move keeps its precise-steering fallback.
    if previous.native then
      local ok, result = pcall(zBoxNative, "MoveTo", x, y, z)
      if not ok or result ~= 1 then return false, "Could not update the chase destination" end
    end
    previous.x, previous.y, previous.z, previous.distance = x, y, z, distance
    return true, "Updated enemy position"
  end
  local stopped, reason = self:StopMovement(nil, true, owner == "pet")
  if not stopped then return false, reason end
  self.destination = { x = x, y = y, z = z, started = GetTime(), progressAt = GetTime(), distance = distance,
    zone = GetRealZoneText and GetRealZoneText() or "", owner = owner, progressX = px, progressY = py, progressZ = pz }
  self.lastMovementMethod = "Lua steering"
  if self:GetBridgeInfo().nativeMove then
    local ok, result = pcall(zBoxNative, "MoveTo", x, y, z)
    if ok and result == 1 then self.destination.native = true; self.lastMovementMethod = "Native click-to-move" end
  end
  return true, "Moving toward the chosen point"
end

local function angleTo(y, x)
  if math.atan2 then return math.atan2(y, x) end
  if x > 0 then return math.atan(y / x) end
  if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
  if y > 0 then return math.pi / 2 end
  if y < 0 then return -math.pi / 2 end
  return 0
end

function B:HeadingToUnit(unit)
  local x, y = self:Position("player")
  local tx, ty = self:Position(unit)
  if not x or not tx or x ~= x or y ~= y or tx ~= tx or ty ~= ty then return nil end
  if (tx-x)^2 + (ty-y)^2 < 0.0001 then return nil end
  local heading = angleTo(ty-y, tx-x)
  if heading < 0 then heading = heading + math.pi*2 end
  return heading
end

function B:MovementTick(now)
  if self.manualUntil and now > self.manualUntil then self:StopMovement() end
  local d = self.destination
  if not d then return end
  if self:IsCastHeld(now) then self:StopMovement(true, true, d.owner == "pet"); return end
  if UnitIsDeadOrGhost("player") or (d.owner ~= "pet" and now - d.started > 35) then self:StopMovement(); return end
  if d.zone ~= (GetRealZoneText and GetRealZoneText() or "") then self:StopMovement(); return end
  local px, py, pz = self:Position()
  local facing = GetPlayerFacing and GetPlayerFacing()
  if not px or not facing then self:StopMovement(); return end
  local dx, dy = d.x - px, d.y - py
  local distance = math.sqrt(dx * dx + dy * dy)
  local speed = GetUnitSpeed and GetUnitSpeed("player") or 7
  local arrival = math.max(0.35, type(speed) == "number" and speed*0.03 or 0.35)
  if distance < arrival and math.abs(d.z-pz) < 2 then self:StopMovement(nil, true, d.owner == "pet"); return end
  if distance < d.distance - 0.3 then d.distance, d.progressAt = distance, now end
  if d.owner == "pet" and (px-d.progressX)^2+(py-d.progressY)^2+(pz-d.progressZ)^2 > 0.3^2 then
    d.progressX, d.progressY, d.progressZ, d.progressAt = px, py, pz, now
  end
  if now - d.progressAt > 3.5 then
    self:StopMovement()
    self:Send("ERROR", { "Movement stopped: no progress. Choose a clear route around obstacles." }, true)
    return
  end
  if d.native and now-d.progressAt > 1.2 then
    local ok,result = pcall(zBoxNative,"StopFollow")
    if not ok or result ~= 1 then self:StopMovement(); return end
    d.native=nil; self.lastMovementMethod="Native CTM stalled / precise steering"
  end
  if d.native then
    local ok, result, state = pcall(zBoxNative, "MoveState")
    if not ok or result ~= 1 then self:StopMovement(); return end
    if state == 4 then return end
    -- Native CTM may settle short of its goal. Finish the last fraction using
    -- precise facing and owned forward input, without changing client globals.
    if state ~= 12 then self:StopMovement(); return end
    d.native = nil
    self.lastMovementMethod = "Native CTM / final correction"
  end
  -- Native XYZ uses +X at facing zero, +Y at pi/2. Turning left increases facing.
  local delta = angleTo(dy, dx) - facing
  while delta > math.pi do delta = delta - math.pi * 2 end
  while delta < -math.pi do delta = delta + math.pi * 2 end
  if self:GetBridgeInfo().mirror then
    local heading = math.mod(angleTo(dy,dx)+math.pi*2, math.pi*2)
    local ok, result = pcall(zBoxNative, "SetHeading", heading)
    if not ok or result ~= 1 then self:StopMovement(); return end
    self:SetAxis("left", false); self:SetAxis("right", false)
    delta = 0
  else
    self:SetAxis("left", delta > 0.08)
    self:SetAxis("right", delta < -0.08)
  end
  local ok = self:SetAxis("forward", math.abs(delta) < 0.55)
  if not ok then self:StopMovement() end
end

local function finite(value)
  return type(value) == "number" and value == value and math.abs(value) < 1000000
end

function B:PickTerrain()
  if type(zAPI) ~= "function" or not GetCursorPosition then return nil, "Terrain picking requires zAPI 1.6+" end
  local scale = UIParent:GetEffectiveScale()
  local width, height = UIParent:GetWidth(), UIParent:GetHeight()
  local cx, cy = GetCursorPosition()
  if not finite(scale) or scale <= 0 or not finite(width) or width <= 0 or
     not finite(height) or height <= 0 or not finite(cx) or not finite(cy) then
    return nil, "Cursor position is unavailable"
  end
  cx, cy = cx / (width * scale), cy / (height * scale)
  if cx < 0 or cx > 1 or cy < 0 or cy > 1 then return nil, "Click inside the game window" end
  -- zAPI refreshes the same native cursor raycast used by ground placement.
  -- Accept only a result aligned with this cursor and its native projection.
  local native, tick, sx, sy, nx, ny, wx, wy, wz, depth = pcall(zAPI, "cursorProjection")
  local tolerance = math.max(0.002, 4/(width*scale), 4/(height*scale))
  if native and type(tick)=="number" and tick==tick and tick>=0 and tick<=4294967295 and finite(sx) and finite(sy) and finite(nx) and finite(ny) and
     finite(wx) and finite(wy) and finite(wz) and finite(depth) and depth > 0.05 and
     math.abs(cx-nx) <= tolerance and math.abs(cy-ny) <= tolerance and
     math.abs(sx-nx) <= tolerance and math.abs(sy-ny) <= tolerance then
    self.lastPickMethod = "Native ground cursor"
    return wx, wy, wz
  end
  local ok, x, y, z, fx, fy, fz, rx, ry, rz, ux, uy, uz = pcall(zAPI, "camera")
  if not ok or not finite(x) or not finite(y) or not finite(z) or
     not finite(fx) or not finite(fy) or not finite(fz) or not finite(rx) or
     not finite(ry) or not finite(rz) or not finite(ux) or not finite(uy) or not finite(uz) then
    return nil, "Camera picking is unavailable; check the zAPI DLL"
  end
  -- Calibrate against the actual native projector instead of assuming an FOV,
  -- aspect ratio, UI scale or full-screen viewport. All samples share depth.
  local bx, by, bz = x + fx * 10, y + fy * 10, z + fz * 10
  local aok, ax, ay = pcall(zAPI, "worldToScreen", bx, by, bz)
  local rok, sx, sy = pcall(zAPI, "worldToScreen", bx + rx, by + ry, bz + rz)
  local uok, tx, ty = pcall(zAPI, "worldToScreen", bx + ux, by + uy, bz + uz)
  if not aok or not rok or not uok or not finite(ax) or not finite(ay) or
     not finite(sx) or not finite(sy) or not finite(tx) or not finite(ty) then
    return nil, "World projection is unavailable"
  end
  local hx, hy, vx, vy = sx - ax, sy - ay, tx - ax, ty - ay
  local determinant = hx * vy - hy * vx
  if math.abs(determinant) < 0.00000001 then return nil, "World projection is degenerate" end
  local a = ((cx - ax) * vy - (cy - ay) * vx) / determinant
  local b = (hx * (cy - ay) - hy * (cx - ax)) / determinant
  local dx, dy, dz = fx * 10 + rx * a + ux * b, fy * 10 + ry * a + uy * b, fz * 10 + rz * a + uz * b
  local length = math.sqrt(dx * dx + dy * dy + dz * dz)
  if not finite(length) or length < 0.001 then return nil, "Invalid camera ray" end
  -- zAPI limits a ray to 250 yards. Leave room for native float rounding.
  local distance = 249 / length
  local hit, picked, wx, wy, wz = pcall(zAPI, "raycast", x, y, z,
    x + dx * distance, y + dy * distance, z + dz * distance)
  if not hit then return nil, "Terrain trace failed" end
  if picked ~= 1 or not finite(wx) or not finite(wy) or not finite(wz) then
    return nil, "No ground hit within 249 yards of the camera; choose closer terrain"
  end
  self.lastPickMethod = "Calibrated terrain ray"
  return wx, wy, wz
end

function B:CaptureMove()
  if not self.connected then return false, "Connect the second character first" end
  local x, y, z = self:PickTerrain()
  if not x then self.lastPick = tostring(y); return false, y end
  self.lastPick = (self.lastPickMethod or "Terrain") .. string.format(" %.1f, %.1f, %.1f", x, y, z)
  local map = GetRealZoneText and GetRealZoneText() or ""
  return self:Command("MOVETO", { string.format("%.3f", x), string.format("%.3f", y), string.format("%.3f", z), map })
end

function B:Manual(axis, enabled)
  if not axes[axis] then return false, "Invalid movement axis" end
  if self.mirrorInput then self:StopMovement() end
  if enabled and (self.destination or self.following or self.pendingCast or self.resumeFollow or self.petState) then self:StopMovement() end
  local ok, reason = self:SetAxis(axis, enabled)
  if not ok then return false, reason end
  self.manualUntil = GetTime() + 0.8
  return true
end

function B:ManualAxes(mask, mirrored)
  mask = tonumber(mask)
  if not mask or mask < 0 or mask > 63 or mask ~= math.floor(mask) then return false, "Invalid movement keys" end
  local originalMask = mask
  local directions = { "forward", "backward", "left", "right", "strafeleft", "straferight" }
  local enabled = {}
  for i = 1, 6 do enabled[i], mask = math.mod(mask, 2) == 1, math.floor(mask / 2) end
  for i = 1, 5, 2 do
    if enabled[i] and enabled[i + 1] then return false, "Opposite movement keys cannot be held together" end
  end
  if not mirrored then self.mirrorInput,self.mirrorStack=nil,nil end
  if self.destination or self.following or (originalMask ~= 0 and (self.pendingCast or self.resumeFollow or self.petState)) then self:StopMovement() end
  for i = 1, 6 do
    local ok, reason = self:SetAxis(directions[i], enabled[i])
    if not ok then self:StopMovement(); return false, reason end
  end
  if originalMask == 0 and (self.pendingCast or self.resumeFollow) then return true end
  self.manualUntil = GetTime() + 0.8
  return true
end
