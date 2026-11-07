-- Cast target dropdown. Replaces click-to-cycle so every mode is visible.
local B,U=zBox,zBox.UI
if not U then return end
local MODES={
 {"TARGET","Main's target","Hostile skills hit your main's current target. Friendly skills go to your main."},
 {"MAIN","Main character","Targeted skills are cast on your main."},
 {"SELF","Skill owner","Skills are cast on the character that owns them."},
 {"KEEP","Owner's target","Skills use whatever the skill owner already has targeted."},
 {"MOUSEOVER","Mouseover","Skills go to the unit under your cursor, in the world or on unit frames. With nothing hovered, friendly skills go to your main and other skills to your main's target. Best used with zBox keybinds."},
}
B.TargetModes=MODES
local function over(f)
 if not f or not f:IsVisible() then return false end
 if MouseIsOver then return MouseIsOver(f) end
 local x,y=GetCursorPosition();local s=f:GetEffectiveScale();local l,r,t,b=f:GetLeft(),f:GetRight(),f:GetTop(),f:GetBottom()
 return l and x>=l*s and x<=r*s and y>=b*s and y<=t*s
end
local valid={};for _,m in ipairs(MODES) do valid[m[1]]=m end

function B:SetTargetMode(mode)
 if not valid[mode] then return false end
 self.targetMode=mode
 if self.BarProfile and self.db and self.db.role=="control" then local p=self:BarProfile();p.targetMode=mode end
 if self.UI and self.UI.frame then self.UI:Refresh() end
 return true
end

function U:TargetMenu()
 if self.targetMenu then return self.targetMenu end
 local m=CreateFrame("Frame","zBoxTargetMenu",self.frame)
 m:SetFrameStrata("FULLSCREEN_DIALOG");m:SetToplevel(true);m:EnableMouse(true);m:SetWidth(150)
 m:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
 m:SetBackdropColor(.06,.09,.13,.97);m:SetBackdropBorderColor(.25,.45,.49,1)
 m.rows={}
 for i,mode in ipairs(MODES) do
  local info=mode
  local r=CreateFrame("Button",nil,m);r:SetHeight(18)
  r:SetPoint("TOPLEFT",m,"TOPLEFT",5,-5-(i-1)*18);r:SetPoint("RIGHT",m,"RIGHT",-5,0)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
  r.check=r:CreateTexture(nil,"OVERLAY");r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  r.check:SetWidth(14);r.check:SetHeight(14);r.check:SetPoint("LEFT",r,"LEFT",1,0)
  r.text=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");r.text:SetPoint("LEFT",r,"LEFT",18,0);r.text:SetText(info[2])
  r.mode=info[1]
  r:SetScript("OnClick",function() B:SetTargetMode(info[1]);m:Hide() end)
  r:SetScript("OnEnter",function()
   GameTooltip:SetOwner(this,"ANCHOR_RIGHT");GameTooltip:SetText(info[2])
   GameTooltip:AddLine(info[3],.7,.85,.85,true);GameTooltip:Show()
  end)
  r:SetScript("OnLeave",function() GameTooltip:Hide() end)
  m.rows[i]=r
 end
 m:SetHeight(10+table.getn(MODES)*18)
 -- Close like a Blizzard dropdown: Escape, a choice, or the cursor leaving it.
 m:SetScript("OnUpdate",function()
  if over(m) or over(U.targetMode) then m.away=0;return end
  m.away=(m.away or 0)+(arg1 or 0);if m.away>1.2 then m:Hide() end
 end)
 m:SetScript("OnShow",function() m.away=0 end)
 m:Hide();table.insert(UISpecialFrames,"zBoxTargetMenu")
 self.targetMenu=m
 return m
end

function U:ShowTargetMenu()
 local m,b=self:TargetMenu(),self.targetMode
 for _,r in ipairs(m.rows) do
  if r.mode==B.targetMode then r.check:Show();r.text:SetTextColor(.3,.95,.8) else r.check:Hide();r.text:SetTextColor(.9,.95,.9) end
 end
 m:ClearAllPoints()
 local bottom,scale=b:GetBottom(),b:GetEffectiveScale()
 if bottom and bottom*scale<(m:GetHeight()+8)*scale then m:SetPoint("BOTTOMLEFT",b,"TOPLEFT",0,2)
 else m:SetPoint("TOPLEFT",b,"BOTTOMLEFT",0,-2) end
 GameTooltip:Hide();m:Show()
end

function U:CycleTarget()
 local m=self:TargetMenu()
 if m:IsShown() then m:Hide() else self:ShowTargetMenu() end
end

local create=U.Create
function U:Create()
 create(self)
 local b=self.targetMode;if not b or b.zBoxDropdown then return end
 b.zBoxDropdown=true
 b.arrow=b:CreateTexture(nil,"OVERLAY");b.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
 b.arrow:SetWidth(16);b.arrow:SetHeight(16);b.arrow:SetPoint("RIGHT",b,"RIGHT",-2,0)
 b.caption:ClearAllPoints();b.caption:SetPoint("LEFT",b,"LEFT",5,0);b.caption:SetPoint("RIGHT",b.arrow,"LEFT",0,0)
 b.caption:SetJustifyH("CENTER");b.caption:SetHeight(12)
 b:SetScript("OnEnter",function()
  this:SetBackdropColor(.13,.24,.29,1)
  GameTooltip:SetOwner(this,"ANCHOR_TOP");GameTooltip:SetText("Cast target")
  GameTooltip:AddLine("Click to choose where account 2's skills are cast.",.7,.85,.85,true)
  GameTooltip:AddLine("Alt-click a dock skill (or right-click a Spells/Actions entry) to cast it on its owner. Right-click a dock skill toggles autocast.",.7,.85,.85,true)
  GameTooltip:Show()
 end)
 b:SetScript("OnLeave",function() this:SetBackdropColor(.09,.13,.18,1);GameTooltip:Hide() end)
 local hide=self.frame:GetScript("OnHide")
 self.frame:SetScript("OnHide",function() if U.targetMenu then U.targetMenu:Hide() end;if hide then hide() end end)
end

-- Generic dropdown used for movement mode and pet approach.
local MOVEMENT={
 {"follow","Follow","Account 2 follows you. Click the Follow button to (re)start following."},
 {"mirror","Mirror","Account 2 copies your movement, jumps and facing. Click the button to pause or resume."},
 {"pet","Pet controls","Follow / Assist / Attack orders, like a pet. Combat ends back in follow."},
}
local APPROACH={
 {"auto","Auto (class)","Melee classes close in; casters and hunters keep range."},
 {"melee","Melee","Always move into melee range when attacking."},
 {"ranged","Caster / ranged","Stay at range when attacking."},
}
function U:ChoiceMenu()
 if self.choiceMenu then return self.choiceMenu end
 local m=CreateFrame("Frame","zBoxChoiceMenu",self.frame)
 m:SetFrameStrata("FULLSCREEN_DIALOG");m:SetToplevel(true);m:EnableMouse(true);m:SetWidth(150)
 m:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
 m:SetBackdropColor(.06,.09,.13,.97);m:SetBackdropBorderColor(.25,.45,.49,1)
 m.rows={}
 for i=1,6 do
  local r=CreateFrame("Button",nil,m);r:SetHeight(18)
  r:SetPoint("TOPLEFT",m,"TOPLEFT",5,-5-(i-1)*18);r:SetPoint("RIGHT",m,"RIGHT",-5,0)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
  r.check=r:CreateTexture(nil,"OVERLAY");r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  r.check:SetWidth(14);r.check:SetHeight(14);r.check:SetPoint("LEFT",r,"LEFT",1,0)
  r.text=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");r.text:SetPoint("LEFT",r,"LEFT",18,0)
  r:SetScript("OnClick",function() local pick,value=m.pick,this.value;m:Hide();if pick then pick(value) end end)
  r:SetScript("OnEnter",function()
   GameTooltip:SetOwner(this,"ANCHOR_RIGHT");GameTooltip:SetText(this.label or "")
   if this.desc then GameTooltip:AddLine(this.desc,.7,.85,.85,true) end;GameTooltip:Show()
  end)
  r:SetScript("OnLeave",function() GameTooltip:Hide() end)
  m.rows[i]=r
 end
 m:SetScript("OnUpdate",function()
  if over(m) or over(m.anchor) then m.away=0;return end
  m.away=(m.away or 0)+(arg1 or 0);if m.away>1.2 then m:Hide() end
 end)
 m:SetScript("OnShow",function() m.away=0 end)
 m:Hide();table.insert(UISpecialFrames,"zBoxChoiceMenu")
 self.choiceMenu=m
 return m
end
function U:ShowChoices(anchor,options,current,pick)
 local m=self:ChoiceMenu()
 if m:IsShown() and m.anchor==anchor then m:Hide();return end
 if self.targetMenu then self.targetMenu:Hide() end
 m.anchor,m.pick=anchor,pick
 for i,r in ipairs(m.rows) do
  local o=options[i]
  if o then
   r.value,r.label,r.desc=o[1],o[2],o[3];r.text:SetText(o[2])
   if o[1]==current then r.check:Show();r.text:SetTextColor(.3,.95,.8) else r.check:Hide();r.text:SetTextColor(.9,.95,.9) end
   r:Show()
  else r:Hide() end
 end
 m:SetHeight(10+table.getn(options)*18);m:SetWidth(math.max(150,anchor:GetWidth() or 0))
 m:ClearAllPoints()
 local bottom,scale=anchor:GetBottom(),anchor:GetEffectiveScale()
 if bottom and bottom*scale<(m:GetHeight()+8)*scale then m:SetPoint("BOTTOMLEFT",anchor,"TOPLEFT",0,2)
 else m:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",0,-2) end
 GameTooltip:Hide();m:Show()
end
function U:ShowMovementMenu(anchor)
 self:ShowChoices(anchor,MOVEMENT,B:MovementMode(),function(mode)
  local ok,reason=B:SetMovementMode(mode);if not ok then B:Notify(reason) end
  U.dirty=true;U:Refresh()
 end)
end
function U:ShowApproachMenu(anchor)
 self:ShowChoices(anchor,APPROACH,B.db.petStyle or "auto",function(style) B.db.petStyle=style;U:Refresh() end)
end
local function addArrow(b)
 if not b or b.arrow then return end
 b.arrow=b:CreateTexture(nil,"OVERLAY");b.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
 b.arrow:SetWidth(16);b.arrow:SetHeight(16);b.arrow:SetPoint("RIGHT",b,"RIGHT",-2,0)
 b.caption:ClearAllPoints();b.caption:SetPoint("LEFT",b,"LEFT",5,0);b.caption:SetPoint("RIGHT",b.arrow,"LEFT",0,0)
 b.caption:SetJustifyH("CENTER");b.caption:SetHeight(12)
end
local create2=U.Create
function U:Create()
 create2(self)
 if self.modeButton and not self.modeButton.zBoxDropdown then
  self.modeButton.zBoxDropdown=true;addArrow(self.modeButton)
  local mb=self.modeButton;mb:SetScript("OnClick",function() U:ShowMovementMenu(mb) end)
 end
 if self.petStyleButton and not self.petStyleButton.zBoxDropdown then
  self.petStyleButton.zBoxDropdown=true;addArrow(self.petStyleButton)
  local pb=self.petStyleButton;pb:SetScript("OnClick",function() U:ShowApproachMenu(pb) end)
 end
 local f=self.followButton
 if f and not f.zBoxDropdown then
  f.zBoxDropdown=true
  -- Left-click keeps its action (follow / pause mirror); right-click now opens
  -- the mode list instead of cycling blindly.
  local click=f:GetScript("OnClick")
  f:SetScript("OnClick",function()
   if arg1=="RightButton" and not (IsShiftKeyDown and IsShiftKeyDown()) then U:ShowMovementMenu(f) elseif click then click() end
  end)
  local enter=f:GetScript("OnEnter")
  f:SetScript("OnEnter",function()
   if enter then enter() end
   GameTooltip:AddLine("Right-click: choose Follow / Mirror / Pet controls.",.3,.95,.8,true);GameTooltip:Show()
  end)
 end
 local hide=self.frame:GetScript("OnHide")
 self.frame:SetScript("OnHide",function() if U.choiceMenu then U.choiceMenu:Hide() end;if hide then hide() end end)
end
