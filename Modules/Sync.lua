local _, ns = ...
local UTRM = UnityToolsRaidManagement
local L = UTRM.L
local Rules = ns.SyncRules
local Codec = ns.PlanCodec

-- Keeps the raid plan and the active encounter the same for the raid leader and the assistants (issue #17).
-- Only promoted players take part: a client sends, requests and accepts only while it is lead or assist itself,
-- and only from senders who are lead or assist when the message arrives. Which copy wins: Modules/SyncRules.lua.
--
--   state    (raid)     which plan this client has and its active encounter; sent after joining or being
--                        promoted, after an import, after choosing an encounter, and in answer to an older state
--   request  (whisper)  "send me your plan" to the sender of a newer state
--   plan     (whisper)  the plan, answering a request
--   force    (raid)     Force sync: the sender's plan for everybody; each recipient confirms before it replaces theirs
local Sync = UTRM:NewModule("Sync", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0")

local Serializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

local PREFIX = "UTRM"
local STATE_DELAY = 2          -- seconds: several triggers in a row send one state
local REQUEST_COOLDOWN = 60    -- seconds before the same plan is requested again
local SEND_COOLDOWN = 30       -- seconds before the same requester gets the plan again
local GREET_COOLDOWN = 30      -- seconds before a member who joined or was promoted is whispered our state again

local wasPromoted = false
local knownPromoted = {}       -- raid member -> promoted, as of the last roster update
local greeted = {}             -- raid member -> GetTime() of the last state whispered to them
local requested = {}           -- plan id .. chosen time -> GetTime() of the request
local sentTo = {}              -- requester -> GetTime() of the last plan sent
local declined = {}            -- plan id .. chosen time -> true: force syncs this client declined (this session)
local pendingForce             -- the force sync waiting for the popup's answer
local versionWarned = false

local function isPromoted(unit)
    return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)
end

-- Whether this client takes part right now
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

function Sync:Transmit(msg, target, priority)
    msg.v = Rules.VERSION
    local text = Serializer:Serialize(msg)
    if target then
        self:SendCommMessage(PREFIX, text, "WHISPER", target, priority or "NORMAL")
    else
        self:SendCommMessage(PREFIX, text, "RAID", nil, priority or "NORMAL")
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

function Sync:SendState()
    self.stateTimer = nil
    if not self:CanSync() then return end
    self:Transmit(stateMessage())
end

-- Several triggers in a row (roster updates, an import right after joining) send one state
function Sync:QueueState()
    if self.stateTimer or not self:CanSync() then return end
    self.stateTimer = self:ScheduleTimer("SendState", STATE_DELAY)
end

function Sync:OnState(sender, msg)
    local theirs = Rules.MetaOfState(msg, sender)
    local plan = currentPlan()
    local mine = Rules.Meta(plan, myName())

    if Rules.PlanWins(theirs, mine) then
        local key = versionKey(theirs)
        if declined[key] or pendingForce then return end
        local last = requested[key]
        if last and GetTime() - last < REQUEST_COOLDOWN then return end
        requested[key] = GetTime()
        self:Transmit({ t = "request", id = theirs.id }, sender)
    elseif Rules.PlanWins(mine, theirs) then
        -- Ours is the one to keep: tell everybody, so the sender asks for it
        self:QueueState()
    elseif Rules.ActiveWins(theirs, mine) then
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
    if prefix ~= PREFIX or not sender or Ambiguate(sender, "none") == myName() then return end
    if not self:CanSync() or not isPromoted(Ambiguate(sender, "none")) then return end

    local ok, raw = Serializer:Deserialize(text)
    if not ok then return end
    local msg, why = Rules.Validate(raw)
    if not msg then
        if why == "version" and not versionWarned then
            versionWarned = true
            UTRM:Print(format(L["%s uses another version of the raid plan sync: update Unity Tools - Raid Management."],
                Ambiguate(sender, "none")))
        end
        return
    end

    local handler = ({ state = "OnState", request = "OnRequest", plan = "OnPlan", force = "OnForce" })[msg.t]
    local handled, err = pcall(self[handler], self, sender, msg)
    if not handled then geterrorhandler()(err) end
end

-- Joining a raid or being promoted: say which plan we have, so the others can answer
function Sync:CheckPromotion()
    local promoted = self:CanSync()
    if promoted and not wasPromoted then
        self:QueueState()
    end
    wasPromoted = promoted
end

-- Somebody joined the raid or was promoted: whisper our state to them, so they learn about our plan at once.
-- Only promoted members take part, so a member who joins without assist gets it when they are promoted.
function Sync:CheckRoster()
    local syncingBefore = wasPromoted
    self:CheckPromotion()

    local now = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name then now[name] = rank > 0 end
        end
    end
    -- When we have just started syncing ourselves, CheckPromotion already told the whole raid
    if syncingBefore and self:CanSync() and currentPlan() then
        for name, promoted in pairs(now) do
            local last = greeted[name]
            if promoted and not knownPromoted[name] and Ambiguate(name, "none") ~= myName()
                and not (last and GetTime() - last < GREET_COOLDOWN) then
                greeted[name] = GetTime()
                self:Transmit(stateMessage(), name)
            end
        end
    end
    knownPromoted = now
end

function Sync:OnEnable()
    self:RegisterComm(PREFIX, "OnComm")
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        self:RegisterEvent(event, "CheckRoster")
    end
    -- A plan imported here or an encounter chosen here: tell the others
    self:RegisterMessage("UTRM_PLAN_IMPORTED", function(_, _, source)
        if source ~= "sync" then self:QueueState() end
    end)
    self:RegisterMessage("UTRM_ENCOUNTER_ACTIVATED", "QueueState")
end
