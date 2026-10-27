local B = zBox
local directions = { "forward", "backward", "left", "right", "strafeleft", "straferight" }
local opposite = { forward = "backward", backward = "forward", left = "right", right = "left",
  strafeleft = "straferight", straferight = "strafeleft" }
local function modifiers()
  return ((IsAltKeyDown and IsAltKeyDown()) and "A" or "") ..
    ((IsControlKeyDown and IsControlKeyDown()) and "C" or "") ..
    ((IsShiftKeyDown and IsShiftKeyDown()) and "S" or "")
end

function B:HoldDirection(axis, down, source)
  if not opposite[axis] then return end
  self.heldInputs = self.heldInputs or {}
  self.heldModifiers = self.heldModifiers or {}
  local key = (source or "key") .. ":" .. axis
  if down then
    if not self.connected or self.db.role ~= "control" then self:Notify("Connect the second character first"); return end
    for id, value in pairs(self.heldInputs) do
      if value == opposite[axis] then self.heldInputs[id], self.heldModifiers[id] = nil, nil end
    end
    self.heldInputs[key] = axis
    if (source or "key") == "key" then self.heldModifiers[key] = modifiers() end
  else
    -- Rebinding/capture can produce a release without a zBox press. Do not
    -- send a stray zero mask that would cancel account 2's follow or Pet order.
    if not self.heldInputs[key] then return end
    self.heldInputs[key] = nil
    self.heldModifiers[key] = nil
  end
  self:SendHeldDirections()
end

function B:SendHeldDirections(renew)
  local mask, bit = 0, 1
  for i = 1, table.getn(directions) do
    local active = false
    for _, axis in pairs(self.heldInputs or {}) do if axis == directions[i] then active = true end end
    if active then mask = mask + bit end
    bit = bit * 2
  end
  self.heldMask, self.lastHeldAt = mask, GetTime()
  if self.connected and self.db.role == "control" then self:Command("AXES", { mask,renew and "renew" or "change" }) end
end

function B:ReleaseDirections(source)
  for id in pairs(self.heldInputs or {}) do
    if not source or string.sub(id, 1, string.len(source) + 1) == source .. ":" then
      self.heldInputs[id] = nil
      if self.heldModifiers then self.heldModifiers[id] = nil end
    end
  end
  self:SendHeldDirections()
end

function B:ControlTick(now)
  local changed, current = false, modifiers()
  for id in pairs(self.heldInputs or {}) do
    if self.heldModifiers and self.heldModifiers[id] and self.heldModifiers[id] ~= current then
      self.heldInputs[id], self.heldModifiers[id], changed = nil, nil, true
    end
  end
  -- A modifier released before its movement key can change the binding that
  -- receives key-up. Release the old chord instead of renewing it indefinitely.
  if changed then self:SendHeldDirections() end
  if self.connected and self.heldMask and self.heldMask > 0 and now - (self.lastHeldAt or 0) >= 0.25 then
    self:SendHeldDirections(true)
  end
end

function B:UseProxy(id)
  local proxy = self.db and self.db.proxies and self.db.proxies[id]
  if not proxy then self:Notify("This remote button no longer exists. Drag it from zBox again."); return end
  if proxy.realm ~= self:Realm() or self:Name(proxy.peer) ~= self:Name(self.db.peer) then
    self:Notify("This button belongs to a different paired character. Drag a new button from zBox."); return
  end
  if proxy.command == "CONTROL" then
    local ok, reason = self:UseControl(proxy.slot)
    if not ok then self:Notify(reason) end
    return
  end
  if proxy.command ~= "ACTION" and proxy.command ~= "SPELL" then return end
  local ok, reason = self:Command(proxy.command, { proxy.slot, proxy.stamp, self:TargetDescriptor(IsAltKeyDown and IsAltKeyDown()) })
  if not ok then self:Notify(reason) end
end

function B:ProxyIcon(texture)
  if not self.macroIcons then
    self.macroIcons = {}
    if GetNumMacroIcons and GetMacroIconInfo then
      for i = 1, GetNumMacroIcons() do self.macroIcons[string.lower(GetMacroIconInfo(i))] = i end
    end
  end
  return self.macroIcons[string.lower(texture)] or 1
end

local controlMacros = {
  petfollow = { "Pet Follow", "Interface\\Icons\\Ability_Tracking" },
  petassist = { "Pet Assist", "Interface\\Icons\\Ability_Hunter_Assist" },
  petattack = { "Pet Attack", "Interface\\Icons\\Ability_GhoulFrenzy" },
  follow = { "Follow", "Interface\\Icons\\Ability_Tracking" },
  assist = { "Assist", "Interface\\Icons\\Ability_Hunter_Assist" },
  move = { "Move", "Interface\\Icons\\Ability_Rogue_Sprint" },
  stop = { "STOP", "Interface\\Icons\\Spell_Nature_TimeStop" },
}

function B:UseControl(kind)
  if not controlMacros[kind] then return false, "Unknown zBox control" end
  if not self.connected or self.db.role ~= "control" then return false, "Connect the second character first" end
  if string.sub(kind, 1, 3) == "pet" then
    if self:MovementMode() ~= "pet" then
      local ok, reason = self:SetMovementMode("pet")
      if not ok then return false, reason end
    end
    return self:PetOrder(string.sub(kind, 4))
  elseif kind == "follow" then return self:FollowCommand()
  elseif kind == "assist" then return self:AssistCommand()
  elseif kind == "stop" then return self:Command("STOP")
  elseif kind == "move" then
    if not self.UI then return false, "The movement picker is unavailable" end
    self.UI:ArmMove(); return true
  end
end

function B:PickupControl(kind)
  local entry = controlMacros[kind]
  if not entry then return false, "Unknown zBox control" end
  return self:PickupProxy("CONTROL", kind, "", entry[2], entry[1])
end

function B:PickupRemote(section, row)
  if section ~= "actions" and section ~= "spells" then return false, "Drag an action or spell" end
  if not row or row[2] == "" or (section == "spells" and row[6] == "1") then return false, "Choose an active skill" end
  return self:PickupProxy(section == "actions" and "ACTION" or "SPELL", row[1],
    section == "actions" and row[4] or row[5], row[2], row[3])
end

function B:PickupProxy(command, slot, stamp, texture, label)
  if not self.connected or self.db.role ~= "control" then return false, "Connect the second character first" end
  if not PickupMacro or not GetMacroInfo or not GetMacroIndexByName then return false, "The macro cursor API is unavailable" end
  if (CursorHasItem and CursorHasItem()) or (CursorHasSpell and CursorHasSpell()) or
     (CursorHasMoney and CursorHasMoney()) or (GetCursorInfo and GetCursorInfo()) then
    return false, "Clear your cursor before dragging a zBox button"
  end
  self.db.proxies = self.db.proxies or {}
  local id, proxy
  for key, value in pairs(self.db.proxies) do
    if value.peer == self.db.peer and value.realm == self:Realm() and value.command == command and value.slot == slot then
      id, proxy = key, value; break
    end
  end
  if not id then
    self.db.proxySerial = (self.db.proxySerial or 0) + 1
    id = tostring(self.db.proxySerial)
    proxy = { peer = self.db.peer, realm = self:Realm(), command = command, slot = slot }
  end
  local body = '/script zBox:UseProxy("' .. id .. '")'
  local name = "zB" .. id .. " " .. string.sub(label, 1, math.max(0, 12 - string.len(id)))
  -- Reuse only our exact macro body. Never overwrite a player's named macro.
  local index
  for i = 1, 36 do
    local _, _, existing = GetMacroInfo(i)
    if existing == body then index = i; break end
  end
  if not index then
    if GetMacroIndexByName(name) ~= 0 then return false, "A macro already uses " .. name .. ". Rename it and try again." end
    local ok, result
    if C_Macro and type(C_Macro.CreateMacro) == "function" then
      ok, result = pcall(C_Macro.CreateMacro, name, texture, body, true)
    elseif CreateMacro then
      -- Vanilla's legacy API takes the per-character flag as argument FIVE.
      ok, result = pcall(CreateMacro, name, self:ProxyIcon(texture), body, nil, true)
    end
    if not ok or type(result) ~= "number" or result < 1 then
      return false, "No character macro slot available. Free a slot in /macro, then drag again."
    end
    index = result
  end
  proxy.stamp, proxy.label, proxy.icon = stamp, label, texture
  self.db.proxies[id] = proxy
  self.nextWatchScan = nil
  local ok, reason = pcall(PickupMacro, index)
  if not ok then return false, tostring(reason) end
  return true, command == "CONTROL" and "Drop the zBox control on one of your action bars." or
    "Drop the remote skill on one of your action bars. Alt-click its macro to target account 2."
end
