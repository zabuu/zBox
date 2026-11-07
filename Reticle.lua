-- Ground reticle for the Move picker: a ring drawn in perspective on the exact
-- ground point a click would send the follower to. Gold over a friendly NPC
-- or game object (walk up and use), green on open ground; hidden when nothing
-- would be hit. A short label says what a click will do.
local B,U=zBox,zBox.UI
if not U then return end
local DOTS,RADIUS=16,1.2 -- ring size in yards

local function finite(v) return type(v)=="number" and v==v and v>-math.huge and v<math.huge end

function U:CreateReticle(parent)
 local r=CreateFrame("Frame","zBoxMoveReticle",parent)
 r:SetAllPoints(UIParent);r:SetFrameStrata("FULLSCREEN_DIALOG");r:EnableMouse(false)
 r.dots={}
 for i=1,DOTS+1 do
  local t=r:CreateTexture(nil,"OVERLAY");t:SetTexture("Interface\\Buttons\\WHITE8X8")
  local size=i>DOTS and 5 or 3;t:SetWidth(size);t:SetHeight(size);t:Hide()
  r.dots[i]=t
 end
 r.label=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");r.label:Hide()
 self.reticle=r
 return r
end

-- Screen position (UIParent units, from the bottom left) of a world point.
local function project(x,y,z)
 local ok,sx,sy,depth=pcall(zAPI,"worldToScreen",x,y,z)
 if not ok or not finite(sx) or not finite(sy) or (finite(depth) and depth<=0) then return end
 if sx<-.1 or sx>1.1 or sy<-.1 or sy>1.1 then return end
 return sx*UIParent:GetWidth(),sy*UIParent:GetHeight()
end

-- What a raw object lookup says, for the label: helps tell "the game reports
-- no object here" from "an object was found but did not match the click".
local function rawObject()
 if type(zBoxNative)~="function" or not B:GetBridgeInfo().objects then return end
 local ok,result,guid=pcall(zBoxNative,"MouseoverObject")
 return ok and result==1 and guid or nil
end

function U:UpdateReticle(force)
 local r=self.reticle;if not r then return end
 local function hide() for _,t in ipairs(r.dots) do t:Hide() end;r.label:Hide();r.target=nil;r.key=nil end
 if type(zAPI)~="function" then return hide() end
 -- Recompute only when the cursor or the camera moved.
 local cx,cy=GetCursorPosition()
 local cok,camX,camY,camZ,fx,fy,fz=pcall(zAPI,"camera")
 local key=string.format("%.1f:%.1f:%s:%s:%s:%s:%s:%s",cx or 0,cy or 0,tostring(camX),tostring(camY),tostring(camZ),tostring(fx),tostring(fy),tostring(fz))
 if not force and key==r.key and r.at and GetTime()-r.at<.25 then return end
 r.key,r.at=key,GetTime()
 local x,y,z,color,text
 local npc=B.PickUseTarget and B:PickUseTarget()
 if npc then x,y,z=B:Position("mouseover") end
 if x then color,text={1,.82,.2},"Talk" else
  x,y,z=B:PickTerrain()
  local object,ox,oy,oz=B.PickUseObject and B:PickUseObject(x,y,z)
  if object then x,y,z,text=ox,oy,oz,"Use" end
  if not x then return hide() end
  npc=object or (B.PickUseTarget and B:PickUseTarget(x,y,z))
  if npc and not object then text="Talk" end
  if not npc and rawObject() then text="Object found, but not where you're pointing" end
  color=npc and {1,.82,.2} or {.3,1,.55}
 end
 r.target={x=x,y=y,z=z,npc=npc}
 local cxp,cyp
 for i=1,DOTS+1 do
  local t=r.dots[i];local px,py
  if i>DOTS then px,py=project(x,y,z);cxp,cyp=px,py else
   local a=(i-1)/DOTS*2*math.pi;px,py=project(x+math.cos(a)*RADIUS,y+math.sin(a)*RADIUS,z+.05)
  end
  if px then
   t:ClearAllPoints();t:SetPoint("CENTER",UIParent,"BOTTOMLEFT",px,py)
   t:SetVertexColor(color[1],color[2],color[3],i>DOTS and 1 or .9);t:Show()
  else t:Hide() end
 end
 if text and cxp then
  r.label:ClearAllPoints();r.label:SetPoint("BOTTOM",UIParent,"BOTTOMLEFT",cxp,cyp+14)
  r.label:SetText(text);r.label:SetTextColor(color[1],color[2],color[3]);r.label:Show()
 else r.label:Hide() end
end

local create=U.CreateMoveOverlay
function U:CreateMoveOverlay()
 create(self)
 local f=self.moveOverlay
 self:CreateReticle(f)
 local update=f:GetScript("OnUpdate")
 f:SetScript("OnUpdate",function()
  if update then update() end
  U:UpdateReticle()
 end)
 local show=f:GetScript("OnShow")
 f:SetScript("OnShow",function() if show then show() end;U:UpdateReticle(true) end)
end
