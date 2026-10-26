local B = zBox
local function split(text, delimiter)
  local out, start = {}, 1
  while true do
    local at = string.find(text, delimiter, start, true)
    if not at then table.insert(out, string.sub(text, start)); return out end
    table.insert(out, string.sub(text, start, at - 1))
    start = at + string.len(delimiter)
  end
end
B.Split = split

function B:Encode(fields)
  local encoded = {}
  for i = 1, table.getn(fields) do
    -- Addon messages still pass the client's chat-escape validator. Keep
    -- literal pipes and control bytes out of every layer of the wire format.
    encoded[i] = string.gsub(tostring(fields[i]), "[%%%c|%^]", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
  end
  return table.concat(encoded, "^")
end

function B:Decode(body)
  local fields = split(body, "^")
  for i = 1, table.getn(fields) do
    fields[i] = string.gsub(fields[i], "%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
  end
  return fields
end

function B:Packets(kind, fields)
  if not self.session or not self.db.key then return nil end
  local body = self:Encode(fields)
  if string.len(body) > 16000 then return nil end
  self.sendID = self.sendID + 1
  local id, parts = self.sendID, math.max(1, math.ceil(string.len(body) / 160))
  local packets = {}
  for i = 1, parts do
    packets[i] = "2~" .. self.db.key .. "~" .. self.session .. "~" .. id .. "~" .. i .. "~" .. parts ..
      "~" .. kind .. "~" .. string.sub(body, (i - 1) * 160 + 1, i * 160)
  end
  return packets, id
end

function B:Send(kind, fields, high)
  local queue = high and self.queueHigh or self.queueLow
  if not queue then return nil end
  if table.getn(queue) > (high and 160 or 256) then return nil end
  local packets, id = self:Packets(kind, fields)
  if not packets then return nil end
  for i = 1, table.getn(packets) do table.insert(queue, packets[i]) end
  return id
end

function B:SendNow(kind, fields)
  if not self:IsEnabled() or self.worldSuspended then return end
  local packets = self:Packets(kind, fields)
  if not packets then return end
  for i = 1, table.getn(packets) do SendAddonMessage(self.prefix, packets[i], self:Channel()) end
end

function B:Pump(now, elapsed)
  self.tokens = math.min(4, (self.tokens or 0) + elapsed * 16)
  local function take(queue, field)
    local index = B[field]
    local packet = queue[index]
    if not packet then return end
    B[field] = index + 1
    if B[field] > table.getn(queue) then
      if field == "highIndex" then B.queueHigh = {} else B.queueLow = {} end
      B[field] = 1
    end
    return packet
  end
  while self.tokens >= 1 do
    local packet = take(self.queueHigh, "highIndex") or take(self.queueLow, "lowIndex")
    if not packet then break end
    SendAddonMessage(self.prefix, packet, self:Channel())
    self.tokens = self.tokens - 1
  end
end

function B:Receive(prefix, message, channel, sender)
  if prefix ~= self.prefix or not self:IsEnabled() or self.worldSuspended then return end
  if channel ~= self:Channel() or self:Name(sender) ~= self:Name(self.db.peer) then return end
  if type(message) ~= "string" or string.len(message) > 254 then return end
  local _, _, version, key, session, idText, partText, countText, kind, chunk =
    string.find(message, "^(%d+)~([^~]+)~([%w]+)~(%d+)~(%d+)~(%d+)~([A-Z]+)~(.*)$")
  if version ~= "2" or key ~= self.db.key or string.len(session or "") > 24 then return end
  local id, part, count = tonumber(idText), tonumber(partText), tonumber(countText)
  if not id or id < 1 or id > 2147483647 or not count or count < 1 or count > 100 or
     not part or part < 1 or part > count or string.len(chunk) > 160 then return end
  local now = GetTime()
  if self.db.role == "agent" and kind == "HELLO" then
    if self.session ~= session then
      if self.connected and self.lastReceive and now - self.lastReceive < 4 then return end
      self:Disconnect()
      self.session = session
    end
  elseif session ~= self.session then return end
  if not self.session then return end
  local incoming = self.incoming[id]
  if not incoming then
    local active = 0
    for _, value in pairs(self.incoming) do active = active + 1 end
    if active >= 16 then return end
    incoming = { parts = {}, count = count, kind = kind, at = now, received = 0 }
    self.incoming[id] = incoming
  end
  if incoming.count ~= count or incoming.kind ~= kind then return end
  if not incoming.parts[part] then
    incoming.parts[part], incoming.received = chunk, incoming.received + 1
  end
  if incoming.received ~= count then return end
  self.incoming[id] = nil
  self:Message(kind, self:Decode(table.concat(incoming.parts)), id, now)
end

function B:Message(kind, fields, id, now)
  if kind == "HELLO" and self.db.role == "agent" then
    if fields[1] ~= self:Realm() then return end
    self.connected, self.lastReceive = true, now
    if self.InstallNPCGuards then self:InstallNPCGuards() end
    self:Send("READY", { self.version, self:Realm(), UnitName("player"),
      type(zBoxNative) == "function" and "bridge" or "lua" }, true)
    self.activeView = self.activeView or { section = "actions", page = 1 }
    self.viewDirty, self.barDirty = true, true
  elseif kind == "READY" and self.db.role == "control" then
    if fields[2] ~= self:Realm() then return end
    local wasConnected = self.connected
    self.connected, self.lastReceive, self.bridgeMode = true, now, fields[4]
    if not wasConnected then
      self.notice = "Connected to " .. self.db.peer
      self:Request(self.view or "actions", self.page or 1)
    end
  elseif kind == "PING" and self.connected then
    self.lastReceive = now
  elseif kind == "CMD" and self.db.role == "agent" and self.connected then
    -- Each command is acknowledged once and is never automatically retried.
    -- A delayed/duplicate command cannot spend a second talent point or equip twice.
    if id <= self.receiveCommandID then return end
    self.receiveCommandID, self.lastReceive, self.lastCommandAt = id, now, now
    local ok, detail = self:Execute(fields)
    self:Send("ACK", { id, ok and "1" or "0", detail or (ok and "Requested" or "Rejected") }, true)
    if fields[1] == "TALENT" or fields[1] == "EQUIP" or fields[1] == "UNEQUIP" or fields[1] == "USEITEM" then
      self.viewDirty = true
    end
  elseif kind == "VIEW" and self.db.role == "agent" and self.connected then
    self.lastReceive = now
    self:SetView(fields[1], fields[2])
  elseif kind == "BAG" and self.db.role == "agent" and self.connected then
    local page = self.Integer(fields[1], 1, 5)
    if page and now - (self.lastBagRequestAt or -10) >= 0.4 then
      self.lastBagRequestAt = now
      self:SendView({ section = "bags", page = page })
    end
  elseif kind == "BAR" and self.db.role == "agent" and self.connected then
    local page = tonumber(fields[1])
    if page and page >= 1 and page <= 10 and page == math.floor(page) then
      self.actionPage, self.barDirty, self.lastReceive = page, true, now
    end
  elseif kind == "TIP" and self.db.role == "agent" and self.connected then
    self.lastReceive = now
    self:SendTooltip(fields[1], fields[2], fields[3])
  elseif kind == "DIAG" and self.db.role == "agent" and self.connected then
    self.lastReceive = now
    self:Send("STATE", { "diagnostics", self:Diagnostics() }, true)
  elseif kind == "STATE" and self.db.role == "control" and self.connected then
    self.lastReceive = now
    self:AcceptState(fields)
  elseif kind == "ACK" and self.db.role == "control" and self.connected then
    self.lastReceive = now
    local pending = self.pending[tonumber(fields[1])]
    if pending then
      self.pending[tonumber(fields[1])] = nil
      if pending.command == "MIRROR" and fields[2] ~= "1" then self:Command("STOP") end
      local castConfirmed = (pending.command == "ACTION" or pending.command == "SPELL") and
        fields[2] == "1" and self.lastCastFeedbackAt and self.lastCastFeedbackAt >= pending.at and now - self.lastCastFeedbackAt < 2
      local quiet = fields[2] == "1" and (pending.command == "AXES" or pending.command == "AXIS" or pending.command == "MIRROR")
      if not castConfirmed and not quiet then self.notice = pending.command .. ": " .. tostring(fields[3]) end
      if fields[2] ~= "1" then self:Print(self.notice) end
    end
  elseif kind == "ERROR" and self.db.role == "control" and self.connected then
    self.lastReceive = now
    self.notice = "Account 2: " .. tostring(fields[1])
    self:Print(self.notice)
  end
  if self.UI then self.UI.dirty = true end
end

function B:Tick(now, elapsed)
  if self.NPCGuardTick then self:NPCGuardTick(now) end
  if self.worldSuspended or not self:IsEnabled() then
    if self.connected then self:Disconnect("Pairing inactive or peer left the group") end
    return
  end
  if self.connected and self.lastReceive and now - self.lastReceive > 4 then
    self:Disconnect("Connection lost; movement stopped")
    self.lastHello = -10
  end
  if self.db.role == "control" and not self.connected and now - self.lastHello >= 2 then
    self.session = self.session or self:NewSession()
    self:Send("HELLO", { self:Realm(), self.version }, true)
    self.lastHello = now
  end
  if self.connected and now - self.lastHeartbeat >= 0.8 then
    self:Send("PING", {}, true)
    self.lastHeartbeat = now
  end
  if self.connected and self.db.role == "agent" then
    self:MovementTick(now)
    self:CastingTick(now)
    self:MirrorAgentTick(now)
    self:PetTick(now)
    if now - self.lastStatus >= 0.5 then
      self:SendStatus()
      self.lastStatus = now
    end
    if self.activeView and self.activeView.section == "quests" and now - (self.lastViewAt or -10) >= 2.5 then self.viewDirty = true end
    if self.activeView and self.viewDirty and now - (self.lastViewAt or -10) >= 0.8 then
      self:SendView()
      self.viewDirty, self.lastViewAt = false, now
    end
    if self.barDirty and self.actionPage and now - (self.lastBarAt or -10) >= 0.8 then
      self:SendView({ section = "actions", page = self.actionPage })
      self.lastBarAt = now
    end
  end
  if self.ControlTick then self:ControlTick(now) end
  if self.MirrorTick then self:MirrorTick(now) end
  for id, incoming in pairs(self.incoming) do
    if now - incoming.at > 30 then self.incoming[id] = nil end
  end
  for id, pending in pairs(self.pending) do
    if now - pending.at > 5 then
      self.pending[id] = nil
      self.notice = pending.command .. ": no acknowledgement; verify on account 2"
    end
  end
  self:Pump(now, elapsed)
  if self.UI then self.UI:Tick(now) end
end
