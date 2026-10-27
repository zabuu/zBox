-- Item operations are bound to a peer, bag slot, full item key and stack count.
-- Trade acceptance is bound to a fresh snapshot of both complete offers.
local B=zBox
local function flag(v) return v and "1" or "0" end
local function partner()
 local guid=B:GUID("NPC");if guid=="" then guid=B:GUID("npc") end
 return guid,UnitName("NPC") or UnitName("npc") or ""
end
function B:TradeSnapshot()
 if not self.tradeOpen then return end
 local guid,name=partner()
 if guid=="" then return end
 local rows={}
 for side=1,2 do
  local info=side==1 and GetTradePlayerItemInfo or GetTradeTargetItemInfo
  local link=side==1 and GetTradePlayerItemLink or GetTradeTargetItemLink
  if not info or not link then return end
  for slot=1,7 do
   local title,icon,count,a,b,c=info(slot)
   table.insert(rows,self:Encode({side,slot,title or "",icon or "",count or 0,link(slot) or "",side==1 and (b or "") or (c or "")}))
  end
 end
 local fields={"trade",self.tradeOpen,guid,name,GetPlayerTradeMoney() or 0,GetTargetTradeMoney() or 0,
  self.tradeAccepted or "0",self.tradeOtherAccepted or "0",table.concat(rows,"\n")}
 -- Acceptance flags are intentionally excluded: accepting the other side is
 -- not an offer change. Item enchantments, quantities and money are included.
 local offer=self:Encode({fields[2],guid,fields[5],fields[6],fields[9]})
 if offer~=self.tradeOfferBody then
  self.tradeOfferBody=offer;self.tradeOfferSerial=(self.tradeOfferSerial or 0)+1
  self.tradeOfferToken=self.tradeOpen.."o"..self.tradeOfferSerial
 end
 fields[10]=self.tradeOfferToken
 return fields
end
function B:TradeItem(fields)
 if not self:GetBridgeInfo().trade then return false,"Trading needs bridge 0.1.10; fully restart both clients after updating" end
 if self:CursorBusy() then return false,"Clear the follower's cursor first" end
 local bag,slot,why=self:ValidateBag(fields[2],fields[3],fields[4])
 if not bag then return false,why end
 local _,count=GetContainerItemInfo(bag,slot)
 if tonumber(fields[5])~=count then return false,"Stack size changed; choose the item again" end
 local guid=fields[6]
 if not guid or not string.find(guid,"^0x%x+$") or not UnitExists(guid) or
    not UnitIsPlayer or not UnitIsPlayer(guid) or (UnitCanAttack and UnitCanAttack("player",guid)) or guid==self:GUID("player") then return false,"Choose a friendly player in range" end
 local px,py,pz=self:Position();local tx,ty,tz=self:Position(guid)
 if not px or not tx or (px-tx)^2+(py-ty)^2+(pz-tz)^2>100 then return false,"Trade recipient is not within 10 yards of the follower" end
 if self.tradeOpen and partner()~=guid then return false,"Close the follower's current trade first" end
 self.tradePending={bag=bag,slot=slot,key=fields[4],count=count,guid=guid,expires=GetTime()+8}
 if self.tradeOpen then return self:PlaceTradeItem() end
 local ok,reason=self:Invoke("InitiateTrade",guid)
 if not ok then self.tradePending=nil end
 return ok,reason
end
function B:PlaceTradeItem()
 local item=self.tradePending
 if not item then return false,"No pending item" end
 self.tradePending=nil
 if not self.tradeOpen or partner()~=item.guid or GetTime()>item.expires or self:CursorBusy() then return false,"Trade changed before placing the item" end
 local bag,slot,why=self:ValidateBag(item.bag,item.slot,item.key)
 local _,count=GetContainerItemInfo(item.bag,item.slot)
 if not bag or count~=item.count then return false,why or "Stack size changed" end
 local empty
 for i=1,6 do if not GetTradePlayerItemLink(i) then empty=i;break end end
 if not empty then return false,"The follower's trade slots are full" end
 local ok,reason=self:Invoke("PickupContainerItem",bag,slot)
 if not ok then return false,reason end
 if not (CursorHasItem and CursorHasItem()) then return false,"Item pickup failed" end
 ok,reason=self:Invoke("ClickTradeButton",empty)
 if CursorHasItem() then self:Invoke("PickupContainerItem",bag,slot) end
 return ok,reason
end
function B:PrepareDestroy(fields)
 if not self:GetBridgeInfo().trade then return false,"Destroy needs bridge 0.1.10; fully restart both clients after updating" end
 local bag,slot,why=self:ValidateBag(fields[2],fields[3],fields[4])
 if not bag then return false,why end
 if self:CursorBusy() then return false,"Clear the follower's cursor first" end
 local _,count=GetContainerItemInfo(bag,slot)
 if tonumber(fields[5])~=count then return false,"Stack size changed; choose the item again" end
 local token=self:NewSession()
 self.destroyPending={token=token,bag=bag,slot=slot,key=fields[4],count=count,expires=GetTime()+20}
 self:Send("STATE",{"destroyconfirm",token,bag,slot,fields[4],count,GetContainerItemLink(bag,slot) or fields[4]},true)
 return true,"Confirm destruction on the driver"
end
function B:DestroyItem(token)
 local item=self.destroyPending;self.destroyPending=nil
 if not item or item.token~=token or GetTime()>item.expires or self:CursorBusy() then return false,"Destruction confirmation expired" end
 local bag,slot,why=self:ValidateBag(item.bag,item.slot,item.key)
 local _,count=GetContainerItemInfo(item.bag,item.slot)
 if not bag or count~=item.count then return false,why or "Stack changed; nothing destroyed" end
 local ok,reason=self:Invoke("PickupContainerItem",bag,slot)
 if not ok then return false,reason end
 -- A successful pickup must empty exactly the validated slot. Never delete a
 -- pre-existing cursor or an item left there by a failed/swap operation.
 if not CursorHasItem() or GetContainerItemLink(bag,slot) then
  if CursorHasItem() then self:Invoke("PickupContainerItem",bag,slot) end
  return false,"Item pickup did not match; nothing destroyed"
 end
 ok,reason=self:Invoke("DeleteCursorItem")
 if CursorHasItem() then self:Invoke("PickupContainerItem",bag,slot) end
 self.viewDirty=true
 return ok,reason
end
function B:TradeAction(command,fields)
 if command=="TRADEITEM" then return self:TradeItem(fields) end
 if command=="DESTROYPREP" then return self:PrepareDestroy(fields) end
 if command=="DESTROY" then return self:DestroyItem(fields[2]) end
 if not self:GetBridgeInfo().trade then return false,"Trade controls need bridge 0.1.10" end
 local current=self:TradeSnapshot()
 if not current or fields[2]~=current[10] or fields[3]~=current[3] then return false,"Trade offer changed; review the latest offer and try again" end
 if command=="TRADEACCEPT" then return self:Invoke("AcceptTrade") end
 if command=="TRADECLOSE" then return self:Invoke("CloseTrade") end
 return false,"Unknown trade action"
end
local execute=B.Execute
function B:Execute(fields)
 local kind=fields[1]
 if kind=="TRADEITEM" or kind=="DESTROYPREP" or kind=="DESTROY" or kind=="TRADEACCEPT" or kind=="TRADECLOSE" then
  self:StopMovement();return self:TradeAction(kind,fields)
 end
 if kind=="STOP" then self.tradePending,self.destroyPending=nil,nil end
 return execute(self,fields)
end
local state=B.AcceptState
function B:AcceptState(fields,id)
 if fields[1]=="trade" then
  if id<=(self.lastTradeID or 0) then return end
  if table.getn(fields)==2 and fields[2]=="closed" then self.cache.trade=nil;self.lastTradeID=id;return end
  if table.getn(fields)~=10 or not self.Integer(fields[5],0,2147483647) or not self.Integer(fields[6],0,2147483647) then return end
  local encoded=self.Split(fields[9],"\n");if table.getn(encoded)~=14 then return end
  local rows={}
  for i,row in ipairs(encoded) do
   rows[i]=self:Decode(row)
   if table.getn(rows[i])~=7 or tonumber(rows[i][1])~=(i<=7 and 1 or 2) or tonumber(rows[i][2])~=math.mod(i-1,7)+1 or not self.Integer(rows[i][5],0,1000000) then return end
  end
  self.cache.trade={fields=fields,rows=rows,at=GetTime()};self.lastTradeID=id
 elseif fields[1]=="destroyconfirm" then
  if table.getn(fields)~=7 or id<=(self.lastDestroyID or 0) then return end
  self.lastDestroyID=id
  local owner,key,session=self.db.peer,self.db.key,self.session
  StaticPopupDialogs=StaticPopupDialogs or {}
  if StaticPopup_Hide then StaticPopup_Hide("ZBOX_DESTROY") end
  StaticPopupDialogs.ZBOX_DESTROY={text="Destroy %s on %s?\nThis permanently destroys the entire stack.",button1=DELETE or "Destroy",button2=CANCEL or "Cancel",timeout=20,whileDead=1,hideOnEscape=1,
   OnAccept=function()
    B:WithFollower(owner,function(b)
     if b.connected and b.db.key==key and b.session==session then b:Command("DESTROY",{fields[2]}) end
    end)
   end}
  if StaticPopup_Show then StaticPopup_Show("ZBOX_DESTROY",fields[7].." x"..fields[6],owner) end
 else return state(self,fields,id) end
end
local function text(parent,value,x,y,width)
 local t=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");t:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);t:SetWidth(width);t:SetJustifyH("LEFT");t:SetText(value);return t
end
local function button(parent,value,x,y,width,fn)
 local f=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate");f:SetWidth(width);f:SetHeight(22);f:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);f:SetText(value);f:SetScript("OnClick",fn);return f
end
function B:ShowBagMenu(row,cell)
 local guid=self:GUID("target")
 local name=UnitName("target")
 if guid=="" or guid==self.peerGUID or not UnitIsPlayer or not UnitIsPlayer("target") or (UnitCanAttack and UnitCanAttack("player","target")) then guid,name=self:GUID("player"),UnitName("player") end
 local f=self.bagMenu
 if not f then
  f=CreateFrame("Frame","zBoxBagMenu",UIParent);self.bagMenu=f
  f:SetWidth(225);f:SetHeight(104);f:SetFrameStrata("TOOLTIP");f:EnableMouse(true);f:SetClampedToScreen(true)
  f:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12});f:SetBackdropColor(.03,.04,.05,1)
  local function run(kind,trade)
   f:Hide();local fields={f.item[1],f.item[2],f.item[8],f.item[4]};if trade then table.insert(fields,f.recipient) end
   local owner,key=f.owner,f.key
   B:WithFollower(owner,function(b)
    if b.db.key~=key then return end
    local ok,why=b:Command(kind,fields);if not ok then b:Notify(why) end
   end)
  end
  button(f,"Use / Equip",8,-8,209,function() run("USEITEM") end)
  f.trade=button(f,"Trade",8,-32,209,function() run("TRADEITEM",true) end)
  button(f,"Destroy...",8,-56,153,function() run("DESTROYPREP") end)
  button(f,"X",164,-56,53,function() f:Hide() end)
  f.ownerLabel=text(f,"",9,-84,205);table.insert(UISpecialFrames,"zBoxBagMenu")
 end
 f.owner,f.key,f.recipient=self.db.peer,self.db.key,guid
 f.item={};for i,v in ipairs(row) do f.item[i]=v end
 f.trade:SetText("Trade to "..(name or "driver"));f.ownerLabel:SetText(self.db.peer.." - stack x"..row[4])
 f:ClearAllPoints();f:SetPoint("TOPLEFT",cell,"BOTTOMLEFT",0,0);f:Show()
end
function B:CreateTradePreview()
 if self.tradeUI then return end
 local f=CreateFrame("Frame","zBoxTradePreview",UIParent);self.tradeUI=f
 f:SetWidth(370);f:SetHeight(410);f:SetPoint("CENTER",UIParent,"CENTER",240,0);f:SetFrameStrata("DIALOG");f:SetFrameLevel(45)
 f:EnableMouse(true);f:SetMovable(true);f:SetClampedToScreen(true);f:RegisterForDrag("LeftButton")
 f:SetScript("OnDragStart",function() f:StartMoving() end);f:SetScript("OnDragStop",function() f:StopMovingOrSizing() end)
 f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=24,insets={left=6,right=6,top=6,bottom=6}})
 f.title=text(f,"Follower trade",18,-15,315);f.labels={};f.icons={}
 for i=1,14 do
  local x=i<=7 and 15 or 193;local y=-67-math.mod(i-1,7)*39
  local icon=f:CreateTexture(nil,"ARTWORK");icon:SetWidth(30);icon:SetHeight(30);icon:SetPoint("TOPLEFT",f,"TOPLEFT",x,y)
  f.icons[i]=icon;f.labels[i]=text(f,"",x+34,y,135);f.labels[i]:SetHeight(35)
 end
 f.own=text(f,"",15,-44,170);f.other=text(f,"",193,-44,164);f.money=text(f,"",15,-345,340)
 local function act(kind)
  if not f.snapshot then return end
  local v=f.snapshot;local ok,why=B:PeerCommand(f.owner,kind,{v.fields[10],v.fields[3]})
  if not ok then B:Notify(why) end
 end
 button(f,"Accept",15,-376,105,function() act("TRADEACCEPT") end)
 button(f,"Cancel trade",127,-376,115,function() act("TRADECLOSE") end)
 button(f,"Hide",249,-376,105,function() f.dismissed=f.snapshot and f.snapshot.fields[2];f:Hide() end)
 f:Hide()
end
local function money(v)
 v=tonumber(v) or 0;return math.floor(v/10000).."g "..math.mod(math.floor(v/100),100).."s "..math.mod(v,100).."c"
end
function B:TradeTick(now)
 if self.tradePending and now>self.tradePending.expires then self.tradePending=nil end
 if self.destroyPending and now>self.destroyPending.expires then self.destroyPending=nil end
 if self.db.role=="agent" then
  if self.connected and (self.tradeDirty or self.tradeOpen) and now>=(self.nextTradeSend or 0) then
   local snapshot=self:TradeSnapshot() or {"trade","closed"}
   if self:Send("STATE",snapshot,true) then self.tradeDirty=nil;self.nextTradeSend=now+(self.tradeDirty and .1 or 1) end
  end
  return
 end
 if not self.db.enabled or self.worldSuspended then
  if self.tradeUI then self.tradeUI:Hide() end
  if self.tradeButton then self.tradeButton:Hide() end
  return
 end
 if TradeFrame and not self.tradeButton then
  self.tradeButton=button(TradeFrame,"Accept follower",20,-390,135,function()
   local f=B.tradeButton;local s=f.snapshot
   if s then local ok,why=B:PeerCommand(f.owner,"TRADEACCEPT",{s.fields[10],s.fields[3]});if not ok then B:Notify(why) end end
  end)
 end
 local match
 local target=TradeFrame and TradeFrame:IsShown() and partner()
 for _,name in ipairs(self:FollowerNames()) do
  local s=self:FollowerState(name)
  local offer=s and s.cache and s.cache.trade
  if s and s.connected and s.peerGUID==target and offer and offer.fields[3]==self:GUID("player") and now-offer.at<10 then match={name,offer};break end
 end
 if self.tradeButton then
  if match then self.tradeButton.owner,self.tradeButton.snapshot=match[1],match[2];self.tradeButton:Show() else self.tradeButton.snapshot=nil;self.tradeButton:Hide() end
 end
 self:CreateTradePreview()
 local f=self.tradeUI;local selected=self.cache.trade
 if not self.connected or not selected or selected.fields[3]==self:GUID("player") or now-selected.at>10 then f:Hide();return end
 f.owner,f.snapshot=self.db.peer,selected
 if f.dismissed==selected.fields[2] then return end
 local class=self.cache.status and self.cache.status[4];local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
 if c then f:SetBackdropBorderColor(c.r,c.g,c.b,1) end
 f.title:SetText(self.db.peer.." trading with "..selected.fields[4])
 f.own:SetText(self.db.peer..(selected.fields[7]=="1" and " - Accepted" or ""));f.other:SetText(selected.fields[4]..(selected.fields[8]=="1" and " - Accepted" or ""))
 for i,row in ipairs(selected.rows) do f.icons[i]:SetTexture(row[4]~="" and row[4] or "Interface\\PaperDoll\\UI-Backpack-EmptySlot");f.labels[i]:SetText((row[3]~="" and row[3].." x"..row[5] or "Empty")..(math.mod(i-1,7)==6 and "\nNot traded" or "")) end
 f.money:SetText("Offers: "..money(selected.fields[5]).." / "..money(selected.fields[6]));f:Show()
end
local events=CreateFrame("Frame")
B.tradeEvents=events
for _,name in ipairs({"TRADE_SHOW","TRADE_CLOSED","TRADE_UPDATE","TRADE_PLAYER_ITEM_CHANGED","TRADE_TARGET_ITEM_CHANGED","TRADE_ACCEPT_UPDATE","TRADE_MONEY_CHANGED"}) do events:RegisterEvent(name) end
events:SetScript("OnEvent",function()
 if not B.ready then return end
 if event=="TRADE_SHOW" then B.tradeOpen=B:NewSession();B.tradeAccepted,B.tradeOtherAccepted="0","0";if B.db.role=="agent" and B.connected and B.tradePending then B:PlaceTradeItem() end
 elseif event=="TRADE_CLOSED" then B.tradeOpen,B.tradePending=nil,nil
 elseif event=="TRADE_ACCEPT_UPDATE" then B.tradeAccepted,B.tradeOtherAccepted=flag(arg1==1),flag(arg2==1) end
 B.tradeDirty=true
end)
