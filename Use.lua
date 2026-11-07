-- Click-to-use: in Move mode, clicking a friendly NPC sends the follower to
-- walk up to it and talk to it (gossip, vendor, trainer, quest giver).
-- With zBoxBridge 0.1.12 (contract 11) game objects work too: chests, herbs,
-- ore, barrels, doors and mailboxes are walked to and right-clicked.
-- Clicking a dead NPC sends the follower to loot it and take everything.
local B=zBox
B.USE_RANGE=4.5 -- talk once within this many yards (the game allows about 6)
B.USE_OBJECT_RADIUS=3 -- a ground click this close to a chest/herb uses it
B.LOOT_RANGE=3.5 -- loot once within this many yards (the game allows about 5)

local function friendlyNPC(unit)
 if not unit or unit=="" then return false end
 local ok,exists=pcall(UnitExists,unit);if not ok or not exists then return false end
 if UnitIsPlayer and UnitIsPlayer(unit) then return false end
 if UnitCanAttack and UnitCanAttack("player",unit) then return false end
 if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return false end
 return true
end

local function corpse(unit)
 if not unit or unit=="" then return false end
 local ok,exists=pcall(UnitExists,unit);if not ok or not exists then return false end
 if UnitIsPlayer and UnitIsPlayer(unit) then return false end
 return UnitIsDead and UnitIsDead(unit) and true or false
end

-- Driver ---------------------------------------------------------------------

-- A dead NPC under the cursor (or the main's dead target near the clicked point).
function B:PickLootTarget(x,y,z)
 local hovered=self:GUID("mouseover")
 if hovered~="" and corpse("mouseover") then return hovered end
 if x and corpse("target") then
  local tx,ty,tz=self:Position("target")
  if tx and (x-tx)^2+(y-ty)^2<=3^2 and math.abs(z-tz)<4 then return self:GUID("target") end
 end
end

-- The NPC the click was on: the hovered NPC, or else the main's target when the
-- clicked ground point lands within a few yards of it.
function B:PickUseTarget(x,y,z)
 local hovered=self:GUID("mouseover")
 if hovered~="" and friendlyNPC("mouseover") then return hovered end
 if x and friendlyNPC("target") then
  local tx,ty,tz=self:Position("target")
  if tx and (x-tx)^2+(y-ty)^2<=4^2 and math.abs(z-tz)<4 then return self:GUID("target") end
 end
end

-- The game object under the cursor (needs bridge contract 11 on this client).
-- When a ground point is known, the object must sit near it: a wrong lookup
-- then falls back to an ordinary move instead of walking somewhere odd.
function B:PickUseObject(x,y,z)
 if type(zBoxNative)~="function" or not self:GetBridgeInfo().objects then return end
 local ok,result,guid,ox,oy,oz=pcall(zBoxNative,"MouseoverObject")
 -- Bridge 0.1.13: otherwise take the game object nearest the clicked point.
 if (not ok or result~=1) and x and self:GetBridgeInfo().nearestObjects then
  ok,result,guid,ox,oy,oz=pcall(zBoxNative,"NearestObject",x,y,z,self.USE_OBJECT_RADIUS)
 end
 if not ok or result~=1 or type(guid)~="string" or not string.find(guid,"^0x%x+$") or string.len(guid)~=18 then return end
 for _,v in ipairs({ox,oy,oz}) do if type(v)~="number" or v~=v or math.abs(v)>100000 then return end end
 local px,py,pz=self:Position("player")
 if not px or (ox-px)^2+(oy-py)^2>120^2 or math.abs(oz-pz)>35 then return end
 if x and ((ox-x)^2+(oy-y)^2>8^2 or math.abs(oz-z)>8) then return end
 return guid,ox,oy,oz
end

local function fmt(v) return string.format("%.3f",v) end

-- Open the Talk window first (like the Talk button); it fills in once the
-- follower reaches the NPC and the dialog opens.
function B:WalkUseNPC(guid,map)
 local ok,reason=self:Command("WALKUSE",{guid,map})
 if ok and self.UI and self.UI.OpenNPC then self.UI:OpenNPC() end
 return ok,reason
end

function B:CaptureMoveOrUse()
 if not self.connected then return false,"Connect the second character first" end
 local map=GetRealZoneText and GetRealZoneText() or ""
 local guid=self:PickUseTarget()
 if guid then return self:WalkUseNPC(guid,map) end
 guid=self:PickLootTarget()
 if guid then return self:Command("WALKUSE",{guid,map,"L"}) end
 local x,y,z=self:PickTerrain()
 local object,ox,oy,oz=self:PickUseObject(x,y,z)
 if object then return self:Command("WALKUSE",{object,map,"O",fmt(ox),fmt(oy),fmt(oz)}) end
 if not x then self.lastPick=tostring(y);return false,y end
 guid=self:PickUseTarget(x,y,z)
 if guid then return self:WalkUseNPC(guid,map) end
 guid=self:PickLootTarget(x,y,z)
 if guid then return self:Command("WALKUSE",{guid,map,"L"}) end
 self.lastPick=(self.lastPickMethod or "Terrain")..string.format(" %.1f, %.1f, %.1f",x,y,z)
 return self:Command("MOVETO",{string.format("%.3f",x),string.format("%.3f",y),string.format("%.3f",z),map})
end

-- Follower -------------------------------------------------------------------

function B:WalkToUse(guid,map)
 if map~=((GetRealZoneText and GetRealZoneText()) or "") then return false,"Both characters must be in the same zone" end
 if not string.find(guid or "","^0x%x+$") then return false,"Invalid NPC" end
 if not self:GetBridgeInfo().npc then return false,"Talking to NPCs needs zBoxBridge 0.1.4 or newer" end
 if UnitAffectingCombat("player") then return false,"Talk outside combat" end
 local ok,reason=self:ChooseTarget(guid);if not ok then return false,reason end
 if not friendlyNPC("target") then return false,"Choose a living friendly NPC" end
 local x,y,z=self:Position("target");local px,py,pz=self:Position("player")
 if not x or not px then return false,"NPC position is unavailable" end
 if (x-px)^2+(y-py)^2<=self.USE_RANGE^2 and math.abs(z-pz)<4 then return self:TalkToNPC(guid) end
 local moved,why=self:BeginMove(x,y,z)
 if not moved then return false,why end
 self.useTarget={guid=guid,started=GetTime()}
 return true,"Walking to "..(UnitName("target") or "the NPC")
end

-- Right-click the corpse (the bridge's NPC right-click loots dead units), then
-- take every item when the loot window opens.
function B:LootCorpse(guid)
 if UnitAffectingCombat("player") then return false,"Loot outside combat" end
 local stopped,reason=self:StopMovement(nil,true);if not stopped then return false,reason end
 local ok,result,detail=pcall(zBoxNative,"InteractNPC",guid)
 if not ok or result~=1 then return false,ok and detail or tostring(result) end
 self.pendingLoot=GetTime()
 return true,"Looting"
end

function B:WalkToLoot(guid,map)
 if map~=((GetRealZoneText and GetRealZoneText()) or "") then return false,"Both characters must be in the same zone" end
 if not string.find(guid or "","^0x%x+$") then return false,"Invalid corpse" end
 if not self:GetBridgeInfo().npc then return false,"Looting needs zBoxBridge 0.1.4 or newer" end
 if UnitAffectingCombat("player") then return false,"Loot outside combat" end
 local ok,reason=self:ChooseTarget(guid);if not ok then return false,reason end
 if not corpse("target") then return false,"That corpse is not loaded by account 2" end
 local x,y,z=self:Position("target");local px,py,pz=self:Position("player")
 if not x or not px then return false,"Corpse position is unavailable" end
 if (x-px)^2+(y-py)^2<=self.LOOT_RANGE^2 and math.abs(z-pz)<4 then return self:LootCorpse(guid) end
 local moved,why=self:BeginMove(x,y,z)
 if not moved then return false,why end
 self.useTarget={guid=guid,started=GetTime(),loot=true}
 return true,"Walking to the corpse"
end

-- Take everything from a loot window this follower opened. Items that need a
-- confirmation (bind on pickup) or that don't fit stay; the window then closes.
function B:TakeLoot()
 if not self.pendingLoot or GetTime()-self.pendingLoot>5 then return end
 self.pendingLoot=nil
 local n=GetNumLootItems and GetNumLootItems() or 0
 for i=n,1,-1 do pcall(LootSlot,i) end
 self.closeLootAt=GetTime()+1
end

if CreateFrame then
 local lootFrame=CreateFrame("Frame")
 lootFrame:RegisterEvent("LOOT_OPENED");lootFrame:RegisterEvent("LOOT_CLOSED")
 lootFrame:SetScript("OnEvent",function()
  if event=="LOOT_OPENED" then B:TakeLoot() else B.closeLootAt=nil end
 end)
end

function B:InteractObject(guid)
 local ok,result,detail=pcall(zBoxNative,"InteractObject",guid)
 return ok and result==1,ok and detail or tostring(result)
end

function B:WalkToObject(guid,map,x,y,z)
 if map~=((GetRealZoneText and GetRealZoneText()) or "") then return false,"Both characters must be in the same zone" end
 if not string.find(guid or "","^0x%x+$") then return false,"Invalid object" end
 if not self:GetBridgeInfo().objects then return false,"Using objects needs zBoxBridge 0.1.12 on this client; fully restart it after updating the DLL" end
 x,y,z=tonumber(x),tonumber(y),tonumber(z)
 if not x or not y or not z then return false,"Invalid object position" end
 local px,py,pz=self:Position("player")
 if not px then return false,"Position is unavailable" end
 if (x-px)^2+(y-py)^2+(z-pz)^2<=self.USE_RANGE^2 then
  local stopped,reason=self:StopMovement(nil,true);if not stopped then return false,reason end
  return self:InteractObject(guid)
 end
 local moved,why=self:BeginMove(x,y,z)
 if not moved then return false,why end
 self.useTarget={guid=guid,started=GetTime(),object=true,x=x,y=y,z=z}
 return true,"Walking to the object"
end

local execute=B.Execute
function B:Execute(fields)
 if fields[1]=="WALKUSE" then
  local n=table.getn(fields)
  if n==7 and fields[4]=="O" then return self:WalkToObject(fields[2],fields[3],fields[5],fields[6],fields[7]) end
  if n==4 and fields[4]=="L" then return self:WalkToLoot(fields[2],fields[3]) end
  if n~=3 then return false,"Invalid use command" end
  return self:WalkToUse(fields[2],fields[3])
 end
 return execute(self,fields)
end

-- Any other stop (new order, STOP, cast, lost progress) cancels the pending talk.
local stopMovement=B.StopMovement
function B:StopMovement(a,b,c)
 self.useTarget=nil
 return stopMovement(self,a,b,c)
end

local movementTick=B.MovementTick
function B:MovementTick(now)
 if self.closeLootAt and now>=self.closeLootAt then
  self.closeLootAt=nil;if CloseLoot then pcall(CloseLoot) end
 end
 local use=self.useTarget
 if use and use.loot then
  if string.lower(self:GUID("target"))~=string.lower(use.guid) or now-use.started>35 then
   self.useTarget=nil;self:StopMovement()
   self:Send("ERROR",{"Loot cancelled: the corpse is no longer targeted"},true)
   return
  end
  local x,y,z=self:Position("target");local px,py,pz=self:Position("player")
  if x and px and (x-px)^2+(y-py)^2<=self.LOOT_RANGE^2 and math.abs(z-pz)<4 then
   self.useTarget=nil
   local ok,why=self:LootCorpse(use.guid)
   if not ok then self:Send("ERROR",{"Could not loot: "..tostring(why)},true) end
   return
  end
 elseif use and use.object then
  if now-use.started>35 then self.useTarget=nil;self:StopMovement();return end
  local px,py,pz=self:Position("player")
  if px and (use.x-px)^2+(use.y-py)^2+(use.z-pz)^2<=self.USE_RANGE^2 then
   self.useTarget=nil
   self:StopMovement(nil,true)
   local ok,why=self:InteractObject(use.guid)
   if not ok then self:Send("ERROR",{"Could not use the object: "..tostring(why)},true) end
   return
  end
 elseif use then
  if string.lower(self:GUID("target"))~=string.lower(use.guid) or now-use.started>35 then
   self.useTarget=nil;self:StopMovement()
   self:Send("ERROR",{"Walk-to-NPC cancelled: the NPC is no longer targeted"},true)
   return
  end
  local x,y,z=self:Position("target");local px,py,pz=self:Position("player")
  if x and px and (x-px)^2+(y-py)^2<=self.USE_RANGE^2 and math.abs(z-pz)<4 then
   self.useTarget=nil
   local ok,why=self:TalkToNPC(use.guid) -- stops movement itself
   if not ok then self:Send("ERROR",{"Could not talk to the NPC: "..tostring(why)},true) end
   return
  end
  -- Keep chasing an NPC that wanders, without resetting the stop watchdog.
  local d=self.destination
  if d and x and (d.x-x)^2+(d.y-y)^2>2^2 then d.x,d.y,d.z=x,y,z;if d.native then pcall(zBoxNative,"MoveTo",x,y,z) end end
 end
 return movementTick(self,now)
end
