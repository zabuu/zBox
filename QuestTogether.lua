local B = zBox
local stages={QUEST_DETAIL="accept",QUEST_PROGRESS="complete",QUEST_COMPLETE="reward"}

local function questID()
  if type(GetQuestID)=="function" then
    local ok,id=pcall(GetQuestID)
    if ok and type(id)=="number" and id>0 then return "id:"..id end
  end
end

local function hasQuest(rows,title,key)
  for _, row in ipairs(rows) do
    if row[3]==title and (not key or not string.find(row[2],"^id:") or row[2]==key) then return row end
  end
  return false
end

-- Observe the server's actual quest-log change instead of replacing protected
-- quest functions or the main character's stock/pfUI button scripts.
function B:ObserveQuestScene(event)
  if stages[event] then
    local guid,title=self:GUID("npc"),GetTitleText and GetTitleText()
    if guid=="" or not title or title=="" then return end
    local before=self:QuestList()
    local row=hasQuest(before,title)
    self.localQuestScene={guid=guid,title=title,key=questID() or (row and string.find(row[2],"^id:") and row[2]),stage=stages[event],
      before=before,at=GetTime()}
  elseif event=="QUEST_FINISHED" and self.localQuestScene then
    self.localQuestScene.finished=GetTime()
    self.questObserveAt=GetTime()+.3
  end
end

function B:QuestObservationTick(now)
  if self.questObserveAt and now>=self.questObserveAt then
    self.questObserveAt=nil;self.questCache=nil;self:ObserveQuestChange()
  end
end

function B:ObserveQuestChange()
  local scene=self.localQuestScene
  if not scene or not self.connected or self.db.role~="control" or self.db.linkQuests==false or
     GetTime()-scene.at>90 or (scene.finished and GetTime()-scene.finished>5) then return end
  local before,after=hasQuest(scene.before,scene.title,scene.key),hasQuest(self:QuestList(),scene.title,scene.key)
  local op
  if scene.stage=="accept" and not before and after then op="accept"
  elseif scene.stage=="reward" and before and not after then op="complete" end
  if op then
    self.localQuestScene=nil
    self:Command("QUESTLINK",{op,scene.key or (after and string.find(after[2],"^id:") and after[2]) or "",scene.title,scene.guid})
  end
end

function B:LinkQuest(fields)
  if table.getn(fields)~=5 or (fields[2]~="accept" and fields[2]~="complete") or
     string.len(fields[4] or "")<1 or string.len(fields[4])>256 or
     (fields[3]~="" and not string.find(fields[3],"^id:%d+$")) or
     not string.find(fields[5] or "","^0x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") then return false,"Invalid linked quest" end
  local op,key,title,guid=fields[2],fields[3]~="" and fields[3] or nil,fields[4],fields[5]
  if op=="accept" and hasQuest(self:QuestList(),title,key) then return true,"Account 2 already has this quest" end
  if op=="complete" and not hasQuest(self:QuestList(),title,key) then return true,"Account 2 does not have this quest" end
  -- Interacting revalidates loaded NPC, hostility, life, combat and six-yard range.
  local ok,reason=self:TalkToNPC(guid)
  if not ok then return false,reason end
  self.questIntent={op=op,key=key,title=title,guid=guid,expires=GetTime()+10}
  self.npcWatch=true
  return true,"Linked quest requested"
end

function B:QuestIntentTick(now)
  local intent=self.questIntent
  if not intent then return end
  if now>intent.expires or UnitAffectingCombat("player") then self.questIntent=nil;return end
  if self.npcGUID~=intent.guid or not self.npcKind or intent.revision==self.npcRevision then return end
  if intent.waitKind==self.npcKind then return end
  local x,y,z=self:Position("player")
  local tx,ty,tz=self:Position(intent.guid)
  if not x or not tx or (x-tx)^2+(y-ty)^2+(z-tz)^2>36 then self.questIntent=nil;return end
  intent.revision=self.npcRevision
  local kind,selected=self.npcKind
  local title=GetTitleText and GetTitleText() or ""
  local id=questID()
  if kind=="detail" or kind=="progress" or kind=="reward" then
    if title~=intent.title or (intent.key and id and intent.key~=id) then self.questIntent=nil;return end
  end
  local choices=kind=="reward" and GetNumQuestChoices() or 0
  if kind=="reward" and intent.op=="complete" and choices>1 then
    self.questIntent=nil
    self:Send("ERROR",{"Choose account 2's quest reward in its NPC window."},true)
    return
  end
  for _, row in ipairs(self:NPCRows()) do
    local op=row[6]
    if (kind=="gossip" or kind=="greeting") and row[3]==intent.title and
       ((intent.op=="accept" and (op=="gossipAvailable" or op=="available")) or
        (intent.op=="complete" and (op=="gossipActive" or op=="active"))) then selected=row;break
    elseif (kind=="detail" and intent.op=="accept" and op=="accept") or
       (kind=="progress" and intent.op=="complete" and op=="complete" and row[9]~="0") or
       (kind=="reward" and intent.op=="complete" and op=="reward") then selected=row;break end
  end
  if selected then
    local issuedRevision=self.npcRevision+1
    intent.waitKind=kind
    local done=selected[6]=="accept" or selected[6]=="reward"
    if done then self.questIntent=nil end
    local ok,reason=self:NPCAction(selected[6],selected[1],selected[5])
    -- NPCAction changes the revision immediately. Only the next actual NPC
    -- event may advance this intent; never retry a spend on a timer.
    if self.questIntent then self.questIntent.revision=issuedRevision end
    if not ok then self.questIntent=nil;self:Send("ERROR",{reason or "Linked quest unavailable"},true) end
  end
end
