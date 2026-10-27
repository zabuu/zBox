local B = zBox

function B:SendQuestProgress(now)
  if now < (self.nextQuestProgress or 0) then return end
  self.nextQuestProgress = now+1
  local rows, encoded = self:QuestList(), {}
  for _, row in ipairs(rows) do table.insert(encoded,self:Encode(row)) end
  local digest = self:Fingerprint(table.concat(encoded,"\n"))
  if digest == self.questProgressDigest and now-(self.lastQuestProgressSent or 0)<30 then return end
  self.questProgressDigest = digest
  self.lastQuestProgressSent=now
  self.questProgressRevision = (self.questProgressRevision or 0)+1
  local pages = math.max(1,math.ceil(table.getn(rows)/5))
  for page=1,pages do
    local part = {}
    for index=(page-1)*5+1,math.min(page*5,table.getn(encoded)) do table.insert(part,encoded[index]) end
    if not self:Send("STATE",{"questprogress",self.questProgressRevision,page,pages,table.concat(part,"\n")},false) then self.questProgressDigest=nil end
  end
end

function B:AcceptQuestProgress(fields)
  if table.getn(fields)~=5 then return end
  local revision,page,total = self.Integer(fields[2],1,2147483647),self.Integer(fields[3],1,8),self.Integer(fields[4],1,8)
  if not revision or not page or not total or page>total or revision <= (self.lastQuestProgress or 0) then return end
  local rows = {}
  if fields[5]~="" then
    for _, encoded in ipairs(self.Split(fields[5],"\n")) do
      local row=self:Decode(encoded)
      if table.getn(row)~=7 or not self.Integer(row[1],1,100) or not tonumber(row[4]) or
         string.len(row[2])>256 or string.len(row[3])>256 or string.len(row[7])>6000 then return end
      table.insert(rows,row)
    end
  end
  if table.getn(rows)>5 then return end
  local incoming=self.questProgressIncoming
  if not incoming or revision>incoming.revision then
    incoming={revision=revision,total=total,pages={}};self.questProgressIncoming=incoming
  end
  if revision~=incoming.revision or total~=incoming.total then return end
  incoming.pages[page]=rows
  local all,keys = {},{}
  for index=1,total do
    if not incoming.pages[index] then return end
    for _, row in ipairs(incoming.pages[index]) do
      if keys[row[2]] then return end
      keys[row[2]]=true;table.insert(all,row)
    end
  end
  self.cache.quests,self.cache.questKeys=all,keys
  self.lastQuestProgress,self.questProgressIncoming=revision,nil
end

function B:SharedQuest(title, id)
  local own
  for _, row in ipairs(self:QuestList()) do
    if (id and row[2]=="id:"..id) or (row[3]==title and (not id or not string.find(row[2],"^id:"))) then own=row;break end
  end
  if not own then return end
  for _, row in ipairs(self.cache.quests or {}) do
    -- IDs win when both clients have them. The level/title key is the stock
    -- client's fallback; do not accidentally combine different quest IDs.
    local bothIDs=string.find(row[2],"^id:") and string.find(own[2],"^id:")
    if row[2]==own[2] or (not bothIDs and row[3]==own[3] and tonumber(row[4])==tonumber(own[4])) then return row end
  end
end

function B:AppendQuestProgress(meta, tooltip)
  if not self.connected or self.db.role~="control" or not meta or not meta.quest then return end
  local row=self:SharedQuest(meta.quest,meta.questid)
  if not row then return end
  tooltip=tooltip or GameTooltip
  local heading=(self.db.peer or "Account 2").." - "..row[3]
  local name=tooltip.GetName and tooltip:GetName()
  if name and tooltip.NumLines then
    for index=1,tooltip:NumLines() do
      local line=getglobal(name.."TextLeft"..index)
      if line and line:GetText()==heading then return end
    end
  end
  local color=RAID_CLASS_COLORS and self.cache.status and RAID_CLASS_COLORS[self.cache.status[4]]
  tooltip:AddLine(heading,color and color.r or 0.3,color and color.g or 0.95,color and color.b or 0.8,true)
  local count=0
  for _, objective in ipairs(self.Split(row[7],"\n")) do
    local relevant=not meta.spawn or meta.texture
    if meta.spawn and string.find(objective,meta.spawn,1,true) then relevant=true end
    for _, item in pairs(meta.item or {}) do if string.find(objective,item,1,true) then relevant=true end end
    if relevant and objective~="" then
      tooltip:AddLine("  "..objective,0.85,0.85,0.85,true);count=count+1
    end
  end
  if count==0 then tooltip:AddLine("  "..row[5],0.85,0.85,0.85,true) end
  tooltip:Show()
end

function B:InstallQuestTooltip()
  if not pfMap or type(pfMap.ShowTooltip)~="function" or pfMap.ShowTooltip==self.questTooltipHook then return end
  local original=pfMap.ShowTooltip
  self.questTooltipHook=function(map,meta,tooltip)
    original(map,meta,tooltip)
    B:AppendQuestProgress(meta,tooltip)
  end
  pfMap.ShowTooltip=self.questTooltipHook
end
