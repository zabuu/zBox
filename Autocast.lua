-- Autocast for linked characters' dock skills, like pet-bar autocast.
-- Right-click a dock slot to toggle it. The skill owner decides when to cast:
-- it walks its autocast skills from the left and casts the first one that is
-- off cooldown, usable and has a valid target, while either character is in combat.
local B=zBox
local MODES={TARGET=true,MAIN=true,SELF=true,KEEP=true,MOUSEOVER=true}

-- Driver --------------------------------------------------------------------

function B:ToggleAutocast(slot)
 local p=self:BarProfile();local e=p.pages[p.page][slot]
 if not e then return false end
 if self:Name(e.peer)==self:Name(UnitName("player")) then
  self:Notify("Autocast is for linked characters' skills");return false
 end
 e.autocast=not e.autocast or nil
 self.notice=(e.label or "Skill").." autocast "..(e.autocast and "on" or "off")
 self:RenderBar();if self.UI then self.UI.dirty=true end
 return true
end

-- Ordered autocast list for one follower, from the visible dock page.
function B:AutocastPayload(name)
 local p=self:BarProfile();local rows={}
 for slot=1,12 do
  local e=p.pages[p.page][slot]
  if e and e.autocast and e.realm==self:Realm() and self:Name(e.peer)==self:Name(name) then
   local cond=e.autocastIf or ""
   if e.command=="SKILL" then table.insert(rows,self:Encode({"S",e.name or "",e.rank or "",cond}))
   elseif e.command=="ACTION" then table.insert(rows,self:Encode({"A",e.slot or "",e.stamp or "",cond})) end
  end
 end
 return table.concat(rows,"\n")
end

function B:SyncAutocast(now)
 if self.db.role~="control" or self.rosterBackground or not self.independentBars or not self.independentBars.ready then return end
 local mode=MODES[self.targetMode or ""] and self.targetMode or "TARGET"
 for _,name in ipairs(self:FollowerNames()) do
  local payload=self:AutocastPayload(name)
  self:WithFollower(name,function(b)
   if not b.connected then return end
   local fresh=b.autoSession==b.session and b.autoPayload==payload and b.autoMode==mode
   if fresh and (payload=="" or now-(b.autoSentAt or -10)<5) then return end
   if b:Send("AUTO",{mode,payload},true) then
    b.autoSession,b.autoPayload,b.autoMode,b.autoSentAt=b.session,payload,mode,now
   end
  end)
 end
end

local barTick=B.BarTick
if barTick then function B:BarTick(now)
 barTick(self,now)
 if now>=(self.nextAutocastSync or 0) then self.nextAutocastSync=now+.25;self:SyncAutocast(now) end
 local s=self.independentBars
 if s and s.ready and self.UI and now>=(self.nextAutocastPaint or 0) then
  self.nextAutocastPaint=now+.05
  local p=self:BarProfile();local alpha=.55+.45*math.abs(math.sin(now*3))
  for i,cell in ipairs(self.UI.dockCells) do
   local e=p.pages[p.page][i]
   if e and e.autocast then
    if not cell.autocast then
     cell.autocast=cell:CreateTexture(nil,"OVERLAY");cell.autocast:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
     cell.autocast:SetWidth(60);cell.autocast:SetHeight(60);cell.autocast:SetPoint("CENTER",cell,"CENTER",0,0)
     cell.autocast:SetVertexColor(.3,1,.6)
    end
    cell.autocast:SetAlpha(alpha);cell.autocast:Show()
   elseif cell.autocast then cell.autocast:Hide() end
  end
 end
end end

-- Follower ------------------------------------------------------------------

local message=B.Message
function B:Message(kind,fields,id,now)
 if self.db.role=="agent" and self.connected then
  if kind=="PING" then self.mainCombat=fields[2]=="1" end
  if kind=="AUTO" then
   self.lastReceive=now
   local mode,list=fields[1],{}
   if table.getn(fields)==2 and MODES[mode or ""] and string.len(fields[2] or "")<=4000 then
    for _,encoded in ipairs(fields[2]=="" and {} or self.Split(fields[2],"\n")) do
     local row=self:Decode(encoded)
     local n=table.getn(row)
     if (n==3 or n==4) and (row[1]=="S" or row[1]=="A") and table.getn(list)<12 then
      local cond=n==4 and row[4]~="" and self:ParseAutocastCondition(row[4]) or nil
      table.insert(list,{kind=row[1],a=row[2],b=row[3],cond=cond,key=encoded})
     end
    end
    self.skillInfo=nil
    if table.getn(list)>0 then
     local old=self.autocast and self.autocast.backoff or {}
     self.autocast={mode=mode,list=list,backoff=old}
    else self.autocast=nil end
   end
  end
 end
 return message(self,kind,fields,id,now)
end

local disconnect=B.Disconnect
function B:Disconnect(reason)
 self.autocast,self.autoCheck,self.mainCombat=nil,nil,nil
 self.autoSession,self.autoPayload,self.autoMode,self.autoSentAt=nil,nil,nil,nil
 return disconnect(self,reason)
end

local function truthy(ok,value) return ok and (value==true or value==1) end
local function attackable(unit)
 if not unit or unit=="" then return false end
 local ok,exists=pcall(UnitExists,unit);if not ok or not exists then return false end
 if UnitIsDeadOrGhost and truthy(pcall(UnitIsDeadOrGhost,unit)) then return false end
 return UnitCanAttack and truthy(pcall(UnitCanAttack,"player",unit))
end

-- Smart checks ---------------------------------------------------------------
-- Classify a skill from its tooltip (English client): heal, damage over time,
-- or a pure effect (buff/debuff with no direct damage). Cached per spell/rank.
B.AUTO_HEAL_BELOW=.9 -- heal a target only below 90% health
B.AUTO_REFRESH_BEFORE=4 -- refresh a full debuff stack this many seconds before it expires

function B:SkillText(command,index)
 if not self.scanTooltip and CreateFrame then
  self.scanTooltip=CreateFrame("GameTooltip","zBoxScanTooltip",UIParent,"GameTooltipTemplate")
 end
 local tip=self.scanTooltip;if not tip then return "" end
 tip:SetOwner(UIParent,"ANCHOR_NONE");tip:ClearLines()
 if command=="SPELL" then tip:SetSpell(index,BOOKTYPE_SPELL or "spell") else tip:SetAction(index) end
 local lines={}
 for i=2,math.min(12,tip:NumLines() or 0) do -- line 1 is the name
  local left=getglobal("zBoxScanTooltipTextLeft"..i);local text=left and left:GetText()
  if text then table.insert(lines,text) end
 end
 tip:Hide()
 return string.lower(table.concat(lines," "))
end

function B:SkillInfo(command,index,stamp)
 self.skillInfo=self.skillInfo or {}
 local key=command..":"..index..":"..tostring(stamp)
 local info=self.skillInfo[key]
 if info then return info end
 local ok,text=pcall(self.SkillText,self,command,index)
 if not ok or type(text)~="string" then text="" end
 local icon
 if command=="SPELL" then icon=GetSpellTexture(index,BOOKTYPE_SPELL or "spell") else icon=GetActionTexture(index) end
 local direct,over,at=false,false,1
 while true do
  local s,e=string.find(text,"damage",at,true);if not s then break end
  if string.find(string.sub(text,e+1,e+12),"^%s*over") then over=true else direct=true end
  at=e+1
 end
 info={icon=icon and string.lower(icon) or "",known=text~="",
  heal=string.find(text,"heal",1,true)~=nil,dot=over and not direct,effect=text~="" and not direct and not over}
 info.hot=info.heal and string.find(text,"over %d+ sec")~=nil
 -- "Can be applied up to 5 times" / "stacks up to 5 times": keep applying until full.
 local _,_,stacks=string.find(text,"up to (%d+) times")
 info.stacks=tonumber(stacks)
 local _,_,lasts=string.find(text,"lasts (%d+) sec")
 if not lasts then _,_,lasts=string.find(text,"for (%d+) sec") end
 info.duration=tonumber(lasts)
 self.skillInfo[key]=info
 return info
end

-- True when unit already shows an aura with this skill's icon (at maxStacks
-- applications, when the skill stacks).
function B:HasAura(unit,icon,harmful,maxStacks)
 if not icon or icon=="" then return false end
 local api=harmful and UnitDebuff or UnitBuff;if not api then return false end
 for i=1,harmful and 16 or 32 do
  local ok,texture,count=pcall(api,unit,i)
  if not ok or not texture then break end
  if string.lower(texture)==icon then return not maxStacks or (tonumber(count) or 1)>=maxStacks end
 end
 return false
end

local function healthFraction(unit)
 local ok,exists=pcall(UnitExists,unit);if not ok or not exists then return end
 if UnitIsDeadOrGhost and truthy(pcall(UnitIsDeadOrGhost,unit)) then return end
 local hok,hp=pcall(UnitHealth,unit);local mok,max=pcall(UnitHealthMax,unit)
 if not hok or not mok or type(hp)~="number" or type(max)~="number" or max<=0 then return end
 return hp/max
end

-- Friendly skill target: heals pick the most hurt of main/owner below the
-- threshold; buffs pick the first of main/owner that lacks the buff.
function B:AutocastFriendly(info,mode)
 local options={}
 local main=self:PeerUnit()
 if mode~="SELF" and main then table.insert(options,{"MAIN",main}) end
 if mode~="MAIN" or not main then table.insert(options,{"SELF","player"}) end
 if not info.known then return options[1] and options[1][1] end
 if info.heal then
  local best,low
  for _,o in ipairs(options) do
   local f=healthFraction(o[2])
   if f and f<self.AUTO_HEAL_BELOW and (not low or f<low) and not (info.hot and self:HasAura(o[2],info.icon)) then best,low=o[1],f end
  end
  return best
 end
 for _,o in ipairs(options) do
  if healthFraction(o[2]) and not self:HasAura(o[2],info.icon) then return o[1] end
 end
end

-- Returns command, index, stamp and target descriptor when this item can fire now.
function B:AutocastCandidate(item,mode,now)
 local book=BOOKTYPE_SPELL or "spell"
 local command,index,stamp,start,duration,enabled,usable,ranged
 if item.kind=="S" then
  index=self:FindSkill(item.a,item.b);if not index then return end
  command,stamp="SPELL",self:SpellStamp(index)
  if IsUsableSpell then local ok,u=pcall(IsUsableSpell,index,book);if ok and not u then return end end
  start,duration,enabled=GetSpellCooldown(index,book)
  if SpellHasRange then local ok,r=pcall(SpellHasRange,index,book);if ok then ranged=not (r==false or r==0) end end
 else
  index=self.Integer(item.a,1,120);if not index or not HasAction(index) or self:ActionStamp(index)~=item.b then return end
  command,stamp="ACTION",item.b
  if IsUsableAction then local ok,u=pcall(IsUsableAction,index);if ok and not u then return end end
  start,duration,enabled=GetActionCooldown(index)
  if ActionHasRange then local ok,r=pcall(ActionHasRange,index);if ok then ranged=not (r==false or r==0) end end
 end
 if self:Cooldown(start,duration,enabled)>0 then return end
 if item.cond and not self:AutocastAllowed(item.cond,mode) then return end
 local target,track
 if mode=="SELF" or mode=="MAIN" or mode=="KEEP" then target=mode end
 local info=self:SkillInfo(command,index,stamp)
 if self:IsFriendlyCast(command,index) then
  target=self:AutocastFriendly(info,mode)
  if not target then return end
 elseif ranged==false then
  -- Self-only skills need no target; skip self-buffs that are already up.
  if info.heal then if (healthFraction("player") or 1)>=self.AUTO_HEAL_BELOW then return end
  elseif info.known and self:HasAura("player",info.icon) then return end
  target="KEEP"
 else
  if mode=="KEEP" then if not attackable("target") then return end
  elseif mode=="TARGET" or mode=="MOUSEOVER" then
   target=self.mainTargetGUID or ""
   if not attackable(target) then return end
  end
  -- DoTs and pure debuffs (stings, curses) are not reapplied while up;
  -- stacking ones (Sunder Armor) are applied until they reach max stacks,
  -- then refreshed shortly before they would fall off.
  if (info.dot or info.effect) and (mode=="KEEP" or mode=="TARGET" or mode=="MOUSEOVER") then
   local guid=mode=="KEEP" and self:GUID("target") or target
   track={guid=guid,icon=info.icon}
   if self:HasAura(mode=="KEEP" and "target" or target,info.icon,true,info.stacks) then
    local applied=self.autoApplied and self.autoApplied[guid..info.icon]
    local due=info.stacks and info.duration and applied and now>=applied+info.duration-self.AUTO_REFRESH_BEFORE
    if not due then return end
   end
  end
 end
 return command,index,stamp,target,track
end

function B:AutocastTick(now)
 local auto=self.autocast
 if not auto or now<(self.nextAutocast or 0) then return end
 self.nextAutocast=now+.15
 local book=BOOKTYPE_SPELL or "spell"
 local check=self.autoCheck
 if check then
  if now<check.at then return end
  -- Count an attempt as cast when it started a cast or a cooldown (incl. GCD).
  local cd=0
  if check.command=="SPELL" then cd=self:Cooldown(GetSpellCooldown(check.index,book)) else cd=self:Cooldown(GetActionCooldown(check.index)) end
  if not (cd>0 or self.castActive or (self.castingUntil and self.castingUntil>now)) then auto.backoff[check.key]=now+1.5
  elseif check.track and check.track.guid~="" then
   -- Remember when we (re)applied a debuff: 1.12 does not expose aura timers.
   self.autoApplied=self.autoApplied or {}
   self.autoApplied[check.track.guid..check.track.icon]=check.at-.6
  end
  self.autoCheck=nil
 end
 if UnitIsDeadOrGhost("player") or self:IsCastHeld(now) then return end
 self.auraNames=nil -- aura names are read at most once per unit per pass
 local unit=self:PeerUnit()
 local combat=UnitAffectingCombat("player") or self.mainCombat or (unit and UnitAffectingCombat(unit))
 if not combat then return end
 for _,item in ipairs(auto.list) do
  if now>=(auto.backoff[item.key] or 0) then
   local command,index,stamp,target,track=self:AutocastCandidate(item,auto.mode,now)
   if command then
    local ok=self:RequestCast(command,index,stamp,target,"")
    if ok then self.autoCheck={key=item.key,command=command,index=index,at=now+.6,track=track};return end
    auto.backoff[item.key]=now+2
   end
  end
 end
end

local tick=B.Tick
function B:Tick(now,elapsed)
 tick(self,now,elapsed)
 if self.connected and self.db.role=="agent" and self.autocast then self:AutocastTick(now) end
end

-- Custom conditions ----------------------------------------------------------
-- Ctrl-right-click a dock skill to give it a condition. Every rule must hold:
--   cp>=4  hp<50  mana>30  rage>=40  energy>=60  mhp<70  thp<20  php<50
--   buff:Name  debuff:Name       (on the skill owner)
--   tbuff:Name tdebuff:Name      (on the enemy: main's target, or owner's target in Owner's target mode)
--   mbuff:Name mdebuff:Name      (on your main)
--   pbuff:Name                   (on the owner's pet)
-- Put ! in front to require it missing (!tdebuff:Sunder). Name|Other means either.
-- Aura names are case-insensitive partial matches; write spaces as _.
-- behind / !behind: the owner is (not) behind the enemy (needs zBoxBridge geometry).
-- aggro / maggro / paggro: the enemy is attacking the owner / main / owner's pet
-- (1.12 has no threat API, so this reads who the enemy has targeted).
-- tdebuff:Sunder>=5 compares the stack count. Rules are separated by spaces or commas.
local NUMBERS={cp=true,combo=true,hp=true,mana=true,power=true,rage=true,energy=true,mhp=true,thp=true,php=true}
local AURAS={buff={"self",false},debuff={"self",true},tbuff={"enemy",false},tdebuff={"enemy",true},
 mbuff={"main",false},mdebuff={"main",true},pbuff={"pet",false},pdebuff={"pet",true}}
local OPS={["<"]=true,["<="]=true,[">"]=true,[">="]=true,["="]=true,["=="]=true,["~="]=true,["!="]=true}
local function compare(a,op,b)
 if op=="<" then return a<b elseif op=="<=" then return a<=b elseif op==">" then return a>b
 elseif op==">=" then return a>=b elseif op=="~=" or op=="!=" then return a~=b end
 return a==b
end

-- Returns a rule list, or nil and an error message for the editor.
function B:ParseAutocastCondition(text)
 text=string.lower(tostring(text or ""))
 if string.len(text)>200 then return nil,"Too long (200 characters max)" end
 local rules={}
 for token in string.gfind(text,"[^%s,]+") do
  local _,_,key,op,num=string.find(token,"^(%a+)([<>=~!]+)(%-?%d+)$")
  local _,_,flagNeg,flag=string.find(token,"^(!?)(%a+)$")
  if flag=="behind" then
   table.insert(rules,{kind="behind",negate=flagNeg=="!"})
  elseif flag=="aggro" or flag=="maggro" or flag=="paggro" then
   table.insert(rules,{kind="aggro",who=({aggro="self",maggro="main",paggro="pet"})[flag],negate=flagNeg=="!"})
  elseif key then
   if not NUMBERS[key] then return nil,"Unknown value '"..key.."'" end
   if not OPS[op] then return nil,"Unknown comparison '"..op.."'" end
   table.insert(rules,{kind="num",key=key=="combo" and "cp" or key,op=op,value=tonumber(num)})
  else
   local _,_,neg,kind,rest=string.find(token,"^(!?)(%a+):(.+)$")
   local aura=kind and AURAS[kind]
   if not aura then return nil,"Can't read '"..token.."'" end
   local _,_,names,cop,count=string.find(rest,"^(.-)([<>=~!]+)(%d+)$")
   if names then if not OPS[cop] then return nil,"Unknown comparison '"..cop.."'" end else names=rest end
   local list={}
   for name in string.gfind(names,"[^|]+") do table.insert(list,(string.gsub(name,"_"," "))) end
   if table.getn(list)==0 then return nil,"Missing aura name in '"..token.."'" end
   table.insert(rules,{kind="aura",unit=aura[1],harmful=aura[2],names=list,negate=neg=="!",op=cop,count=tonumber(count)})
  end
 end
 if table.getn(rules)>12 then return nil,"Too many rules (12 max)" end
 return rules
end

-- Lower-cased aura names (with stack counts) on a unit, read from tooltips.
function B:AuraNames(unit,harmful)
 self.auraNames=self.auraNames or {}
 local key=unit..(harmful and ":d" or ":b")
 if self.auraNames[key] then return self.auraNames[key] end
 local list={}
 if not self.scanTooltip and CreateFrame then
  self.scanTooltip=CreateFrame("GameTooltip","zBoxScanTooltip",UIParent,"GameTooltipTemplate")
 end
 local tip,api=self.scanTooltip,harmful and UnitDebuff or UnitBuff
 if tip and api then
  for i=1,harmful and 16 or 32 do
   local ok,texture,count=pcall(api,unit,i)
   if not ok or not texture then break end
   tip:SetOwner(UIParent,"ANCHOR_NONE");tip:ClearLines()
   if harmful then pcall(tip.SetUnitDebuff,tip,unit,i) else pcall(tip.SetUnitBuff,tip,unit,i) end
   local line=getglobal("zBoxScanTooltipTextLeft1");local name=line and line:GetText()
   tip:Hide()
   table.insert(list,{name=string.lower(name or ""),count=tonumber(count) or 1})
  end
 end
 self.auraNames[key]=list
 return list
end

local function percent(unit,current,maximum)
 local ok,exists=pcall(UnitExists,unit);if not ok or not exists then return end
 local a,b=current(unit),maximum(unit)
 if type(a)~="number" or type(b)~="number" or b<=0 then return end
 return a/b*100
end

function B:AutocastUnit(which,mode)
 if which=="self" then return "player" end
 if which=="main" then return self:PeerUnit() end
 if which=="pet" then return "pet" end
 if mode=="KEEP" then return "target" end
 local guid=self.mainTargetGUID
 return guid and guid~="" and guid or nil
end

function B:AutocastValue(key,mode)
 if key=="cp" then
  if not GetComboPoints then return 0 end
  local ok,cp=pcall(GetComboPoints,"player","target");if not ok or type(cp)~="number" then ok,cp=pcall(GetComboPoints) end
  return ok and tonumber(cp) or 0
 end
 if key=="rage" or key=="energy" then local ok,v=pcall(UnitMana,"player");return ok and tonumber(v) or 0 end
 if key=="mana" or key=="power" then return percent("player",UnitMana,UnitManaMax) end
 local unit=({hp="player",mhp=self:PeerUnit(),php="pet",thp=self:AutocastUnit("enemy",mode)})[key]
 if not unit then return end
 return percent(unit,UnitHealth,UnitHealthMax)
end

-- True/false when the owner is behind the enemy's back half; nil when unknown.
function B:AutocastBehind(mode)
 local guid=mode=="KEEP" and self:GUID("target") or self.mainTargetGUID
 if not guid or guid=="" or not self.PetGeometry then return end
 local g=self:PetGeometry(guid);if not g or g.distance<.2 then return end
 local dx,dy=g.px-g.x,g.py-g.y
 return (dx*math.cos(g.facing)+dy*math.sin(g.facing))/g.distance < -.1
end

-- Whether the enemy is attacking who ("self", "main", "pet"); nil when there is
-- no enemy to look at. An enemy with no target is attacking nobody.
function B:AutocastAggro(who,mode)
 local enemy=mode=="KEEP" and self:GUID("target") or self.mainTargetGUID
 if not enemy or enemy=="" then return end
 local victim
 if self:GUID("target")==enemy then victim="targettarget"
 else local main=self:PeerUnit();if main and not string.find(main,"^0x") then victim=main.."targettarget" end end
 if not victim or self:GUID((string.gsub(victim,"target$","")))~=enemy then return end
 local v=self:GUID(victim);if v=="" then return false end
 local unit=who=="main" and self:PeerUnit() or (who=="pet" and "pet" or "player")
 local u=unit and self:GUID(unit) or ""
 return u~="" and string.lower(u)==string.lower(v)
end

function B:AutocastAllowed(rules,mode)
 for _,r in ipairs(rules) do
  if r.kind=="aggro" then
   local has=self:AutocastAggro(r.who,mode)
   if has==nil or has==r.negate then return false end
  elseif r.kind=="behind" then
   local behind=self:AutocastBehind(mode)
   if behind==nil or behind==r.negate then return false end
  elseif r.kind=="num" then
   local v=self:AutocastValue(r.key,mode)
   if not v or not compare(v,r.op,r.value) then return false end
  else
   local unit=self:AutocastUnit(r.unit,mode)
   local found=false
   if unit then
    for _,aura in ipairs(self:AuraNames(unit,r.harmful)) do
     for _,name in ipairs(r.names) do
      if aura.name~="" and string.find(aura.name,name,1,true) and (not r.op or compare(aura.count,r.op,r.count)) then found=true;break end
     end
     if found then break end
    end
   end
   if found==r.negate then return false end
  end
 end
 return true
end

-- Driver-side editor.
function B:SetAutocastCondition(slot,text)
 local p=self:BarProfile();local e=p.pages[p.page][slot]
 if not e then return false,"Empty slot" end
 text=string.gsub(tostring(text or ""),"^%s*(.-)%s*$","%1")
 if text=="" then e.autocastIf=nil
 else
  local rules,err=self:ParseAutocastCondition(text);if not rules then return false,err end
  e.autocastIf=text
  if self:Name(e.peer)~=self:Name(UnitName("player")) then e.autocast=true end
 end
 self:RenderBar();if self.UI then self.UI.dirty=true end
 return true
end

local HELP="Every rule must be true. Separate rules with spaces.\n"..
 "|cff88ddddcp>=4|r combo points   |cff88ddddhp<50|r owner health %   |cff88ddddmhp<70|r main health %\n"..
 "|cff88ddddthp<20|r enemy health %   |cff88ddddmana>30|r mana %   |cff88ddddrage>=40|r  |cff88ddddenergy>=60|r\n"..
 "|cff88ddddtbuff:Frenzy||Enrage|r enemy has a buff   |cff88ddddtdebuff:Sunder>=5|r enemy debuff (stacks)\n"..
 "|cff88ddddbuff:|r / |cff88dddddebuff:|r on owner   |cff88ddddmbuff:|r on main   |cff88ddddpbuff:|r on pet\n"..
 "|cff88ddddbehind|r owner is behind the enemy, |cff88dddd!behind|r not behind.\n"..
 "|cff88ddddaggro|r enemy is attacking the owner (|cff88ddddmaggro|r your main, |cff88ddddpaggro|r owner's pet).\n"..
 "Put |cff88dddd!|r in front for \"missing\" (|cff88dddd!tdebuff:Serpent_Sting|r). Use _ for spaces."

function B:OpenAutocastEditor(slot)
 local p=self:BarProfile();local e=p.pages[p.page][slot]
 if not e or not CreateFrame then return false end
 if self:Name(e.peer)==self:Name(UnitName("player")) then self:Notify("Autocast is for linked characters' skills");return false end
 local f=self.autoEditor
 if not f then
  f=CreateFrame("Frame","zBoxAutocastEditor",UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG");f:SetToplevel(true);f:EnableMouse(true);f:SetMovable(true)
  f:RegisterForDrag("LeftButton");f:SetScript("OnDragStart",function() this:StartMoving() end)
  f:SetScript("OnDragStop",function() this:StopMovingOrSizing() end)
  f:SetWidth(430);f:SetHeight(206);f:SetPoint("CENTER",UIParent,"CENTER",0,120)
  f:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
  f:SetBackdropColor(.025,.035,.045,.97);f:SetBackdropBorderColor(.25,.45,.49,1)
  f.title=f:CreateFontString(nil,"OVERLAY","GameFontNormal");f.title:SetPoint("TOPLEFT",f,"TOPLEFT",12,-10)
  f.box=CreateFrame("EditBox","zBoxAutocastEditorBox",f,"InputBoxTemplate")
  f.box:SetWidth(396);f.box:SetHeight(24);f.box:SetPoint("TOPLEFT",f,"TOPLEFT",18,-30);f.box:SetAutoFocus(false);f.box:SetMaxLetters(200)
  f.box:SetScript("OnEscapePressed",function() f:Hide() end)
  f.box:SetScript("OnEnterPressed",function() B:SaveAutocastEditor() end)
  f.box:SetScript("OnTextChanged",function()
   local text=f.box:GetText() or "";local ok,err=B:ParseAutocastCondition(text)
   if string.gsub(text,"%s","")=="" then f.status:SetText("No condition: smart checks only.");f.status:SetTextColor(.7,.85,.85)
   elseif ok then f.status:SetText("Looks good.");f.status:SetTextColor(.3,1,.6)
   else f.status:SetText(err);f.status:SetTextColor(1,.4,.35) end
  end)
  f.status=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");f.status:SetPoint("TOPLEFT",f,"TOPLEFT",14,-58)
  f.help=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");f.help:SetPoint("TOPLEFT",f,"TOPLEFT",14,-76)
  f.help:SetWidth(404);f.help:SetJustifyH("LEFT");f.help:SetText(HELP)
  local function btn(caption,x,handler)
   local b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate");b:SetWidth(70);b:SetHeight(20)
   b:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",x,10);b:SetText(caption);b:SetScript("OnClick",handler);return b
  end
  f.save=btn("Save",-160,function() B:SaveAutocastEditor() end)
  f.clear=btn("Clear",-86,function() f.box:SetText("");B:SaveAutocastEditor() end)
  f.cancel=btn("Cancel",-12,function() f:Hide() end)
  f:Hide();table.insert(UISpecialFrames,"zBoxAutocastEditor")
  self.autoEditor=f
 end
 f.slot,f.page=slot,p.page
 f.title:SetText("Autocast condition: "..(e.label or e.name or "Skill"))
 f.box:SetText(e.autocastIf or "");f.status:SetText("")
 f:Show();f.box:SetFocus()
 if f.box:GetScript("OnTextChanged") then f.box:GetScript("OnTextChanged")() end
 return true
end

function B:SaveAutocastEditor()
 local f=self.autoEditor;if not f then return false end
 local p=self:BarProfile()
 if p.page~=f.page then f:Hide();return false end
 local ok,err=self:SetAutocastCondition(f.slot,f.box:GetText())
 if not ok then f.status:SetText(err or "Can't save");f.status:SetTextColor(1,.4,.35);return false end
 f:Hide();return true
end
