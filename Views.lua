-- Presentation for the remote character. All actions still use UI.lua's
-- existing handlers and the agent's live item/dialog fingerprints.
local B, U = zBox, zBox.UI
local frameBackdrop = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local slots = { [0] = "AmmoSlot", "HeadSlot", "NeckSlot", "ShoulderSlot", "ShirtSlot", "ChestSlot",
  "WaistSlot", "LegsSlot", "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot",
  "Trinket0Slot", "Trinket1Slot", "BackSlot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot", "TabardSlot" }
local slotNames = { [0] = "Ammo", "Head", "Neck", "Shoulders", "Shirt", "Chest", "Waist", "Legs", "Feet",
  "Wrists", "Hands", "Ring", "Ring", "Trinket", "Trinket", "Back", "Main hand", "Off hand", "Ranged", "Tabard" }

local function text(parent, size, x, y, width, height, dark)
  local f = parent:CreateFontString(nil, "OVERLAY")
  f:SetFont("Fonts\\FRIZQT__.TTF", size)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  f:SetWidth(width); f:SetHeight(height); f:SetJustifyH("LEFT"); f:SetJustifyV("TOP")
  if dark then f:SetTextColor(0.22, 0.13, 0.07) else f:SetTextColor(0.88, 0.76, 0.48) end
  return f
end

local function panel(parent, x, y, width, height, parchment)
  local f = CreateFrame("Frame", nil, parent)
  f:SetFrameLevel(parent:GetFrameLevel() + 1)
  f:SetWidth(width); f:SetHeight(height); f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  f:SetBackdrop(frameBackdrop); f:SetBackdropColor(0.055, 0.055, 0.065, 1)
  f:SetBackdropBorderColor(0.4, 0.33, 0.2, 1)
  if parchment then
    f.paper = f:CreateTexture(nil, "BACKGROUND")
    f.paper:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    f.paper:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    f.paper:SetTexture("Interface\\QuestFrame\\UI-QuestGreeting-TopLeft")
    f.paper:SetTexCoord(0.12, 0.98, 0.36, 0.98)
  end
  return f
end

local function smallButton(parent, caption, x, y, width, callback)
  local f = CreateFrame("Button", nil, parent)
  f:SetFrameLevel(parent:GetFrameLevel() + 1)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); f:SetWidth(width); f:SetHeight(23)
  f:SetBackdrop(frameBackdrop); f:SetBackdropColor(0.10, 0.09, 0.07, 1)
  f.caption = text(f, 10, 3, -5, width-6, 14)
  f.caption:SetJustifyH("CENTER"); f.caption:SetText(caption)
  f:SetScript("OnClick", callback)
  f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  return f
end

local function scrolling(parent, x, y, width, height)
  local scroll = CreateFrame("ScrollFrame", nil, parent)
  scroll:SetFrameLevel(parent:GetFrameLevel() + 1)
  scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  scroll:SetWidth(width); scroll:SetHeight(height); scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  child:SetWidth(width); child:SetHeight(height)
  scroll:SetScrollChild(child); scroll.body = child
  local function move(delta)
    scroll:SetVerticalScroll(math.max(0, math.min(scroll.maxScroll or 0, scroll:GetVerticalScroll() + delta)))
  end
  scroll:SetScript("OnMouseWheel", function() move(-arg1 * 36) end)
  scroll.up = smallButton(parent, "^", x+width+2, y, 18, function() move(-72) end)
  scroll.down = smallButton(parent, "v", x+width+2, y-height+23, 18, function() move(72) end)
  return scroll
end

local function fitScroll(scroll, height, identity)
  scroll.body:SetHeight(math.max(height, scroll:GetHeight()))
  scroll.maxScroll = math.max(0, height-scroll:GetHeight())
  if scroll.identity ~= identity then scroll:SetVerticalScroll(0); scroll.identity = identity end
  scroll:SetVerticalScroll(math.min(scroll.maxScroll, scroll:GetVerticalScroll()))
  if scroll.maxScroll > 0 then scroll.up:Show(); scroll.down:Show() else scroll.up:Hide(); scroll.down:Hide() end
end

local function measured(fontString, value, width, size)
  fontString:SetHeight(4000)
  fontString:SetText(value)
  local height = fontString:GetStringHeight()
  if type(height) == "number" and height > 0 then return height + 4 end
  local lines = 0
  for _, line in ipairs(B.Split(value, "\n")) do lines = lines + math.max(1, math.ceil(string.len(line) / math.max(1, width/(size*0.55)))) end
  return lines * (size+3)
end

function U:CreateCharacterViews()
  self.characterViews, self.bagWindows = {}, {}
  self.bookView = panel(self.content, 0, 0, 472, 382, true)
  local spine = self.bookView:CreateTexture(nil, "ARTWORK")
  spine:SetTexture(0.35, 0.23, 0.10, 0.3); spine:SetWidth(2); spine:SetHeight(360)
  spine:SetPoint("TOPLEFT", self.bookView, "TOPLEFT", 235, -10)
  self.gearView = panel(self.content, 0, 0, 472, 360)
  self.gearName = text(self.gearView, 15, 80, -10, 312, 20); self.gearName:SetJustifyH("CENTER")
  self.gearInfo = text(self.gearView, 10, 80, -34, 312, 16); self.gearInfo:SetJustifyH("CENTER")
  self.gearModel = CreateFrame("PlayerModel", nil, self.gearView)
  self.gearModel:SetPoint("TOPLEFT", self.gearView, "TOPLEFT", 100, -54)
  self.gearModel:SetWidth(272); self.gearModel:SetHeight(248)
  self.gearModel:EnableMouse(false)
  self.gearHint = text(self.gearView, 9, 98, -303, 276, 14); self.gearHint:SetJustifyH("CENTER")
  self.gearHint:SetText("Equipment on account 2")
  self.talentView = panel(self.content, 0, 0, 472, 354)
  self.talentArt = {}
  for i = 1, 4 do
    local art = self.talentView:CreateTexture(nil, "BACKGROUND")
    art:SetWidth(232); art:SetHeight(173)
    art:SetPoint("TOPLEFT", self.talentView, "TOPLEFT", 4+math.mod(i-1,2)*232, -4-math.floor((i-1)/2)*173)
    art:SetVertexColor(0.55, 0.55, 0.55)
    self.talentArt[i] = art
  end
  self.questView = panel(self.content, 0, 0, 472, 342, true)
  self.questList = panel(self.questView, 6, -6, 184, 330)
  self.questHeading = text(self.questList, 11, 10, -9, 164, 20)
  self.questHeading:SetText("Quest log")
  self.questScroll = scrolling(self.questView, 202, -12, 238, 316)
  self.questDetailTitle = text(self.questScroll.body, 15, 0, 0, 234, 42, true)
  self.questDetailText = text(self.questScroll.body, 11, 0, -50, 234, 800, true)
  self.npcView = panel(self.content, 0, 0, 472, 364, true)
  self.npcScroll = scrolling(self.npcView, 16, -12, 416, 338)
  self.npcHeading = text(self.npcScroll.body, 16, 0, 0, 412, 24, true)
  self.npcQuestTitle = text(self.npcScroll.body, 13, 0, -30, 412, 34, true)
  self.npcDialogue = text(self.npcScroll.body, 12, 0, -56, 412, 3000, true)
  self.bagView = panel(self.content, 0, 0, 472, 42)
  self.bagButtons = {}
  for page = 1, 5 do
    local b = smallButton(self.bagView, page == 1 and "Backpack" or ("Bag " .. (page-1)), 6+(page-1)*93, -8, 89, function()
      U:ToggleBag(this.bagPage)
    end)
    b.bagPage = page; self.bagButtons[page] = b
  end
  self.characterViews = { self.bookView, self.gearView, self.talentView, self.questView, self.npcView, self.bagView }
  self.browser:SetScript("OnHide", function() GameTooltip:Hide(); U.hovered = nil end)
end

function U:CharacterViewHeight(view, fallback)
  if B.view == "bags" then
    local height = 180
    for page = 1, 5 do
      if (self.bagOpen and self.bagOpen[page]) or page == B.page then
        local bag = B.cache.bags and B.cache.bags[page]
        height = math.max(height, 98+math.floor((page-1)/3)*185+math.ceil((bag and table.getn(bag.rows) or 16)/4)*35)
      end
    end
    return height
  end
  local heights = { actions = 62, spells = 382, gear = 360, talents = 354, quests = 342, npc = 364 }
  return heights[B.view] or fallback
end

function U:ResetCharacterViews()
  for _, f in ipairs(self.characterViews) do f:Hide() end
  for page, f in pairs(self.bagWindows) do
    if B.view ~= "bags" or not self.bagOpen or not self.bagOpen[page] then f:Hide() end
  end
  for _, cell in ipairs(self.cells) do
    cell:Hide(); cell.row = nil
    cell:SetParent(self.content); cell:SetFrameLevel(self.content:GetFrameLevel()+4)
    cell:SetBackdrop(nil)
    cell:SetHighlightTexture("")
    cell.icon:Show()
    cell.icon:ClearAllPoints(); cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
    cell.icon:SetWidth(32); cell.icon:SetHeight(32)
    cell.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    cell.border:Show(); cell.name:Show(); cell.sub:Show()
    cell.name:SetTextColor(0.9, 0.9, 0.85); cell.sub:SetTextColor(0.55, 0.7, 0.78)
    cell.name:SetFont("Fonts\\FRIZQT__.TTF", 10)
    cell.name:ClearAllPoints(); cell.name:SetPoint("TOPLEFT", cell, "TOPLEFT", 38, -2)
    cell.count:ClearAllPoints(); cell.count:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -21)
    cell.count:SetWidth(30)
    cell.count:SetTextColor(1, 1, 1)
  end
end

function U:PlaceViewCell(cell, parent, x, y, width, height)
  cell:SetParent(parent); cell:SetFrameLevel(parent:GetFrameLevel()+4)
  cell:ClearAllPoints(); cell:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  cell:SetWidth(width); cell:SetHeight(height)
end

function U:RenderGear(view)
  self.gearView:Show()
  local status = B.cache.status
  self.gearName:SetText(B.db.peer or "Account 2")
  self.gearInfo:SetText(status and ("Level " .. status[3] .. " " .. status[4]) or "")
  local unit = B.connected and B:PeerUnit()
  if unit and (not UnitIsVisible or UnitIsVisible(unit)) then
    if self.gearModelUnit ~= unit or self.gearModelSnapshot ~= view.id then
      self.gearModel:SetUnit(unit); self.gearModel:SetRotation(0.4)
      self.gearModelUnit, self.gearModelSnapshot = unit, view.id
    end
    self.gearModel:Show(); self.gearHint:SetText("Equipment on account 2")
  else self.gearModel:Hide(); self.gearHint:SetText("Move account 2 nearby for its character preview") end
  local positions = {}
  for index, slot in ipairs({1,2,3,15,5,4,19,9}) do positions[slot] = {12, -12-(index-1)*37} end
  for index, slot in ipairs({10,6,7,8,11,12,13,14}) do positions[slot] = {428, -12-(index-1)*37} end
  for index, slot in ipairs({16,17,18,0}) do positions[slot] = {162+(index-1)*40, -324} end
  for i, row in ipairs(view.rows) do
    local cell, slot = self.cells[i], tonumber(row[1])
    local position = positions[slot]
    if position then
      self:RenderCell(cell, row, i, "gear")
      self:PlaceViewCell(cell, self.gearView, position[1], position[2], 32, 32)
      cell.name:Hide(); cell.sub:Hide(); cell.tooltip = slotNames[slot]
      if row[2] == "" and GetInventorySlotInfo and slots[slot] then
        local _, texture = GetInventorySlotInfo(slots[slot])
        if texture then cell.icon:SetTexture(texture) end
        cell.icon:SetVertexColor(0.55, 0.55, 0.55)
      end
    end
  end
end

function U:RenderQuests(view)
  self.questView:Show()
  self.questHeading:SetText(self.questMainOnly and "Main's quest log" or "Account 2's quest log")
  local selected = view.rows[1]
  for _, row in ipairs(view.rows) do if row[2] == self.questSelected then selected = row end end
  for i, row in ipairs(view.rows) do
    local cell = self.cells[i]
    self:RenderCell(cell, row, i, "quests")
    self:PlaceViewCell(cell, self.questList, 7, -34-(i-1)*56, 170, 52)
    cell.icon:Hide(); cell.border:Hide()
    cell.name:ClearAllPoints(); cell.name:SetPoint("TOPLEFT", cell, "TOPLEFT", 6, -5)
    cell.name:SetWidth(158); cell.name:SetHeight(28)
    cell.name:SetText("[" .. row[4] .. "] " .. row[3])
    cell.sub:ClearAllPoints(); cell.sub:SetPoint("TOPLEFT", cell, "TOPLEFT", 6, -35)
    cell.sub:SetWidth(158); cell.sub:SetHeight(14); cell.sub:SetText(row[5])
    cell:SetBackdrop(frameBackdrop)
    cell:SetBackdropColor(row == selected and 0.23 or 0.07, row == selected and 0.18 or 0.07, 0.07, 1)
  end
  if not selected then self.questDetailTitle:SetText("No quests"); self.questDetailText:SetText(""); return end
  self.questSelected = selected[2]
  self.questDetailTitle:SetText(selected[3])
  local value = (selected[6] ~= "" and (selected[6] .. "\n\n") or "") .. "Objectives\n" ..
    (selected[7] ~= "" and selected[7] or selected[5]) .. "\n\n" ..
    (self.questMainOnly and "Account 2: not in quest log" or B:QuestComparison(selected))
  local height = measured(self.questDetailText, value, 234, 11)
  self.questDetailText:SetHeight(height)
  fitScroll(self.questScroll, 54+height, selected[2])
end

function U:RenderNPC(view)
  self.npcView:Show()
  local meta, scroll = view.meta or {}, self.npcScroll
  self.npcHeading:SetText(meta[2] or view.title)
  self.npcQuestTitle:SetText(meta[3] or "")
  local value = meta[4] or ""
  if meta[5] and meta[5] ~= "" then value = value .. "\n\nObjectives\n" .. meta[5] end
  if value == "" and table.getn(view.rows) == 0 then value = "Target an NPC and click Talk. Account 2 must be within interaction range." end
  local top = meta[3] and meta[3] ~= "" and 70 or 34
  self.npcDialogue:ClearAllPoints(); self.npcDialogue:SetPoint("TOPLEFT", scroll.body, "TOPLEFT", 0, -top)
  local height = value ~= "" and measured(self.npcDialogue, value, 412, 12) or 0
  self.npcDialogue:SetText(value); self.npcDialogue:SetHeight(math.max(1, height))
  local y = top + height + 14
  for i, row in ipairs(view.rows) do
    local cell = self.cells[i]
    self:RenderCell(cell, row, i, "npc")
    local merchant = row[6] == "buy" or row[6] == "train" or row[6] == "reward"
    local rowHeight = merchant and 48 or 32
    self:PlaceViewCell(cell, scroll.body, 2, -y, 410, rowHeight)
    cell.name:SetTextColor(0.23, 0.12, 0.04); cell.sub:SetTextColor(0.34, 0.24, 0.12)
    cell.name:SetWidth(366); cell.name:SetHeight(16)
    cell.sub:SetWidth(366); cell.sub:SetHeight(27)
    cell.border:Hide()
    if row[6] == "accept" then cell.name:SetText("Accept quest"); cell.sub:SetText("")
    elseif row[6] == "complete" then cell.name:SetText("Continue"); cell.sub:SetText("")
    elseif row[6] == "close" then cell.name:SetText("Goodbye"); cell.sub:SetText("")
    elseif not merchant then cell.sub:SetText("") end
    if not merchant then
      cell.icon:SetWidth(20); cell.icon:SetHeight(20)
      cell.icon:SetTexture((row[6] == "available" or row[6] == "gossipAvailable") and "Interface\\GossipFrame\\AvailableQuestIcon" or
        ((row[6] == "active" or row[6] == "gossipActive") and "Interface\\GossipFrame\\ActiveQuestIcon" or row[2]))
      cell.name:ClearAllPoints(); cell.name:SetPoint("TOPLEFT", cell, "TOPLEFT", 28, -4)
    end
    if row[9] == "0" then cell.name:SetTextColor(0.45, 0.40, 0.32) end
    cell:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    y = y + rowHeight + 4
  end
  fitScroll(scroll, y+8, (meta[1] or "") .. ":" .. (meta[2] or "") .. ":" .. (meta[3] or "") .. ":" .. tostring(view.page) .. ":" .. B:Fingerprint(value))
end

function U:ToggleBag(page)
  self.bagOpen = self.bagOpen or { [1] = true }
  self.bagOpen[page] = not self.bagOpen[page]
  if self.bagOpen[page] then B:Request("bags", page) end
  self:Refresh()
end

function U:CreateBagWindow(page)
  local f = panel(self.browser, 0, 0, 154, 220)
  f:SetFrameLevel(self.browser:GetFrameLevel()+6)
  f.bagPage, f.cells = page, {}
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true); f:RegisterForDrag("LeftButton")
  f.title = text(f, 10, 10, -10, 113, 22)
  f.close = smallButton(f, "x", 128, -5, 20, function()
    U.bagOpen[page] = false; f:Hide(); U:Refresh()
  end)
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local point, _, relative, x, y = this:GetPoint()
    if point and relative and x and y then
      B.db.bagPositions = B.db.bagPositions or {}
      B.db.bagPositions[page] = { point, relative, x, y }
    end
  end)
  local position = B.db.bagPositions and B.db.bagPositions[page]
  f:ClearAllPoints()
  if position then f:SetPoint(position[1], UIParent, position[2], position[3], position[4])
  else f:SetPoint("TOPLEFT", self.content, "TOPLEFT", math.mod(page-1,3)*158, -50-math.floor((page-1)/3)*185) end
  for i = 1, 36 do
    local cell = self:CreateCell(100+page*40+i, f)
    cell:SetPoint("TOPLEFT", f, "TOPLEFT", 8+math.mod(i-1,4)*35, -38-math.floor((i-1)/4)*35)
    cell:SetWidth(32); cell:SetHeight(32)
    cell.name:Hide(); cell.sub:Hide()
    f.cells[i] = cell
  end
  self.bagWindows[page] = f
  return f
end

function U:RenderBags(view)
  self.bagView:Show()
  self.bagOpen = self.bagOpen or { [1] = true }
  if self.lastCharacterView ~= "bags" then self.bagOpen[view.page] = true end
  self.bagOpen[view.page] = self.bagOpen[view.page] ~= false
  for page = 1, 5 do
    self.bagButtons[page].caption:SetTextColor(self.bagOpen[page] and 1 or 0.55, self.bagOpen[page] and 0.82 or 0.55, 0.45)
    if self.bagOpen[page] then
      local bag = B.cache.bags and B.cache.bags[page]
      local f = self.bagWindows[page] or self:CreateBagWindow(page)
      f.title:SetText(bag and ((bag.meta and bag.meta[1]) or bag.title) or (page == 1 and "Backpack" or ("Bag " .. (page-1))))
      f:Show()
      local size = bag and table.getn(bag.rows) or 0
      f:SetHeight(44+math.max(1, math.ceil(size/4))*35)
      for i, cell in ipairs(f.cells) do
        local row = bag and bag.rows[i]
        if row then
          cell.row, cell.section, cell.tooltip = row, "bags", "Empty slot"
          cell.icon:SetTexture(row[3] ~= "" and row[3] or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
          cell.count:SetText(tonumber(row[4]) > 1 and row[4] or "")
          cell.cooldown:SetText(""); cell:Show()
          cell.icon:SetVertexColor(row[5] == "1" and 0.5 or 1, row[5] == "1" and 0.5 or 1, row[5] == "1" and 0.5 or 1)
          local quality = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[tonumber(row[6])]
          local selected = B.bagSelection and tostring(B.bagSelection.bag) == row[1] and tostring(B.bagSelection.slot) == row[2]
          if selected then cell.border:SetTexture(0.3, 1, 0.75, 1)
          elseif quality and row[8] ~= "" then cell.border:SetTexture(quality.r, quality.g, quality.b, 1)
          else cell.border:SetTexture(0.2, 0.22, 0.25, 1) end
        else cell.row = nil; cell:Hide() end
      end
      if not bag then f.title:SetText("Loading bag...") end
    end
  end
end

function U:RenderCharacterView(view)
  local section = view.section
  if section == "gear" then self:RenderGear(view)
  elseif section == "quests" then self:RenderQuests(view)
  elseif section == "npc" then self:RenderNPC(view)
  elseif section == "bags" then self:RenderBags(view)
  elseif section == "spells" or section == "talents" or section == "actions" then
    local parent = self.content
    if section == "spells" then self.bookView:Show(); parent = self.bookView
    elseif section == "talents" then
      self.talentView:Show(); parent = self.talentView
      local suffixes = { "-TopLeft", "-TopRight", "-BottomLeft", "-BottomRight" }
      for i, art in ipairs(self.talentArt) do
        if view.meta and view.meta[1] and view.meta[1] ~= "" then art:SetTexture("Interface\\TalentFrame\\" .. view.meta[1] .. suffixes[i]); art:Show() else art:Hide() end
      end
    end
    for i, row in ipairs(view.rows) do
      local cell = self.cells[i]
      self:RenderCell(cell, row, i, section)
      if section == "spells" then
        self:PlaceViewCell(cell, parent, 12+math.floor((i-1)/12)*236, -12-math.mod(i-1,12)*30, 220, 28)
        cell.icon:SetWidth(24); cell.icon:SetHeight(24)
        cell.name:ClearAllPoints(); cell.name:SetPoint("TOPLEFT", cell, "TOPLEFT", 32, -1)
        cell.name:SetWidth(180); cell.name:SetHeight(14); cell.name:SetTextColor(0.22, 0.13, 0.07)
        cell.sub:ClearAllPoints(); cell.sub:SetPoint("TOPLEFT", cell, "TOPLEFT", 32, -15)
        cell.sub:SetWidth(180); cell.sub:SetHeight(12); cell.sub:SetTextColor(0.42, 0.31, 0.17)
      elseif section == "talents" then
        self:PlaceViewCell(cell, parent, 46+(tonumber(row[5])-1)*112, -12-(tonumber(row[4])-1)*47, 36, 36)
        cell.name:Hide(); cell.sub:Hide()
        cell.icon:SetWidth(36); cell.icon:SetHeight(36)
        cell.count:SetTextColor(tonumber(row[6]) == tonumber(row[7]) and 1 or 0.3, 1, 0.3)
      else
        self:PlaceViewCell(cell, parent, 8+(i-1)*38, -10, 32, 32)
        cell.name:Hide(); cell.sub:Hide()
      end
    end
  else return false end
  self.lastCharacterView = section
  return true
end

function U:CharacterViewsTick(now)
  if self.bagAwaiting then
    local bag = B.cache.bags and B.cache.bags[self.bagAwaiting.page]
    if (bag and bag.id > self.bagAwaiting.id) or now-self.bagAwaiting.at > 8 then self.bagAwaiting = nil end
  end
  if B.connected and B.view == "bags" and self.browser:IsShown() and now-(self.lastBagPoll or -10) >= 1.2 then
    if self.bagAwaiting then return end
    self.lastBagPoll = now
    self.bagPollPage = math.mod(self.bagPollPage or 0,5)+1
    for _ = 1, 5 do
      if self.bagOpen and self.bagOpen[self.bagPollPage] then
        local bag = B.cache.bags and B.cache.bags[self.bagPollPage]
        if B:Send("BAG", { self.bagPollPage }, false) then self.bagAwaiting = { page = self.bagPollPage, id = bag and bag.id or 0, at = now } end
        break
      end
      self.bagPollPage = math.mod(self.bagPollPage,5)+1
    end
  end
end
