-- WoW 1.12 / Lua 5.0. No received text is evaluated as Lua or a macro.
zBox = { version = "0.3.0", prefix = "zBox2", cache = {}, clock = 0 }
local B = zBox
local protectedInputs = { UseAction = true, CastSpell = true, Jump = true,
  MoveForwardStart = true, MoveForwardStop = true, MoveBackwardStart = true, MoveBackwardStop = true,
  TurnLeftStart = true, TurnLeftStop = true, TurnRightStart = true, TurnRightStop = true,
  StrafeLeftStart = true, StrafeLeftStop = true, StrafeRightStart = true, StrafeRightStop = true }

function B:Print(text)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcczBox:|r " .. tostring(text)) end
end

function B:Notify(text)
  self.notice = tostring(text)
  self:Print(text)
  if self.UI then self.UI:Refresh() end
end

function B:Name(name)
  return string.lower(tostring(name or ""))
end

function B:Realm()
  return (GetRealmName and GetRealmName()) or ""
end

function B:GroupUnit(name)
  if self:Name(UnitName("player")) == self:Name(name) then return "player" end
  local count = GetNumRaidMembers and GetNumRaidMembers() or 0
  if count > 0 then
    for i = 1, count do
      if self:Name(UnitName("raid" .. i)) == self:Name(name) then return "raid" .. i end
    end
  else
    count = GetNumPartyMembers and GetNumPartyMembers() or 0
    for i = 1, count do
      if self:Name(UnitName("party" .. i)) == self:Name(name) then return "party" .. i end
    end
  end
end

function B:Channel()
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
end

function B:GUID(unit)
  if not unit or not UnitExists(unit) then return "" end
  local exists, guid = UnitExists(unit)
  if type(guid) == "string" then return guid end
  if GetUnitGUID then guid = GetUnitGUID(unit) end
  if type(guid) ~= "string" and UnitGUID then guid = UnitGUID(unit) end
  if type(guid) == "string" then return guid end
  return ""
end

function B:GetBridgeInfo()
  if self.bridgeInfo then return self.bridgeInfo end
  local info = { ready = false, label = "Bridge not loaded" }
  if type(zBoxNative) == "function" then
    local ok, result, version, contract = pcall(zBoxNative, "capabilities")
    if ok and result == 1 and (contract == 2 or contract == 3) then
      info.ready, info.label, info.version = true, "Native inputs " .. string.gsub(tostring(version), "zBoxBridge ", ""), version
      info.npc = contract >= 3
      info.mirror = contract >= 3
    else
      info.label = "Bridge update required"
    end
  end
  self.bridgeInfo = info
  return info
end

function B:Diagnostics()
  local info = self:GetBridgeInfo()
  local report = "Addon " .. self.version .. "; " .. info.label .. "; " ..
    (self.lastInvoke or "No input requested since reload") .. "; cast event=" .. (self.lastCastSignal or "none") ..
    "; pick=" .. (self.lastPick or "none")
  if info.ready then
    local ok, result, detail = pcall(zBoxNative, "status")
    if ok and result == 1 then report = report .. "; " .. tostring(detail) end
  end
  return report
end

function B:Invoke(name, a, b, c)
  local fn = getglobal(name)
  if type(fn) ~= "function" then return false, name .. " is unavailable" end
  if protectedInputs[name] and not self:GetBridgeInfo().ready then
    local reason = "Protected input needs zBoxBridge 0.1.3. Fully close and restart both clients after installing the update."
    self.lastInvoke = name .. ": " .. reason
    return false, reason
  end
  -- The optional, separate bridge confines execution context changes to its
  -- fixed API allowlist. It never replaces or updates the shared zAPI DLL.
  if type(zBoxNative) == "function" then
    local ok, result, detail = pcall(zBoxNative, name, a, b, c)
    self.lastInvoke = name .. ": " .. tostring(ok and detail or result)
    if not ok then return false, tostring(result) end
    return result == 1, detail
  end
  local ok, reason = pcall(fn, a, b, c)
  self.lastInvoke = name .. ": " .. (ok and "Requested through Lua" or tostring(reason))
  if not ok then return false, tostring(reason) end
  return true
end

function B:NewSession()
  return string.format("%x%x", math.floor(GetTime() * 1000), math.random(65535))
end

function B:Configure(role, peer, key)
  if role ~= "control" and role ~= "agent" then return false, "Unknown role" end
  if not peer or not string.find(peer, "^[%a][%a%-]*$") or string.len(peer) > 48 then
    return false, "Enter the other character's name"
  end
  if self:Name(peer) == self:Name(UnitName("player")) then return false, "Choose the other character" end
  if not key or not string.find(key, "^[%w_%-]+$") or string.len(key) < 8 or string.len(key) > 32 then
    return false, "The shared pairing code must be 8-32 letters, numbers, _ or -"
  end
  self:Disconnect("Pairing changed")
  self.db.role, self.db.peer, self.db.key, self.db.realm = role, peer, key, self:Realm()
  self.db.enabled = true
  self.session = role == "control" and self:NewSession() or nil
  self.lastHello = -10
  self:Notify(role == "control" and ("Connecting to " .. peer .. "; both characters must be grouped") or
    ("Allowing commands from " .. peer .. " on " .. self.db.realm))
  return true
end

function B:Disconnect(reason)
  if self.StopMovement then self:StopMovement() end
  self.connected, self.session, self.lastReceive = false, nil, nil
  self.cache, self.pending, self.incoming = {}, {}, {}
  self.queueHigh, self.queueLow, self.lowIndex, self.highIndex = {}, {}, 1, 1
  self.sendID, self.receiveCommandID, self.activeView = 0, 0, nil
  self.lastSnapshotID, self.bagSelection = nil, nil
  self.lastBarSnapshotID, self.heldInputs, self.heldMask = nil, {}, 0
  self.heldModifiers = {}
  self.castRequestAt, self.lastCastSignal, self.lastCastFeedbackAt = nil, nil, nil
  self.npcKind, self.npcGUID, self.npcName = nil, nil, nil
  self.mirrorPaused, self.lastMirrorAt = true, nil
  if self.UI then
    self.UI.held, self.UI.hovered = nil, nil
    self.UI:CancelMove()
    self.UI.dirty = true
    if self.UI.frame and self.UI.frame:IsShown() then self.UI:Refresh() end
  end
  if reason then self.notice = reason end
end

function B:IsEnabled()
  return self.db and self.db.enabled and self.db.realm == self:Realm() and self:Channel() and
    self:GroupUnit(self.db.peer) ~= nil
end

function B:TargetDescriptor(selfCast)
  if selfCast or self.targetMode == "SELF" then return "SELF" end
  if self.targetMode == "MAIN" then return "MAIN" end
  if self.targetMode == "KEEP" then return "KEEP" end
  return self:GUID("target")
end

function B:Command(command, fields)
  if not self.connected or self.db.role ~= "control" then return false, "Not connected" end
  fields = fields or {}
  if command == "FOLLOW" or command == "MOVETO" or command == "AXIS" or command == "AXES" or command == "TALK" or command == "NPC" then
    self.mirrorPaused = true
  end
  if command == "STOP" or command == "FOLLOW" or command == "MOVETO" or command == "ACTION" or command == "SPELL" or command == "TALK" or command == "NPC" then
    self.heldInputs, self.heldMask = {}, 0
    self.heldModifiers = {}
    if self.UI then self.UI.held = nil end
  end
  table.insert(fields, 1, command)
  if command == "STOP" then
    self.mirrorPaused = true
    self:SendNow("CMD", fields)
    self.notice = "Emergency stop sent"
    return true
  end
  local id = self:Send("CMD", fields, true)
  if not id then return false, "Command queue is full" end
  self.pending[id] = { at = GetTime(), command = command }
  return true
end

function B:Request(section, page)
  if self.db.role ~= "control" then return end
  page = page or 1
  self.view, self.page = section, page
  if section == "actions" then self.actionPage = page end
  self.selection = nil
  if self.connected then self:Send("VIEW", { section, page }, true) end
end

function B:Initialize()
  zBoxDB = zBoxDB or {}
  self.db = zBoxDB
  self.bridgeInfo = nil
  self.targetMode, self.view, self.page, self.actionPage = "TARGET", "actions", 1, 1
  self:Disconnect()
  if self.db.enabled and self.db.realm == self:Realm() and self.db.role == "control" then
    self.session = self:NewSession()
  end
  self.lastHello, self.lastHeartbeat, self.lastStatus = -10, -10, -10
  self.ready = true
  self:HookMirrorJump()
  if self.UI then self.UI:Create() end
  self:Print("Loaded " .. self.version .. ". /zbox opens the panel; /zbox help explains pairing.")
end

function B:Slash(message)
  local _, _, command, rest = string.find(message or "", "^(%S*)%s*(.-)%s*$")
  command = string.lower(command or "")
  if command == "control" or command == "allow" then
    local _, _, peer, key = string.find(rest, "^(%S+)%s+(%S+)$")
    local ok, reason = self:Configure(command == "control" and "control" or "agent", peer, key)
    if not ok then self:Notify(reason) end
  elseif command == "off" then
    if self.connected and self.db.role == "control" then self:SendNow("CMD", { "STOP" }) end
    self.db.enabled = false
    self:Disconnect("Disabled")
    self:Notify("Disabled on this character")
  elseif command == "stop" then
    if self.db.role == "control" then self:Command("STOP") else self:StopMovement() end
  elseif command == "move" then
    if self.UI then self.UI:ArmMove() end
  elseif command == "keys" then
    if self.UI then self.UI:ShowKeys() end
  elseif command == "mirror" then
    if rest == "off" then self:SetMirrorMode(false)
    elseif rest == "pause" then if self.connected then self:Command("STOP") end
    else local ok, reason = self:SetMirrorMode(true); if not ok then self:Notify(reason) end end
  elseif command == "scale" then
    if self.UI then
      local ok, reason = self.UI:SetScale(rest == "reset" and 0.85 or rest)
      if not ok then self:Notify(reason) end
    end
  elseif command == "diag" then
    self:Print(self:Diagnostics())
    if self.connected and self.db.role == "control" then self:Send("DIAG", {}, true) end
  elseif command == "help" then
    self:Print("Group both characters. On account 2: /zbox allow MainName sharedcode")
    self:Print("On account 1: /zbox control AltName sharedcode (same code, 8-32 characters)")
    self:Print("/zbox = panel; /zbox stop = emergency stop; /zbox off = revoke pairing")
    self:Print("Click-to-move needs zAPI and GetPlayerFacing; zBoxBridge enables protected inputs.")
    self:Print("/zbox diag reports input bridge versions and the last operation on both clients.")
    self:Print("/zbox scale 0.75 changes panel size; /zbox scale reset restores 85%.")
    self:Print("/zbox mirror enables movement/heading/jump mirroring; /zbox mirror pause stops it; /zbox mirror off selects Follow mode.")
  else
    if self.UI then self.UI:Toggle() end
  end
end

local frame = CreateFrame("Frame", "zBoxEvents")
B.frame = frame
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("SPELLCAST_START")
frame:RegisterEvent("SPELLCAST_STOP")
frame:RegisterEvent("SPELLCAST_FAILED")
frame:RegisterEvent("SPELLCAST_INTERRUPTED")
frame:RegisterEvent("SPELLCAST_CHANNEL_START")
frame:RegisterEvent("SPELLCAST_CHANNEL_STOP")
frame:RegisterEvent("SPELLCAST_DELAYED")
frame:RegisterEvent("SPELLCAST_CHANNEL_UPDATE")
local npcEvents = { "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED",
  "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED" }
local npcEventSet = {}
for _, name in ipairs(npcEvents) do frame:RegisterEvent(name); npcEventSet[name] = true end
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:SetScript("OnEvent", function()
  if event == "PLAYER_LOGIN" then B:Initialize(); return end
  if not B.ready then return end
  if event == "CHAT_MSG_ADDON" then
    B:Receive(arg1, arg2, arg3, arg4)
  elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
    B.worldSuspended = true
    B:Disconnect("Loading or logged out")
  elseif event == "PLAYER_ENTERING_WORLD" then
    B.worldSuspended = false
    B.lastHello = -10
  elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
    if not B:IsEnabled() then B:Disconnect("Peer is not in the group") end
  elseif npcEventSet[event] then
    if B.db.role == "agent" then B:NPCEvent(event) end
  elseif event == "QUEST_LOG_UPDATE" then
    if not B.questReadUntil or GetTime() > B.questReadUntil then
      B.questCache = nil
      B.viewDirty = true
      if B.UI then B.UI.dirty = true end
    end
  elseif event == "UI_ERROR_MESSAGE" then
    if B.connected and B.db.role == "agent" and B.lastCommandAt and GetTime() - B.lastCommandAt < 2 then
      B:Send("ERROR", { tostring(arg1 or "Game action failed") }, true)
    end
  elseif event == "SPELLCAST_START" or event == "SPELLCAST_STOP" or event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" or event == "SPELLCAST_CHANNEL_START" or event == "SPELLCAST_CHANNEL_STOP" or event == "SPELLCAST_DELAYED" or event == "SPELLCAST_CHANNEL_UPDATE" then
    if B.db.role == "agent" then B:CastEvent(event, arg2 or arg1) end
    if B.connected and B.db.role == "agent" and B.castRequestAt and GetTime() - B.castRequestAt < 8 then
      B.lastCastSignal = event .. (arg1 and (": " .. tostring(arg1)) or "")
      B:Send("STATE", { "cast", event, tostring(arg1 or "") }, true)
    end
  else
    B.viewDirty = true
    if event == "ACTIONBAR_SLOT_CHANGED" or event == "SPELLS_CHANGED" then B.barDirty = true end
  end
end)
frame:SetScript("OnUpdate", function()
  if not B.ready then return end
  B.clock = B.clock + (arg1 or 0)
  if B.clock < 0.05 then return end
  local elapsed = B.clock
  B.clock = 0
  B:Tick(GetTime(), elapsed)
end)
SLASH_ZBOX1 = "/zbox"
SlashCmdList["ZBOX"] = function(message) B:Slash(message) end
BINDING_HEADER_ZBOX = "zBox - second character"
BINDING_NAME_ZBOX_TOGGLE = "Toggle control panel"
BINDING_NAME_ZBOX_STOP = "Stop second character"
BINDING_NAME_ZBOX_MOVE = "Choose a move destination"
BINDING_NAME_ZBOX_FORWARD = "Account 2: hold to move forward"
BINDING_NAME_ZBOX_BACKWARD = "Account 2: hold to move backward"
BINDING_NAME_ZBOX_LEFT = "Account 2: hold to turn left"
BINDING_NAME_ZBOX_RIGHT = "Account 2: hold to turn right"
BINDING_NAME_ZBOX_STRAFELEFT = "Account 2: hold to strafe left"
BINDING_NAME_ZBOX_STRAFERIGHT = "Account 2: hold to strafe right"
BINDING_NAME_ZBOX_FOLLOW = "Account 2: follow main"
BINDING_NAME_ZBOX_ASSIST = "Account 2: assist main"
BINDING_NAME_ZBOX_JUMP = "Account 2: jump"
