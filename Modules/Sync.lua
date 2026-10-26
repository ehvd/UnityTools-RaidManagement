local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L
local Rules = ns.SyncRules
local Codec = ns.PlanCodec

-- Keeps the raid plan and the active encounter the same across the raid (issue #17). Which copy wins:
-- Modules/SyncRules.lua.
--
-- Trust: only the raid leader and assistants are sources. Plans, force syncs and active encounters are accepted only
-- from senders who are lead or assist when the message arrives, and only they answer requests and force sync. Every
-- raid member with the addon receives: members say which plan they have when they join or reload, so a promoted
-- client can answer, and they may request a plan. A member's own plan is never taken by anybody.
--
--   state    (raid or whisper)  which plan this client has and its active encounter; sent when joining the raid,
--                               when promoted, after an import and after choosing an encounter (lead and assists),
--                               to a member who just joined, and in answer to somebody with an older plan
--   request  (whisper)          "send me your plan" to the lead or assist who sent a newer state
--   plan     (whisper)          the plan, answering a request
--   force    (raid)             Force sync: the sender's plan for everybody; each recipient confirms first
local Sync = UTRM:NewModule("Sync", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0")

local Serializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

local PREFIX = "UTRM"
local STATE_DELAY = 2          -- seconds: several triggers in a row (joining, roster updates) send one state
local REQUEST_COOLDOWN = 60    -- seconds before the same plan is requested again
local SEND_COOLDOWN = 30       -- seconds before the same requester gets the plan again
local ANSWER_COOLDOWN = 10     -- seconds before the same player is whispered our state again
local IN_FLIGHT_TIMEOUT = 5    -- seconds after which a state that never reported leaving no longer blocks the next

local wasInRaid, wasPromoted = false, false
local members = {}             -- raid member names as of the last roster update
local answered = {}            -- player -> GetTime() of the last state whispered to them
local requested = {}           -- plan id .. chosen time -> GetTime() of the request
local sentTo = {}              -- requester -> GetTime() of the last plan sent
local declined = {}            -- plan id .. chosen time -> true: force syncs this client declined (this session)
local pendingForce             -- the force sync waiting for the popup's answer
local versionWarned = false

local function isPromoted(unit)
    return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)
end

-- Whether this client is a source: lead or assist in a raid (answers requests, Force sync)
function Sync:CanSync()
    return IsInRaid() and isPromoted("player")
end

local function myName()
    return UnitName("player")
end

local function currentPlan()
    return UTRM:GetModule("PlanImport"):GetPlan()
end

local function versionKey(meta)
    return meta.id .. "#" .. tostring(meta.c)
end

local function report(message, failed)
    if UTRM.PlanWindow then
        UTRM.PlanWindow:Refresh(failed and ("|cffff4040" .. message .. "|r") or message)
    end
end

------------------------------------------------------------------------------------------------- wire ---

-- `onSent` (optional) is called once the whole message has left (AceComm reports every chunk)
function Sync:Transmit(msg, target, priority, onSent)
    msg.v = Rules.VERSION
    local text = Serializer:Serialize(msg)
    local callback = onSent and function(_, sent, total)
        if sent >= total then onSent() end
    end
    if target then
        self:SendCommMessage(PREFIX, text, "WHISPER", target, priority or "NORMAL", callback)
    else
        self:SendCommMessage(PREFIX, text, "RAID", nil, priority or "NORMAL", callback)
    end
end

-- A plan table as compact text for the addon channel, and back
local function encodePlan(plan)
    return LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(Serializer:Serialize(plan)))
end

local function decodePlan(text)
    local compressed = LibDeflate:DecodeForWoWAddonChannel(text)
    local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil end
    local ok, plan = Serializer:Deserialize(serialized)
    if not ok or type(plan) ~= "table" or not Codec.IsSupported(plan.protocol) or Codec.Check(plan) then
        return nil
    end
    return plan
end

------------------------------------------------------------------------------------------------ state ---

local function stateMessage()
    local plan = currentPlan()
    local meta = Rules.Meta(plan, myName())
    return meta and {
        t = "state", id = meta.id, c = meta.c, g = meta.g, a = meta.a, at = meta.at, n = plan.event.title,
    } or { t = "state" }
end

-- Sends the state to the raid at ALERT priority (ahead of other addons' queued traffic). Only one is on its way at a
-- time: asking again meanwhile sends the latest state once the previous one has left, so a quick series of choices
-- never queues stale states.
function Sync:SendState()
    if self.stateTimer then
        self:CancelTimer(self.stateTimer)
        self.stateTimer = nil
    end
    if not IsInRaid() then return end
    if self.stateSentAt and GetTime() - self.stateSentAt < IN_FLIGHT_TIMEOUT then
        self.stateDirty = true
        return
    end
    self.stateSentAt, self.stateDirty = GetTime(), false
    self:Transmit(stateMessage(), nil, "ALERT", function()
        self.stateSentAt = nil
        if self.stateDirty then
            self:SendState()
        end
    end)
end

-- Several triggers in a row (joining, roster updates, an import right after joining) send one state
function Sync:QueueState()
    if self.stateTimer or not IsInRaid() then return end
    self.stateTimer = self:ScheduleTimer("SendState", STATE_DELAY)
end

-- Whispers our state to one player (a newcomer, or somebody whose plan is older), not too often
function Sync:AnswerState(target)
    local last = answered[target]
    if last and GetTime() - last < ANSWER_COOLDOWN then return end
    answered[target] = GetTime()
    self:Transmit(stateMessage(), target, "ALERT")
end

function Sync:OnState(sender, msg, trusted)
    local theirs = Rules.MetaOfState(msg, sender)
    local plan = currentPlan()
    local mine = Rules.Meta(plan, myName())

    if Rules.PlanWins(theirs, mine) then
        -- A newer plan, but only lead and assists are sources
        if not trusted then return end
        local key = versionKey(theirs)
        if declined[key] or pendingForce then return end
        local last = requested[key]
        if last and GetTime() - last < REQUEST_COOLDOWN then return end
        requested[key] = GetTime()
        self:Transmit({ t = "request", id = theirs.id }, sender)
    elseif Rules.PlanWins(mine, theirs) then
        -- Ours is the one to keep: tell the sender, so they ask for it (if we are a source)
        if self:CanSync() then self:AnswerState(sender) end
    elseif trusted and Rules.ActiveWins(theirs, mine) then
        for _, encounter in ipairs(plan.encounters) do
            if encounter.key == theirs.a then
                plan.active, plan.activeAt = theirs.a, theirs.at
                report(format(L["%s chose %s"], Ambiguate(sender, "none"), encounter.label))
                self:SendMessage("UTRM_ENCOUNTER_SYNCED", encounter)
                break
            end
        end
    end
end

function Sync:OnRequest(sender, msg)
    local plan = currentPlan()
    if not plan or Rules.Identity(plan) ~= msg.id then return end
    local last = sentTo[sender]
    if last and GetTime() - last < SEND_COOLDOWN then return end
    sentTo[sender] = GetTime()
    self:Transmit({ t = "plan", p = encodePlan(plan) }, sender, "BULK")
end

-- Stores a plan that came from `sender`; it keeps the sender's chosen time and active encounter
function Sync:Store(plan, sender)
    plan.syncedFrom = Ambiguate(sender, "none")
    UTRM:GetModule("PlanImport"):StoreSynced(plan)
    report(format(L["Raid plan %s synced from %s."], plan.event.title, plan.syncedFrom))
end

function Sync:OnPlan(sender, msg)
    local plan = decodePlan(msg.p)
    if not plan then return end
    local theirs = Rules.Meta(plan, sender)
    if declined[versionKey(theirs)] then return end
    if Rules.PlanWins(theirs, Rules.Meta(currentPlan(), myName())) then
        self:Store(plan, sender)
    end
end

------------------------------------------------------------------------------------------------ force ---

-- Force sync: sends this client's plan and active encounter to the raid, chosen now, so it beats every other copy
-- (after the recipients confirm). Returns true or false and a message for the status line.
function Sync:ForceSync()
    if not self:CanSync() then
        return false, L["Only the raid leader or an assistant can sync, in a raid."]
    end
    local plan = currentPlan()
    if not plan then
        return false, L["No raid plan imported yet."]
    end
    plan.chosenAt = GetServerTime()
    self:Transmit({ t = "force", p = encodePlan(plan) }, nil, "BULK")
    return true, L["Force sync sent: the others are asked to accept your raid plan."]
end

StaticPopupDialogs["UNITYTOOLSRAIDMANAGEMENT_FORCE_SYNC"] = {
    text = L["%s wants to replace your raid plan with \"%s\" (Force sync). Accept?"],
    button1 = ACCEPT,
    button2 = DECLINE,
    OnAccept = function() Sync:AnswerForce(true) end,
    OnCancel = function() Sync:AnswerForce(false) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Sync:OnForce(sender, msg)
    local plan = decodePlan(msg.p)
    if not plan then return end
    pendingForce = { plan = plan, sender = sender, key = versionKey(Rules.Meta(plan, sender)) }
    StaticPopup_Show("UNITYTOOLSRAIDMANAGEMENT_FORCE_SYNC", Ambiguate(sender, "none"), plan.event.title)
end

function Sync:AnswerForce(accepted)
    local force = pendingForce
    pendingForce = nil
    if not force then return end
    if accepted then
        self:Store(force.plan, force.sender)
    else
        declined[force.key] = true
        report(format(L["Force sync from %s declined: your raid plan is kept."], Ambiguate(force.sender, "none")))
    end
end

---------------------------------------------------------------------------------------------- receive ---

function Sync:OnComm(prefix, text, _, sender)
    if prefix ~= PREFIX or not sender or not IsInRaid() then return end
    local name = Ambiguate(sender, "none")
    if name == myName() or not UnitInRaid(name) then return end

    local ok, raw = Serializer:Deserialize(text)
    if not ok then return end
    local msg, why = Rules.Validate(raw)
    if not msg then
        if why == "version" and not versionWarned then
            versionWarned = true
            UTRM:Print(format(L["%s uses another version of the raid plan sync: update Unity Tools - Raid Management."], name))
        end
        return
    end

    local trusted = isPromoted(name)
    local handled, err = true, nil
    if msg.t == "state" then
        handled, err = pcall(self.OnState, self, sender, msg, trusted)
    elseif msg.t == "request" then
        if self:CanSync() then handled, err = pcall(self.OnRequest, self, sender, msg) end
    elseif trusted then   -- plan, force: only from lead and assists
        handled, err = pcall(msg.t == "plan" and self.OnPlan or self.OnForce, self, sender, msg)
    end
    if not handled then geterrorhandler()(err) end
end

-- Joining the raid (or a reload in it) or being promoted: tell the raid which plan we have, so the others answer.
-- A member who joined: whisper our state to them (when we are a source with a plan), so they get it at once.
function Sync:CheckRoster()
    local inRaid, promoted = IsInRaid(), self:CanSync()
    if inRaid and (not wasInRaid or (promoted and not wasPromoted)) then
        self:QueueState()
    end

    local now = {}
    if inRaid then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            if name then now[name] = true end
        end
    end
    if wasInRaid and promoted and currentPlan() then
        for name in pairs(now) do
            if not members[name] and Ambiguate(name, "none") ~= myName() then
                self:AnswerState(name)
            end
        end
    end
    members, wasInRaid, wasPromoted = now, inRaid, promoted
end

function Sync:OnEnable()
    self:RegisterComm(PREFIX, "OnComm")
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        self:RegisterEvent(event, "CheckRoster")
    end
    -- A plan imported here (by a source): tell the raid
    self:RegisterMessage("UTRM_PLAN_IMPORTED", function(_, _, source)
        if source ~= "sync" and self:CanSync() then self:QueueState() end
    end)
    -- An encounter chosen here (by a source): tell the raid at once, so their windows follow the note
    self:RegisterMessage("UTRM_ENCOUNTER_ACTIVATED", function()
        if self:CanSync() then self:SendState() end
    end)
end
