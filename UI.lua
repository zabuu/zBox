local B = zBox
local U = { cells = {}, lastTick = 0 }
B.UI = U
local backdrop = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 } }
local equipment = { [0] = "Ammo", "Head", "Neck", "Shoulders", "Shirt", "Chest", "Waist", "Legs",
  "Feet", "Wrists", "Hands", "Finger 1", "Finger 2", "Trinket 1", "Trinket 2", "Back",
  "Main hand", "Off hand", "Ranged", "Tabard" }

local function label(parent, text, size, x, y, width)
  local f = parent:CreateFontString(nil, "OVERLAY")
  f:SetFont("Fonts\\FRIZQT__.TTF", size or 11)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if width then f:SetWidth(width) end
  f:SetJustifyH("LEFT")
  f:SetText(text)
  return f
end

local function button(parent, caption, x, y, width, handler)
  local f = CreateFrame("Button", nil, parent)
  f:SetFrameLevel(parent:GetFrameLevel() + 1)
  f:SetWidth(width or 85); f:SetHeight(25)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  f:SetBackdrop(backdrop); f:SetBackdropColor(0.09, 0.13, 0.18, 1)
  f:SetBackdropBorderColor(0.25, 0.45, 0.49, 1)
  local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("CENTER", f, "CENTER", 0, 0); text:SetText(caption)
  f.caption = text
  f:SetScript("OnClick", handler)
  f:SetScript("OnEnter", function() this:SetBackdropColor(0.13, 0.24, 0.29, 1) end)
  f:SetScript("OnLeave", function() this:SetBackdropColor(0.09, 0.13, 0.18, 1) end)
  return f
end

local function edit(parent, name, x, y, width)
  local f = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
  f:SetFrameLevel(parent:GetFrameLevel() + 1)
  f:SetWidth(width); f:SetHeight(24); f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  f:SetAutoFocus(false); f:SetMaxLetters(48)
  f:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  f:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  return f
end

local function compactButton(parent, caption, x, y, width, handler)
  local f = button(parent, caption, x, y, width, handler)
  f:SetHeight(20)
  return f
end

function U:SetScale(value)
  value = tonumber(value)
  if not value or value ~= value or value < 0.55 or value > 1.25 then
    return false, "Use /zbox scale 0.55 to 1.25; /zbox scale reset restores 85%."
  end
  B.db.uiScale = value
  self.frame:SetScale(value)
  if self.restoreButton then self.restoreButton:SetScale(value) end
  if self.pad then self.pad:SetScale(value) end
  if self.scaleLabel then self.scaleLabel:SetText(string.format("%.0f%%", value * 100)) end
  self:PlacePanels()
  return true
end

function U:PlacePanel(panel, right)
  if not panel then return end
  local scale = self.frame:GetEffectiveScale()
  local top, bottom = self.frame:GetTop(), self.frame:GetBottom()
  if not top or not bottom then return end
  local screen = UIParent:GetHeight() * UIParent:GetEffectiveScale()
  local above, below = math.max(0, screen - top * scale - 5 * scale), math.max(0, bottom * scale - 5 * scale)
  local height = panel:GetHeight() * scale
  local down = above < height and below > above
  local room = down and below or above
  local panelScale = math.min(1, room / math.max(1, height))
  local previous = panel.zBoxPlacement
  if previous and previous.down == down and previous.right == right and math.abs(previous.scale - panelScale) < 0.0001 then return end
  panel.zBoxPlacement = { down = down, right = right, scale = panelScale }
  panel:SetScale(panelScale)
  panel:ClearAllPoints()
  local edge = right and "RIGHT" or "LEFT"
  panel:SetPoint((down and "TOP" or "BOTTOM") .. edge, self.frame, (down and "BOTTOM" or "TOP") .. edge, 0, down and -5 or 5)
  -- Frame levels are assigned before controls are created. Raising an existing
  -- panel does not raise its children in 1.12, so its background would eat clicks.
end

function U:PlacePanels()
  if not self.frame then return end
  self:PlacePanel(self.browser)
  self:PlacePanel(self.setup)
  self:PlacePanel(self.keys, true)
end

function U:Run(command, fields)
  local ok, reason = B:Command(command, fields)
  if not ok then B:Notify(reason) end
end

function U:Create()
  if self.frame then return end
  local f = CreateFrame("Frame", "zBoxPanel", UIParent)
  self.frame = f
  f:SetWidth(496); f:SetHeight(110)
  local pos = B.db.position
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 140) end
  f:SetFrameStrata("DIALOG"); f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:SetBackdrop(backdrop); f:SetBackdropColor(0.025, 0.035, 0.045, 0.95)
  f:SetBackdropBorderColor(0.16, 0.25, 0.28, 1)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local point, _, relative, x, y = this:GetPoint()
    if point and relative and x and y then B.db.position = { point, relative, x, y } end
    U:PlacePanels()
  end)
  f:SetScript("OnHide", function()
    U:CancelMove(); U:ReleaseAxis()
    U.browser:Hide(); U.pad:Hide(); U.setup:Hide(); U.keys:Hide()
    U:UpdateVisibility()
  end)
  f:SetScript("OnShow", function() U:UpdateVisibility() end)
  table.insert(UISpecialFrames, "zBoxPanel")
  label(f, "zBox", 11, 12, -8, 36):SetTextColor(0.35, 0.9, 0.8)
  self.connection = label(f, "Not paired", 10, 52, -9, 250)
  compactButton(f, "More", 310, -4, 52, function() U:ToggleBrowser() end)
  compactButton(f, "Keys", 366, -4, 44, function() U:ShowKeys() end)
  compactButton(f, "Setup", 414, -4, 48, function() U:ShowSetup() end)
  self.closeButton = compactButton(f, "x", 466, -4, 18, function() U:Minimize() end)
  self.closeButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText(B.connected and "Minimize zBox" or "Close zBox")
    if B.connected then GameTooltip:AddLine("A zBox + button stays visible while linked.", 0.7, 0.9, 0.85, true) end
    GameTooltip:Show()
  end)
  self.closeButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.restoreButton = compactButton(UIParent, "zBox  +", 0, 0, 84, function() U:Restore() end)
  self.restoreButton:SetFrameStrata("DIALOG"); self.restoreButton:SetClampedToScreen(true)
  self.restoreButton:SetHeight(24)
  self.restoreButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP"); GameTooltip:SetText("Restore zBox")
    GameTooltip:AddLine("Linked to " .. (B.db.peer or "account 2") .. ". Click to expand the panel.", 0.7, 0.9, 0.85, true)
    GameTooltip:Show()
  end)
  self.restoreButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.restoreButton:Hide()
  self.health = label(f, "Account 2 is not connected", 9, 12, -28, 252)
  self.power = label(f, "", 9, 416, -28, 68)
  self.power:SetJustifyH("RIGHT")
  self.target = label(f, "Target: --", 9, 272, -28, 140)
  self.target:SetHeight(12)
  self.inputMode = label(f, "", 9, 416, -28, 68)
  self.inputMode:SetJustifyH("RIGHT"); self.inputMode:SetTextColor(0.45, 0.6, 0.64)
  self.strip = CreateFrame("Frame", nil, f)
  self.strip:SetWidth(472); self.strip:SetHeight(34)
  self.strip:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -45)
  self.dockCells = {}
  for i = 1, 12 do
    local cell = self:CreateCell(i, self.strip, true)
    cell:SetPoint("TOPLEFT", self.strip, "TOPLEFT", (i - 1) * 40, 0)
    self.dockCells[i] = cell
  end
  compactButton(f, "<", 12, -84, 22, function() U:BarPage(-1) end)
  self.barPage = label(f, "1/10", 9, 38, -89, 34)
  compactButton(f, ">", 76, -84, 22, function() U:BarPage(1) end)
  self.targetMode = compactButton(f, "Main's target", 106, -84, 112, function() U:CycleTarget() end)
  self.targetMode:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Cast target")
    GameTooltip:AddLine("Click to cycle: main's target, main character, account 2, or account 2's current target.", 0.7, 0.85, 0.85, true)
    GameTooltip:AddLine("Right-click any skill to target account 2 directly.", 0.7, 0.85, 0.85, true)
    GameTooltip:Show()
  end)
  self.targetMode:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.followButton = compactButton(f, "Follow", 224, -84, 76, function()
    if arg1 == "RightButton" then
      local ok, reason = B:SetMirrorMode(not B.db.mirrorMovement)
      if not ok then B:Notify(reason) end
    elseif B.db.mirrorMovement then B:ToggleMirrorPause()
    else U:Run("FOLLOW") end
  end)
  self.followButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  self.followButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP"); GameTooltip:SetText("Movement mode")
    GameTooltip:AddLine("Right-click: switch Follow / Mirror. In Mirror mode, click to pause or resume.", 0.7, 0.9, 0.85, true)
    GameTooltip:AddLine("Mirror copies your movement, jump and character heading, including mouse turning.", 0.7, 0.9, 0.85, true); GameTooltip:Show()
  end)
  self.followButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  compactButton(f, "Move", 306, -84, 76, function() U:ArmMove() end)
  local stop = compactButton(f, "STOP", 388, -84, 96, function() U:Run("STOP") end)
  stop.caption:SetTextColor(1, 0.4, 0.36)
  self.toast = CreateFrame("Frame", nil, f)
  self.toast:SetWidth(496); self.toast:SetHeight(22)
  self.toast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3)
  self.toast:SetBackdrop(backdrop); self.toast:SetBackdropColor(0.025, 0.035, 0.045, 0.95)
  self.notice = label(self.toast, "", 9, 8, -5, 480)
  self.notice:SetHeight(14); self.notice:SetTextColor(0.6, 0.78, 0.8)
  self.toast:Hide()
  self:CreateBrowser()
  self:CreateSetup()
  self:CreateDirectionPad()
  self:CreateMoveOverlay()
  self:CreateKeys()
  local scale = tonumber(B.db.uiScale) or 0.85
  self:SetScale(math.max(0.55, math.min(1.25, scale)))
  self:Refresh()
  if B.db.enabled then f:Hide() else self:ShowSetup() end
end

function U:CreateBrowser()
  local f = CreateFrame("Frame", "zBoxBrowser", self.frame)
  self.browser = f
  f:SetFrameLevel(self.frame:GetFrameLevel() + 10)
  f:SetWidth(496); f:SetHeight(405); f:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 0, 5)
  f:SetClampedToScreen(true)
  f:SetBackdrop(backdrop); f:SetBackdropColor(0.025, 0.035, 0.045, 0.97); f:EnableMouse(true)
  self.tabs, self.targetButtons = {}, {}
  local tabs = { { "Actions", "actions" }, { "Spells", "spells" }, { "Bags", "bags" },
    { "Gear", "gear" }, { "Talents", "talents" }, { "Quests", "quests" }, { "NPC", "npc" } }
  for i = 1, table.getn(tabs) do
    local entry = tabs[i]
    local b = button(f, entry[1], 12 + (i - 1) * 68, -10, 64, function()
      B:Request(this.section, 1); U:Refresh()
    end)
    b.section = entry[2]; self.tabs[i] = b
  end
  button(f, "<", 12, -43, 22, function() U:Page(-1) end)
  self.pageLabel = label(f, "1 / 10", 9, 40, -50, 40)
  button(f, ">", 84, -43, 22, function() U:Page(1) end)
  self.viewTitle = label(f, "", 10, 116, -50, 196)
  self.viewTitle:SetHeight(14)
  self.aux = button(f, "Move pad", 318, -43, 80, function()
    if B.view == "npc" then U:Run("TALK", { B:GUID("target") })
    elseif B.view == "quests" then U.questMainOnly = not U.questMainOnly; U.questPage = 1; U:Refresh()
    elseif U.pad:IsShown() then U.pad:Hide() else U.pad:Show() end
  end)
  button(f, "Refresh", 404, -43, 80, function() B:Request(B.view, B.page) end)
  self.help = label(f, "", 9, 12, -76, 472)
  self.help:SetHeight(20)
  self.content = CreateFrame("Frame", nil, f)
  self.content:SetWidth(472); self.content:SetHeight(270)
  self.content:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -99)
  for i = 1, 48 do self.cells[i] = self:CreateCell(i, self.content) end
  self.empty = label(self.content, "", 11, 4, -10, 464)
  self.selectionText = label(f, "", 9, 12, -379, 472)
  self.selectionText:SetHeight(18)
  self:CreateCharacterViews()
  f:Hide()
end

function U:ToggleBrowser()
  self.keys:Hide(); self.setup:Hide()
  if self.browser:IsShown() then self.browser:Hide()
  else self.browser:Show(); B:Request(B.view, B.page); self:Refresh() end
end

function U:BarPage(delta)
  B.actionPage = math.max(1, math.min(10, B.actionPage + delta))
  if B.view == "actions" then B:Request("actions", B.actionPage)
  elseif B.connected then B:Send("BAR", { B.actionPage }, true) end
  self:Refresh()
end

function U:CycleTarget()
  local modes = { "TARGET", "MAIN", "SELF", "KEEP" }
  for i = 1, 4 do if B.targetMode == modes[i] then B.targetMode = modes[math.mod(i, 4) + 1]; break end end
  self:Refresh()
end

function U:CreateCell(index, parent, dock)
  local cell = CreateFrame("Button", (dock and "zBoxDock" or "zBoxCell") .. index, parent)
  cell:SetFrameLevel(parent:GetFrameLevel() + 1)
  cell.isDock = dock
  cell:SetWidth(dock and 32 or 115); cell:SetHeight(dock and 32 or 43)
  cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  cell:RegisterForDrag("LeftButton")
  cell:SetScript("OnDragStart", function() U:Drag(this) end)
  cell:SetScript("OnDragStop", function()
    this.dragging, this.ignoreClickUntil = nil, GetTime() + 0.4
  end)
  cell.icon = cell:CreateTexture(nil, "ARTWORK")
  cell.icon:SetWidth(32); cell.icon:SetHeight(32); cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
  cell.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
  cell.border = cell:CreateTexture(nil, "BACKGROUND")
  cell.border:SetTexture(0.15, 0.21, 0.26, 0.9)
  cell.border:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -2, 2)
  cell.border:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 2, -2)
  cell.name = label(cell, "", 10, 38, -2, 75)
  cell.name:SetHeight(29)
  cell.sub = label(cell, "", 9, 38, -30, 75)
  cell.sub:SetTextColor(0.55, 0.7, 0.78)
  cell.count = label(cell, "", 10, 1, -21, 30)
  cell.count:SetJustifyH("RIGHT")
  cell.cooldown = label(cell, "", 14, 0, -8, 32)
  cell.cooldown:SetJustifyH("CENTER")
  cell.cooldown:SetTextColor(1, 0.85, 0.3)
  cell:SetScript("OnEnter", function() U:Tooltip(this) end)
  cell:SetScript("OnLeave", function() U.hovered = nil; GameTooltip:Hide() end)
  cell:SetScript("OnClick", function()
    if not this.dragging and (not this.ignoreClickUntil or GetTime() > this.ignoreClickUntil) then U:Click(this, arg1) end
  end)
  if dock then cell.name:Hide(); cell.sub:Hide() end
  return cell
end

function U:Drag(cell)
  cell.dragging = true
  cell.ignoreClickUntil = GetTime() + 0.4
  local ok, reason = B:PickupRemote(cell.section, cell.row)
  if reason then B:Notify(reason) end
end

function U:Page(delta)
  if B.view == "quests" and self.questMainOnly then
    self.questPage = math.max(1, math.min(math.max(1, math.ceil(table.getn(B:MainOnlyQuests()) / 5)), (self.questPage or 1) + delta))
    self:Refresh(); return
  end
  local view = B.cache.view
  local limits = { actions = 10, spells = 40, bags = 5, gear = 1, talents = 3, quests = 8, npc = 40 }
  local maxPage = view and view.section == B.view and view.maximum or limits[B.view]
  local page = math.max(1, math.min(maxPage, B.page + delta))
  B:Request(B.view, page)
  self:Refresh()
end

function U:Tooltip(cell)
  local row = cell.row
  if not row then return end
  GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
  if cell.section == "bags" and row[8] ~= "" then GameTooltip:SetHyperlink(row[8])
  elseif cell.section == "gear" and row[4] ~= "" then GameTooltip:SetHyperlink(row[4])
  else
    GameTooltip:SetText(cell.tooltip or cell.name:GetText() or "")
    if cell.section == "quests" then
      GameTooltip:AddLine("Account 2: " .. row[5] .. "\n" .. row[7], 0.7, 0.9, 0.85, true)
      GameTooltip:AddLine(B:QuestComparison(row), 0.9, 0.85, 0.65, true)
    elseif cell.section == "npc" then
      GameTooltip:AddLine(row[4], 0.7, 0.9, 0.85, true)
      if row[9] == "0" then GameTooltip:AddLine("Unavailable", 1, 0.4, 0.3) end
      if row[6] == "buy" or row[6] == "train" or row[6] == "reward" then GameTooltip:AddLine("Click once to review, then click again to confirm.", 1, 0.8, 0.3, true) end
    elseif cell.section == "talents" then
      GameTooltip:AddLine("Rank " .. row[6] .. " / " .. row[7], 1, 1, 1)
      GameTooltip:AddLine("Click to spend ONE talent point on account 2.", 0.5, 0.9, 0.8, true)
      GameTooltip:AddLine("Normal level, tier and prerequisite rules apply.", 0.8, 0.8, 0.8, true)
    elseif cell.section == "actions" or cell.section == "spells" then
      GameTooltip:AddLine("Click: cast. Right-click: self. Drag: add to your own bars.", 0.5, 0.9, 0.8, true)
    end
  end
  GameTooltip:Show()
  if B.connected and (cell.section == "actions" or cell.section == "spells" or cell.section == "talents") then
    self.hovered = { cell = cell, section = cell.section, page = tostring(cell.isDock and B.actionPage or B.page), index = row[1] }
    if not self:RemoteTooltip() then B:Send("TIP", { cell.section, cell.isDock and B.actionPage or B.page, row[1] }, true) end
  end
end

function U:RemoteTooltip()
  local hover, tooltip = self.hovered, B.cache.tooltip
  if not hover or not tooltip or tooltip.text == "" or hover.section ~= tooltip.section or
     hover.page ~= tooltip.page or hover.index ~= tooltip.index then return false end
  if not hover.cell:IsShown() then return false end
  if not hover.cell.isDock and (B.view ~= hover.section or tostring(B.page) ~= hover.page) then return false end
  GameTooltip:SetOwner(hover.cell, "ANCHOR_RIGHT")
  local lines = B.Split(tooltip.text, "\n")
  GameTooltip:SetText(lines[1])
  for i = 2, table.getn(lines) do GameTooltip:AddLine(lines[i], 0.9, 0.9, 0.9, true) end
  if hover.section == "talents" then GameTooltip:AddLine("Click to spend ONE point on account 2.", 0.4, 1, 0.8, true) end
  GameTooltip:Show()
  return true
end

function U:Click(cell, mouse)
  local row = cell.row
  if not row or not B.connected then return end
  if mouse == "LeftButton" and IsShiftKeyDown() and (cell.section == "actions" or cell.section == "spells") then
    local ok, reason = B:PickupRemote(cell.section, row)
    if reason then B:Notify(reason) end
    return
  end
  if cell.section == "quests" then
    self.questSelected = row[2]
    self:Refresh()
    self:Tooltip(cell)
  elseif cell.section == "npc" then
    if mouse ~= "LeftButton" then return end
    if row[9] == "0" then B:Notify("This service is unavailable"); return end
    if row[6] == "buy" or row[6] == "train" or row[6] == "reward" then
      if self.npcConfirm ~= row[5] or GetTime() > (self.npcConfirmUntil or 0) then
        self.npcConfirm, self.npcConfirmUntil = row[5], GetTime() + 8
        B:Notify("Click again to confirm: " .. row[3] .. (tonumber(row[7]) > 0 and (" - " .. B:Money(row[7])) or ""))
        return
      end
    end
    self.npcConfirm = nil
    self:Run("NPC", { row[6], row[1], row[5] })
  elseif cell.section == "actions" then
    if row[2] == "" then return end
    self:Run("ACTION", { row[1], row[4], B:TargetDescriptor(mouse == "RightButton") })
  elseif cell.section == "spells" then
    if row[6] == "1" then B:Notify("That spell is passive"); return end
    self:Run("SPELL", { row[1], row[5], B:TargetDescriptor(mouse == "RightButton") })
  elseif cell.section == "bags" then
    if row[8] == "" then return end
    if mouse == "RightButton" then
      self:Run("USEITEM", { row[1], row[2], row[8] })
    else
      B.bagSelection = { bag = row[1], slot = row[2], key = row[8], link = row[7] }
      B.notice = "Selected item. Open Gear and click its destination slot."
      self:Refresh()
    end
  elseif cell.section == "gear" then
    if mouse == "RightButton" or (IsShiftKeyDown() and mouse == "LeftButton") then
      if row[4] == "" then return end
      self:Run("UNEQUIP", { row[1], row[4] })
    elseif B.bagSelection and mouse == "LeftButton" then
      local selected = B.bagSelection
      self:Run("EQUIP", { selected.bag, selected.slot, selected.key, row[1], row[4] })
      B.bagSelection = nil
    end
  elseif cell.section == "talents" and mouse == "LeftButton" then
    self:Run("TALENT", { B.page, row[1], row[6] })
  end
end

function U:Refresh()
  if not self.frame then return end
  self:UpdateVisibility()
  local view = B.cache.view
  if B.view == "quests" and self.questMainOnly and B.cache.questKeys then
    local all, rows, page = B:MainOnlyQuests(), {}, self.questPage or 1
    for i = (page-1)*5+1, math.min(page*5, table.getn(all)) do table.insert(rows, all[i]) end
    view = { section = "quests", page = B.page, rows = rows, title = "Main only - missing on account 2", maximum = math.max(1, math.ceil(table.getn(all)/5)), displayPage = page }
  end
  self.connection:SetText(B.connected and ((B.db.peer or "") .. "  /  Connected") or
    (B.db.enabled and ("Waiting for " .. (B.db.peer or "peer") .. " in your group") or "Not paired"))
  self.connection:SetTextColor(B.connected and 0.3 or 1, B.connected and 0.95 or 0.7, 0.7)
  local status = B.cache.status
  self.followButton.caption:SetText(B.db.mirrorMovement and (B.mirrorPaused and "Mirror II" or "Mirror ON") or "Follow")
  if self.modeButton then self.modeButton.caption:SetText(B.db.mirrorMovement and "Mirror movement" or "Follow mode") end
  if status then
    self.health:SetText("HP " .. status[5] .. "/" .. status[6] .. "    Power " .. status[7] .. "/" .. status[8])
    local movement = status[13] == "Moving to point" and "Moving" or (status[13] == "Following" and "Follow" or status[13])
    self.power:SetText(movement == "Idle" and status[10] == "1" and "Combat" or movement)
    self.target:SetText(status[9])
    if string.find(status[14], "^Native inputs ") then self.power:Show(); self.inputMode:Hide()
    else self.power:Hide(); self.inputMode:SetText("Input update"); self.inputMode:Show() end
  else
    self.health:SetText(B.db.role == "agent" and "Agent mode: controlled by " .. (B.db.peer or "") or "Account 2 is not connected")
    self.power:SetText(""); self.target:SetText("Target: --"); self.inputMode:SetText("")
  end
  local bodyHeight = 48
  if view and view.section == B.view and view.page == B.page then
    local count = table.getn(view.rows)
    local columns = B.view == "bags" and 8 or 4
    local step = (B.view == "actions" or B.view == "bags") and 48 or (B.view == "gear" and 49 or 43)
    bodyHeight = math.max(48, math.ceil(count / columns) * step)
    if B.view == "talents" then
      bodyHeight = 48
      for i = 1, count do bodyHeight = math.max(bodyHeight, tonumber(view.rows[i][4]) * 33) end
    elseif B.view == "quests" or B.view == "npc" then
      bodyHeight = math.max(48, count * (B.view == "quests" and 65 or 48))
    end
  end
  bodyHeight = self:CharacterViewHeight(view, bodyHeight)
  self.content:SetHeight(bodyHeight)
  self.browser:SetHeight(99 + bodyHeight + 32)
  self:PlacePanels()
  self.aux.caption:SetText(B.view == "npc" and "Talk" or (B.view == "quests" and (self.questMainOnly and "Alt quests" or "Main only") or "Move pad"))
  self.selectionText:ClearAllPoints()
  self.selectionText:SetPoint("TOPLEFT", self.browser, "TOPLEFT", 12, -99 - bodyHeight - 9)
  self.barPage:SetText(tostring(B.actionPage) .. "/10")
  local modes = { TARGET = "Main's target", MAIN = "Main character", SELF = "Account 2", KEEP = "Alt's target" }
  self.targetMode.caption:SetText(modes[B.targetMode])
  local bar = B.cache.bar
  for i = 1, 12 do
    local cell = self.dockCells[i]
    if bar and bar.page == B.actionPage and bar.rows[i] then self:RenderCell(cell, bar.rows[i], i, "actions")
    else
      cell.row = nil; cell.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
      cell.count:SetText(""); cell.cooldown:SetText("")
    end
  end
  for i = 1, table.getn(self.targetButtons) do
    local b = self.targetButtons[i]
    b.caption:SetTextColor(b.mode == B.targetMode and 0.3 or 0.9, 0.95, b.mode == B.targetMode and 0.8 or 0.9)
  end
  for i = 1, table.getn(self.tabs) do
    local b = self.tabs[i]
    b.caption:SetTextColor(b.section == B.view and 0.3 or 0.9, 0.95, b.section == B.view and 0.8 or 0.9)
  end
  self:ResetCharacterViews()
  self.empty:Hide()
  if not view or view.section ~= B.view or view.page ~= B.page then
    self.viewTitle:SetText("Account 2 - " .. B.view)
    self.pageLabel:SetText(tostring(B.page))
    self.empty:SetText(B.connected and "Loading from account 2..." or "Pair both characters and put them in the same party.")
    self.empty:Show()
    if B.view == "bags" then self:RenderBags({ page = B.page }); self.empty:Hide() end
  else
    self.viewTitle:SetText(view.title)
    self.pageLabel:SetText((view.displayPage or view.page) .. " / " .. view.maximum)
    if not self:RenderCharacterView(view) then
      for i = 1, math.min(48, table.getn(view.rows)) do self:RenderCell(self.cells[i], view.rows[i], i, view.section) end
    end
    if table.getn(view.rows) == 0 and B.view ~= "quests" and B.view ~= "npc" and B.view ~= "bags" then
      self.empty:SetText("This page is empty."); self.empty:Show()
    end
  end
  local help = { actions = "Click to cast. Right-click for self. Drag a skill onto your own action bars.",
    spells = "Click to cast. Drag a spell onto your bars. Passive spells cannot be used.",
    bags = "Left click selects an item for equipping. Right click uses it on account 2.",
    gear = "Select an item in Bags, then click its slot. Right-click gear to unequip.",
    talents = "Click a talent to spend ONE point on account 2. The server checks normal prerequisites.",
    quests = "Select a quest to read objectives and compare progress. Main only shows missing questlines.",
    npc = "Target an NPC and click Talk. Account 2 must be nearby. Purchases require a second click." }
  self.help:SetText(help[B.view])
  if B.view == "npc" and self.npcConfirm and GetTime() < (self.npcConfirmUntil or 0) then
    self.selectionText:SetText("Click the same offer again to confirm. Prices are checked on account 2.")
  else self.selectionText:SetText(B.bagSelection and ("Selected: " .. B.bagSelection.link) or "") end
  local notice = B.notice or ""
  if notice ~= self.lastNotice then
    self.lastNotice, self.noticeUntil = notice, GetTime() + 3
    self.notice:SetText(notice)
    if notice ~= "" then self.toast:Show() else self.toast:Hide() end
  end
  self.dirty = false
end

function U:RenderCell(cell, row, index, section)
  cell.row, cell.section = row, section
  local col, line, xstep, ystep = math.mod(index - 1, 4), math.floor((index - 1) / 4), 118, 43
  local icon, name, sub = "", "", ""
  if section == "actions" then
    icon, name, sub = row[2], row[3], "Slot " .. row[1]
    cell.count:SetText(tonumber(row[5]) > 1 and row[5] or "")
    ystep = 48
  elseif section == "spells" then
    icon, name, sub = row[2], row[3], row[6] == "1" and "Passive" or row[4]
    cell.count:SetText("")
  elseif section == "bags" then
    col, line, xstep, ystep = math.mod(index - 1, 8), math.floor((index - 1) / 8), 59, 48
    icon, name, sub = row[3], "", ""
    cell.count:SetText(tonumber(row[4]) > 1 and row[4] or "")
  elseif section == "gear" then
    icon, name = row[2], equipment[tonumber(row[1])] or "Equipment"
    local _, _, itemName = string.find(row[3], "|h%[(.-)%]|h")
    sub = itemName or "Empty"
    cell.count:SetText("")
    ystep = 49
  elseif section == "talents" then
    col, line, xstep, ystep = tonumber(row[5]) - 1, tonumber(row[4]) - 1, 118, 33
    icon, name, sub = row[3], row[2], ""
    cell.count:SetText(row[6] .. "/" .. row[7])
  elseif section == "quests" then
    col, line, xstep, ystep = 0, index-1, 472, 65
    icon, name = "Interface\\Icons\\INV_Misc_Note_01", "[" .. row[4] .. "] " .. row[3]
    sub = (self.questMainOnly and "Main: " or "Alt: ") .. row[5] .. " - " .. row[7]
    if not self.questMainOnly then sub = sub .. "\n" .. B:QuestComparison(row) else sub = sub .. "\nAlt: not in quest log" end
    cell.count:SetText("")
  elseif section == "npc" then
    col, line, xstep, ystep = 0, index-1, 472, 48
    icon, name, sub = row[2], row[3], row[4]
    cell.count:SetText("")
  end
  if not cell.isDock then
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", self.content, "TOPLEFT", col * xstep + 2, -line * ystep)
    cell:SetWidth((section == "quests" or section == "npc") and 468 or (section == "bags" and 44 or 115))
  end
  local wide = section == "quests" or section == "npc"
  cell:SetHeight(cell.isDock and 32 or (wide and ystep-2 or (section == "talents" and 32 or 43)))
  cell.name:SetWidth(wide and 425 or 75); cell.name:SetHeight(wide and 14 or 29)
  cell.sub:ClearAllPoints(); cell.sub:SetPoint("TOPLEFT", cell, "TOPLEFT", 38, wide and -17 or -30)
  cell.sub:SetWidth(wide and 425 or 75); cell.sub:SetHeight(section == "quests" and 42 or 22)
  cell.name:SetText(name); cell.sub:SetText(sub); cell.tooltip = name
  cell.icon:SetTexture(icon ~= "" and icon or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
  cell.icon:SetVertexColor(1, 1, 1)
  cell.cooldown:SetText("")
  cell:Show()
end

function U:CreateSetup()
  local f = CreateFrame("Frame", nil, self.frame)
  self.setup = f
  f:SetWidth(450); f:SetHeight(348); f:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 0, 5)
  f:SetFrameLevel(self.frame:GetFrameLevel() + 15); f:SetClampedToScreen(true)
  f:EnableMouse(true); f:SetBackdrop(backdrop); f:SetBackdropColor(0.025, 0.035, 0.045, 1)
  label(f, "Pair characters", 13, 16, -16)
  label(f, "Group both characters and use the same pairing code.", 10, 16, -43, 416)
  label(f, "Other character", 10, 16, -80)
  self.peer = edit(f, "zBoxPeerInput", 130, -72, 286)
  label(f, "Pairing code", 10, 16, -119)
  self.key = edit(f, "zBoxKeyInput", 130, -111, 194)
  self.key:SetMaxLetters(32)
  button(f, "Generate", 334, -111, 82, function() U.key:SetText(B:NewSession() .. B:NewSession()) end)
  label(f, "Account 1: Control.  Account 2: Allow.", 10, 16, -155, 416)
  button(f, "Control", 16, -177, 194, function() U:Pair("control") end)
  button(f, "Allow", 222, -177, 194, function() U:Pair("agent") end)
  label(f, "Only this character and realm. /zbox off revokes pairing.", 9, 16, -218, 416)
  label(f, "Panel scale", 10, 16, -249, 104)
  compactButton(f, "-", 130, -243, 28, function() U:SetScale(math.max(0.55, (B.db.uiScale or 0.85) - 0.05)) end)
  self.scaleLabel = label(f, "85%", 10, 170, -249, 42)
  compactButton(f, "+", 216, -243, 28, function() U:SetScale(math.min(1.25, (B.db.uiScale or 0.85) + 0.05)) end)
  compactButton(f, "Reset", 258, -243, 72, function() U:SetScale(0.85) end)
  label(f, "Movement mode", 10, 16, -280, 114)
  self.modeButton = compactButton(f, "Follow mode", 130, -274, 200, function()
    local ok, reason = B:SetMirrorMode(not B.db.mirrorMovement)
    if not ok then B:Notify(reason) end
  end)
  button(f, "Disable / revoke", 16, -308, 170, function() B:Slash("off"); U:Refresh() end)
  button(f, "Diagnostics", 196, -308, 128, function() B:Slash("diag") end)
  button(f, "Close", 334, -308, 82, function() f:Hide() end)
  f:Hide()
end

function U:Pair(role)
  local ok, reason = B:Configure(role, self.peer:GetText(), self.key:GetText())
  if not ok then B:Notify(reason); return end
  self.peer:ClearFocus(); self.key:ClearFocus(); self.setup:Hide(); self:Refresh()
end

function U:ShowSetup()
  B:ReleaseDirections()
  self.frame:Show(); self.browser:Hide(); self.pad:Hide(); self.keys:Hide()
  self.peer:SetText(B.db.peer or "")
  self.key:SetText(B.db.key or "")
  self.setup:Show()
end

function U:CreateDirectionPad()
  local f = CreateFrame("Frame", "zBoxDirectionPad", UIParent)
  self.pad = f
  f:SetWidth(180); f:SetHeight(180); f:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 5, 0)
  f:SetFrameStrata("DIALOG"); f:SetBackdrop(backdrop); f:SetBackdropColor(0.025, 0.04, 0.065, 0.97)
  label(f, "Hold to move account 2", 10, 12, -12, 160)
  local directions = { { "Forward", "forward", 57, -32 }, { "Left", "left", 8, -65 },
    { "Back", "backward", 65, -65 }, { "Right", "right", 122, -65 },
    { "Strafe L", "strafeleft", 15, -99 }, { "Strafe R", "straferight", 97, -99 } }
  for i = 1, table.getn(directions) do
    local row = directions[i]
    local b = button(f, row[1], row[3], row[4], (i > 4 and 67 or 50), function() end)
    b.axis = row[2]
    b:SetScript("OnMouseDown", function()
      if arg1 ~= "LeftButton" or not B.connected then return end
      U:ReleaseAxis()
      U.held = this.axis
      B:HoldDirection(U.held, true, "mouse")
    end)
    b:SetScript("OnMouseUp", function() U:ReleaseAxis() end)
    b:SetScript("OnLeave", function()
      this:SetBackdropColor(0.09, 0.13, 0.18, 1)
      if U.held == this.axis then U:ReleaseAxis() end
    end)
  end
  button(f, "Assist", 12, -140, 72, function() U:Run("ASSIST") end)
  button(f, "Jump", 96, -140, 72, function() U:Run("JUMP") end)
  f:SetScript("OnHide", function() U:ReleaseAxis() end)
  f:Hide()
end

function U:ReleaseAxis()
  if self.held then
    local axis = self.held
    self.held = nil
    B:HoldDirection(axis, false, "mouse")
  end
end

function U:CreateMoveOverlay()
  local f = CreateFrame("Frame", "zBoxMovePicker", UIParent)
  self.moveOverlay = f
  f:SetAllPoints(WorldFrame); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:EnableMouse(true)
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  hint:SetPoint("TOP", UIParent, "TOP", 0, -100)
  hint:SetText("zBox: click terrain to move account 2. Right-click or Escape cancels.")
  f:SetScript("OnMouseDown", function()
    if arg1 == "LeftButton" then
      local ok, reason = B:CaptureMove()
      if not ok then B:Notify(reason); return end
    end
    U:CancelMove()
  end)
  f:Hide()
  table.insert(UISpecialFrames, "zBoxMovePicker")
end

function U:ArmMove()
  if not B.connected or B.db.role ~= "control" then B:Notify("Connect the second character first"); return end
  if type(zAPI) ~= "function" then B:Notify("Click picking requires the zAPI DLL"); return end
  if self.moveOverlay:IsShown() then self:CancelMove(); return end
  self.moveOverlay:Show()
end

function U:CancelMove()
  if self.moveOverlay then self.moveOverlay:Hide() end
end

function U:Toggle()
  if not self.frame then return end
  if self.frame:IsShown() then self:Minimize() else self:Restore() end
end

function U:UpdateVisibility()
  if self.closeButton then self.closeButton.caption:SetText(B.connected and "-" or "x") end
  if not self.restoreButton then return end
  if B.connected and not self.frame:IsShown() then
    if not self.restoreButton:IsShown() then
      self.restoreButton:ClearAllPoints()
      self.restoreButton:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
      self.restoreButton:Show()
    end
  else self.restoreButton:Hide() end
end

function U:Minimize()
  self.frame:Hide()
  GameTooltip:Hide()
  self:UpdateVisibility()
end

function U:Restore()
  self.frame:Show()
  GameTooltip:Hide()
  self:Refresh()
  self:PlacePanels()
end

function U:Tick(now)
  self:UpdateVisibility()
  if not self.frame:IsShown() or now - self.lastTick < 0.15 then return end
  self.lastTick = now
  self:PlacePanels()
  if self.dirty then self:Refresh() end
  self:CharacterViewsTick(now)
  if self.noticeUntil and now > self.noticeUntil then self.toast:Hide() end
  local cds = B.cache.cooldowns
  if cds and cds.page == B.actionPage then
    for _, cells in ipairs({ self.cells, self.dockCells }) do
      for i = 1, table.getn(cells) do
        local cell = cells[i]
        local row = cell.section == "actions" and cell.row and cds.rows[tonumber(cell.row[1])]
        if cell:IsShown() and row then
          local remaining = math.max(0, tonumber(row[2]) - (now - cds.at))
          cell.cooldown:SetText(remaining > 0.1 and tostring(math.ceil(remaining)) or "")
          cell.count:SetText(tonumber(row[6]) > 1 and row[6] or "")
          cell.icon:SetVertexColor(row[4] == "1" and 1 or 0.45, row[5] == "1" and 0.45 or 1, 1)
        end
      end
    end
  end
end

local keyRows = {
  { "Move to click", "ZBOX_MOVE" }, { "Forward", "ZBOX_FORWARD" }, { "Backward", "ZBOX_BACKWARD" },
  { "Turn left", "ZBOX_LEFT" }, { "Turn right", "ZBOX_RIGHT" },
  { "Strafe left", "ZBOX_STRAFELEFT" }, { "Strafe right", "ZBOX_STRAFERIGHT" },
  { "Follow main", "ZBOX_FOLLOW" }, { "Assist main", "ZBOX_ASSIST" }, { "Jump", "ZBOX_JUMP" },
  { "Emergency stop", "ZBOX_STOP" }, { "Show / hide panel", "ZBOX_TOGGLE" }
}

function U:CreateKeys()
  local f = CreateFrame("Frame", "zBoxKeys", self.frame)
  self.keys, self.keyButtons = f, {}
  f:SetWidth(396); f:SetHeight(376); f:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT", 0, 5)
  f:SetFrameLevel(self.frame:GetFrameLevel() + 20); f:SetClampedToScreen(true)
  f:SetBackdrop(backdrop); f:SetBackdropColor(0.025, 0.035, 0.045, 1); f:EnableMouse(true)
  label(f, "Account 2 keybindings", 13, 14, -15)
  button(f, "x", 364, -8, 20, function() f:Hide() end)
  self.keyHint = label(f, "Click a binding, then press a key or mouse button.", 9, 14, -43, 368)
  self.keyHint:SetHeight(28)
  for i = 1, table.getn(keyRows) do
    local entry = keyRows[i]
    label(f, entry[1], 10, 14, -80 - (i - 1) * 24, 165)
    local b = button(f, "Unbound", 196, -72 - (i - 1) * 24, 186, function()
      U.bindingCapture = this.binding
      U.keyHint:SetText("Press a key. Escape cancels; Backspace clears this binding.")
      f:EnableKeyboard(true)
    end)
    b.binding = entry[2]; self.keyButtons[i] = b
  end
  f:SetScript("OnKeyDown", function() U:CaptureBinding(arg1) end)
  f:SetScript("OnMouseUp", function()
    local map = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
    if map[arg1] then U:CaptureBinding(map[arg1]) end
  end)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function() U:CaptureBinding(arg1 > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
  f:SetScript("OnHide", function() U.bindingCapture = nil; f:EnableKeyboard(false) end)
  f:EnableKeyboard(false); f:Hide()
end

function U:ShowKeys()
  B:ReleaseDirections()
  self.frame:Show(); self.setup:Hide(); self.browser:Hide(); self.pad:Hide()
  self:RefreshKeys(); self.keys:Show()
end

function U:RefreshKeys()
  for i = 1, table.getn(self.keyButtons) do
    local b = self.keyButtons[i]
    local first, second
    if GetBindingKey then first, second = GetBindingKey(b.binding) end
    b.caption:SetText(first and (first .. (second and (" / " .. second) or "")) or "Unbound")
  end
end

function U:CaptureBinding(key)
  local binding = self.bindingCapture
  if not binding then return end
  if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then return end
  if key ~= "ESCAPE" and SetBinding and GetBindingKey then
    local chord = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") ..
      (IsShiftKeyDown() and "SHIFT-" or "") .. key
    local first, second = GetBindingKey(binding)
    -- Assign first so an unsupported key cannot destroy the existing binding.
    if key ~= "BACKSPACE" and not SetBinding(chord, binding) then
      self.keyHint:SetText("That key cannot be bound. Choose another."); return
    end
    if first and first ~= chord then SetBinding(first) end
    if second and second ~= chord then SetBinding(second) end
    if key == "BACKSPACE" then
      if first then SetBinding(first) end
      if second then SetBinding(second) end
    end
    if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
  end
  self.bindingCapture = nil; self.keys:EnableKeyboard(false); self:RefreshKeys()
  self.keyHint:SetText("Click a binding, then press a key or mouse button.")
end
