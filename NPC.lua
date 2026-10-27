local B = zBox
local icon = "Interface\\Icons\\INV_Misc_Note_01"
local events = { GOSSIP_SHOW = "gossip", QUEST_GREETING = "greeting", QUEST_DETAIL = "detail",
  QUEST_PROGRESS = "progress", QUEST_COMPLETE = "reward", MERCHANT_SHOW = "merchant", TRAINER_SHOW = "trainer" }
local closed = { GOSSIP_CLOSED = "gossip", QUEST_FINISHED = "quest", MERCHANT_CLOSED = "merchant", TRAINER_CLOSED = "trainer" }

function B:NPCEvent(name)
  if events[name] then
    self.npcKind, self.npcGUID, self.npcName = events[name], self:GUID("npc"), UnitName("npc") or "NPC"
    if self.npcGUID == "" then self.npcGUID = self:GUID("target") end
  elseif closed[name] then
    local kind = self.npcKind
    if kind == closed[name] or (closed[name] == "quest" and (kind == "greeting" or kind == "detail" or kind == "progress" or kind == "reward")) then
      self.npcKind = nil
    end
  end
  self.npcRevision = (self.npcRevision or 0) + 1
  self.npcDirty=true
  if events[name] or closed[name] then self.npcPage=1 end
  self.viewDirty = true
end

function B:Money(copper)
  copper = math.floor(tonumber(copper) or 0)
  return string.format("%dg %ds %dc", math.floor(copper / 10000), math.mod(math.floor(copper / 100), 100), math.mod(copper, 100))
end

-- Each row carries a fingerprint of the live dialog, offer, cost and quantity.
-- Commands select one of these fixed operations, never received Lua text.
function B:NPCRows()
  local rows, kind = {}, self.npcKind
  local function add(op, index, name, detail, texture, cost, quantity, available)
    local row = { index or 0, texture or icon, tostring(name or ""), string.sub(tostring(detail or ""), 1, 1800), "", op,
      cost or 0, quantity or 0, available == false and "0" or "1" }
    row[5] = B:Fingerprint(B:Encode({ B.npcGUID or "", B.npcRevision or 0, kind or "", row[1], row[3], row[4], op, row[7], row[8], row[9] }))
    table.insert(rows, row)
  end
  if kind == "gossip" then
    local options = { GetGossipOptions() }
    for i = 1, table.getn(options), 2 do
      add("gossip", (i+1)/2, options[i], "Talk", "Interface\\GossipFrame\\" .. tostring(options[i+1] or "gossip") .. "GossipIcon")
    end
    -- The stock 1.12 client returns title/level pairs for both quest lists.
    local available, active = { GetGossipAvailableQuests() }, { GetGossipActiveQuests() }
    for i = 1, table.getn(available), 2 do add("gossipAvailable", (i+1)/2, available[i], "Available quest - level " .. tostring(available[i+1])) end
    for i = 1, table.getn(active), 2 do add("gossipActive", (i+1)/2, active[i], "Current quest - level " .. tostring(active[i+1])) end
  elseif kind == "greeting" then
    for i = 1, GetNumAvailableQuests() do add("available", i, GetAvailableTitle(i), "Available quest") end
    for i = 1, GetNumActiveQuests() do add("active", i, GetActiveTitle(i), "Current quest") end
  elseif kind == "detail" then
    add("accept", 0, GetTitleText(), tostring(GetQuestText() or "") .. "\nClick to accept quest")
  elseif kind == "progress" then
    add("complete", 0, GetTitleText(), tostring(GetProgressText() or "") .. "\nContinue to rewards", nil, 0, 0, IsQuestCompletable() and true or false)
  elseif kind == "reward" then
    local count = GetNumQuestChoices()
    local cost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    local price = cost > 0 and (" - costs " .. self:Money(cost)) or ""
    if count == 0 then add("reward", 0, GetTitleText(), "Complete quest and collect rewards" .. price, nil, cost) end
    for i = 1, count do
      local name, texture, quantity = GetQuestItemInfo("choice", i)
      add("reward", i, name, GetTitleText() .. "\nChoose this reward (x" .. tostring(quantity or 1) .. ")" .. price, texture, cost)
    end
  elseif kind == "merchant" then
    for i = 1, GetMerchantNumItems() do
      local name, texture, price, quantity, stock, usable = GetMerchantItemInfo(i)
      if name then add("buy", i, name, "Buy " .. tostring(quantity or 1) .. " for " .. self:Money(price) .. (stock == -1 and "" or (" - stock " .. tostring(stock))), texture, price, quantity or 1, stock ~= 0) end
    end
  elseif kind == "trainer" then
    for i = 1, GetNumTrainerServices() do
      local name, rank, state = GetTrainerServiceInfo(i)
      local price = GetTrainerServiceCost(i) or 0
      if state ~= "header" and state ~= "used" then
        add("train", i, tostring(name or "") .. " " .. tostring(rank or ""), tostring(state or "") .. " - " .. self:Money(price), GetTrainerServiceIcon and GetTrainerServiceIcon(i), price, 0, state == "available")
      end
    end
  end
  if kind then add("close", 0, "Close conversation", self.npcName) end
  return rows
end

function B:NPCView(page)
  local all, rows = self:NPCRows(), {}
  local size=(self.npcKind=="gossip" or self.npcKind=="greeting") and 32 or 6
  for i = (page-1)*size+1, math.min(page*size, table.getn(all)) do table.insert(rows, self:Encode(all[i])) end
  return rows, self.npcKind and ((self.npcName or "NPC") .. " - " .. self.npcKind) or "Target an NPC, then click Talk", math.max(1, math.ceil(table.getn(all)/size))
end

function B:NPCPresentation()
  local kind, title, dialogue, objectives = self.npcKind or "", "", "", ""
  if kind == "gossip" then dialogue = GetGossipText and GetGossipText() or ""
  elseif kind == "greeting" then dialogue = GetGreetingText and GetGreetingText() or ""
  elseif kind == "detail" then
    title, dialogue = GetTitleText(), GetQuestText() or ""
    objectives = GetObjectiveText and GetObjectiveText() or ""
  elseif kind == "progress" then title, dialogue = GetTitleText(), GetProgressText() or ""
  elseif kind == "reward" then title, dialogue = GetTitleText(), GetRewardText and GetRewardText() or ""
  end
  local extras={}
  local function items(category,apiKind,count)
    if not GetQuestItemInfo then return end
    for index=1,math.min(count or 0,10) do
      local name,texture,quantity=GetQuestItemInfo(apiKind,index)
      table.insert(extras,self:Encode({category,name or "",texture or "",quantity or 1}))
    end
  end
  if kind=="detail" or kind=="reward" then
    if kind=="detail" then items("choice","choice",GetNumQuestChoices and GetNumQuestChoices() or 0) end
    items("reward","reward",GetNumQuestRewards and GetNumQuestRewards() or 0)
    local money=GetRewardMoney and GetRewardMoney() or 0
    if money>0 then table.insert(extras,self:Encode({"money",self:Money(money),"",1})) end
    if GetRewardSpell then
      local texture,name=GetRewardSpell()
      if name then table.insert(extras,self:Encode({"spell",name,texture or "",1})) end
    end
  elseif kind=="progress" then
    items("required","required",GetNumQuestItems and GetNumQuestItems() or 0)
    local money=GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    if money>0 then table.insert(extras,self:Encode({"required",self:Money(money),"",1})) end
  end
  -- Keep the NPC's actual text separate from action captions and fingerprints.
  -- This fits the transport budget alongside the six visible choices.
  local all=self:NPCRows()
  local close=all[table.getn(all)]
  return { kind, self.npcName or "NPC", title or "", string.sub(dialogue, 1, 6000), string.sub(objectives, 1, 2000),
    self.npcGUID or "",tostring(self.npcRevision or 0),table.concat(extras,"\n"),close and close[5] or "" }
end

function B:TalkToNPC(guid)
  if not self:GetBridgeInfo().npc then return false, "NPC interaction needs zBoxBridge 0.1.4; restart both clients after updating the DLL" end
  if UnitAffectingCombat("player") then return false, "Talk outside combat" end
  local ok, reason = self:ChooseTarget(guid)
  if not ok then return false, reason end
  if not UnitExists("target") or (UnitIsPlayer and UnitIsPlayer("target")) or
     (UnitCanAttack and UnitCanAttack("player", "target")) or UnitIsDeadOrGhost("target") then return false, "Choose a living friendly NPC" end
  local x,y,z = self:Position("player")
  local tx,ty,tz = self:Position("target")
  if not x or not tx or (x-tx)^2 + (y-ty)^2 + (z-tz)^2 > 36 then return false, "Move account 2 within 6 yards of the NPC first" end
  local stopped, stopReason = self:StopMovement(nil, true)
  if not stopped then return false, stopReason end
  local success, result, detail = pcall(zBoxNative, "InteractNPC", guid)
  return success and result == 1, success and detail or tostring(result)
end

function B:NPCAction(op, index, expected)
  if not self:GetBridgeInfo().npc then return false, "Update zBoxBridge to 0.1.4 for NPC controls" end
  if UnitAffectingCombat("player") then return false, "Use NPC controls outside combat" end
  local selected
  for _, row in ipairs(self:NPCRows()) do
    if row[6] == op and tostring(row[1]) == tostring(index) and row[5] == expected then selected = row; break end
  end
  if not selected then return false, "NPC dialog or price changed; refresh and select again" end
  if selected[9] == "0" then return false, "This service is unavailable" end
  if tonumber(selected[7]) > (GetMoney and GetMoney() or 0) then return false, "Account 2 cannot afford this" end
  local operations = { gossip = "SelectGossipOption", gossipAvailable = "SelectGossipAvailableQuest", gossipActive = "SelectGossipActiveQuest",
    available = "SelectAvailableQuest", active = "SelectActiveQuest", accept = "AcceptQuest", complete = "CompleteQuest", reward = "GetQuestReward",
    buy = "BuyMerchantItem", train = "BuyTrainerService" }
  if op == "close" then
    local close = { gossip = "CloseGossip", merchant = "CloseMerchant", trainer = "CloseTrainer" }
    return self:Invoke(close[self.npcKind] or "CloseQuest")
  end
  local fn = operations[op]
  if not fn then return false, "Unknown NPC action" end
  self:StopMovement()
  -- Invalidate immediately: duplicate/double clicks cannot spend twice.
  self.npcRevision = (self.npcRevision or 0) + 1
  self.npcDirty=true
  self.viewDirty = true
  if op == "accept" or op == "complete" then return self:Invoke(fn) end
  -- Vanilla's quantity argument counts offers; one offer may contain several items.
  return self:Invoke(fn, tonumber(index), op == "buy" and 1 or nil)
end
