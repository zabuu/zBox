local B = zBox
local function integer(value, low, high)
  value = tonumber(value)
  if value and value == math.floor(value) and value >= low and value <= high then return value end
end
B.Integer = integer
local function flag(value) return value and "1" or "0" end
local function text(value) return value == nil and "" or tostring(value) end

function B:Fingerprint(value)
  local hash = 5381
  value = tostring(value or "")
  for i = 1, string.len(value) do hash = math.mod(hash * 33 + string.byte(value, i), 2147483647) end
  return tostring(hash)
end

function B:ActionStamp(slot)
  local kind, id
  if GetActionInfo then kind, id = GetActionInfo(slot) end
  return self:Fingerprint(text(kind) .. ":" .. text(id) .. ":" .. text(GetActionTexture(slot)) .. ":" .. text(GetActionText(slot)))
end

function B:SpellStamp(index)
  local name, rank = GetSpellName(index, BOOKTYPE_SPELL or "spell")
  return self:Fingerprint(text(name) .. ":" .. text(rank))
end

function B:ItemKey(link)
  if not link then return "" end
  local _, _, key = string.find(link, "|H(item:[^|]+)|h")
  return key or link
end

function B:Cooldown(start, duration, enabled)
  if not start or not duration or enabled == 0 then return 0, duration or 0 end
  return math.max(0, start + duration - GetTime()), duration
end

function B:SendStatus()
  local className, class = UnitClass("player")
  local points = UnitCharacterPoints and UnitCharacterPoints("player") or 0
  self:Send("STATE", { "status", UnitName("player"), UnitLevel("player"), class or className or "",
    UnitHealth("player"), UnitHealthMax("player"), UnitMana("player"), UnitManaMax("player"),
    UnitName("target") or "No target", flag(UnitAffectingCombat("player")), flag(UnitIsDeadOrGhost("player")),
    points or 0, self.petState and (self.petState.guid and "Pet attack" or (self.petState.mode == "assist" and "Pet assist" or "Following")) or (self.destination and "Moving to point" or (self.following and "Following" or "Idle")),
    self:GetBridgeInfo().label }, true)
  if self.actionPage then
    local rows, first = {}, (self.actionPage - 1) * 12 + 1
    for slot = first, first + 11 do
      local start, duration, enabled = GetActionCooldown(slot)
      local remaining = self:Cooldown(start, duration, enabled)
      local usable, noMana = IsUsableAction(slot)
      table.insert(rows, self:Encode({ slot, string.format("%.2f", remaining), duration or 0,
        flag(usable), flag(noMana), GetActionCount(slot) or 0, flag(IsCurrentAction(slot)) }))
    end
    self:Send("STATE", { "cooldowns", self.actionPage, table.concat(rows, "\n") }, false)
  end
end

function B:SetView(section, page)
  local limits = { actions = 10, spells = 40, bags = 5, gear = 1, talents = 3, quests = 8, npc = 40 }
  if not limits[section] then return end
  page = integer(page, 1, limits[section])
  if not page then return end
  self.activeView, self.viewDirty = { section = section, page = page }, true
  if section == "actions" then self.actionPage, self.barDirty = page, true end
  -- Drop unsent state from the previous view. Commands/heartbeats use another queue.
  self.queueLow, self.lowIndex = {}, 1
end

function B:ActionLabel(slot)
  local label = GetActionText(slot)
  if label and label ~= "" then return label end
  if not self.scanTooltip and CreateFrame then
    self.scanTooltip = CreateFrame("GameTooltip", "zBoxScanTooltip", UIParent, "GameTooltipTemplate")
  end
  if self.scanTooltip and HasAction(slot) then
    self.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    self.scanTooltip:ClearLines()
    self.scanTooltip:SetAction(slot)
    local first = getglobal("zBoxScanTooltipTextLeft1")
    label = first and first:GetText()
    self.scanTooltip:Hide()
    if label and label ~= "" then return label end
  end
  return "Action " .. slot
end

function B:SendView(override)
  local view = override or self.activeView
  if not view then return end
  local section, page, rows, title, maximum, presentation = view.section, view.page, {}, "", 1, {}
  if section == "actions" then
    maximum, title = 10, "Account 2 action bar - page " .. page
    for slot = (page - 1) * 12 + 1, page * 12 do
      local start, duration, enabled = GetActionCooldown(slot)
      local remaining = self:Cooldown(start, duration, enabled)
      local usable, noMana = IsUsableAction(slot)
      table.insert(rows, self:Encode({ slot, GetActionTexture(slot) or "", self:ActionLabel(slot),
        self:ActionStamp(slot), GetActionCount(slot) or 0, flag(usable), flag(noMana),
        string.format("%.2f", remaining), duration or 0, flag(IsCurrentAction(slot)) }))
    end
  elseif section == "spells" then
    local total = 0
    for tab = 1, GetNumSpellTabs() do
      local _, _, offset, count = GetSpellTabInfo(tab)
      total = math.max(total, (offset or 0) + (count or 0))
    end
    maximum = math.max(1, math.ceil(total / 24))
    title = "Account 2 spellbook"
    for index = (page - 1) * 24 + 1, math.min(page * 24, total) do
      local name, rank = GetSpellName(index, BOOKTYPE_SPELL or "spell")
      local passive = IsPassiveSpell and IsPassiveSpell(index, BOOKTYPE_SPELL or "spell")
      table.insert(rows, self:Encode({ index, GetSpellTexture(index, BOOKTYPE_SPELL or "spell") or "",
        name or "", rank or "", self:SpellStamp(index), flag(passive) }))
    end
  elseif section == "bags" then
    local bag, size = page - 1, GetContainerNumSlots(page - 1) or 0
    maximum, title = 5, bag == 0 and "Account 2 backpack" or ("Account 2 bag " .. bag)
    presentation = { (GetBagName and GetBagName(bag)) or (bag == 0 and "Backpack" or ("Bag " .. bag)), size }
    for slot = 1, size do
      local icon, count, locked, quality = GetContainerItemInfo(bag, slot)
      local link = GetContainerItemLink(bag, slot)
      table.insert(rows, self:Encode({ bag, slot, icon or "", count or 0, flag(locked), quality or -1,
        link or "", self:ItemKey(link) }))
    end
  elseif section == "gear" then
    title = "Account 2 equipment"
    for slot = 0, 19 do
      local link = GetInventoryItemLink("player", slot)
      table.insert(rows, self:Encode({ slot, GetInventoryItemTexture("player", slot) or "", link or "",
        self:ItemKey(link) }))
    end
  elseif section == "talents" then
    maximum = GetNumTalentTabs() or 3
    local name, _, spent, background = GetTalentTabInfo(page)
    presentation = { background or "" }
    local points = UnitCharacterPoints and UnitCharacterPoints("player") or 0
    title = (name or "Talents") .. " - " .. (spent or 0) .. " spent, " .. (points or 0) .. " available"
    for index = 1, GetNumTalents(page) do
      local talentName, icon, tier, column, rank, maxRank, exceptional, meets = GetTalentInfo(page, index)
      table.insert(rows, self:Encode({ index, talentName or "", icon or "", tier or 1, column or 1,
        rank or 0, maxRank or 0, flag(meets) }))
    end
  elseif section == "quests" then
    rows, title, maximum = self:QuestView(page)
  elseif section == "npc" then
    rows, title, maximum = self:NPCView(page)
    presentation = self:NPCPresentation()
  end
  self.snapshotID = (self.snapshotID or 0) + 1
  self:Send("STATE", { "snapshot", section, page, self.snapshotID, title, maximum, table.concat(rows, "\n"), self:Encode(presentation) }, false)
  if section == "actions" then self.barDirty = false end
end

function B:AcceptState(fields)
  if fields[1] == "status" then
    if table.getn(fields) ~= 14 then return end
    self.cache.status = fields
  elseif fields[1] == "snapshot" then
    if (table.getn(fields) ~= 7 and table.getn(fields) ~= 8) or not integer(fields[4], 1, 2147483647) or
       not integer(fields[6], 1, 40) then return end
    local forView = fields[2] == self.view and tonumber(fields[3]) == self.page
    local forBar = fields[2] == "actions" and tonumber(fields[3]) == self.actionPage
    local forBag = fields[2] == "bags" and self.view == "bags" and integer(fields[3], 1, 5)
    if forBag then
      local previous = self.cache.bags and self.cache.bags[forBag]
      if previous and tonumber(fields[4]) <= previous.id then forBag = nil end
    end
    if not forView and not forBar and not forBag then return end
    if forView and tonumber(fields[4]) <= (self.lastSnapshotID or 0) then forView = false end
    if forBar and tonumber(fields[4]) <= (self.lastBarSnapshotID or 0) then forBar = false end
    if not forView and not forBar and not forBag then return end
    local rows = {}
    if fields[7] ~= "" then
      local encoded = self.Split(fields[7], "\n")
      if table.getn(encoded) > 48 then return end
      local minimum = { actions = 10, spells = 6, bags = 8, gear = 4, talents = 8, quests = 7, npc = 9 }
      local numeric = { actions = { 1, 5, 6, 7, 8, 9, 10 }, spells = { 1, 6 },
        bags = { 1, 2, 4, 5, 6 }, gear = { 1 }, talents = { 1, 4, 5, 6, 7, 8 }, quests = { 1, 4 }, npc = { 1, 7, 8, 9 } }
      if not minimum[fields[2]] then return end
      for i = 1, table.getn(encoded) do
        rows[i] = self:Decode(encoded[i])
        if table.getn(rows[i]) < minimum[fields[2]] or not tonumber(rows[i][1]) then return end
        for _, field in ipairs(numeric[fields[2]]) do if not tonumber(rows[i][field]) then return end end
      end
    end
    local snapshot = { section = fields[2], page = tonumber(fields[3]), title = fields[5],
      maximum = tonumber(fields[6]), rows = rows, id = tonumber(fields[4]), meta = fields[8] and self:Decode(fields[8]) or {} }
    if forBag then
      self.cache.bags = self.cache.bags or {}
      self.cache.bags[forBag] = snapshot
    end
    if forView then self.lastSnapshotID, self.cache.view = tonumber(fields[4]), snapshot end
    if forBar then self.lastBarSnapshotID, self.cache.bar = tonumber(fields[4]), snapshot end
    self.selection = nil
  elseif fields[1] == "questkeys" and table.getn(fields) == 2 then
    self.cache.questKeys = {}
    for _, encoded in ipairs(self.Split(fields[2], "\n")) do
      self.cache.questKeys[self:Decode(encoded)[1]] = true
    end
  elseif fields[1] == "cooldowns" then
    if table.getn(fields) ~= 3 then return end
    if tonumber(fields[2]) ~= self.actionPage then return end
    self.cache.cooldowns = { page = self.actionPage, at = GetTime(), rows = {} }
    local rows = self.Split(fields[3], "\n")
    if table.getn(rows) > 12 then return end
    for i = 1, table.getn(rows) do
      local row = self:Decode(rows[i])
      if table.getn(row) ~= 7 or not integer(row[1], 1, 120) or not tonumber(row[2]) then return end
      self.cache.cooldowns.rows[tonumber(row[1])] = row
    end
  elseif fields[1] == "cast" then
    if table.getn(fields) ~= 3 then return end
    local messages = { SPELLCAST_START = "Casting", SPELLCAST_STOP = "Cast finished",
      SPELLCAST_FAILED = "Cast failed", SPELLCAST_INTERRUPTED = "Cast interrupted" }
    local message = messages[fields[2]]
    if message then
      self.lastCastFeedbackAt = GetTime()
      self.notice = "Account 2: " .. message .. (fields[3] ~= "" and (" " .. fields[3]) or "")
    end
  elseif fields[1] == "diagnostics" then
    if table.getn(fields) == 2 then self:Print("Account 2: " .. fields[2]); self.notice = fields[2] end
  elseif fields[1] == "tooltip" then
    if table.getn(fields) ~= 5 then return end
    self.cache.tooltip = { section = fields[2], page = fields[3], index = fields[4], text = fields[5] }
    if self.UI then self.UI:RemoteTooltip() end
  end
end

function B:SendTooltip(section, page, index)
  local now = GetTime()
  if now - (self.lastTooltipAt or -10) < 0.25 then return end
  page, index = integer(page, 1, 40), integer(index, 1, 960)
  if not page or not index then return end
  if not self.scanTooltip then
    self.scanTooltip = CreateFrame("GameTooltip", "zBoxScanTooltip", UIParent, "GameTooltipTemplate")
  end
  local tip = self.scanTooltip
  tip:SetOwner(UIParent, "ANCHOR_NONE"); tip:ClearLines()
  if section == "actions" and index <= 120 then tip:SetAction(index)
  elseif section == "spells" then tip:SetSpell(index, BOOKTYPE_SPELL or "spell")
  elseif section == "talents" and page <= 3 and index <= GetNumTalents(page) then tip:SetTalent(page, index)
  else return end
  local lines = {}
  for line = 1, math.min(20, tip:NumLines() or 0) do
    local left, right = getglobal("zBoxScanTooltipTextLeft" .. line), getglobal("zBoxScanTooltipTextRight" .. line)
    local value = (left and left:GetText()) or ""
    local extra = right and right:GetText()
    if extra and extra ~= "" then value = value .. "   " .. extra end
    table.insert(lines, string.sub(value, 1, 300))
  end
  tip:Hide()
  self.lastTooltipAt = now
  self:Send("STATE", { "tooltip", section, page, index, table.concat(lines, "\n") }, false)
end

function B:ChooseTarget(descriptor)
  if descriptor == "KEEP" then return true end
  if descriptor == "SELF" then return self:Invoke("TargetUnit", "player") end
  if descriptor == "MAIN" then
    local unit = self:GroupUnit(self.db.peer)
    if unit then return self:Invoke("TargetUnit", unit) end
    return false, "Main character is not available"
  end
  -- Let the client apply the actual spell's target rules. Armor, mounts, etc.
  -- do not need an enemy; hostile spells report their normal missing-target error.
  if descriptor == "" or not descriptor then return self:Invoke("ClearTarget") end
  if not string.find(descriptor, "^0x%x+$") then return false, "Invalid target GUID" end
  if not UnitExists(descriptor) then return false, "That target is not loaded by account 2" end
  -- Use the client's Lua target API. The current zAPI setTarget command calls
  -- 0x493540 as fastcall(GUID*), but this client's setter consumes an eight-byte
  -- GUID from the stack and returns with ret 8. Entering that command can
  -- corrupt the caller's stack before the spell is even attempted.
  local ok, reason = self:Invoke("TargetUnit", descriptor)
  if not ok then return false, reason end
  local selected = self:GUID("target")
  if selected == "" or string.lower(selected) ~= string.lower(descriptor) then
    return false, "Account 2 could not select that target"
  end
  return true
end

function B:CursorBusy()
  return (CursorHasItem and CursorHasItem()) or (CursorHasSpell and CursorHasSpell()) or
    (CursorHasMoney and CursorHasMoney())
end

function B:ValidateBag(bag, slot, expected)
  bag, slot = integer(bag, 0, 4), integer(slot, 1, 36)
  if not bag or not slot or slot > GetContainerNumSlots(bag) then return nil, nil, "Invalid bag slot" end
  local _, _, locked = GetContainerItemInfo(bag, slot)
  if locked then return nil, nil, "Item is locked" end
  local key = self:ItemKey(GetContainerItemLink(bag, slot))
  if key == "" or key ~= expected then return nil, nil, "Bag contents changed; refresh and choose the item again" end
  return bag, slot
end

function B:Equip(bag, slot, expected, equipmentSlot, oldEquipment)
  if UnitAffectingCombat("player") then return false, "Change equipment outside combat" end
  if self:CursorBusy() then return false, "Account 2 already has something on its cursor" end
  local reason
  bag, slot, reason = self:ValidateBag(bag, slot, expected)
  if not bag then return false, reason end
  equipmentSlot = integer(equipmentSlot, 0, 19)
  if not equipmentSlot then return false, "Invalid equipment slot" end
  if oldEquipment ~= self:ItemKey(GetInventoryItemLink("player", equipmentSlot)) then
    return false, "Equipment changed; refresh and try again"
  end
  local ok, detail = self:Invoke("PickupContainerItem", bag, slot)
  if not ok then return false, detail end
  ok, detail = self:Invoke("EquipCursorItem", equipmentSlot)
  -- If equipping swapped an item onto the cursor, put it in the original bag
  -- slot. Invalid equips also return the original item instead of stranding it.
  if CursorHasItem and CursorHasItem() then self:Invoke("PickupContainerItem", bag, slot) end
  return ok, detail or "Equip requested; account 2 may need to confirm a bind-on-equip dialog"
end

function B:Unequip(slot, expected)
  if UnitAffectingCombat("player") or self:CursorBusy() then return false, "Leave combat and clear account 2's cursor first" end
  slot = integer(slot, 0, 19)
  if not slot or expected == "" or self:ItemKey(GetInventoryItemLink("player", slot)) ~= expected then
    return false, "Equipment changed; refresh and try again"
  end
  -- Only the backpack accepts every ordinary item; special-purpose bags are
  -- deliberately not guessed. No empty backpack slot means no item is picked up.
  for destination = 1, GetContainerNumSlots(0) do
    if not GetContainerItemLink(0, destination) then
      local ok, reason = self:Invoke("PickupInventoryItem", slot)
      if not ok then return false, reason end
      ok, reason = self:Invoke("PickupContainerItem", 0, destination)
      if CursorHasItem and CursorHasItem() then self:Invoke("PickupInventoryItem", slot) end
      return ok, reason or "Unequip requested"
    end
  end
  return false, "Make room in account 2's backpack first"
end

function B:Execute(fields)
  local command = fields[1]
  if command == "STOP" then
    local stopped, reason = self:StopMovement(nil, true)
    self:Invoke("SpellStopCasting")
    if SpellStopTargeting then self:Invoke("SpellStopTargeting") end
    if AttackTarget and IsCurrentSpell and IsCurrentSpell("Attack") then self:Invoke("AttackTarget") end
    return stopped, stopped and "Stopped movement and casting" or reason
  elseif command == "FOLLOW" then
    local unit = self:GroupUnit(self.db.peer)
    if not unit then return false, "Main character is unavailable" end
    self:StopMovement()
    local ok, detail = self:Invoke("FollowUnit", unit)
    self.following = ok
    return ok, detail or "Follow requested"
  elseif command == "PET" then
    return self:ReceivePet(fields[2],fields[3],fields[4])
  elseif command == "TALK" then
    return self:TalkToNPC(fields[2])
  elseif command == "NPC" then
    return self:NPCAction(fields[2], fields[3], fields[4])
  elseif command == "ASSIST" then
    local unit = self:GroupUnit(self.db.peer)
    if not unit then return false, "Main character is unavailable" end
    return self:Invoke("AssistUnit", unit)
  elseif command == "MOVETO" then
    if fields[5] ~= ((GetRealZoneText and GetRealZoneText()) or "") then return false, "Both characters must be in the same zone" end
    return self:BeginMove(fields[2], fields[3], fields[4])
  elseif command == "AXIS" then
    return self:Manual(fields[2], fields[3] == "1")
  elseif command == "AXES" then
    return self:ManualAxes(fields[2])
  elseif command == "MIRROR" then
    return self:AcceptMirror(fields[2], fields[3], fields[4])
  elseif command == "JUMP" then
    if fields[2] == "mirror" and self:IsCastHeld(GetTime()) then return true, "Jump skipped while casting" end
    return self:Invoke("Jump")
  elseif command == "ACTION" then
    local slot = integer(fields[2], 1, 120)
    if not slot or not HasAction(slot) then return false, "This action slot is empty" end
    if fields[3] ~= self:ActionStamp(slot) then return false, "Action bar changed; refresh before clicking again" end
    return self:RequestCast(command, slot, fields[3], fields[4])
  elseif command == "SPELL" then
    local index = integer(fields[2], 1, 960)
    if not index or fields[3] ~= self:SpellStamp(index) then return false, "Spellbook changed; refresh first" end
    if IsPassiveSpell and IsPassiveSpell(index, BOOKTYPE_SPELL or "spell") then return false, "This spell is passive" end
    return self:RequestCast(command, index, fields[3], fields[4])
  elseif command == "USEITEM" then
    if self:CursorBusy() then return false, "Clear account 2's cursor first" end
    local bag, slot, reason = self:ValidateBag(fields[2], fields[3], fields[4])
    if not bag then return false, reason end
    return self:Invoke("UseContainerItem", bag, slot)
  elseif command == "EQUIP" then
    return self:Equip(fields[2], fields[3], fields[4], fields[5], fields[6])
  elseif command == "UNEQUIP" then
    return self:Unequip(fields[2], fields[3])
  elseif command == "TALENT" then
    local tab, index, expected = integer(fields[2], 1, 3), integer(fields[3], 1, 40), integer(fields[4], 0, 10)
    if not tab or not index or not expected or index > GetNumTalents(tab) then return false, "Invalid talent" end
    local name, _, _, _, rank, maxRank = GetTalentInfo(tab, index)
    if not name or rank ~= expected then return false, "Talent rank changed; refresh before spending another point" end
    if rank >= maxRank then return false, "Talent is already at its maximum rank" end
    local points = UnitCharacterPoints and UnitCharacterPoints("player") or 0
    if points < 1 then return false, "No talent points available" end
    if UnitAffectingCombat("player") then return false, "Spend talents outside combat" end
    return self:Invoke("LearnTalent", tab, index)
  end
  return false, "Unknown command"
end
