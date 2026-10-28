local B=zBox
function B:IsGUID(value)
 return type(value)=="string" and string.find(value,"^0x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$")~=nil
end
function B:FindSkill(name,rank)
 if type(name)~="string" or name=="" or string.len(name)>180 or type(rank)~="string" or string.len(rank)>80 then return end
 self.skillIndices=self.skillIndices or {}
 local key=name.."\031"..rank;local cached=self.skillIndices[key]
 if cached then local n,r=GetSpellName(cached,BOOKTYPE_SPELL or "spell");if n==name and (r or "")==rank and not (IsPassiveSpell and IsPassiveSpell(cached,BOOKTYPE_SPELL or "spell")) then return cached end end
 local total=0
 for tab=1,GetNumSpellTabs() do local _,_,offset,count=GetSpellTabInfo(tab);total=math.max(total,(offset or 0)+(count or 0)) end
 for i=1,math.min(960,total) do
  local n,r=GetSpellName(i,BOOKTYPE_SPELL or "spell")
  if n==name and (r or "")==rank and not (IsPassiveSpell and IsPassiveSpell(i,BOOKTYPE_SPELL or "spell")) then self.skillIndices[key]=i;return i end
 end
end
function B:IsFriendlyCast(command,index)
 if type(IsHelpfulSpell)~="function" then return false end
 local spell,book=index,BOOKTYPE_SPELL or "spell"
 if command=="ACTION" then
  local kind,id
  if GetActionInfo then kind,id=GetActionInfo(index) end
  if kind=="macro" and GetMacroSpell then
   local ok,_,_,spellID=pcall(GetMacroSpell,id)
   if not ok then return false end
   spell,book=spellID,nil
  elseif kind=="spell" then spell,book=id,nil
  else return false end
 end
 if not spell then return false end
 local ok,helpful=pcall(IsHelpfulSpell,spell,book)
 if not ok or (helpful~=true and helpful~=1) then return false end
 if IsHarmfulSpell then local accepted,harmful=pcall(IsHarmfulSpell,spell,book);if accepted and (harmful==true or harmful==1) then return false end end
 -- Self-only utility spells have no friendly unit target to redirect.
 local range
 if book then range=SpellHasRange else range=C_Spell and C_Spell.SpellHasRange end
 if range then local accepted,ranged=pcall(range,spell,book);if accepted and (ranged==false or ranged==0) then return false end end
 return true
end
function B:MacroDetails(slot)
 if SM_ACTION and SM_ACTION[slot] and GetSuperMacroInfo then
  local name,_,body=GetSuperMacroInfo(SM_ACTION[slot]);return name,body
 end
 local kind,id
 if GetActionInfo then kind,id=GetActionInfo(slot) end
 if kind=="macro" and GetMacroInfo then local name,_,body=GetMacroInfo(id);return name,body end
end
function B:ActionDetails(slot)
 local macro,body=self:MacroDetails(slot)
 if macro then return "macro",macro,"",string.find(string.lower(body or ""),"mouseover",1,true) and "1" or "0" end
 local kind,id
 if GetActionInfo then kind,id=GetActionInfo(slot) end
 if kind=="spell" and id then
  local name,rank
  if GetSpellInfo then local ok,n,r=pcall(GetSpellInfo,id);if ok then name,rank=n,r end end
  if not name then name,rank=GetSpellName(id,BOOKTYPE_SPELL or "spell") end
  return kind,name or "",rank or "","0"
 elseif kind=="macro" then
  local name,icon,body
  if GetMacroInfo then name,icon,body=GetMacroInfo(id) end
  return kind,name or self:ActionLabel(slot),"",string.find(string.lower(body or ""),"mouseover",1,true) and "1" or "0"
 end
 return kind or "","","","0"
end
local stamp=B.ActionStamp
function B:ActionStamp(slot)
 local macro,body=self:MacroDetails(slot)
 if macro then
  return self:Fingerprint(stamp(self,slot)..":"..(body or ""))
 end
 return stamp(self,slot)
end
local target=B.TargetDescriptor
function B:TargetDescriptor(selfCast)
 if not selfCast and self.targetMode=="MOUSEOVER" then return self:GUID("mouseover") end
 return target(self,selfCast)
end
function B:ClickDescriptor(selfCast)
 if selfCast then return "SELF" end
 return "LEFT:"..self:TargetDescriptor(false)
end
local choose=B.ChooseTarget
function B:ChooseTarget(descriptor)
 if descriptor=="KEEP" then return true end
 local unit=descriptor=="SELF" and "player" or (descriptor=="MAIN" and self:PeerUnit() or descriptor)
 if unit and unit~="" then
  local guid=self:GUID(unit)
  if guid~="" and guid==self:GUID("target") then return true end
 end
 return choose(self,descriptor)
end
function B:CastAction(index,selfCast,mouseover,descriptor)
 self.lastMacroTarget=nil
 local _,_,_,usesMouseover=self:ActionDetails(index)
 if usesMouseover~="1" then return self:Invoke("UseAction",index,0,selfCast and 1 or nil) end
 local effective=mouseover or ""
 if descriptor=="SELF" then effective=self:GUID("player")
 elseif descriptor=="MAIN" then effective=self:GUID(self:PeerUnit()) end
 if effective=="" then effective=self:GUID("target") end
 self.lastMacroTarget=effective~="" and effective or "unavailable"
 if not self:IsGUID(effective) or self:GUID(effective)=="" then return false,"Mouseover macro: no loaded cast target" end
 if type(SetMouseoverUnit)~="function" then return false,"Mouseover macros need SetMouseoverUnit from Nampower/SuperWoW" end
 local previous=self:GUID("mouseover")
 local cleve=CleveRoids;local old=cleve and cleve.mouseoverUnit
 local mo=cleve and cleve.__mo;local triggered=mo and mo.selfTriggered
 if mo then mo.selfTriggered=true end
 local ok,why=pcall(SetMouseoverUnit,effective)
 if not ok then if mo then mo.selfTriggered=triggered end;return false,tostring(why) end
 if cleve then cleve.mouseoverUnit=effective end
 local accepted,reason=self:Invoke("UseAction",index,0,selfCast and 1 or nil)
 if cleve then cleve.mouseoverUnit=old end
 if previous~="" and self:GUID(previous)=="" then previous="" end
 pcall(SetMouseoverUnit,previous)
 if mo then mo.selfTriggered=triggered end
 return accepted,reason
end
local execute=B.Execute
function B:Execute(fields)
 if fields[1]=="SKILL" then
  if table.getn(fields)~=5 then return false,"Invalid skill request" end
  local index=self:FindSkill(fields[2],fields[3])
  if not index then return false,"That exact spell/rank is not in the follower's spellbook" end
  return self:RequestCast("SPELL",index,self:SpellStamp(index),fields[4],fields[5])
 end
 if fields[1]=="ACTION" or fields[1]=="SPELL" then
  local mouse=fields[5]
  if mouse and mouse~="" and not self:IsGUID(mouse) then return false,"Invalid mouseover GUID" end
 end
 return execute(self,fields)
end
-- Keep the most recent main target for ungrouped Pet assist. Never append
-- "target" to a GUID and hand the resulting invalid token to Unit APIs.
local message=B.Message
function B:Message(kind,fields,id,now)
 if (kind=="MAINTARGET" or kind=="PING") and self.db.role=="agent" and self.connected and fields[1]~=nil and id>(self.lastMainTargetID or 0) then
  if fields[1]=="" or self:IsGUID(fields[1]) then self.mainTargetGUID,self.lastMainTargetID,self.lastReceive=fields[1],id,now end
 end
 return message(self,kind,fields,id,now)
end
function B:SendMainTarget()
 if not self.db or self.db.role~="control" then return end
 local guid=self:GUID("target")
 for _,name in ipairs(self:FollowerNames()) do self:WithFollower(name,function(b)
  if b.connected then b:SendNow("MAINTARGET",{guid}) end
 end) end
end

local initialize=B.Initialize
function B:Initialize()
 zBoxDB=zBoxDB or {}
 if zBoxDB.feedbackSchema~=2 then zBoxDB.verboseFeedback=false;zBoxDB.feedbackSchema=2 end
 initialize(self)
end
