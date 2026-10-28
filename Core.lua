-- WoW 1.12 / Lua 5.0. No received text is evaluated as Lua or a macro.
zBox = { version = "0.10.1", prefix = "zBox2", cache = {}, clock = 0 }
local B = zBox
local function validGUID(value) return type(value)=="string" and string.find(value,"^0x%x+$") end
local protectedInputs = { UseAction = true, CastSpell = true, Jump = true,
  MoveForwardStart = true, MoveForwardStop = true, MoveBackwardStart = true, MoveBackwardStop = true,
  TurnLeftStart = true, TurnLeftStop = true, TurnRightStart = true, TurnRightStop = true,
  StrafeLeftStart = true, StrafeLeftStop = true, StrafeRightStart = true, StrafeRightStop = true }
protectedInputs.StartAttack, protectedInputs.StopAttack, protectedInputs.CastSpellNoToggle, protectedInputs.Stuck = true, true, true, true

function B:Print(text)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcczBox:|r " .. tostring(text)) end
end

function B:Notify(text)
  self.notice = tostring(text)
  self:Print(text)
  if self.UI then self.UI:Refresh() end
end

-- Routine remote failures belong in the dock. Chat is opt-in for debugging.
function B:RemoteFeedback(text)
  text = tostring(text or "Game action failed")
  local now = GetTime()
  self.lastRemoteError = text
  if not self.lastFeedbackAt or now-self.lastFeedbackAt>=1 then
    self.notice, self.lastFeedbackAt = text,now
  end
  if self.db.verboseFeedback and (not self.feedbackChatAt or now-self.feedbackChatAt>=5) then
    self.feedbackChatAt=now;self.lastFeedbackChatAt=now;self:Print(text)
  end
end

function B:RelayGameError(text)
  local now = GetTime()
  self.lastGameError, self.lastGameErrorCall = tostring(text or "Game action failed"),self.activeInvoke
  if self.lastErrorRelayAt and (now-self.lastErrorRelayAt<0.5 or
      (self.lastErrorRelayText==self.lastGameError and now-self.lastErrorRelayAt<3)) then return end
  self.lastErrorRelayAt,self.lastErrorRelayText = now,self.lastGameError
  self:Send("ERROR",{self.lastGameError},true)
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
  if self.localReady then return "LOCAL" end
  if self:GetBridgeInfo().directWhisper then return "WHISPER" end
  if self.db and not self:GroupUnit(self.db.peer) then return nil end
  if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
end

function B:PeerUnit()
  local grouped = self:GroupUnit(self.db.peer)
  if grouped then return grouped end
  if not self.peerGUID then return end
  local ok, exists = pcall(UnitExists,self.peerGUID)
  if not ok or not exists then return end
  local named, name = pcall(UnitName,self.peerGUID)
  if named and self:Name(name)==self:Name(self.db.peer) then return self.peerGUID end
end

function B:SetPeerGUID(guid)
  self.peerGUID = type(guid)=="string" and string.find(guid,"^0x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") and guid or nil
end

function B:GUID(unit)
  if type(unit)~="string" or unit=="" then return "" end
  -- Raw GUID + "target" is not a portable unit token. For an ungrouped
  -- driver, use its authenticated target snapshot instead of querying it.
  if self.peerGUID and unit==self.peerGUID.."target" then return self.mainTargetGUID or "" end
  local probe=self.dependencyProbe;self.dependencyProbe=true
  local ok,exists,guid=pcall(UnitExists,unit)
  local present=ok and exists
  if present and not validGUID(guid) and GetUnitGUID then local accepted,value=pcall(GetUnitGUID,unit);if accepted then guid=value end end
  if present and not validGUID(guid) and UnitGUID then local accepted,value=pcall(UnitGUID,unit);if accepted then guid=value end end
  self.dependencyProbe=probe
  return present and validGUID(guid) and guid or ""
end

function B:GetBridgeInfo()
  if self.bridgeInfo then return self.bridgeInfo end
  local info = { ready = false, label = "Bridge not loaded" }
  if type(zBoxNative) == "function" then
    local ok, result, version, contract = pcall(zBoxNative, "capabilities")
    if ok and result == 1 and (contract == 2 or contract == 3 or contract == 4 or contract == 5 or contract == 6 or contract == 7 or contract == 8 or contract == 9 or contract == 10) then
      info.ready, info.label, info.version = true, "Native inputs " .. string.gsub(tostring(version), "zBoxBridge ", ""), version
      info.npc = contract >= 3
      info.mirror = contract >= 3
      info.jumpEvents = contract >= 4
      info.nativeMove = contract >= 5
      info.directWhisper = contract >= 6
      info.localIPC = contract >= 7
      info.activity = contract >= 8
      info.multiLocal = contract >= 9
      info.trade = contract >= 9
      -- Stuck does not depend on the passive jump observer's availability.
      info.unstuck = contract >= 10 or version == "zBoxBridge 0.1.11"
    else
      info.label = "Bridge update required"
    end
  end
  self.bridgeInfo = info
  return info
end

function B:DependencyReport()
  local apiVersion = "missing"
  if type(zAPI)=="function" then
    local ok, version = pcall(zAPI,"version")
    apiVersion = ok and version and tostring(version) or "loaded/version unknown"
  end
  local npVersion = "not reported"
  if type(GetNampowerVersion)=="function" then
    local ok, major, minor, patch = pcall(GetNampowerVersion)
    if ok and major then npVersion=tostring(major).."."..tostring(minor or 0).."."..tostring(patch or 0) end
  end
  local ok, guid = pcall(self.GUID,self,"player")
  local lookup = "no player GUID"
  if ok and guid ~= "" then
    local previous = self.dependencyProbe
    self.dependencyProbe = true
    local accepted, exists = pcall(UnitExists,guid)
    self.dependencyProbe = previous
    lookup = accepted and exists and "ok" or "FAILED"
  end
  return "UnitXP="..(type(UnitXP)=="function" and "loaded" or "missing")..
    ", zAPI="..apiVersion..", SuperWoW="..tostring(SUPERWOW_VERSION or "not reported")..
    ", ClassicAPI="..tostring(CLASSIC_API_VERSION or "not reported")..", Nampower="..npVersion..
    ", GUID lookup="..lookup..", facing="..(type(GetPlayerFacing)=="function" and "ready" or "missing")..
    ", spell info="..(type(GetSpellInfo)=="function" and "ready" or "missing")
end

function B:Diagnostics()
  local info = self:GetBridgeInfo()
  local report = "Addon " .. self.version .. "; " .. info.label .. "; " ..
    (self.lastInvoke or "No input requested since reload") .. "; cast event=" .. (self.lastCastSignal or "none") ..
    "; pick=" .. (self.lastPick or "none") .. "; jump sequence=" .. tostring(self.lastMirrorJump or "none")
  report = report .. "; movement=" .. (self.lastMovementMethod or "none") .. "; pet=" .. (self.petState and self.petState.mode or "off")
  if self.lastGameError then report = report .. "; last game error=" .. self.lastGameError .. " @ " .. (self.lastGameErrorCall or "between zBox calls") end
  if self.lastRemoteError then report=report.."; last remote error="..self.lastRemoteError end
  if self.lastUnstuckResult then report=report.."; unstuck="..self.lastUnstuckResult end
  if self.lastMacroTarget then report=report.."; mouseover macro target="..self.lastMacroTarget end
  if info.ready then
    local ok, result, detail = pcall(zBoxNative, "status")
    if ok and result == 1 then report = report .. "; " .. tostring(detail) end
  end
  if self.NPCGuardStatus then report = report .. "; NPC automation=" .. self:NPCGuardStatus() end
  report = report .. "; dependencies: " .. self:DependencyReport()
  report = report .. "; transport=" .. (self:Channel() or "No transport: ungrouped pairing needs bridge 0.1.7")
  if self.localDetail then report = report .. "; " .. self.localDetail end
  report=report.."; zDNumbers="..(self.damageBridge and "pet relay ready" or "not loaded / update required")
  if self.damageBridge then report=report.."; damage sent/received="..tostring(self.damageRelayed or 0).."/"..tostring(self.damageReceived or 0) end
  if self.lastRoundTrip then report = report .. "; command ack=" .. math.floor(self.lastRoundTrip*1000+0.5) .. "ms" end
  report=report.."; awake="..(self.db.keepAwake==false and "off" or (self.activityStatus or (info.activity and "ready" or "needs bridge 0.1.9")))
  if self.db.mirrorStack or self.lastStackStatus then report=report.."; stack="..(self.lastStackStatus or (self.db.mirrorStack and "on" or "off")) end
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
    local previous = self.activeInvoke
    self.activeInvoke = name .. "(" .. (a ~= nil and tostring(a) or "") .. ")"
    local ok, result, detail = pcall(zBoxNative, name, a, b, c)
    self.activeInvoke = previous
    self.lastInvoke = name .. ": " .. tostring(ok and detail or result)
    if not ok then return false, tostring(result) end
    return result == 1, detail
  end
  local previous = self.activeInvoke
  self.activeInvoke = name .. "(" .. (a ~= nil and tostring(a) or "") .. ")"
  local ok, reason = pcall(fn, a, b, c)
  self.activeInvoke = previous
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
  if self.CloseLocalTransport then self:CloseLocalTransport() end
  self:Disconnect("Pairing changed")
  self.db.role, self.db.peer, self.db.key, self.db.realm = role, peer, key, self:Realm()
  self.db.enabled = true
  self.session = role == "control" and self:NewSession() or nil
  self.lastHello = -10
  self:Notify(role == "control" and ("Connecting to " .. peer .. (self:GetBridgeInfo().localIPC and self.db.localTransport~=false and " (automatic local DLL / whisper)" or
    (self:GetBridgeInfo().directWhisper and " by addon whisper" or "; ungrouped pairing needs bridge 0.1.7"))) or
    ("Allowing commands from " .. peer .. " on " .. self.db.realm))
  return true
end

function B:Disconnect(reason)
  if self.StopMovement then self:StopMovement() end
  if self.localOpened then pcall(zBoxNative,"LocalDiscard") end
  self.connected, self.session, self.lastReceive = false, nil, nil
  self.peerGUID = nil
  self.peerVersion=nil
  self.mainTargetGUID,self.lastMainTargetID=nil,nil
  self.independentDock=nil
  if self.RestoreNPCGuards then self:RestoreNPCGuards() end
  self.cache, self.pending, self.incoming = {}, {}, {}
  self.queueHigh, self.queueLow, self.lowIndex, self.highIndex = {}, {}, 1, 1
  self.sendID, self.receiveCommandID, self.activeView = 0, 0, nil
  self.lastSnapshotID, self.bagSelection = nil, nil
  self.lastBarSnapshotID, self.heldInputs, self.heldMask = nil, {}, 0
  self.heldModifiers = {}
  self.castRequestAt, self.lastCastSignal, self.lastCastFeedbackAt = nil, nil, nil
  self.lastGameError, self.lastGameErrorCall = nil,nil
  self.lastRemoteError,self.lastFeedbackAt,self.lastFeedbackChatAt = nil,nil,nil
  self.lastDamageID=nil
  self.lastErrorRelayAt,self.lastErrorRelayText = nil,nil
  self.lastRoundTrip = nil
  self.localStopPacket = nil
  self.npcKind, self.npcGUID, self.npcName = nil, nil, nil
  self.npcDirty,self.npcWatch,self.questIntent,self.localQuestScene = nil,nil,nil,nil
  self.lastNPCSnapshot,self.npcDismissedRevision = nil,nil
  self.npcClosing=nil
  self.questObserveAt=nil
  self.questProgressDigest,self.nextQuestProgress,self.lastQuestProgress,self.questProgressIncoming = nil,nil,nil,nil
  self.nextActivity,self.activityStatus = nil,nil
  self.mirrorPaused, self.lastMirrorAt = true, nil
  self.lastMirrorJump = nil
  self.lastStackX,self.lastStackY,self.lastStackZ,self.lastStackEnabled,self.lastStackStatus=nil,nil,nil,nil,nil
  if self.ResetMacroCooldowns then self:ResetMacroCooldowns() end
  if self.UI then
    if self.UI.EndBinding then self.UI:EndBinding() end
    self.UI.held, self.UI.hovered = nil, nil
    self.UI.bagAwaiting, self.UI.questSelected = nil, nil
    self.UI:CancelMove()
    if self.UI.UpdateVisibility then self.UI:UpdateVisibility() end
    self.UI.dirty = true
    if self.UI.frame and self.UI.frame:IsShown() then self.UI:Refresh() end
  end
  if reason then self.notice = reason end
end

function B:IsEnabled()
  return self.db and self.db.enabled and self.db.realm == self:Realm() and self:Channel() ~= nil
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
  if command == "FOLLOW" or command == "PET" or command == "MOVETO" or command == "AXIS" or command == "AXES" or command == "TALK" or command == "NPC" or command=="QUESTLINK" then
    self.mirrorPaused = true
  end
  if command == "STOP" or command == "FOLLOW" or command == "PET" or command == "MOVETO" or command == "TALK" or command == "NPC" or command=="QUESTLINK" then
    self.heldInputs, self.heldMask = {}, 0
    self.heldModifiers = {}
    if self.UI then self.UI.held = nil end
  end
  table.insert(fields, 1, command)
  if command == "UNSTUCK" then
    local _,_,major,minor,patch=string.find(self.peerVersion or "","^(%d+)%.(%d+)%.(%d+)$")
    major,minor,patch=tonumber(major),tonumber(minor),tonumber(patch)
    if not major or (major==0 and (minor<9 or (minor==9 and patch<2))) then
      return false,"Update zBox to 0.9.2 on this follower and reload its UI"
    end
    self.mirrorPaused,self.heldInputs,self.heldMask,self.heldModifiers=true,{},0,{}
    if self.UI then self.UI.held=nil end
    -- Do not put recovery behind the normal action queue, or retry it later.
    if not self:SendNow("CMD",fields) then return false,"Could not send Unstuck" end
    self.pending[self.sendID]={at=GetTime(),command=command}
    return true
  end
  if command == "STOP" then
    self.mirrorPaused = true
    if not self:SendNow("CMD", fields) then return false, self.notice or "Could not send Stop" end
    self.notice = self.localStopPacket and "Emergency stop queued (local IPC busy)" or "Emergency stop sent"
    return true
  end
  local id = self:Send("CMD", fields, true)
  if not id then return false, "Command queue is full" end
  self.pending[id] = { at = GetTime(), command = command }
  if self.localReady then
    self:Pump(GetTime(),0)
    if not self.connected then return false,self.notice end
  end
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
  -- /reload recreates Lua while the DLL survives: retire its previous claim.
  if self.CloseLocalTransport then self:CloseLocalTransport(true) end
  self.targetMode, self.view, self.page, self.actionPage = "TARGET", "actions", 1, 1
  self:Disconnect()
  if self.db.enabled and self.db.realm == self:Realm() and self.db.role == "control" then
    self.session = self:NewSession()
  end
  self.lastHello, self.lastHeartbeat, self.lastStatus = -10, -10, -10
  self.ready = true
  if self.InstallNPCGuards then self:InstallNPCGuards() end
  if self.InstallDamageBridge then self:InstallDamageBridge() end
  if self.InstallQuestTooltip then self:InstallQuestTooltip() end
  if self.UI then self.UI:Create() end
  self:Print("Loaded " .. self.version .. ". /zbox opens the panel; /zbox help explains pairing.")
end

function B:Slash(message)
  local _, _, command, rest = string.find(message or "", "^(%S*)%s*(.-)%s*$")
  command = string.lower(command or "")
  if command == "unstuck" then
    if rest~="" then self:Notify("Use /unstuck or /zbox unstuck (no arguments)");return end
    local ok,reason=self:UnstuckAll()
    if reason then self:Notify(reason) end
  elseif command == "control" or command == "allow" then
    local _, _, peer, key = string.find(rest, "^(%S+)%s+(%S+)$")
    local ok, reason = self:Configure(command == "control" and "control" or "agent", peer, key)
    if not ok then self:Notify(reason) end
  elseif command == "off" then
    if self.connected and self.db.role == "control" then self:SendNow("CMD", { "STOP" }) end
    self.db.enabled = false
    if self.CloseLocalTransport then self:CloseLocalTransport() end
    self:Disconnect("Disabled")
    self:Notify("Disabled on this character")
  elseif command == "stop" then
    if self.db.role == "control" then self:Command("STOP") else self:StopMovement() end
  elseif command == "move" then
    if self.UI then self.UI:ArmMove() end
  elseif command == "keys" then
    if self.UI then self.UI:ShowKeys() end
  elseif command == "stack" then
    if rest~="" and rest~="on" and rest~="off" then self:Notify("Use /zbox stack [on|off]");return end
    local enabled=rest=="on" or (rest=="" and not self.db.mirrorStack)
    local ok,reason=self:SetMirrorStack(enabled)
    if reason then self:Notify(reason) end
  elseif command == "talk" or command == "npc" then
    if self.UI then self.UI:Talk() end
  elseif command == "awake" then
    if rest~="on" and rest~="off" then self:Notify("Use /zbox awake on|off (on account 2)");return end
    self.db.keepAwake=rest=="on";self.nextActivity=nil
    self:Notify("Linked background activity "..rest)
  elseif command == "quests" and (rest=="on" or rest=="off") then
    self.db.linkQuests=rest=="on"
    self:Notify("Linked quest pickup/turn-in "..rest)
  elseif command == "pet" then
    local ok,reason
    if rest == "follow" or rest == "assist" or rest == "attack" then ok,reason=self:UseControl("pet" .. rest)
    elseif rest == "" then ok,reason=self:SetMovementMode("pet")
    else ok,reason=false,"Use /zbox pet follow, /zbox pet assist or /zbox pet attack" end
    if not ok then self:Notify(reason) end
  elseif command == "attack" or command == "assist" or command == "follow" then
    local ok,reason
    if command == "attack" then ok,reason=self:AttackCommand()
    elseif command == "assist" then ok,reason=self:AssistCommand()
    else ok,reason=self:FollowCommand() end
    if not ok then self:Notify(reason) end
  elseif command == "mirror" then
    if rest == "off" then self:SetMirrorMode(false)
    elseif rest == "pause" then if self.connected then self:Command("STOP") end
    else local ok, reason = self:SetMirrorMode(true); if not ok then self:Notify(reason) end end
  elseif command == "scale" then
    if self.UI then
      local ok, reason = self.UI:SetScale(rest == "reset" and 0.85 or rest)
      if not ok then self:Notify(reason) end
    end
  elseif command == "feedback" then
    if rest~="quiet" and rest~="verbose" then self:Notify("Use /zbox feedback quiet or /zbox feedback verbose");return end
    self.db.verboseFeedback=rest=="verbose"
    self:Notify(self.db.verboseFeedback and "Remote error chat enabled (limited repeats)" or "Remote combat errors stay in the dock and diagnostics")
  elseif command == "transport" then
    if rest ~= "auto" and rest ~= "whisper" then self:Notify("Use /zbox transport auto or /zbox transport whisper"); return end
    if self.connected and self.db.role == "control" then self:Command("STOP") end
    self:CloseLocalTransport(); self:Disconnect("Transport changed")
    self.db.localTransport = rest ~= "whisper"
    self.lastHello = -10
    self:Notify(rest == "auto" and "Automatic local DLL transport enabled" or "Addon whisper transport selected")
  elseif command == "diag" then
    self:Print(self:Diagnostics())
    if self.connected and self.db.role == "control" then self:Send("DIAG", {}, true) end
  elseif command == "help" then
    self:Print("/unstuck or /zbox unstuck = Stuck() on this character and every connected follower; pauses movement")
    self:Print("/zbox talk = interact/open account 2's NPC window; drag Talk onto your bars or bind it in Keys")
    self:Print("/zbox quests on|off = linked quest pickup/turn-in; /zbox awake on|off = linked background activity (account 2)")
    self:Print("On account 2: /zbox allow MainName sharedcode; party membership is not required with bridge 0.1.7.")
    self:Print("On account 1: /zbox control AltName sharedcode (same code, 8-32 characters)")
    self:Print("/zbox = panel; /zbox stop = emergency stop; /zbox off = revoke pairing")
    self:Print("/zbox transport auto = prefer local DLL; /zbox transport whisper = compare addon-message transport")
    self:Print("Click-to-move needs zAPI and GetPlayerFacing; zBoxBridge enables protected inputs.")
    self:Print("/zbox diag reports input bridge versions and the last operation on both clients.")
    self:Print("/zbox scale 0.75 changes panel size; /zbox scale reset restores 85%.")
    self:Print("/zbox mirror enables movement/heading/jump mirroring; /zbox mirror pause stops it; /zbox mirror off selects Follow mode.")
    self:Print("/zbox pet follow, /zbox pet assist and /zbox pet attack also work in macros. Drag the matching controls onto your bars.")
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
frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("UPDATE_MACROS")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("SPELLCAST_START")
frame:RegisterEvent("SPELLCAST_STOP")
frame:RegisterEvent("SPELLCAST_FAILED")
frame:RegisterEvent("SPELLCAST_INTERRUPTED")
frame:RegisterEvent("SPELLCAST_CHANNEL_START")
frame:RegisterEvent("SPELLCAST_CHANNEL_STOP")
frame:RegisterEvent("SPELLCAST_DELAYED")
frame:RegisterEvent("SPELLCAST_CHANNEL_UPDATE")
local npcEvents = { "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_ITEM_UPDATE",
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
    if B.CloseLocalTransport then B:CloseLocalTransport() end
    B:Disconnect("Loading or logged out")
  elseif event == "PLAYER_ENTERING_WORLD" then
    B.worldSuspended = false
    B.lastHello = -10
  elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
    if not B:IsEnabled() then B:Disconnect("Pairing transport unavailable") end
  elseif npcEventSet[event] then
    if B.db.role == "agent" then B:NPCEvent(event)
    elseif B.connected and B.ObserveQuestScene then B:ObserveQuestScene(event) end
  elseif event == "QUEST_LOG_UPDATE" then
    if not B.questReadUntil or GetTime() > B.questReadUntil then
      B.questCache = nil
      if B.ObserveQuestChange then B:ObserveQuestChange() end
      B.viewDirty = true
      if B.UI then B.UI.dirty = true end
    end
  elseif event == "UI_ERROR_MESSAGE" then
    if not B.dependencyProbe and B.connected and B.db.role == "agent" and B.lastCommandAt and GetTime() - B.lastCommandAt < 2 then
      B:RelayGameError(arg1)
    end
  elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
    B.nextAgentCooldownCheck = nil
  elseif event == "UPDATE_MACROS" then
    B.nextWatchScan = nil
  elseif event == "SPELLCAST_START" or event == "SPELLCAST_STOP" or event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" or event == "SPELLCAST_CHANNEL_START" or event == "SPELLCAST_CHANNEL_STOP" or event == "SPELLCAST_DELAYED" or event == "SPELLCAST_CHANNEL_UPDATE" then
    if B.db.role == "agent" then B:CastEvent(event, arg2 or arg1) end
    if B.connected and B.db.role == "agent" and B.castRequestAt and GetTime() - B.castRequestAt < 8 then
      B.lastCastSignal = event .. (arg1 and (": " .. tostring(arg1)) or "")
      B:Send("STATE", { "cast", event, tostring(arg1 or "") }, true)
    end
  else
    B.viewDirty = true
    if event == "ACTIONBAR_SLOT_CHANGED" or event == "SPELLS_CHANGED" then B.barDirty = true end
    if event == "ACTIONBAR_SLOT_CHANGED" or event == "SPELLS_CHANGED" then B.nextWatchScan, B.nextAgentCooldownCheck = nil,nil end
  end
end)
frame:SetScript("OnUpdate", function()
  if not B.ready then return end
  B.clock = B.clock + (arg1 or 0)
  if B:GetBridgeInfo().localIPC then B:LocalTransportTick(GetTime()) end
  if B.localReady then
    B:MirrorTick(GetTime())
    B:Pump(GetTime(),0)
  end
  if B.connected and B.db.role=="agent" and B.mirrorStack and B.mirrorStack.active then B:MirrorAgentTick(GetTime()) end
  if B.clock < 0.05 then return end
  local elapsed = B.clock
  B.clock = 0
  B:Tick(GetTime(), elapsed)
end)
SLASH_ZBOX1 = "/zbox"
SlashCmdList["ZBOX"] = function(message) B:Slash(message) end
SLASH_ZBOX_UNSTUCK1 = "/unstuck"
SlashCmdList["ZBOX_UNSTUCK"] = function(message) B:Slash("unstuck "..(message or "")) end
BINDING_HEADER_ZBOX = "zBox - second character"
BINDING_NAME_ZBOX_TOGGLE = "Toggle control panel"
BINDING_NAME_ZBOX_STOP = "Stop second character"
BINDING_NAME_ZBOX_MOVE = "Choose a move destination"
BINDING_NAME_ZBOX_STACK = "Toggle Mirror Stack centering"
BINDING_NAME_ZBOX_TALK = "Talk to NPC with account 2"
BINDING_NAME_ZBOX_FORWARD = "Account 2: hold to move forward"
BINDING_NAME_ZBOX_BACKWARD = "Account 2: hold to move backward"
BINDING_NAME_ZBOX_LEFT = "Account 2: hold to turn left"
BINDING_NAME_ZBOX_RIGHT = "Account 2: hold to turn right"
BINDING_NAME_ZBOX_STRAFELEFT = "Account 2: hold to strafe left"
BINDING_NAME_ZBOX_STRAFERIGHT = "Account 2: hold to strafe right"
BINDING_NAME_ZBOX_FOLLOW = "Account 2: follow main"
BINDING_NAME_ZBOX_ASSIST = "Account 2: assist main"
BINDING_NAME_ZBOX_ATTACK = "Account 2: pet attack target"
BINDING_NAME_ZBOX_JUMP = "Account 2: jump"
