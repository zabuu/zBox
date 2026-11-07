-- Follow formations. The driver picks one; FOLLOW carries it to followers.
-- Center keeps the game's own follow. Left, Right, Front and Random walk to a
-- spot around the main, turned with the main's facing, using native
-- click-to-move (zBoxBridge contract 5+). Too far away or no geometry: the
-- follower falls back to normal follow until it is close again.
local B=zBox
local FORMATIONS={
 {"left","Left","Follows behind and to your left."},
 {"center","Center","Follows right behind you, like normal follow."},
 {"right","Right","Follows behind and to your right."},
 {"front","Front","Walks in front of you, like a shield."},
 {"random","Random","Trails behind you while you move; each time you stop it picks one spot in a wide zone behind you (1.5-5 yards back, up to 4 yards to either side) and stays there."},
}
B.Formations=FORMATIONS
local valid={};for _,f in ipairs(FORMATIONS) do valid[f[1]]=f end
-- Offsets in yards: forward (+ ahead of the main), right (+ to its right).
local OFFSETS={left={-2.5,-2.5},right={-2.5,2.5},front={3,0}}
B.FORMATION_FALLBACK=40 -- beyond this, use normal follow to catch up
-- Range: Close (default) or Far, which keeps 8-12 yards away so a hunter can shoot.
B.FORMATION_FAR={near=8,far=12,fixed=10}
local RANGES={close="Close",far="Far"}

-- Driver ---------------------------------------------------------------------

function B:Formation()
 local f=self.db and self.db.formation
 return valid[f or ""] and f or "center"
end

function B:FormationRange()
 local r=self.db and self.db.formationRange
 return RANGES[r or ""] and r or "close"
end

function B:SetFormationRange(range)
 if not RANGES[range or ""] then return false,"Unknown range" end
 self.db.formationRange=range
 self.notice="Formation range: "..RANGES[range]
 if self.UI and self.UI.UpdateFormationTab then self.UI:UpdateFormationTab() end
 if self.db.role=="control" and self.connected and self:AnyFollowerFollowing() then self:Command("FOLLOW") end
 return true
end

function B:SetFormation(name)
 if not valid[name or ""] then return false,"Unknown formation" end
 self.db.formation=name
 self.notice="Formation: "..valid[name][2]
 if self.UI then self.UI.dirty=true;if self.UI.UpdateFormationTab then self.UI:UpdateFormationTab() end end
 -- Re-issue Follow so a follower that is already following switches now.
 if self.db.role=="control" and self.connected and self:AnyFollowerFollowing() then self:Command("FOLLOW") end
 return true
end

function B:AnyFollowerFollowing()
 if self.FollowerNames and self.roster then
  for _,name in ipairs(self:FollowerNames()) do
   local s=self:FollowerState(name);if s and s.cache and s.cache.status and s.cache.status[13]=="Following" then return true end
  end
 end
 local status=self.cache and self.cache.status
 return status and status[13]=="Following" or false
end

local command=B.Command
function B:Command(kind,fields)
 if kind=="FOLLOW" then
  fields=fields or {}
  if fields[1]==nil then fields[1]=self:Formation() end
  if fields[2]==nil then fields[2]=self:FormationRange() end
 end
 return command(self,kind,fields)
end

-- Follower -------------------------------------------------------------------

local execute=B.Execute
function B:Execute(fields)
 if fields[1]=="FOLLOW" then
  self.formation=valid[fields[2] or ""] and fields[2] or "center"
  self.formationRange=RANGES[fields[3] or ""] and fields[3] or "close"
 end
 return execute(self,fields)
end

-- Random spot in a box behind the main: 1.5-5 yards back, up to 4 yards to
-- either side (wider than the Left/Right spots), as sketched by Sam.
B.FORMATION_RANDOM={back1=1.5,back2=5,side=4}
local function randomOffset(far)
 if far then
  -- 8-12 yards away, anywhere from back-left to back-right.
  local z=B.FORMATION_FAR
  local d=z.near+math.random()*(z.far-z.near);local a=(math.random()*2-1)*math.pi/4
  return {-d*math.cos(a),d*math.sin(a)}
 end
 local z=B.FORMATION_RANDOM
 return {-(z.back1+math.random()*(z.back2-z.back1)),(math.random()*2-1)*z.side}
end

-- Fixed spots keep their direction; Far pushes them out to 10 yards.
local function formationOffset(name,far)
 if name=="random" then return randomOffset(far) end
 local o=OFFSETS[name] or {-2,0}
 if not far then return {o[1],o[2]} end
 local len=math.sqrt(o[1]*o[1]+o[2]*o[2]);local k=B.FORMATION_FAR.fixed/len
 return {o[1]*k,o[2]*k}
end

-- Follow the main in formation instead of the game's follow.
local invoke=B.Invoke
function B:Invoke(name,a,b,c)
 local far=self.formationRange=="far"
 if name=="FollowUnit" and self.db.role=="agent" and ((self.formation or "center")~="center" or far)
    and a and a==self:PeerUnit() and self:GetBridgeInfo().nativeMove then
  local formation=self.formation or "center"
  self.formationState={name=formation,far=far,unit=a,offset=formationOffset(formation,far)}
  return true,"Following in "..valid[formation][2].." formation"..(far and " (far)" or "")
 end
 return invoke(self,name,a,b,c)
end

local stopMovement=B.StopMovement
function B:StopMovement(a,b,c)
 self.formationState=nil
 return stopMovement(self,a,b,c)
end

local function native(name,a,b,c)
 local ok,result=pcall(zBoxNative,name,a,b,c)
 return ok and result==1
end

function B:FormationTick(now)
 local st=self.formationState
 if not st or not self.following or now<(st.next or 0) then return end
 st.next=now+.1
 if self:IsCastHeld(now) then return end
 local guid=self:GUID(st.unit)
 local g=guid~="" and self.PetGeometry and self:PetGeometry(guid)
 if not g or g.distance>self.FORMATION_FALLBACK then
  -- Catch up with the game's follow, then take the spot again.
  if not st.native then st.native=invoke(self,"FollowUnit",st.unit) or false;st.goal=nil end
  return
 end
 if st.native then
  if g.distance>self.FORMATION_FALLBACK-10 then return end
  native("StopFollow");st.native=nil
 end
 local moving=st.mainX and (g.x-st.mainX)^2+(g.y-st.mainY)^2>.15^2
 st.mainX,st.mainY=g.x,g.y
 if moving then st.stillSince=nil elseif st.mainMoving or not st.stillSince then st.stillSince=now end
 st.mainMoving=moving
 local cf,sf=math.cos(g.facing),math.sin(g.facing)
 -- Facing 0 points along +x and turns toward +y; the main's right is (sin, -cos).
 local function spot(o) return g.x+o[1]*cf+o[2]*sf,g.y+o[1]*sf-o[2]*cf end
 local tx,ty
 if st.name=="random" then
  -- Random: trail straight behind while the main moves; once it has stopped,
  -- pick one spot in the zone and walk there. No re-picking until it moves again.
  if moving then st.landing=nil
  elseif not st.landing and st.stillSince and now-st.stillSince>=.4 then
   local x,y=spot(randomOffset(st.far));st.landing={x,y}
  end
  if st.landing then tx,ty=st.landing[1],st.landing[2]
  else tx,ty=spot(st.far and {-B.FORMATION_FAR.fixed,0} or {-(B.FORMATION_RANDOM.back1+B.FORMATION_RANDOM.back2)/2,0}) end
 else tx,ty=spot(st.offset) end
 local d2=(tx-g.px)^2+(ty-g.py)^2
 if d2>(moving and .6 or 1)^2 then
  local retry=st.landing and 3 or 1.5
  if not st.goal or (st.goal[1]-tx)^2+(st.goal[2]-ty)^2>.6^2 or now-st.sentAt>retry then
   if native("MoveTo",tx,ty,g.z) then st.goal,st.sentAt,st.faced={tx,ty},now,nil end
  end
 else
  if st.goal then native("StopFollow");st.goal=nil end
  -- Settled while the main stands still: face the same way.
  if not moving and not st.faced and st.stillSince and now-st.stillSince>.3 then
   st.faced=native("SetHeading",math.mod(g.facing+math.pi*2,math.pi*2))
  end
 end
end

local tick=B.Tick
function B:Tick(now,elapsed)
 tick(self,now,elapsed)
 if self.connected and self.db.role=="agent" and self.formationState then self:FormationTick(now) end
end

-- Driver UI: a tab on the panel's right edge that pops out the formations ----

local U=B.UI
if not U then return end
local ICONS="Interface\\AddOns\\zBox\\media\\formation-"

function U:UpdateFormationTab()
 local tab=self.formationTab;if not tab then return end
 local current=B:Formation()
 tab.icon:SetTexture(ICONS..current)
 if self.formationFlyout then
  for _,b in ipairs(self.formationFlyout.buttons) do
   if b.name==current then b.ring:Show() else b.ring:Hide() end
  end
  local range=B:FormationRange()
  for _,b in ipairs(self.formationFlyout.ranges or {}) do
   if b.range==range then b:SetBackdropColor(.12,.4,.38,1);b:SetBackdropBorderColor(.3,1,.75,1)
   else b:SetBackdropColor(.05,.08,.1,1);b:SetBackdropBorderColor(.25,.45,.49,1) end
  end
 end
end

function U:FormationFlyout()
 if self.formationFlyout then return self.formationFlyout end
 local f=CreateFrame("Frame","zBoxFormations",self.frame)
 f:SetFrameStrata("DIALOG");f:SetFrameLevel(self.frame:GetFrameLevel()+20);f:EnableMouse(true)
 f:SetWidth(12+table.getn(FORMATIONS)*44);f:SetHeight(92)
 f:SetPoint("LEFT",self.formationTab,"RIGHT",2,0)
 f:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
 f:SetBackdropColor(.025,.035,.045,.97);f:SetBackdropBorderColor(.25,.45,.49,1)
 f.buttons={}
 for i,info in ipairs(FORMATIONS) do
  local data=info
  local b=CreateFrame("Button",nil,f);b:SetWidth(40);b:SetHeight(40)
  b:SetPoint("TOPLEFT",f,"TOPLEFT",8+(i-1)*44,-6)
  b.name=data[1]
  b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetAllPoints(b);b.icon:SetTexture(ICONS..data[1])
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
  b.ring=b:CreateTexture(nil,"OVERLAY");b.ring:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  b.ring:SetBlendMode("ADD");b.ring:SetAllPoints(b);b.ring:Hide()
  b.text=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");b.text:SetPoint("TOP",b,"BOTTOM",0,-1);b.text:SetText(data[2])
  b:SetScript("OnClick",function() B:SetFormation(data[1]);U:UpdateFormationTab() end)
  b:SetScript("OnEnter",function()
   GameTooltip:SetOwner(b,"ANCHOR_TOP");GameTooltip:SetText(data[2].." formation")
   GameTooltip:AddLine(data[3],.7,.85,.85,true);GameTooltip:Show()
  end)
  b:SetScript("OnLeave",function() GameTooltip:Hide() end)
  f.buttons[i]=b
 end
 -- Range row: Close / Far.
 f.ranges={}
 for i,key in ipairs({"close","far"}) do
  local range=key
  local b=CreateFrame("Button",nil,f);b:SetWidth(70);b:SetHeight(18)
  b:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",8+(i-1)*76,6)
  b:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
  b.text=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");b.text:SetPoint("CENTER",b,"CENTER",0,0);b.text:SetText(RANGES[range])
  b.range=range
  b:SetScript("OnClick",function() B:SetFormationRange(range);U:UpdateFormationTab() end)
  b:SetScript("OnEnter",function()
   GameTooltip:SetOwner(b,"ANCHOR_TOP");GameTooltip:SetText(RANGES[range].." range")
   GameTooltip:AddLine(range=="far" and "Keeps 8-12 yards away, so a hunter can shoot." or "Stays close, within a few yards.",.7,.85,.85,true);GameTooltip:Show()
  end)
  b:SetScript("OnLeave",function() GameTooltip:Hide() end)
  f.ranges[i]=b
 end
 f.rangeLabel=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");f.rangeLabel:SetPoint("LEFT",f.ranges[2],"RIGHT",8,0);f.rangeLabel:SetText("Distance")
 f:Hide();table.insert(UISpecialFrames,"zBoxFormations")
 self.formationFlyout=f
 return f
end

function U:ToggleFormations()
 local f=self:FormationFlyout()
 if f:IsShown() then f:Hide() else self:UpdateFormationTab();f:Show() end
end

local create=U.Create
function U:Create()
 create(self)
 if self.formationTab or not self.frame then return end
 local tab=CreateFrame("Button","zBoxFormationTab",self.frame)
 tab:SetWidth(26);tab:SetHeight(44);tab:SetPoint("TOPLEFT",self.frame,"TOPRIGHT",-1,-30)
 tab:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=10,insets={left=2,right=2,top=2,bottom=2}})
 tab:SetBackdropColor(.025,.035,.045,.95);tab:SetBackdropBorderColor(.25,.45,.49,1)
 tab.icon=tab:CreateTexture(nil,"ARTWORK");tab.icon:SetWidth(22);tab.icon:SetHeight(22);tab.icon:SetPoint("CENTER",tab,"CENTER",0,0)
 tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
 tab:SetScript("OnClick",function() U:ToggleFormations() end)
 tab:SetScript("OnEnter",function()
  GameTooltip:SetOwner(tab,"ANCHOR_RIGHT");GameTooltip:SetText("Formation: "..valid[B:Formation()][2]..(B:FormationRange()=="far" and " (far)" or ""))
  GameTooltip:AddLine("Click to choose where your followers stand while following.",.7,.85,.85,true);GameTooltip:Show()
 end)
 tab:SetScript("OnLeave",function() GameTooltip:Hide() end)
 self.formationTab=tab
 self:UpdateFormationTab()
end
