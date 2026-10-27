-- Each peer owns a complete protocol/runtime state. Modules keep their existing
-- root reference; switch that state only for the duration of a synchronous call.
local B=zBox
local shared={version=true,prefix=true,frame=true,UI=true,db=true,ready=true,clock=true,worldSuspended=true,
 bridgeInfo=true,roster=true,rosterOrder=true,rosterCurrent=true,rosterBackground=true,rosterSending=true,
 rosterUI=true,macroIcons=true,cooldownButtons=true,freeBars=true,freeCursor=true,tradeUI=true,tradeEvents=true,
 vitalsProvider=true,damageBridge=true,tradeButton=true,bagMenu=true,rosterTick=true}
local inputs={"heldInputs","heldMask","heldModifiers","lastHeldAt","mirrorPaused","lastMirrorAt","lastMirrorJump",
 "lastMirrorMask","lastMirrorHeading","lastStackX","lastStackY","lastStackZ","lastStackEnabled"}
for _,key in ipairs(inputs) do shared[key]=true end
local function capture()
 local state={}
 for k,v in pairs(B) do if type(v)~="function" and not shared[k] then state[k]=v end end
 return state
end
local function apply(state)
 local keys={}
 for k,v in pairs(B) do if type(v)~="function" and not shared[k] then table.insert(keys,k) end end
 for _,k in ipairs(keys) do B[k]=nil end
 for k,v in pairs(state) do B[k]=v end
end
function B:FollowerNames()
 return self.rosterOrder or {self.db.peer}
end
function B:AnyFollowerConnected()
 if self.connected then return true end
 for _,name in ipairs(self:FollowerNames()) do local state=self:FollowerState(name);if state and state.connected then return true end end
 return false
end
function B:WithFollower(name,fn,...)
 local key=self:Name(name)
 if key==self:Name(self.db.peer) then return fn(self,unpack(arg)) end
 if not self.roster or not self.roster[key] then return false,"That follower is not paired" end
 local previous,ui,background=self.db.peer,self.UI,self.rosterBackground
 self.roster[self:Name(previous)]=capture()
 apply(self.roster[key]);self.db.peer=name;self.rosterCurrent=key;self.rosterBackground=true;self.UI=nil
 if self:GetBridgeInfo().multiLocal then pcall(zBoxNative,"LocalSelect",name) end
 local result={pcall(fn,self,unpack(arg))}
 self.roster[key]=capture();apply(self.roster[self:Name(previous)])
 self.db.peer,self.rosterCurrent,self.UI,self.rosterBackground=previous,self:Name(previous),ui,background
 if self:GetBridgeInfo().multiLocal then pcall(zBoxNative,"LocalSelect",previous) end
 if not result[1] then error(result[2]) end
 return unpack(result,2,table.getn(result))
end
function B:FollowerState(name)
 if self:Name(name)==self:Name(self.db.peer) then return self end
 return self.roster and self.roster[self:Name(name)]
end
function B:PeerCommand(name,command,fields)
 return self:WithFollower(name,function(b) return b:Command(command,fields) end)
end
function B:SelectFollower(name)
 local key=self:Name(name)
 if key==self:Name(self.db.peer) then return true end
 if not self.roster or not self.roster[key] then return false end
 if self.bagMenu then self.bagMenu:Hide() end
 if self.CancelFreeDrag and self.freeCursor then self:CancelFreeDrag() end
 self.roster[self:Name(self.db.peer)]=capture();apply(self.roster[key])
 self.db.peer,self.rosterCurrent=name,key
 if self:GetBridgeInfo().multiLocal then pcall(zBoxNative,"LocalSelect",name) end
 if self.UI then
  if self.UI.npcWindow then self.UI.npcWindow:Hide() end
  for _,bag in pairs(self.UI.bagWindows or {}) do bag:Hide() end
  self.UI.bagAwaiting=nil;self.UI.questSelected=nil;self.UI.dirty=true;self.UI:Refresh()
 end
 if self.connected then self:Request(self.view or "actions",self.page or 1) end
 return true
end
function B:CycleFollower()
 local names=self:FollowerNames()
 for i,name in ipairs(names) do if self:Name(name)==self:Name(self.db.peer) then return self:SelectFollower(names[math.mod(i,table.getn(names))+1]) end end
end
local disconnect=B.Disconnect
function B:Disconnect(reason)
 local keep={}
 if self.rosterBackground then for _,key in ipairs(inputs) do keep[key]=self[key] end end
 disconnect(self,reason)
 self.tradeOpen,self.tradePartner,self.tradePending,self.destroyPending=nil,nil,nil,nil
 self.lastTradeID,self.lastDestroyID,self.lastVitalsID=nil,nil,nil
 if self.rosterBackground then for _,key in ipairs(inputs) do self[key]=keep[key] end end
end
function B:RetireFollowers()
 if self.roster then
  for _,name in ipairs(self.rosterOrder) do self:WithFollower(name,function(b) b:CloseLocalTransport();b:Disconnect() end) end
 end
 self.roster,self.rosterOrder,self.rosterCurrent=nil,nil,nil
 if self:GetBridgeInfo().multiLocal then pcall(zBoxNative,"LocalCloseAll") end
end
local configure=B.Configure
function B:ConfigureRoster(names,key)
 if table.getn(names)<1 or table.getn(names)>16 then return false,"Use 1 to 16 followers" end
 local seen={}
 for _,name in ipairs(names) do
  if not string.find(name or "","^[%a][%a%-]*$") or string.len(name)>48 or self:Name(name)==self:Name(UnitName("player")) or seen[self:Name(name)] then
   return false,"Enter distinct follower names, excluding this character"
  end
  seen[self:Name(name)]=true
 end
 if not key or not string.find(key,"^[%w_%-]+$") or string.len(key)<8 or string.len(key)>32 then return false,"The shared pairing code must be 8-32 letters, numbers, _ or -" end
 self:RetireFollowers()
 local ok,reason=configure(self,"control",names[1],key)
 if not ok then return ok,reason end
 self.db.peers=names;self:BuildRoster(names)
 return true
end
function B:BuildRoster(names)
 if self.db.role~="control" then return end
 self.roster,self.rosterOrder,self.rosterCurrent={},{},self:Name(self.db.peer)
 local original=capture()
 for _,name in ipairs(names) do
  table.insert(self.rosterOrder,name)
  if self:Name(name)~=self.rosterCurrent then
   local state={cache={},pending={},incoming={},queueHigh={},queueLow={},lowIndex=1,highIndex=1,
    sendID=0,receiveCommandID=0,connected=false,session=self:NewSession(),lastHello=-10,lastHeartbeat=-10,lastStatus=-10,
    view="actions",page=1,actionPage=1,targetMode="TARGET"}
   self.roster[self:Name(name)]=state
  else self.roster[self:Name(name)]=original end
 end
end
function B:Configure(role,peer,key)
 if role=="control" then return self:ConfigureRoster({peer},key) end
 self:RetireFollowers();self.db.peers=nil
 return configure(self,role,peer,key)
end
local initialize=B.Initialize
function B:Initialize()
 if self.roster then self:RetireFollowers() end
 if self:GetBridgeInfo().multiLocal then pcall(zBoxNative,"LocalCloseAll") end
 initialize(self)
 if self.db.role=="control" and self.db.peer then
  local names=self.db.peers or {self.db.peer}
  local found=false;for _,name in ipairs(names) do if self:Name(name)==self:Name(self.db.peer) then found=true end end
  if not found then self.db.peer=names[1] end
  self:BuildRoster(names)
 end
end
local command=B.Command
local broadcast={FOLLOW=true,PET=true,MOVETO=true,AXIS=true,AXES=true,JUMP=true,MIRROR=true,STOP=true,ASSIST=true}
function B:Command(kind,fields)
 if self.roster and not self.rosterBackground and not self.rosterSending and broadcast[kind] then
  local any,detail=false,nil;self.rosterSending=true
  for _,name in ipairs(self.rosterOrder) do
   local copy={};for i,v in ipairs(fields or {}) do copy[i]=v end
   local ok,why=self:WithFollower(name,command,kind,copy);any=ok or any;detail=why or detail
  end
  self.rosterSending=nil
  return any,any and nil or detail
 end
 return command(self,kind,fields)
end
local receive=B.Receive
function B:Receive(prefix,message,channel,sender)
 if self.roster and self:Name(sender)~=self:Name(self.db.peer) then
  if self.roster[self:Name(sender)] then return self:WithFollower(sender,receive,prefix,message,channel,sender) end
  return
 end
 return receive(self,prefix,message,channel,sender)
end
local localTick=B.LocalTransportTick
function B:LocalTransportTick(now)
 if self.rosterOrder and table.getn(self.rosterOrder)>1 and not self:GetBridgeInfo().multiLocal then
  if self.localOpened then self:CloseLocalTransport() end
  return -- A legacy singleton channel cannot safely represent several peers.
 end
 if self.rosterBackground and not self:GetBridgeInfo().multiLocal then return end
 if self.roster and not self.rosterBackground and self:GetBridgeInfo().multiLocal then
  for _,name in ipairs(self.rosterOrder) do if self:Name(name)~=self:Name(self.db.peer) then self:WithFollower(name,localTick,now) end end
  pcall(zBoxNative,"LocalSelect",self.db.peer)
 end
 return localTick(self,now)
end
local tick=B.Tick
function B:Tick(now,elapsed)
 tick(self,now,elapsed)
 if self.roster and not self.rosterBackground then
  for _,name in ipairs(self.rosterOrder) do if self:Name(name)~=self:Name(self.db.peer) then self:WithFollower(name,tick,now,elapsed) end end
 end
 if not self.rosterBackground then
  if self.FreeBarTick then self:FreeBarTick(now) end
  if self.TradeTick then self:TradeTick(now) end
  if self.InstallVitalsProvider then self:InstallVitalsProvider() end
 end
end
for _,method in ipairs({"ControlTick","MirrorTick","PaintMacroCooldowns","FindCooldownButtons","InstallQuestTooltip"}) do
 local original=B[method]
 B[method]=function(self,a,b,c) if not self.rosterBackground then return original(self,a,b,c) end end
end
local slash=B.Slash
function B:Slash(text)
 if string.find(text or "","^off%s*$") or string.find(text or "","^transport%s") then
  if self.roster then self:Command("STOP");self:RetireFollowers() end
 end
 return slash(self,text)
end
local prior=B.frame:GetScript("OnEvent")
B.frame:SetScript("OnEvent",function()
 if B.ready and (event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT") then B:RetireFollowers() end
 prior()
 if B.ready and event=="PLAYER_ENTERING_WORLD" and B.db.role=="control" and B.db.peer and not B.roster then B:BuildRoster(B.db.peers or {B.db.peer}) end
end)
