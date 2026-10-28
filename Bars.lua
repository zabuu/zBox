-- Independent, saved bars. No Blizzard action slots, macro slots or permanent
-- key bindings are allocated. Every entry retains its character and realm.
local B,U=zBox,zBox.UI
local function copy(t) local out={};for k,v in pairs(t) do out[k]=v end;return out end
local function state() B.independentBars=B.independentBars or {};return B.independentBars end
function B:BarProfile()
 self.db.barProfiles=self.db.barProfiles or {}
 local key=self:Realm()..":"..self:Name(self.db.peer or UnitName("player"))
 local p=self.db.barProfiles[key]
 if not p then p={pages={},bindings={},page=1};self.db.barProfiles[key]=p end
 p.pages,p.bindings=p.pages or {},p.bindings or {};p.page=self.Integer(p.page,1,10) or 1
 p.pages[p.page]=p.pages[p.page] or {}
 return p,key
end
function B:BarEntry(slot)
 local p=self:BarProfile();return p.pages[p.page][slot]
end
function B:EntryOwner(entry)
 if not entry or entry.realm~=self:Realm() then return end
 if self:Name(entry.peer)==self:Name(UnitName("player")) then return self,true end
 local owner=self.FollowerState and self:FollowerState(entry.peer)
 if owner and owner.connected and self.db.enabled and self.db.role=="control" and not self.worldSuspended then return owner,false end
end
function B:UseBarSlot(slot,selfCast)
 local s=state();if s.binding or s.cursor or self.worldSuspended then return false end
 if ChatFrameEditBox and ChatFrameEditBox:IsShown() then return false end
 local entry=self:BarEntry(slot);if not entry then return false end
 local owner,own=self:EntryOwner(entry)
 if not owner then self:RemoteFeedback(entry.peer.." is not connected");return false end
 -- Resolve main mouseover/target before switching to the skill owner's state.
 local descriptor,mouse=self:TargetDescriptor(selfCast),self:GUID("mouseover")
 if own then
  local index=entry.command=="SKILL" and self:FindSkill(entry.name,entry.rank)
  if not index then self:RemoteFeedback("That spell/rank is no longer in your spellbook");return false end
  if not selfCast and self:IsFriendlyCast("SPELL",index) then descriptor="SELF" end
  local ok,why=self:ChooseTarget(descriptor=="MAIN" and "SELF" or descriptor)
  if ok then ok,why=self:Invoke("CastSpell",index,BOOKTYPE_SPELL or "spell") end
  if not ok then self:RemoteFeedback(why) end
  return ok,why
 end
 if not selfCast then descriptor="LEFT:"..descriptor end
 return self:WithFollower(entry.peer,function(b)
  local fields=entry.command=="SKILL" and {entry.name,entry.rank,descriptor,mouse} or {entry.slot,entry.stamp,descriptor,mouse}
  local ok,why=b:Command(entry.command,fields);if not ok then b:RemoteFeedback(why) end
  return ok,why
 end)
end
function B:StartBarDrag(entry,source)
 if self:CursorBusy() or (GetCursorInfo and GetCursorInfo()) then return false,"Clear your cursor first" end
 local s=state();s.cursor={entry=copy(entry),source=source}
 if not s.cursorFrame then
  local f=CreateFrame("Frame",nil,UIParent);f:SetWidth(32);f:SetHeight(32);f:SetFrameStrata("TOOLTIP");f:EnableMouse(false)
  f.icon=f:CreateTexture(nil,"OVERLAY");f.icon:SetAllPoints(f);s.cursorFrame=f
  local cancel=CreateFrame("Frame","zBoxBarCursorCancel",UIParent);cancel:Hide()
  cancel:SetScript("OnHide",function() B:CancelBarDrag() end);s.cancel=cancel;table.insert(UISpecialFrames,"zBoxBarCursorCancel")
 end
 s.cursorFrame.icon:SetTexture(entry.icon);s.cursorFrame:Show();s.cancel:Show()
 return true,"Drop on a zBox slot. Escape cancels; Shift-drag moves; Shift-right-click removes."
end
function B:CancelBarDrag()
 local s=state();s.cursor=nil
 if s.cursorFrame then s.cursorFrame:Hide();s.cancel:Hide() end
end
function B:PickupRemote(section,row)
 if not self.connected or self.db.role~="control" then return false,"Connect the follower first" end
 if not row or (section~="actions" and section~="spells") or row[2]=="" or (section=="spells" and row[6]=="1") then return false,"Choose an active spell or macro" end
 local entry={peer=self.db.peer,realm=self:Realm(),icon=row[2],label=row[3]}
 if section=="spells" then entry.command,entry.name,entry.rank="SKILL",row[3],row[4] or ""
 elseif row[11]=="spell" and row[12] and row[12]~="" then entry.command,entry.name,entry.rank="SKILL",row[12],row[13] or ""
 else entry.command,entry.slot,entry.stamp,entry.mouseover="ACTION",row[1],row[4],row[14]=="1" end
 return self:StartBarDrag(entry)
end
function B:DropBarSlot(slot)
 local s=state();local p,key=self:BarProfile();local entry=s.cursor and s.cursor.entry
 local native=false
 if not entry and GetCursorInfo then
  local kind,index,book=GetCursorInfo()
  if kind=="spell" and book~="pet" and self.Integer(index,1,960) then
   local name,rank=GetSpellName(index,BOOKTYPE_SPELL or "spell")
   if name and not (IsPassiveSpell and IsPassiveSpell(index,BOOKTYPE_SPELL or "spell")) then
    entry={peer=UnitName("player"),realm=self:Realm(),command="SKILL",name=name,rank=rank or "",label=name,icon=GetSpellTexture(index,BOOKTYPE_SPELL or "spell")};native=true
   end
  end
 end
 if not entry then return false end
 local old=p.pages[p.page][slot];local source=s.cursor and s.cursor.source
 if source and source.key==key and source.page==p.page and source.slot==slot then self:CancelBarDrag();return true end
 p.pages[p.page][slot]=copy(entry)
 if source then
  local origin=self.db.barProfiles[source.key];if origin and origin.pages[source.page] then origin.pages[source.page][source.slot]=old end
 end
 self:CancelBarDrag()
 if native and ClearCursor then ClearCursor() end
 self:InvalidateBarWatches();self:RenderBar();return true
end
function B:InvalidateBarWatches()
 self.nextWatchScan=nil
 for _,name in ipairs(self:FollowerNames()) do local owner=self:FollowerState(name);if owner then owner.nextWatchScan=nil end end
end
function B:FinishBarDrag()
 if not state().cursor or not self.UI then return end
 local x,y=GetCursorPosition()
 for i,cell in ipairs(self.UI.dockCells) do
  local l,r,t,b=cell:GetLeft(),cell:GetRight(),cell:GetTop(),cell:GetBottom();local scale=cell:GetEffectiveScale()
  if cell:IsVisible() and l and r and t and b and x>=l*scale and x<=r*scale and y>=b*scale and y<=t*scale then return self:DropBarSlot(i) end
 end
end
-- Retire the former pfUI-slot adapter. Legacy exported macros remain usable.
function B:FreeBarTick(now)
 self:BarTick(now)
end
function B:FinishFreeDrag() return self:FinishBarDrag() end
function B:BindingChord(key)
 return ((IsAltKeyDown and IsAltKeyDown()) and "ALT-" or "")..((IsControlKeyDown and IsControlKeyDown()) and "CTRL-" or "")..((IsShiftKeyDown and IsShiftKeyDown()) and "SHIFT-" or "")..key
end
function B:ShortBarKey(key)
 key=key or ""
 key=string.gsub(key,"ALT%-","A");key=string.gsub(key,"CTRL%-","C");key=string.gsub(key,"SHIFT%-","S")
 key=string.gsub(key,"MOUSEWHEELUP","WU");key=string.gsub(key,"MOUSEWHEELDOWN","WD")
 key=string.gsub(key,"BUTTON","M");key=string.gsub(key,"NUMPAD","N");key=string.gsub(key,"SPACE","Sp")
 return key
end
function B:BindBarKeys(force)
 local s=state();if not s.owner or not ClearOverrideBindings or not SetOverrideBindingClick then return end
 local p,key=self:BarProfile();local active=self.db.enabled and self.db.role=="control" and self.db.realm==self:Realm() and not self.worldSuspended and self:AnyFollowerConnected() and not s.binding
 local signature=key..":"..tostring(active)
 for i=1,12 do signature=signature..":"..(p.bindings[i] or "") end
 if not force and signature==s.bindingSignature then return end
 ClearOverrideBindings(s.owner);s.bindingSignature=signature
 if active then for i=1,12 do
  if p.bindings[i] then pcall(SetOverrideBindingClick,s.owner,true,p.bindings[i],"zBoxBarKey"..i,"LeftButton") end
 end end
end
function B:CaptureBarKey(key)
 local s=state();if not s.binding then return end
 if key=="ESCAPE" then return self:EndBarBinding() end
 if not s.hover then return end
 if key=="LSHIFT" or key=="RSHIFT" or key=="LCTRL" or key=="RCTRL" or key=="LALT" or key=="RALT" then return end
 local p=self:BarProfile()
 if key=="BACKSPACE" or key=="DELETE" then p.bindings[s.hover]=nil
 else
  local chord=self:BindingChord(key)
  if chord=="BUTTON1" or chord=="BUTTON2" then return end
  for i=1,12 do if p.bindings[i]==chord then p.bindings[i]=nil end end
  p.bindings[s.hover]=chord
 end
 self:RenderBar();self:BarTooltip(s.hover)
end
function B:EndBarBinding()
 local s=state();s.binding,s.hover=nil,nil
 if s.capture then s.capture:Hide();s.capture:EnableKeyboard(false) end
 if s.bindButton then s.bindButton.caption:SetText("Bind") end
 self:BindBarKeys(true);GameTooltip:Hide()
end
function B:ToggleBarBinding()
 local s=state();if s.binding then return self:EndBarBinding() end
 if not SetOverrideBindingClick or not ClearOverrideBindings then self:Notify("Independent hotkeys need ClassicAPI's override-binding API. Your WoW bindings were not changed.");return end
 s.binding=true;local _,key=self:BarProfile();s.bindingProfile=key
 s.capture:ClearAllPoints();s.capture:SetPoint("CENTER",UIParent,"CENTER",0,0);s.capture:SetWidth(1);s.capture:SetHeight(1);s.capture:EnableMouse(false);s.capture:Show();s.capture:EnableKeyboard(true)
 s.bindButton.caption:SetText("Done");self:BindBarKeys(true)
 self.notice="Hover a zBox slot and press a key or side mouse button. Backspace clears; Escape exits."
end
function B:HoverBarSlot(slot)
 local s=state();s.hover=slot
 if s.binding then
  local cell=self.UI.dockCells[slot];s.capture:ClearAllPoints();s.capture:SetAllPoints(cell);s.capture:EnableMouse(true);s.capture:Show();s.capture:EnableKeyboard(true)
 end
 self:BarTooltip(slot)
end
function B:BarTooltip(slot)
 if not self.UI then return end
 local cell=self.UI.dockCells[slot];local p=self:BarProfile();local e=p.pages[p.page][slot];local s=state()
 GameTooltip:SetOwner(cell,"ANCHOR_TOP");GameTooltip:SetText(e and (e.label.." - "..e.peer) or "Empty zBox slot")
 if e and e.rank and e.rank~="" then GameTooltip:AddLine(e.rank,.75,.8,.85) end
 if e then GameTooltip:AddLine("Friendly skills: left-click main, right-click skill owner.",.65,.85,.85,true) end
 if e and e.mouseover then GameTooltip:AddLine("Mouseover macro: uses your mouseover, then the chosen cast target.",.4,.9,.85,true) end
 if p.bindings[slot] then
  GameTooltip:AddLine("zBox key: "..p.bindings[slot],1,.85,.3)
  local action=GetBindingAction and GetBindingAction(p.bindings[slot])
  if action and action~="" then GameTooltip:AddLine("WoW also uses this key: "..action..". Its saved binding stays unchanged.",.8,.7,.5,true) end
 end
 GameTooltip:AddLine(s.binding and "Press a key, modified click, side button or wheel. Backspace clears; Escape finishes." or "Drag spells here from any linked character or your own spellbook. Shift-drag moves; Shift-right-click removes.",.65,.85,.85,true)
 if s.binding then GameTooltip:AddLine("Keys apply to this bar position on every zBox page.",.6,.7,.75,true) end
 GameTooltip:Show()
end
function B:RenderBar()
 local s=state();if not s.ready or not self.UI then return end
 local p,key=self:BarProfile()
 if s.profile~=key then
  if s.binding then self:EndBarBinding() end
  s.profile=key;self.targetMode=p.targetMode or "TARGET";self:InvalidateBarWatches()
 else p.targetMode=self.targetMode end
 local modes={TARGET="Main's target",MAIN="Main character",SELF="Skill owner",KEEP="Owner's target",MOUSEOVER="Mouseover"}
 self.UI.targetMode.caption:SetText(modes[self.targetMode] or modes.TARGET)
 self.UI.barPage:SetText(p.page.."/10")
 for i,cell in ipairs(self.UI.dockCells) do
  local e=p.pages[p.page][i];cell.entry=e;cell.row=nil;cell.section="custom"
  cell.icon:SetTexture(e and e.icon or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
  cell.owner:SetText(e and string.sub(e.peer,1,9) or "")
  cell.key:SetText(self:ShortBarKey(p.bindings[i]));cell.count:SetText("");cell.cooldown:SetText("")
  local owner,own=self:EntryOwner(e);cell.icon:SetVertexColor(owner and 1 or .45,owner and 1 or .45,owner and 1 or .45)
  if e and owner then
   local cd
   if own and e.command=="SKILL" then
    local index=self:FindSkill(e.name,e.rank)
    if index and GetSpellCooldown then local start,duration,enabled=GetSpellCooldown(index,BOOKTYPE_SPELL or "spell");local remaining=self:Cooldown(start,duration,enabled);cd={endsAt=GetTime()+remaining,duration=duration,valid=true,at=GetTime()} end
   else cd=owner.cache.proxyCooldowns and owner.cache.proxyCooldowns[e.watch] end
   if cd and cd.valid and GetTime()-cd.at<5 and cd.endsAt>GetTime()+.05 then
    local overlay=self:CooldownOverlay(cell)
    if CooldownFrame_SetTimer then CooldownFrame_SetTimer(overlay.swipe,cd.endsAt-cd.duration,cd.duration,1) end
    overlay.text:SetText(tostring(math.ceil(cd.endsAt-GetTime())));overlay:Show()
   elseif cell.zBoxCooldown then cell.zBoxCooldown:Hide() end
  elseif cell.zBoxCooldown then cell.zBoxCooldown:Hide() end
 end
 self:BindBarKeys()
end
function B:BarTick(now)
 local s=state();if not s.ready then return end
 if s.feedback then self:RemoteFeedback(s.feedback);s.feedback=nil;if self.UI then self.UI.dirty=true end end
 if s.cursor and s.cursorFrame then local x,y=GetCursorPosition();local scale=UIParent:GetEffectiveScale();s.cursorFrame:ClearAllPoints();s.cursorFrame:SetPoint("CENTER",UIParent,"BOTTOMLEFT",x/scale,y/scale) end
 if now>=(s.paintAt or 0) then s.paintAt=now+.1;self:RenderBar() end
end
local create=U.Create
function U:Create()
 create(self)
 local s=state();if s.ready then return end
 s.owner=CreateFrame("Frame","zBoxIndependentBindings",UIParent)
 for i,cell in ipairs(self.dockCells) do
  local slot=i
  local keyButton=CreateFrame("Button","zBoxBarKey"..i,UIParent);keyButton:EnableMouse(false);keyButton:RegisterForClicks("LeftButtonUp");keyButton:SetWidth(1);keyButton:SetHeight(1)
  keyButton:SetScript("OnClick",function() B:UseBarSlot(slot) end)
  cell.owner=cell:CreateFontString(nil,"OVERLAY");cell.owner:SetFont("Fonts\\FRIZQT__.TTF",8,"OUTLINE");cell.owner:SetPoint("BOTTOM",cell,"BOTTOM",0,0)
  cell.key=cell:CreateFontString(nil,"OVERLAY");cell.key:SetFont("Fonts\\FRIZQT__.TTF",8,"OUTLINE");cell.key:SetPoint("TOPRIGHT",cell,"TOPRIGHT",0,0);cell.key:SetWidth(32);cell.key:SetHeight(10);cell.key:SetJustifyH("RIGHT")
  cell:SetScript("OnEnter",function() B:HoverBarSlot(slot) end)
  cell:SetScript("OnLeave",function() if not state().binding then GameTooltip:Hide() end end)
  cell:SetScript("OnReceiveDrag",function() B:DropBarSlot(slot) end)
  cell:SetScript("OnDragStart",function()
   local p,key=B:BarProfile();local e=p.pages[p.page][slot]
   if e and IsShiftKeyDown() and not state().binding then B:StartBarDrag(e,{key=key,page=p.page,slot=slot}) end
  end)
  cell:SetScript("OnDragStop",function() B:FinishBarDrag();state().ignoreClickUntil=GetTime()+.25 end)
  cell:SetScript("OnClick",function()
   if state().binding then return end
   if state().ignoreClickUntil and GetTime()<state().ignoreClickUntil then return end
   if state().cursor or (GetCursorInfo and GetCursorInfo()) then B:DropBarSlot(slot)
   elseif arg1=="RightButton" and IsShiftKeyDown() then local p=B:BarProfile();p.pages[p.page][slot]=nil;B:InvalidateBarWatches();B:RenderBar()
   else B:UseBarSlot(slot,arg1=="RightButton" or (IsAltKeyDown and IsAltKeyDown())) end
  end)
 end
 local capture=CreateFrame("Frame",nil,UIParent);s.capture=capture
 capture:SetFrameStrata("FULLSCREEN_DIALOG");capture:EnableMouse(true);capture:EnableMouseWheel(true)
 capture:SetScript("OnKeyDown",function() B:CaptureBarKey(arg1) end)
 capture:SetScript("OnMouseDown",function()
  local names={LeftButton="BUTTON1",RightButton="BUTTON2",MiddleButton="BUTTON3"};local key=names[arg1]
  if not key then local _,_,n=string.find(arg1 or "","^Button(%d+)$");if n then key="BUTTON"..n end end
  if key then B:CaptureBarKey(key) end
 end)
 capture:SetScript("OnMouseWheel",function() B:CaptureBarKey(arg1>0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
 capture:SetScript("OnLeave",function() capture:EnableMouse(false);s.hover=nil;GameTooltip:Hide() end)
 capture:EnableKeyboard(false);capture:Hide()
 local bind=CreateFrame("Button",nil,self.frame);s.bindButton=bind
 bind:SetWidth(39);bind:SetHeight(20);bind:SetPoint("TOPLEFT",self.frame,"TOPLEFT",211,-4)
 bind:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
 bind:SetBackdropColor(.09,.13,.18,1);bind:SetBackdropBorderColor(.25,.45,.49,1)
 bind.caption=bind:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");bind.caption:SetPoint("CENTER",bind,"CENTER",0,0);bind.caption:SetText("Bind")
 bind:SetScript("OnClick",function() B:ToggleBarBinding() end)
 self.connection:SetWidth(151);self.followerSelector:SetWidth(155)
 local hide=self.frame:GetScript("OnHide")
 self.frame:SetScript("OnHide",function() B:EndBarBinding();B:CancelBarDrag();if hide then hide() end end)
 s.ready=true;B:RenderBar()
end
local refresh=U.Refresh
function U:Refresh() refresh(self);B:RenderBar() end
function U:BarPage(delta)
 local p=B:BarProfile();p.page=math.mod(math.mod(p.page-1+delta,10)+10,10)+1;p.pages[p.page]=p.pages[p.page] or {};B:RenderBar()
end
local page=U.Page
function U:Page(delta)
 if B.view=="actions" then B:Request("actions",math.mod(math.mod(B.page-1+delta,10)+10,10)+1);self:Refresh();return end
 return page(self,delta)
end
function U:CycleTarget()
 local modes={"TARGET","MAIN","SELF","KEEP","MOUSEOVER"}
 for i,mode in ipairs(modes) do if B.targetMode==mode then B.targetMode=modes[math.mod(i,5)+1];break end end
 local p=B:BarProfile();p.targetMode=B.targetMode;self:Refresh()
end
local tick=U.Tick
function U:Tick(now) tick(self,now);B:RenderBar() end
local cooldowns=B.SyncCooldownWatches
function B:SyncCooldownWatches(now)
 local active=state().profile
 local p=active and self.db.barProfiles and self.db.barProfiles[active] or self:BarProfile()
 for _,entries in pairs(p.pages) do for _,e in pairs(entries) do
  if self:Name(e.peer)==self:Name(self.db.peer) and e.realm==self:Realm() then
   local command=e.command=="SKILL" and "SKILL" or "ACTION"
   e.watch=self:RemoteProxy(command,e.name or e.slot,e.rank or e.stamp,e.icon,e.label)
  end
 end end
 return cooldowns(self,now)
end
local initialize=B.Initialize
function B:Initialize()
 initialize(self)
 if self.db.role=="control" then self.view,self.page,self.actionPage="spells",1,nil end
end
local message=B.Message
function B:Message(kind,fields,id,now)
 if self.rosterBackground and self.db.role=="control" then
  if kind=="ERROR" then state().feedback=self.db.peer..": "..tostring(fields[1])
  elseif kind=="ACK" and fields[2]=="0" then state().feedback=self.db.peer..": "..tostring(fields[3]) end
 end
 if kind=="INDEPENDENT" and self.connected and self.db.role=="agent" and table.getn(fields)==0 then
  self.independentDock,self.actionPage,self.barDirty=true,nil,false
 end
 local result=message(self,kind,fields,id,now)
 if kind=="READY" and self.connected and self.db.role=="control" then self:Send("INDEPENDENT",{},true) end
 return result
end
local setView=B.SetView
function B:SetView(section,page)
 setView(self,section,page)
 if self.independentDock and section~="actions" then self.actionPage,self.barDirty=nil,false end
end
local slash=B.Slash
function B:Slash(text)
 if string.find(text or "","^bars%s*") then self.UI:Restore();self:Notify("Drag skills onto the independent zBox bar. Bind sets its own keys; each linked character has a saved bar.");return end
 return slash(self,text)
end
local original=B.frame:GetScript("OnEvent")
B.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
B.frame:SetScript("OnEvent",function()
 local name=event
 if B.ready and name=="PLAYER_TARGET_CHANGED" then B:SendMainTarget() end
 if name=="SPELLS_CHANGED" then B.skillIndices=nil end
 original()
 if B.ready and (name=="PLAYER_LEAVING_WORLD" or name=="PLAYER_LOGOUT") then
  B:EndBarBinding();B:CancelBarDrag()
  local s=state();if s.owner and ClearOverrideBindings then ClearOverrideBindings(s.owner);s.bindingSignature=nil end
 end
end)
