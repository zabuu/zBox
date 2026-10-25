local B = zBox

function B:QuestList()
  if self.questCache and GetTime() - (self.questCacheAt or 0) < 2 then return self.questCache end
  local rows, group = {}, ""
  if not GetNumQuestLogEntries then return rows end
  local collapsed, restore = {}, {}
  local selection = GetQuestLogSelection and GetQuestLogSelection()
  for index = 1, GetNumQuestLogEntries() do
    local title, level, tag, header, isCollapsed = GetQuestLogTitle(index)
    if header and isCollapsed then collapsed[title] = true end
  end
  local expanded = next(collapsed) and ExpandQuestHeader and CollapseQuestHeader
  if expanded then
    self.questReadUntil = GetTime() + 0.2
    ExpandQuestHeader(0)
    for index = 1, GetNumQuestLogEntries() do
      local title, level, tag, header = GetQuestLogTitle(index)
      if header and collapsed[title] then table.insert(restore, index) end
    end
  end
  local ok, errorText = pcall(function()
    for index = 1, GetNumQuestLogEntries() do
      local title, level, tag, header, isCollapsed, complete = GetQuestLogTitle(index)
      if header then
        group = title or ""
      elseif title then
        local objectives = {}
        for objective = 1, (GetNumQuestLeaderBoards(index) or 0) do
          local description, kind, done = GetQuestLogLeaderBoard(objective, index)
          table.insert(objectives, (done and "[done] " or "") .. tostring(description or ""))
        end
        local idFunction = C_QuestLog and C_QuestLog.GetQuestIDForLogIndex or GetQuestIDForLogIndex
        local id = idFunction and idFunction(index)
        local key = id and id > 0 and ("id:" .. id) or (tostring(level or 0) .. ":" .. title)
        table.insert(rows, { index, key, title, level or 0, complete == 1 and "Complete" or (complete == -1 and "Failed" or "In progress"),
          group, table.concat(objectives, "\n") })
      end
    end
  end)
  if expanded then
    for index = table.getn(restore), 1, -1 do CollapseQuestHeader(restore[index]) end
    if selection and SelectQuestLogEntry then SelectQuestLogEntry(selection) end
  end
  if not ok then self.questReadError = tostring(errorText); return self.questCache or {} end
  self.questCache, self.questCacheAt = rows, GetTime()
  return rows
end

function B:QuestView(page)
  local all, rows, keys = self:QuestList(), {}, {}
  for i = 1, table.getn(all) do
    table.insert(keys, self:Encode({ all[i][2] }))
    if i > (page - 1) * 5 and i <= page * 5 then table.insert(rows, self:Encode(all[i])) end
  end
  self:Send("STATE", { "questkeys", table.concat(keys, "\n") }, false)
  return rows, "Account 2 quests (" .. table.getn(all) .. ")", math.max(1, math.ceil(table.getn(all) / 5))
end

function B:QuestComparison(row)
  for _, own in ipairs(self:QuestList()) do
    if own[2] == row[2] then
      return "Main: " .. own[5] .. (own[7] ~= "" and (" - " .. own[7]) or "")
    end
  end
  return "Main: not in quest log"
end

function B:MainOnlyQuests()
  local rows = {}
  if not self.cache.questKeys then return rows end
  for _, own in ipairs(self:QuestList()) do
    if not self.cache.questKeys[own[2]] then table.insert(rows, own) end
  end
  return rows
end
