-- Pause known addon automation at its own entry points. The protected game API
-- functions and saved addon preferences remain untouched on both clients.
local B = zBox
local globals = _G or getfenv(0)
local guardedEvents = { GOSSIP_SHOW = true, QUEST_GREETING = true, QUEST_DETAIL = true,
  QUEST_PROGRESS = true, QUEST_COMPLETE = true }
local entries = { LazyPig_OnEvent = "event", LazyPig_OnUpdate = "update",
  LazyPig_ReplyQuest = "skip", LazyPig_RecordQuest = "skip", LazyPig_FixQuest = "skip" }
local installed = {}

function B:IsLinkedAgent()
  return self.connected and self.db and self.db.enabled and self.db.role == "agent" and not self.worldSuspended
end

local function guard(original, kind)
  return function(a, b, c, d)
    if B:IsLinkedAgent() then
      if kind == "skip" or (kind == "event" and guardedEvents[a]) then return end
      -- LazyPig's update loop accepts a visible quest while Alt is held. Leave
      -- that update idle until Alt/detail closes, without spoofing input state
      -- or changing the QuestHaste addon global it uses as an opt-out.
      if kind == "update" and not QuestHaste and IsAltKeyDown and IsAltKeyDown() and
         QuestFrameDetailPanel and QuestFrameDetailPanel:IsVisible() then return end
    end
    return original(a, b, c, d)
  end
end

function B:InstallNPCGuards()
  if not self:IsLinkedAgent() then self:RestoreNPCGuards(); return end
  for name, kind in pairs(entries) do
    local current, previous = globals[name], installed[name]
    if type(current) == "function" and (not previous or current ~= previous.wrapper) then
      local wrapper = guard(current, kind)
      installed[name] = { wrapper = wrapper, original = current }
      globals[name] = wrapper
    end
  end
end

function B:RestoreNPCGuards()
  for name, entry in pairs(installed) do
    if globals[name] == entry.wrapper then globals[name] = entry.original end
    installed[name] = nil
  end
end

function B:NPCGuardTick(now)
  if now - (self.lastNPCGuardAt or -10) < 1 then return end
  self.lastNPCGuardAt = now
  self:InstallNPCGuards()
end

function B:NPCGuardStatus()
  if not self:IsLinkedAgent() then return "normal" end
  if next(installed) then return "_LazyPig dialogue paused while linked" end
  return "no supported auto-NPC addon detected"
end
