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

function B:CloseLocalTransport(force)
  if self.localOpened or (force and self:GetBridgeInfo().localIPC) then pcall(zBoxNative,"LocalClose") end
  self.localOpened, self.localReady, self.localPeerEpoch = nil,nil,nil
  self.localRetryAt, self.lastLocalPoll, self.localDetail = nil,nil,nil
end

function B:LocalTransportTick(now)
  if self.lastLocalPoll and now-self.lastLocalPoll<0.01 then return end
  self.lastLocalPoll = now
  local wasReady, previousEpoch = self.localReady and true or false, self.localPeerEpoch
  local enabled = self.db and self.db.enabled and self.db.realm==self:Realm() and
    not self.worldSuspended and self.db.localTransport~=false and self:GetBridgeInfo().localIPC
  local ready, epoch = false,nil
  if enabled then
    if not self.localOpened and now>=(self.localRetryAt or 0) then
      self.localRetryAt = now+1
      local ok,result,detail = pcall(zBoxNative,"LocalOpen",self:Realm(),UnitName("player"),self.db.peer,self.db.key,self.db.role=="control" and 0 or 1)
      self.localOpened = ok and result==1
      self.localDetail = self.localOpened and "Local DLL IPC waiting for peer" or tostring(ok and detail or result)
    end
    if self.localOpened then
      local ok,result,peer,detail = pcall(zBoxNative,"LocalInfo")
      if ok and result==0 then return end -- Contention is transient, never a route change.
      if ok and result==1 then
        epoch = type(peer)=="string" and peer~="" and peer or nil
        ready, self.localDetail = epoch~=nil,detail
      else
        self:CloseLocalTransport();self.localRetryAt=now+1
        self.localDetail = "Local DLL IPC unavailable: " .. tostring(ok and detail or result)
      end
    end
  elseif self.localOpened then self:CloseLocalTransport() end
  if wasReady~=ready or (ready and previousEpoch~=epoch) then
    self:Disconnect(ready and "Switching to local DLL communication" or "Local peer unavailable; reconnecting through addon messages")
    self.lastHello = -10
  end
  self.localReady, self.localPeerEpoch = ready,epoch
  if not ready then return end
  for i=1,64 do
    local ok,result,packet = pcall(zBoxNative,"LocalRead")
    if not ok or result==-1 then self:Disconnect("Local receive failed");break end
    if result~=1 then break end
    self:Receive(self.prefix,packet,"LOCAL",self.db.peer)
  end
end

function B:Encode(fields)
  local encoded = {}
  for i = 1, table.getn(fields) do
    -- Addon messages still pass the client's chat-escape validator. Keep
    -- literal pipes, control bytes and UTF-8 bytes out of every wire layer.
    -- Decode restores localized text after all fragments have arrived.
    encoded[i] = string.gsub(tostring(fields[i]), "[%%%c|%^\128-\255]", function(c)
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
  local chunkSize = self.localReady and 4096 or 160
  local id, parts = self.sendID, math.max(1, math.ceil(string.len(body) / chunkSize))
  local packets = {}
  for i = 1, parts do
    packets[i] = "2~" .. self.db.key .. "~" .. self.session .. "~" .. id .. "~" .. i .. "~" .. parts ..
      "~" .. kind .. "~" .. string.sub(body, (i - 1) * chunkSize + 1, i * chunkSize)
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
  if not self:IsEnabled() or self.worldSuspended then return false end
  local packets = self:Packets(kind, fields)
  if not packets then return false end
  local priority = kind=="CMD" and fields[1]=="STOP" and 2 or 1
  for i = 1, table.getn(packets) do
    local sent = self:Transmit(packets[i],priority)
    if sent==nil and self.localReady and priority==2 then self.localStopPacket=packets[i];return true end
    if not sent then return false end
  end
  return true
end

function B:Transmit(packet,priority)
  if self.localReady then
    local ok,result,detail = pcall(zBoxNative,"LocalSend",packet,priority or 0)
    if ok and result==1 then return true end
    if ok and result==0 then return nil end -- Retry a full/busy lane without dropping the frame.
    self:Disconnect("Local send failed: " .. tostring(ok and detail or result));return false
  end
  if self:Channel()=="WHISPER" then
    local ok, result, reason = pcall(zBoxNative,"Whisper",self.db.peer,packet)
    if ok and result==1 then return true end
    self:Disconnect("Addon whisper failed: "..tostring(ok and reason or result))
    return false
  end
  SendAddonMessage(self.prefix,packet,self:Channel())
  return true
end

function B:Pump(now, elapsed)
  if self.localStopPacket then
    if not self:Transmit(self.localStopPacket,2) then return end
    self.localStopPacket=nil
  end
  self.tokens = math.min(4, (self.tokens or 0) + elapsed * 16)
  local function advance(queue, field)
    local index = B[field]
    B[field] = index + 1
    if B[field] > table.getn(queue) then
      if field == "highIndex" then B.queueHigh = {} else B.queueLow = {} end
      B[field] = 1
    end
  end
  local budget = self.localReady and 32 or math.floor(self.tokens)
  for i=1,budget do
    local high = self.queueHigh[self.highIndex]~=nil
    local queue, field = high and self.queueHigh or self.queueLow, high and "highIndex" or "lowIndex"
    local packet = queue[self[field]]
    if not packet then break end
    local sent = self:Transmit(packet,high and 1 or 0)
    if not sent then break end
    advance(queue,field)
    if not self.localReady then self.tokens = self.tokens - 1 end
  end
end

function B:Receive(prefix, message, channel, sender)
  if prefix ~= self.prefix or not self:IsEnabled() or self.worldSuspended then return end
  local expected = self:Channel()
  -- Stock 1.12 emits addon whispers as UNKNOWN; its addon-event channel map
  -- names only party/raid/guild/battleground. Some client mods label WHISPER.
  if channel ~= expected and not (expected == "WHISPER" and channel == "UNKNOWN") then return end
  if self:Name(sender) ~= self:Name(self.db.peer) then return end
  local localRoute = expected=="LOCAL"
  if type(message) ~= "string" or string.len(message) > (localRoute and 4352 or 254) then return end
  local _, _, version, key, session, idText, partText, countText, kind, chunk =
    string.find(message, "^(%d+)~([^~]+)~([%w]+)~(%d+)~(%d+)~(%d+)~([A-Z]+)~(.*)$")
  if version ~= "2" or key ~= self.db.key or string.len(session or "") > 24 then return end
  local id, part, count = tonumber(idText), tonumber(partText), tonumber(countText)
  if not id or id < 1 or id > 2147483647 or not count or count < 1 or count > (localRoute and 4 or 100) or
     not part or part < 1 or part > count or string.len(chunk) > (localRoute and 4096 or 160) then return end
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
    incoming = { parts = {}, count = count, kind = kind, at = now, received = 0, bytes = 0 }
    self.incoming[id] = incoming
  end
  if incoming.count ~= count or incoming.kind ~= kind then return end
  if not incoming.parts[part] then
    incoming.bytes = incoming.bytes + string.len(chunk)
    if incoming.bytes>16000 then self.incoming[id]=nil;return end
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
    self:SetPeerGUID(fields[3])
    if self.InstallNPCGuards then self:InstallNPCGuards() end
    self:Send("READY", { self.version, self:Realm(), UnitName("player"),
      type(zBoxNative) == "function" and "bridge" or "lua", self:GUID("player") }, true)
    self.activeView = self.activeView or { section = "actions", page = 1 }
    self.questProgressDigest,self.nextQuestProgress = nil,nil
    self.viewDirty, self.barDirty = true, true
  elseif kind == "READY" and self.db.role == "control" then
    if fields[2] ~= self:Realm() or self:Name(fields[3]) ~= self:Name(self.db.peer) then return end
    local wasConnected = self.connected
    self.connected, self.lastReceive, self.bridgeMode = true, now, fields[4]
    self:SetPeerGUID(fields[5])
    self.peerVersion=fields[1]
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
  elseif kind == "NPCVIEW" and self.db.role == "agent" and self.connected then
    local page=self.Integer(fields[1],1,40)
    if page then self.lastReceive,self.npcPage,self.npcWatch,self.npcDirty=now,page,true,true end
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
  elseif kind == "WATCH" and self.db.role == "agent" and self.connected then
    self.lastReceive = now
    self:AcceptCooldownWatches(fields,id)
  elseif kind == "TIP" and self.db.role == "agent" and self.connected then
    self.lastReceive = now
    self:SendTooltip(fields[1], fields[2], fields[3])
  elseif kind == "DIAG" and self.db.role == "agent" and self.connected then
    self.lastReceive = now
    self:Send("STATE", { "diagnostics", self:Diagnostics() }, true)
  elseif kind == "DAMAGE" and self.db.role == "control" and self.connected then
    self.lastReceive=now
    self:AcceptDamage(fields,id)
  elseif kind == "STATE" and self.db.role == "control" and self.connected then
    self.lastReceive = now
    self:AcceptState(fields,id)
  elseif kind == "ACK" and self.db.role == "control" and self.connected then
    self.lastReceive = now
    local pending = self.pending[tonumber(fields[1])]
    if pending then
      self.lastRoundTrip = math.max(0,now-pending.at)
      self.pending[tonumber(fields[1])] = nil
      if pending.command=="UNSTUCK" then
        self.lastUnstuckResult=fields[2]=="1" and "Requested through native input" or tostring(fields[3])
        if fields[2]~="1" then self:Print("Unstuck on "..self.db.peer..": "..tostring(fields[3])) end
      end
      if pending.command == "MIRROR" and fields[2] ~= "1" then self:Command("STOP") end
      local castConfirmed = (pending.command == "ACTION" or pending.command == "SPELL" or pending.command=="SKILL") and
        fields[2] == "1" and self.lastCastFeedbackAt and self.lastCastFeedbackAt >= pending.at and now - self.lastCastFeedbackAt < 2
      local quiet = fields[2] == "1" and (pending.command == "AXES" or pending.command == "AXIS" or pending.command == "MIRROR")
      if fields[2]=="1" and not castConfirmed and not quiet then self.notice = pending.command .. ": " .. tostring(fields[3]) end
      if fields[2] ~= "1" then self:RemoteFeedback(pending.command..": "..tostring(fields[3])) end
    end
  elseif kind == "ERROR" and self.db.role == "control" and self.connected then
    self.lastReceive = now
    self:RemoteFeedback((self.db.peer or "Follower")..": "..tostring(fields[1]))
  end
  if self.UI then self.UI.dirty = true end
end

function B:Tick(now, elapsed)
  self:LocalTransportTick(now)
  if self.NPCGuardTick then self:NPCGuardTick(now) end
  if self.worldSuspended or not self:IsEnabled() then
    if self.connected then self:Disconnect("Pairing inactive or transport unavailable") end
    return
  end
  if self.connected and self.lastReceive and now - self.lastReceive > 4 then
    self:Disconnect("Connection lost; movement stopped")
    self.lastHello = -10
  end
  if self.db.role == "control" and not self.connected and now - self.lastHello >= (self.localReady and 0.25 or 2) then
    self.session = self.session or self:NewSession()
    self:Send("HELLO", { self:Realm(), self.version, self:GUID("player") }, true)
    self.lastHello = now
  end
  if self.connected and now - self.lastHeartbeat >= 0.8 then
    self:Send("PING",self.db.role=="control" and {self:GUID("target")} or {},true)
    self.lastHeartbeat = now
  end
  if self.connected and self.db.role == "agent" then
    self:ActivityTick(now)
    self:QuestIntentTick(now)
    self:SendQuestProgress(now)
    self:MovementTick(now)
    self:CastingTick(now)
    self:MirrorAgentTick(now)
    self:PetTick(now)
    self:SendWatchedCooldowns(now)
    if self.npcDirty and now-(self.lastNPCAt or -10)>=0.15 then
      self:SendView({section="npc",page=self.npcPage or 1})
      self.npcDirty,self.lastNPCAt=false,now
    end
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
  if self.connected and self.db.role=="control" and now >= (self.nextQuestTooltipHook or 0) then
    self.nextQuestTooltipHook=now+2;self:InstallQuestTooltip()
  end
  if self.connected and self.db.role=="control" then self:QuestObservationTick(now) end
  if self.ControlTick then self:ControlTick(now) end
  if self.MirrorTick then self:MirrorTick(now) end
  if self.MacroCooldownTick then self:MacroCooldownTick(now) end
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
