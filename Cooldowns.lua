local B = zBox
local function finite(value, maximum)
  return type(value) == "number" and value == value and value >= 0 and value <= maximum
end

function B:MacroProxy(index,anyPeer)
  if not GetMacroInfo or not index then return end
  local _, _, body = GetMacroInfo(index)
  local _, _, id = string.find(body or "", '^/script zBox:UseProxy%("(%d+)"%)%s*$')
  local proxy = id and self.db.proxies and self.db.proxies[id]
  if proxy and proxy.realm == self:Realm() and (anyPeer or self:Name(proxy.peer) == self:Name(self.db.peer)) and
     (proxy.command == "ACTION" or proxy.command == "SPELL") then return id, proxy end
end

function B:SyncCooldownWatches(now)
  local rows, watches = {}, {}
  for index = 1, 36 do
    local id, proxy = self:MacroProxy(index)
    if id and not watches[id] then
      watches[id] = { command=proxy.command, slot=proxy.slot, stamp=proxy.stamp }
      table.insert(rows, self:Encode({id,proxy.command,proxy.slot,proxy.stamp}))
    end
  end
  for _,id in pairs(not self.independentBars and self.db.barSlots or {}) do
    local proxy=self.db.proxies and self.db.proxies[id]
    if proxy and not watches[id] and proxy.realm==self:Realm() and self:Name(proxy.peer)==self:Name(self.db.peer) then
      watches[id]={command=proxy.command,slot=proxy.slot,stamp=proxy.stamp}
      table.insert(rows,self:Encode({id,proxy.command,proxy.slot,proxy.stamp}))
    end
  end
  local active=self.independentBars and self.independentBars.profile
  local profile=active and self.db.barProfiles and self.db.barProfiles[active]
  for _,entries in pairs(profile and profile.pages or {}) do for _,entry in pairs(entries) do
    local id=entry.watch;local proxy=id and self.db.proxies and self.db.proxies[id]
    if proxy and not watches[id] and self:Name(proxy.peer)==self:Name(self.db.peer) then
      watches[id]={command=proxy.command,slot=proxy.slot,stamp=proxy.stamp}
      table.insert(rows,self:Encode({id,proxy.command,proxy.slot,proxy.stamp}))
    end
  end end
  table.sort(rows)
  local payload = table.concat(rows, "\n")
  local changed = payload ~= self.cooldownWatchPayload
  if not changed and now-(self.lastWatchAt or -10)<5 then return end
  if payload == "" and not self.cooldownWatchToken then return end
  local token = changed and self:NewSession() or self.cooldownWatchToken
  if not self:Send("WATCH", {token,payload}, true) then return end
  if changed then self.cache.proxyCooldowns, self.lastProxyCooldownID = {}, nil end
  self.cooldownWatchToken, self.cooldownWatchPayload, self.cooldownWatches = token, payload, watches
  self.lastWatchAt = now
end

function B:AcceptCooldownWatches(fields, id)
  if table.getn(fields) ~= 2 or not string.find(fields[1], "^%w+$") or string.len(fields[1])>32 or
     id <= (self.lastWatchID or 0) then return end
  local rows = fields[2] == "" and {} or self.Split(fields[2], "\n")
  if table.getn(rows)>156 then return end
  local watches = {}
  for _, encoded in ipairs(rows) do
    local row = self:Decode(encoded)
    local maximum = row[2] == "ACTION" and 120 or (row[2] == "SPELL" and 960)
    local skill=row[2]=="SKILL" and type(row[3])=="string" and string.len(row[3])>0 and string.len(row[3])<=180 and string.len(row[4] or "")<=80
    if table.getn(row)~=4 or not self.Integer(row[1],1,2147483647) or watches[row[1]] then return end
    if not skill and (not maximum or not self.Integer(row[3],1,maximum) or not self.Integer(row[4],0,2147483647)) then return end
    watches[row[1]] = { command=row[2],slot=skill and row[3] or tonumber(row[3]),stamp=row[4] }
  end
  self.agentCooldownWatches, self.agentCooldownToken, self.lastWatchID = watches, fields[1], id
  self.agentCooldownSignature, self.lastAgentCooldownAt, self.nextAgentCooldownCheck = nil, nil, nil
end

function B:SendWatchedCooldowns(now)
  if not self.agentCooldownWatches or now<(self.nextAgentCooldownCheck or 0) then return end
  self.nextAgentCooldownCheck = now+0.1
  local rows, signature = {}, {}
  for id, watch in pairs(self.agentCooldownWatches) do
    local skill=watch.command=="SKILL" and self:FindSkill(watch.slot,watch.stamp)
    local valid = watch.command == "ACTION" and HasAction(watch.slot) and self:ActionStamp(watch.slot)==watch.stamp or
      watch.command == "SPELL" and self:SpellStamp(watch.slot)==watch.stamp or skill
    local start, duration, enabled = 0,0,1
    local api = watch.command == "ACTION" and GetActionCooldown or GetSpellCooldown
    if valid and type(api)=="function" then
      local ok
      ok,start,duration,enabled = pcall(api,skill or watch.slot,BOOKTYPE_SPELL or "spell")
      valid = ok and finite(start,1e12) and finite(duration,604800)
    else valid = false end
    if not valid or enabled == 0 then start,duration=0,0 end
    local remaining = math.min(duration,math.max(0,start+duration-now))
    table.insert(rows,self:Encode({id,string.format("%.2f",remaining),duration,valid and "1" or "0"}))
    table.insert(signature,self:Encode({id,start,duration,enabled or 1,valid and "1" or "0"}))
  end
  -- Stable iteration order keeps the signature independent of Lua table order.
  table.sort(rows); table.sort(signature)
  local key = table.concat(signature,"\n")
  if key == self.agentCooldownSignature and now-(self.lastAgentCooldownAt or -10)<2 then return end
  if self:Send("STATE", {"proxycd",self.agentCooldownToken,table.concat(rows,"\n")},true) then
    self.agentCooldownSignature, self.lastAgentCooldownAt = key, now
  end
end

function B:AcceptProxyCooldowns(fields, id)
  if table.getn(fields)~=3 or fields[2]~=self.cooldownWatchToken or not self.Integer(id,1,2147483647) or
     id <= (self.lastProxyCooldownID or 0) then return end
  local rows = fields[3]=="" and {} or self.Split(fields[3],"\n")
  if table.getn(rows)>156 then return end
  local cache, now = {}, GetTime()
  for _, encoded in ipairs(rows) do
    local row = self:Decode(encoded)
    local remaining,duration = tonumber(row[2]),tonumber(row[3])
    if table.getn(row)~=4 or not self.cooldownWatches or not self.cooldownWatches[row[1]] or cache[row[1]] or
       not finite(remaining,604800) or not finite(duration,604800) or remaining>duration+0.1 or
       (row[4]~="0" and row[4]~="1") then return end
    cache[row[1]] = { endsAt=now+remaining,duration=duration,valid=row[4]=="1",at=now }
  end
  self.cache.proxyCooldowns, self.lastProxyCooldownID = cache, id
end

local pfBars = {"Main","Paging","Right","Vertical","Left","Top","StanceBar1","StanceBar2","StanceBar3","StanceBar4"}
local stockBars = { {"ActionButton",0}, {"BonusActionButton",0}, {"MultiBarBottomLeftButton",60},
  {"MultiBarBottomRightButton",48}, {"MultiBarRightButton",24}, {"MultiBarLeftButton",36} }

function B:FindCooldownButtons()
  self.cooldownButtons = self.cooldownButtons or {}
  for _, bar in ipairs(pfBars) do
    for index=1,12 do
      local button = getglobal("pfActionBar"..bar.."Button"..index)
      if button then self.cooldownButtons[button] = {pf=true} end
    end
  end
  for _, bar in ipairs(stockBars) do
    for index=1,12 do
      local button = getglobal(bar[1]..index)
      if button then self.cooldownButtons[button] = {slot=index+bar[2],paged=bar[2]==0} end
    end
  end
end

function B:CooldownButtonSlot(button, source)
  if source.pf then return self.Integer(button.id,1,120) end
  if source.paged and ActionButton_GetPagedID then
    local ok, slot = pcall(ActionButton_GetPagedID,button)
    if ok and self.Integer(slot,1,120) then return slot end
  end
  return self.Integer(button.action,1,120) or
    source.slot + (source.paged and 12*((GetActionBarPage and GetActionBarPage() or 1)-1) or 0)
end

function B:CooldownOverlay(button)
  if button.zBoxCooldown then return button.zBoxCooldown end
  local frame = CreateFrame("Frame",nil,button)
  frame:SetAllPoints(button); frame:SetFrameLevel(button:GetFrameLevel()+5); frame:EnableMouse(false)
  frame.swipe = CreateFrame("Model",nil,frame,"CooldownFrameTemplate")
  frame.swipe:SetAllPoints(frame); frame.swipe:EnableMouse(false)
  frame.swipe.noCooldownCount = 1
  local textFrame = CreateFrame("Frame",nil,frame)
  textFrame:SetAllPoints(frame); textFrame:SetFrameLevel(frame.swipe:GetFrameLevel()+1); textFrame:EnableMouse(false)
  frame.text = textFrame:CreateFontString(nil,"OVERLAY")
  frame.text:SetFont("Fonts\\FRIZQT__.TTF",math.max(10,math.min(18,button:GetWidth()*0.4)),"OUTLINE")
  frame.text:SetPoint("CENTER",textFrame,"CENTER",0,0); frame.text:SetTextColor(1,0.85,0.3)
  button.zBoxCooldown = frame
  return frame
end

function B:PaintMacroCooldowns(now)
  for button, source in pairs(self.cooldownButtons or {}) do
    local id
    if button:IsVisible() then
      local slot = self:CooldownButtonSlot(button,source)
      local kind, macro
      if slot and GetActionInfo then kind,macro=GetActionInfo(slot) end
      if kind=="macro" then id=self:MacroProxy(macro,true)
      elseif slot and GetActionText and GetMacroIndexByName then id=self:MacroProxy(GetMacroIndexByName(GetActionText(slot) or ""),true) end
      if not self.independentBars and not id and source.pf and slot and not HasAction(slot) then id=self.db.barSlots and self.db.barSlots[slot] end
    end
    local proxy=id and self.db.proxies and self.db.proxies[id]
    local owner=proxy and self.FollowerState and self:FollowerState(proxy.peer) or self
    local cd = id and owner and owner.connected and owner.cache.proxyCooldowns and owner.cache.proxyCooldowns[id]
    local remaining = cd and cd.endsAt-now or 0
    if cd and cd.valid and now-cd.at<=5 and remaining>0.05 then
      local frame = self:CooldownOverlay(button)
      if frame.proxy~=id or math.abs((frame.endsAt or 0)-cd.endsAt)>0.2 or frame.duration~=cd.duration then
        if CooldownFrame_SetTimer then CooldownFrame_SetTimer(frame.swipe,cd.endsAt-cd.duration,cd.duration,1) end
        frame.proxy, frame.endsAt, frame.duration = id,cd.endsAt,cd.duration
      end
      local text = remaining>=3600 and (math.ceil(remaining/3600).."h") or
        (remaining>=60 and (math.ceil(remaining/60).."m") or (remaining>=10 and tostring(math.ceil(remaining)) or string.format("%.1f",remaining)))
      frame.text:SetText(text); frame:Show()
    elseif button.zBoxCooldown then button.zBoxCooldown:Hide() end
  end
end

function B:MacroCooldownTick(now)
  if self.db.role~="control" then return end
  if self.connected and now>=(self.nextWatchScan or 0) then self.nextWatchScan=now+1; self:SyncCooldownWatches(now) end
  if now>=(self.nextCooldownButtons or 0) then self.nextCooldownButtons=now+0.5; self:FindCooldownButtons() end
  if now>=(self.nextCooldownPaint or 0) then self.nextCooldownPaint=now+0.1; self:PaintMacroCooldowns(now) end
end

function B:ResetMacroCooldowns()
  for button in pairs(self.cooldownButtons or {}) do if not self.rosterBackground and button.zBoxCooldown then button.zBoxCooldown:Hide() end end
  self.cooldownWatchToken, self.cooldownWatchPayload, self.cooldownWatches, self.lastWatchAt = nil,nil,nil,nil
  self.agentCooldownToken, self.agentCooldownWatches, self.lastWatchID, self.lastProxyCooldownID = nil,nil,nil,nil
  self.agentCooldownSignature, self.lastAgentCooldownAt, self.nextWatchScan = nil,nil,nil
end
