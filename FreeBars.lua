-- pfUI bindings click their bar buttons. An empty slot can therefore represent
-- a remote action without allocating a Blizzard macro or changing UseAction.
local B=zBox
local names={"Main","Paging","Right","Vertical","Left","Top","StanceBar1","StanceBar2","StanceBar3","StanceBar4"}
local function native(slot) return slot and HasAction and HasAction(slot) end
function B:DirectBarsAvailable() return pfUI and pfUI.bars and true or false end
function B:RemoteProxy(command,slot,stamp,texture,label)
 self.db.proxies=self.db.proxies or {}
 local id,proxy
 for key,value in pairs(self.db.proxies) do
  if self:Name(value.peer)==self:Name(self.db.peer) and value.realm==self:Realm() and value.command==command and tostring(value.slot)==tostring(slot) then id,proxy=key,value;break end
 end
 if not id then
  self.db.proxySerial=(self.db.proxySerial or 0)+1;id=tostring(self.db.proxySerial)
  proxy={peer=self.db.peer,realm=self:Realm(),command=command,slot=slot}
 end
 proxy.stamp,proxy.icon,proxy.label=stamp,texture,label;self.db.proxies[id]=proxy
 return id
end
function B:BeginFreeDrag(id,source)
 if self:CursorBusy() or (GetCursorInfo and GetCursorInfo()) then return false,"Clear your cursor first" end
 self.freeCursor={id=id,source=source}
 if not self.freeBars then self.freeBars={buttons={}} end
 if not self.freeBars.cursor then
  local f=CreateFrame("Frame",nil,UIParent);f:SetWidth(32);f:SetHeight(32);f:SetFrameStrata("TOOLTIP");f:EnableMouse(false)
  f.icon=f:CreateTexture(nil,"OVERLAY");f.icon:SetAllPoints(f)
  self.freeBars.cursor=f
  local cancel=CreateFrame("Frame","zBoxRemoteCursorCancel",UIParent);cancel:Hide()
  cancel:SetScript("OnHide",function() B:CancelFreeDrag() end)
  self.freeBars.cancel=cancel;table.insert(UISpecialFrames,"zBoxRemoteCursorCancel")
 end
 self.freeBars.cursor.icon:SetTexture(self.db.proxies[id].icon);self.freeBars.cursor:Show();self.freeBars.cancel:Show()
 if pfUI and pfUI.bars.UpdateGrid then pfUI.bars:UpdateGrid(1) end
 self:FreeBarTick(GetTime(),true)
 return true,"Drop on an empty pfUI bar slot. Escape cancels; Shift-drag moves; Shift-right-click removes."
end
function B:CancelFreeDrag()
 self.freeCursor=nil
 if self.freeBars then self.freeBars.cursor:Hide();self.freeBars.cancel:Hide() end
 if pfUI and pfUI.bars.UpdateGrid then pfUI.bars:UpdateGrid(0) end
end
function B:PlaceFreeProxy(button)
 local cursor=self.freeCursor
 local slot=button and self.Integer(button.id,1,120)
 if not cursor or not slot then return false end
 if native(slot) then self:Notify("Choose an empty action bar slot");return false end
 self.db.barSlots=self.db.barSlots or {}
 if cursor.source and self.db.barSlots[cursor.source]==cursor.id then self.db.barSlots[cursor.source]=nil end
 self.db.barSlots[slot]=cursor.id;self.nextWatchScan=nil;self:CancelFreeDrag()
 self:FreeBarTick(GetTime(),true)
 return true
end
function B:FinishFreeDrag()
 if not self.freeCursor then return end
 local x,y=GetCursorPosition()
 for button in pairs(self.freeBars.buttons) do
  if button:IsVisible() then
   local l,r,t,b=button:GetLeft(),button:GetRight(),button:GetTop(),button:GetBottom();local scale=button:GetEffectiveScale()
   if l and r and t and b and x>=l*scale and x<=r*scale and y>=b*scale and y<=t*scale then return self:PlaceFreeProxy(button) end
  end
 end
end
local pickup=B.PickupRemote
function B:PickupRemote(section,row)
 if self:DirectBarsAvailable() and self.db.macroBars~=true then
  if not self.connected or self.db.role~="control" then return false,"Connect a follower first" end
  if (section~="actions" and section~="spells") or not row or row[2]=="" or (section=="spells" and row[6]=="1") then return false,"Choose an active skill" end
  local id=self:RemoteProxy(section=="actions" and "ACTION" or "SPELL",row[1],section=="actions" and row[4] or row[5],row[2],row[3])
  return self:BeginFreeDrag(id)
 end
 return pickup(self,section,row)
end
local use=B.UseProxy
function B:UseProxy(id,selfCast)
 local proxy=self.db.proxies and self.db.proxies[id]
 if not proxy or proxy.realm~=self:Realm() then return use(self,id) end
 if self.rosterCurrent and self.rosterCurrent~=self:Name(self.db.peer) then return use(self,id) end
 if self:Name(proxy.peer)~=self:Name(self.db.peer) and not (self.roster and self.roster[self:Name(proxy.peer)]) then return use(self,id) end
 if proxy.command=="CONTROL" then
  local ok,reason=self:UseControl(proxy.slot);if not ok then self:Notify(reason) end
  return ok,reason
 end
 return self:WithFollower(proxy.peer,function(b)
  if proxy.command~="ACTION" and proxy.command~="SPELL" then return end
  local ok,reason=b:Command(proxy.command,{proxy.slot,proxy.stamp,b:TargetDescriptor(selfCast or (IsAltKeyDown and IsAltKeyDown()))})
  if not ok then b:Notify(reason) end
  return ok,reason
 end)
end
function B:DecorateFreeButton(button)
 if self.freeBars.buttons[button] then return end
 self.freeBars.buttons[button]=true
 local click,drag,receive,enter,leave=button:GetScript("OnClick"),button:GetScript("OnDragStart"),button:GetScript("OnReceiveDrag"),button:GetScript("OnEnter"),button:GetScript("OnLeave")
 button:SetScript("OnClick",function()
  local slot=B.Integer(this.id,1,120);local id=slot and B.db.barSlots and B.db.barSlots[slot]
  if B.freeCursor then if arg1=="RightButton" then B:CancelFreeDrag() else B:PlaceFreeProxy(this) end;return end
  if id and not native(slot) then
   if arg1=="RightButton" and IsShiftKeyDown() then B.db.barSlots[slot]=nil;B.nextWatchScan=nil
   else local selfCast=arg1=="RightButton" or this.slfcast;this.slfcast=nil;B:UseProxy(id,selfCast) end
   return
  end
  if click then click() end
 end)
 button:SetScript("OnDragStart",function()
  local slot=B.Integer(this.id,1,120);local id=slot and B.db.barSlots and B.db.barSlots[slot]
  if id and not native(slot) then if IsShiftKeyDown() then B:BeginFreeDrag(id,slot) end;return end
  if drag then drag() end
 end)
 button:SetScript("OnDragStop",function() B:FinishFreeDrag() end)
 button:SetScript("OnReceiveDrag",function()
  if B.freeCursor then B:PlaceFreeProxy(this);return end
  if receive then receive() end
  local slot=B.Integer(this.id,1,120);if slot and native(slot) and B.db.barSlots then B.db.barSlots[slot]=nil;B.nextWatchScan=nil end
 end)
 button:SetScript("OnEnter",function()
  local slot=B.Integer(this.id,1,120);local id=slot and B.db.barSlots and B.db.barSlots[slot];local proxy=id and B.db.proxies[id]
  if proxy and not native(slot) then
   GameTooltip:SetOwner(this,"ANCHOR_RIGHT");GameTooltip:SetText(proxy.label.." - "..proxy.peer)
   GameTooltip:AddLine("Remote skill. Right-click: self. Shift-drag: move. Shift-right-click: remove.",.6,.85,.85,true);GameTooltip:Show()
  elseif enter then enter() end
 end)
 button:SetScript("OnLeave",function() GameTooltip:Hide();if leave then leave() end end)
 local f=CreateFrame("Frame",nil,button);f:SetAllPoints(button);f:SetFrameLevel(button:GetFrameLevel()+3);f:EnableMouse(false)
 f.icon=f:CreateTexture(nil,"ARTWORK");f.icon:SetAllPoints(f);f.icon:SetTexCoord(.06,.94,.06,.94)
 f.owner=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");f.owner:SetPoint("BOTTOM",f,"BOTTOM",0,1);f.owner:SetFont("Fonts\\FRIZQT__.TTF",8,"OUTLINE")
 button.zBoxRemote=f;f:Hide()
end
function B:FreeBarTick(now,force)
 if not self:DirectBarsAvailable() or not self.db then return end
 if not self.freeBars then self.freeBars={buttons={}} end
 if now>=(self.freeBars.scanAt or 0) then
  self.freeBars.scanAt=now+1
  for _,name in ipairs(names) do for i=1,12 do local f=getglobal("pfActionBar"..name.."Button"..i);if f then self:DecorateFreeButton(f) end end end
 end
 if self.freeCursor then
  local x,y=GetCursorPosition();local scale=UIParent:GetEffectiveScale();local f=self.freeBars.cursor
  f:ClearAllPoints();f:SetPoint("CENTER",UIParent,"BOTTOMLEFT",x/scale,y/scale)
 end
 if not force and now<(self.freeBars.paintAt or 0) then return end
 self.freeBars.paintAt=now+.05
 for button in pairs(self.freeBars.buttons) do
  local slot=self.Integer(button.id,1,120);local id=slot and self.db.barSlots and self.db.barSlots[slot];local proxy=id and self.db.proxies and self.db.proxies[id]
  if id and native(slot) then self.db.barSlots[slot]=nil;id,proxy=nil,nil;self.nextWatchScan=nil end
  if proxy and proxy.realm==self:Realm() then
   local f=button.zBoxRemote;f.icon:SetTexture(proxy.icon);f.owner:SetText(string.sub(proxy.peer,1,7));f:Show();button:Show();button:SetAlpha(1)
  else button.zBoxRemote:Hide() end
 end
end
local slash=B.Slash
function B:Slash(message)
 local _,_,mode=string.find(message or "","^bars%s+(%a+)%s*$")
 if mode then
  if mode~="macro" and mode~="direct" then self:Notify("Use /zbox bars direct or /zbox bars macro");return end
  self.db.macroBars=mode=="macro";self:Notify(mode=="macro" and "Dragging skills creates bar macros" or "Dragging skills uses empty pfUI slots without macros; stock bars use macros");return
 end
 return slash(self,message)
end
