local B = zBox

-- Only the live, explicitly paired agent receives a background activity lease.
-- No movement, key presses or chat messages are generated to simulate input.
function B:ActivityTick(now)
  if not self.connected or self.db.role ~= "agent" or self.db.keepAwake == false or
     self.worldSuspended or not self.lastReceive or now-self.lastReceive > 4 then return end
  if self.nextActivity and now < self.nextActivity then return end
  self.nextActivity = now+30
  if self:GetBridgeInfo().activity then
    local ok, result = pcall(zBoxNative,"RefreshActivity")
    self.activityStatus = ok and result==1 and "linked background activity" or "activity refresh failed"
  else self.activityStatus = "background activity needs bridge 0.1.9" end
  -- Clear an already-set flag once, only when the client positively reports it.
  -- Never toggle AFK speculatively (which would mark an active character away).
  if type(UnitIsAFK)=="function" and type(SendChatMessage)=="function" then
    local ok, away = pcall(UnitIsAFK,"player")
    if ok and (away==true or away==1) then pcall(SendChatMessage,"","AFK") end
  end
end
