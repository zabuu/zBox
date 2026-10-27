-- A separate remote conversation using the client's own dialogue templates.
-- It never reparents the main character's widgets or installs their callbacks.
local B,U=zBox,zBox.UI
local border={edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,
  insets={left=3,right=3,top=3,bottom=3}}

local function font(parent,template,size)
  local text=parent:CreateFontString(nil,"OVERLAY",template)
  if not template then text:SetFont("Fonts\\FRIZQT__.TTF",size or 12) end
  text:SetJustifyH("LEFT");text:SetJustifyV("TOP")
  return text
end

local function copyFont(target,source)
  if not source or not source.GetFont then return end
  local path,size,flags=source:GetFont()
  if type(path)=="string" and type(size)=="number" then target:SetFont(path,size,flags) end
  if source.GetTextColor then
    local r,g,b,a=source:GetTextColor()
    if r then target:SetTextColor(r,g,b,a or 1) end
  end
end

local function height(text,value,width)
  text:SetWidth(width);text:SetHeight(0);text:SetText(value)
  local measured=text:GetStringHeight()
  local result=type(measured)=="number" and measured>0 and measured or math.max(14,math.ceil(string.len(value)/40)*15)
  text:SetHeight(result+2)
  return result+2
end

function U:CreateNPCWindow()
  if self.npcWindow then return end
  local f=CreateFrame("Frame","zBoxNPCWindow",UIParent)
  self.npcWindow=f
  f:SetWidth(384);f:SetHeight(512);f:SetPoint("CENTER",UIParent,"CENTER",210,0)
  f:SetFrameStrata("DIALOG");f:SetFrameLevel(40);f:SetMovable(true);f:SetClampedToScreen(true)
  f:SetHitRectInsets(0,30,0,70)
  f:EnableMouse(true);f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart",function() f:StartMoving() end)
  f:SetScript("OnDragStop",function()
    f:StopMovingOrSizing()
    local point,_,relative,x,y=f:GetPoint()
    if point and relative and x and y then B.db.npcPosition={point,relative,x,y} end
  end)
  local pos=B.db.npcPosition
  if pos then f:ClearAllPoints();f:SetPoint(pos[1],UIParent,pos[2],pos[3],pos[4]) end
  f.art=CreateFrame("Frame","zBoxNPCWindowArt",f,"GossipFramePanelTemplate")
  f.art:SetFrameLevel(f:GetFrameLevel())
  f.art:SetAllPoints(f);f.art:EnableMouse(false)
  f.chrome=CreateFrame("Frame",nil,f);f.chrome:SetFrameLevel(f:GetFrameLevel()+4)
  f.chrome:SetAllPoints(f);f.chrome:EnableMouse(false)
  f.classBorder=CreateFrame("Frame",nil,f)
  f.classBorder:SetFrameLevel(f:GetFrameLevel()+2);f.classBorder:EnableMouse(false)
  f.classBorder:SetPoint("TOPLEFT",f,"TOPLEFT",12,-18)
  f.classBorder:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-28,66)
  f.classBorder:SetBackdrop(border)
  f.portrait=f:CreateTexture(nil,"ARTWORK")
  f.portrait:SetParent(f.chrome)
  f.portrait:SetWidth(60);f.portrait:SetHeight(60);f.portrait:SetPoint("TOPLEFT",f,"TOPLEFT",7,-6)
  f.name=font(f,"GameFontHighlight");f.name:SetWidth(235);f.name:SetHeight(20)
  f.name:SetParent(f.chrome)
  f.name:SetPoint("TOP",f,"TOP",0,-23);f.name:SetJustifyH("CENTER")
  f.owner=font(f.chrome,"GameFontNormalSmall");f.owner:SetWidth(205);f.owner:SetHeight(14)
  f.owner:SetPoint("TOPLEFT",f,"TOPLEFT",27,-55)
  f.close=CreateFrame("Button","zBoxNPCWindowClose",f,"UIPanelCloseButton")
  f.close:SetFrameLevel(f:GetFrameLevel()+8)
  f.close:SetPoint("CENTER",f,"TOPRIGHT",-42,-31)
  f.close:SetScript("OnClick",function() U:CloseNPC() end)
  f.scroll=CreateFrame("ScrollFrame","zBoxNPCWindowScroll",f,"UIPanelScrollFrameTemplate")
  f.scroll:SetFrameLevel(f:GetFrameLevel()+4)
  f.scroll:SetPoint("TOPLEFT",f,"TOPLEFT",23,-81);f.scroll:SetWidth(300);f.scroll:SetHeight(334)
  f.body=CreateFrame("Frame",nil,f.scroll);f.body:SetWidth(300);f.body:SetHeight(334)
  f.scroll:SetScrollChild(f.body);f.scroll:EnableMouseWheel(true)
  f.scroll:SetScript("OnMouseWheel",function()
    f.scroll:SetVerticalScroll(math.max(0,math.min(f.maxScroll or 0,f.scroll:GetVerticalScroll()-arg1*30)))
  end)
  f.questTitle=font(f.body,"QuestTitleFont");f.questTitle:SetPoint("TOPLEFT",f.body,"TOPLEFT",10,-10)
  f.dialogue=font(f.body,"QuestFont");f.dialogue:SetPoint("TOPLEFT",f.body,"TOPLEFT",10,-10)
  f.objectives=font(f.body,"QuestFont");f.rows={}
  for index=1,32 do
    local b=CreateFrame("Button","zBoxNPCChoice"..index,f.body)
    b.section="npc";b:SetWidth(290);b:SetHeight(24)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
    b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetWidth(16);b.icon:SetHeight(16)
    b.icon:SetPoint("TOPLEFT",b,"TOPLEFT",0,-1)
    b.label=font(b,"QuestFont");b.label:SetPoint("TOPLEFT",b,"TOPLEFT",20,0)
    b.name,b.remoteNPC=b.label,true
    b.detail=font(b,"GameFontNormalSmall");b.detail:SetPoint("TOPLEFT",b,"TOPLEFT",40,-20)
    b:SetScript("OnClick",function()
      if this.row and this.row[6]=="reward" then
        f.selectedReward=this.row[5]
        U:RenderNPCWindow(B.cache.npc)
      else U:Click(this,"LeftButton") end
    end)
    b:SetScript("OnEnter",function() if this.row then U:Tooltip(this) end end)
    b:SetScript("OnLeave",function() GameTooltip:Hide();U.hovered=nil end)
    f.rows[index]=b
  end
  f.primary=CreateFrame("Button","zBoxNPCWindowPrimary",f,"UIPanelButtonTemplate")
  f.primary:SetFrameLevel(f:GetFrameLevel()+6)
  f.primary:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",23,73);f.primary:SetWidth(130);f.primary:SetHeight(22)
  f.primary.section="npc";f.primary:SetScript("OnClick",function()
    local row=this.row
    if row and row[6]=="reward" and tonumber(row[7])==0 then U:Run("NPC",{row[6],row[1],row[5]})
    else U:Click(this,"LeftButton") end
  end)
  f.goodbye=CreateFrame("Button","zBoxNPCWindowGoodbye",f,"UIPanelButtonTemplate")
  f.goodbye:SetFrameLevel(f:GetFrameLevel()+6)
  f.goodbye:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-39,73);f.goodbye:SetWidth(100);f.goodbye:SetHeight(22)
  f.goodbye:SetText(GOODBYE or "Goodbye");f.goodbye:SetScript("OnClick",function() U:CloseNPC() end)
  f.prev=CreateFrame("Button","zBoxNPCWindowPrevious",f,"UIPanelButtonTemplate")
  f.prev:SetFrameLevel(f:GetFrameLevel()+6)
  f.prev:SetPoint("TOPLEFT",f,"TOPLEFT",240,-53);f.prev:SetWidth(25);f.prev:SetHeight(18);f.prev:SetText("<")
  f.prev:SetScript("OnClick",function() U:NPCPage(-1) end)
  f.next=CreateFrame("Button","zBoxNPCWindowNext",f,"UIPanelButtonTemplate")
  f.next:SetFrameLevel(f:GetFrameLevel()+6)
  f.next:SetPoint("TOPLEFT",f,"TOPLEFT",298,-53);f.next:SetWidth(25);f.next:SetHeight(18);f.next:SetText(">")
  f.next:SetScript("OnClick",function() U:NPCPage(1) end)
  f.page=font(f.chrome,"GameFontNormalSmall");f.page:SetPoint("TOPLEFT",f,"TOPLEFT",267,-56)
  f.page:SetWidth(30);f.page:SetHeight(16);f.page:SetJustifyH("CENTER")
  f.confirm=font(f.chrome,"GameFontNormalSmall");f.confirm:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",24,52)
  f.confirm:SetWidth(300);f.confirm:SetHeight(16)
  f.extras={}
  for index=1,24 do
    local item=CreateFrame("Frame",nil,f.body)
    item:SetWidth(290);item:SetHeight(38)
    item.icon=item:CreateTexture(nil,"ARTWORK");item.icon:SetWidth(32);item.icon:SetHeight(32)
    item.icon:SetPoint("TOPLEFT",item,"TOPLEFT",0,0)
    item.label=font(item,"QuestFont");item.label:SetWidth(246);item.label:SetHeight(34)
    item.label:SetPoint("TOPLEFT",item,"TOPLEFT",40,0);f.extras[index]=item
  end
  f:SetScript("OnHide",function()
    if B.cache.npc then B.npcDismissedRevision=B.cache.npc.meta[7] end
    GameTooltip:Hide()
  end)
  table.insert(UISpecialFrames,"zBoxNPCWindow")
  f:Hide()
end

function U:SkinNPCWindow(kind)
  local f=self.npcWindow
  local quest=kind=="detail" or kind=="progress" or kind=="reward" or kind=="greeting"
  local source=quest and QuestFrame or GossipFrame
  local skinned=source and source.backdrop and pfUI and pfUI.api
  if source and source.GetScale then f:SetScale(source:GetScale() or 1) end
  if skinned and not f.pfSkinned then
    local api=pfUI.api
    if api.StripTextures then api.StripTextures(f.art) end
    if api.CreateBackdrop then
      api.CreateBackdrop(f,nil,nil,.75)
      f.backdrop:ClearAllPoints();f.backdrop:SetPoint("TOPLEFT",f,"TOPLEFT",12,-18)
      f.backdrop:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-28,66)
      api.CreateBackdrop(f.scroll,nil,true,.75)
    end
    f.paper=f.scroll:CreateTexture(nil,"BACKGROUND");f.paper:SetAllPoints(f.scroll)
    f.paper:SetTexCoord(.1,1,0,1);f.paper:SetTexture("Interface\\Stationery\\StationeryTest1")
    f.scroll:SetHeight(330)
    if api.SkinButton then for _, b in ipairs({f.primary,f.goodbye,f.prev,f.next}) do api.SkinButton(b) end end
    if api.SkinCloseButton then api.SkinCloseButton(f.close,f.backdrop,-6,-6) end
    local scrollbar=getglobal("zBoxNPCWindowScrollScrollBar")
    if scrollbar and api.SkinScrollbar then api.SkinScrollbar(scrollbar) end
    f.pfSkinned=true
  end
  if f.pfSkinned then
    f:SetHitRectInsets(12,28,18,66)
    f.classBorder:Hide()
    f.portrait:Hide();f.name:ClearAllPoints();f.name:SetPoint("TOP",f.backdrop,"TOP",0,-10)
  else
    f.classBorder:Show()
    f.portrait:Show()
    local guid=B.cache.npc and B.cache.npc.meta[6]
    if guid and guid~="" and SetPortraitTexture then pcall(SetPortraitTexture,f.portrait,guid)
    else f.portrait:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookIcon") end
  end
  copyFont(f.name,source and getglobal((quest and "Quest" or "Gossip").."FrameNpcNameText"))
  local bodyFonts={detail=QuestDescription,progress=QuestProgressText,reward=QuestRewardText,greeting=GreetingText}
  copyFont(f.dialogue,quest and bodyFonts[kind] or GossipGreetingText)
  local titleFonts={detail=QuestTitleText,progress=QuestProgressTitleText,reward=QuestRewardTitleText}
  copyFont(f.questTitle,titleFonts[kind])
  local color=RAID_CLASS_COLORS and B.cache.status and RAID_CLASS_COLORS[B.cache.status[4]]
  local r,g,b=color and color.r or .3,color and color.g or .95,color and color.b or .8
  f.classBorder:SetBackdropBorderColor(r,g,b,1)
  if f.backdrop then f.backdrop:SetBackdropBorderColor(r,g,b,1) end
  f.owner:SetText((B.db.peer or "Account 2").."'s conversation");f.owner:SetTextColor(r,g,b)
end

function U:RenderNPCWindow(view)
  local f,meta=self.npcWindow,view.meta or {}
  if not f then return end
  self:SkinNPCWindow(meta[1])
  f.name:SetText(meta[2] or "NPC")
  local y=10
  if (meta[3] or "")~="" then
    y=y+height(f.questTitle,meta[3],270)+14;f.questTitle:Show()
  else f.questTitle:Hide() end
  f.dialogue:ClearAllPoints();f.dialogue:SetPoint("TOPLEFT",f.body,"TOPLEFT",10,-y)
  local value=meta[4] or ""
  if meta[1]=="" then value="Target an NPC, then press Talk. Account 2 must be within 6 yards." end
  y=y+height(f.dialogue,value,270)+20
  f.objectives:ClearAllPoints();f.objectives:SetPoint("TOPLEFT",f.body,"TOPLEFT",10,-y)
  if (meta[5] or "")~="" then
    y=y+height(f.objectives,(QUEST_OBJECTIVES or "Objectives").."\n"..meta[5],270)+18;f.objectives:Show()
  else f.objectives:Hide() end
  f.primary:Hide();f.primary.row=nil
  local hasRewards=false
  for _, row in ipairs(view.rows) do if row[6]=="reward" and tonumber(row[1])>0 then hasRewards=true end end
  local index=0
  for _, row in ipairs(view.rows) do
    local op=row[6]
    if op=="accept" or op=="complete" or (op=="reward" and tonumber(row[1])==0) then
      f.primary.row=row;f.primary:Show()
      f.primary:SetText(op=="accept" and (ACCEPT or "Accept") or (op=="complete" and (CONTINUE or "Continue") or (COMPLETE_QUEST or "Complete Quest")))
      if row[9]=="0" then f.primary:Disable() else f.primary:Enable() end
    elseif op~="close" then
      index=index+1
      local cell=f.rows[index]
      cell.row=row;cell:SetPoint("TOPLEFT",f.body,"TOPLEFT",0,-y)
      if op=="reward" and f.selectedReward==row[5] then
        f.primary.row=row;f.primary:SetText(COMPLETE_QUEST or "Complete Quest");f.primary:Show();f.primary:Enable()
        cell:LockHighlight()
      else cell:UnlockHighlight()
      end
      local item=op=="buy" or op=="train" or (op=="reward" and hasRewards)
      local icon=(op=="available" or op=="gossipAvailable") and "Interface\\GossipFrame\\AvailableQuestIcon" or
        ((op=="active" or op=="gossipActive") and "Interface\\GossipFrame\\ActiveQuestIcon" or row[2])
      cell.icon:SetTexture(icon);cell.icon:SetWidth(item and 32 or 16);cell.icon:SetHeight(item and 32 or 16)
      cell.label:ClearAllPoints();cell.label:SetPoint("TOPLEFT",cell,"TOPLEFT",item and 40 or 20,0)
      local rowHeight=height(cell.label,row[3],item and 245 or 270)
      if item then
        cell.detail:SetText(row[4]);cell.detail:SetWidth(240);cell.detail:SetHeight(28);cell.detail:Show()
        rowHeight=math.max(48,rowHeight+28)
      else cell.detail:Hide() end
      cell:SetHeight(rowHeight);cell:Show();y=y+rowHeight+4
    end
  end
  for i=index+1,32 do f.rows[i].row=nil;f.rows[i]:Hide() end
  local extraIndex,category=0,nil
  if (meta[8] or "")~="" then
    for _, encoded in ipairs(B.Split(meta[8],"\n")) do
      local row=B:Decode(encoded)
      if table.getn(row)==4 and extraIndex<24 then
        extraIndex=extraIndex+1
        local item=f.extras[extraIndex]
        item:SetPoint("TOPLEFT",f.body,"TOPLEFT",0,-y)
        local headings={choice=REWARD_CHOICES or "Choose a reward",reward=REWARD_ITEMS or "You will receive",required=REQUIRED_ITEMS or "Required items",spell=REWARD_SPELL or "Spell learned",money=REWARDS or "Rewards"}
        local caption=(row[1]~=category and ((headings[row[1]] or "Rewards").."\n") or "")..row[2]
        if tonumber(row[4]) and tonumber(row[4])>1 then caption=caption.." x"..row[4] end
        item.label:SetText(caption);item.icon:SetTexture(row[3]);item:Show()
        category=row[1];y=y+42
      end
    end
  end
  for i=extraIndex+1,24 do f.extras[i]:Hide() end
  f.body:SetHeight(math.max(f.scroll:GetHeight(),y+8));f.maxScroll=math.max(0,y+8-f.scroll:GetHeight())
  local identity=(meta[7] or "")..":"..view.page
  if identity~=f.identity then f.scroll:SetVerticalScroll(0);f.identity=identity end
  f.scroll:SetVerticalScroll(math.min(f.scroll:GetVerticalScroll(),f.maxScroll))
  f.scroll:UpdateScrollChildRect()
  if view.maximum>1 then f.prev:Show();f.next:Show();f.page:SetText(view.page.."/"..view.maximum);f.page:Show()
  else f.prev:Hide();f.next:Hide();f.page:Hide() end
end

function U:ReceiveNPC(view)
  self:CreateNPCWindow()
  local kind=view.meta[1] or ""
  if kind=="" then self.npcWindow:Hide();return end
  self:RenderNPCWindow(view)
  if not B.npcClosing and B.npcDismissedRevision~=view.meta[7] then
    if not self.npcWindow:IsShown() and not B.db.npcPosition then
      local source=(kind=="gossip" and GossipFrame or QuestFrame)
      if source and source:IsShown() then
        self.npcWindow:ClearAllPoints();self.npcWindow:SetPoint("TOPLEFT",source,"TOPRIGHT",5,0)
      end
    end
    self.npcWindow:Show()
  end
end

function U:OpenNPC()
  if not B.connected or B.db.role~="control" then return false,"Connect the second character first" end
  self:CreateNPCWindow()
  B.npcDismissedRevision,B.npcClosing=nil,nil
  self:RenderNPCWindow(B.cache.npc or {meta={"","NPC"},rows={},page=1,maximum=1})
  self.npcWindow:Show()
  B:Send("NPCVIEW",{B.cache.npc and B.cache.npc.page or 1},true)
  return true
end

function U:Talk()
  local ok,reason=self:OpenNPC()
  if not ok then B:Notify(reason);return false,reason end
  local guid=B:GUID("target")
  if guid=="" and B.cache.npc and B.cache.npc.meta[1]~="" then return true end
  return B:Command("TALK",{guid})
end

function U:CloseNPC()
  B.npcClosing=true
  local view=B.cache.npc
  local sent=false
  if view then
    for _, row in ipairs(view.rows) do
      if row[6]=="close" then self:Run("NPC",{"close",row[1],row[5]});sent=true;break end
    end
    if not sent and view.meta[9] and view.meta[9]~="" then self:Run("NPC",{"close",0,view.meta[9]}) end
  end
  if self.npcWindow then self.npcWindow:Hide() end
end

function U:NPCPage(delta)
  local view=B.cache.npc
  if view then B:Send("NPCVIEW",{math.max(1,math.min(view.maximum,view.page+delta))},true) end
end
