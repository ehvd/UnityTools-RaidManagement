local _, ns = ...

-- Tells whether a pasted string is one Gargul's TMB importer takes (issue #45), without importing it. Follows
-- TMB:import in Gargul's Classes/TMB.lua (checked against Gargul 8.0.2): it trims the text and picks the format by
-- its first line — Gargul's item CSV ("6948,player1,player2"), DFT (starts with "), RRobin (a JSON object with
-- `reserves`), TMB's JSON ({"wishlists":...}), else base64(zlib(...)) of any of these, which is what /loot-policy
-- gives. Where Gargul would accept a string that imports nothing, this refuses it.
-- Pure Lua apart from LibDeflate, which the caller passes in, and PlanCodec (loaded first), so tests/gargul-string
-- can run it outside the game.
local GargulString = {}
ns.GargulString = GargulString

local Codec = ns.PlanCodec

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Splits on a plain separator, keeping empty parts
local function split(text, separator)
    local parts, start = {}, 1
    while true do
        local i = text:find(separator, start, true)
        if not i then
            parts[#parts + 1] = text:sub(start)
            return parts
        end
        parts[#parts + 1] = text:sub(start, i - 1)
        start = i + #separator
    end
end

local function isPositive(value)
    return value ~= nil and value > 0
end

-- TMB:CSVFormatToTMB: lines "itemID,player,player|player,player[2]" and "Group:player,player". At least one item
-- line with a player is needed.
local function checkCSV(text)
    for line in text:gmatch("[^\n]+") do
        if not line:match("^(.+):") then
            local parts = split(line, ",")
            local itemID = tonumber(parts[1])
            if parts[2] and isPositive(itemID and math.floor(itemID)) then
                for i = 2, #parts do
                    if trim(parts[i]) ~= "" then return true end
                end
            end
        end
    end
    return false
end

-- TMB:DFTFormatToTMB: entries split by ";", each an "itemID^..." line and then "|cffxxxxxxplayer|r: |priority" lines
-- until a "Free Roll" one. At least one item with a player and a priority is needed.
local function checkDFT(text)
    text = text:gsub('"', "")
    for _, entry in ipairs(split(text, ";")) do
        local itemID
        local first = true
        for line in entry:gmatch("[^\n]+") do
            if first then
                itemID = tonumber(split(line, "^")[1])
                if not isPositive(itemID) then break end
                first = false
            else
                if line:find("Free Roll", 1, true) then break end
                line = trim(line):sub(12):gsub("|r: :", ""):gsub("|r: ", "")
                local parts = split(line, "|")
                if parts[2] and parts[1] ~= "" and tonumber(parts[2]) then return true end
            end
        end
    end
    return false
end

local function hasEntries(value)
    return type(value) == "table" and next(value) ~= nil
end

-- TMB's JSON: something to import — wishlists, loot priorities, item notes or tiers
local function checkTMB(data)
    return type(data) == "table" and (hasEntries(data.wishlists)
        or (type(data.loot) == "string" and data.loot ~= "")
        or hasEntries(data.notes) or hasEntries(data.tiers))
end

-- Text -> the format ("csv", "dft", "rrobin", "tmb", each but rrobin with ".compressed" when it came base64(zlib)) and
-- the trimmed text to store, or nil and why not: "empty", "csv", "dft", "rrobin", "base64", "zlib", "json", "nothing"
local function check(text, LibDeflate, decompressed)
    text = trim(text)
    local firstLine = text:match("[^\n]+")
    if not firstLine or trim(firstLine) == "" then
        return nil, "empty"
    end
    local suffix = decompressed and ".compressed" or ""
    if firstLine:match("^[0-9]+,") then
        if checkCSV(text) then return "csv" .. suffix end
        return nil, "csv"
    elseif firstLine:sub(1, 1) == '"' then
        if checkDFT(text) then return "dft" .. suffix end
        return nil, "dft"
    elseif firstLine == "{" then
        local data = Codec.JSONDecode(text)
        if type(data) == "table" and data.reserves then
            if hasEntries(data.reserves) then return "rrobin" .. suffix end
            return nil, "rrobin"
        end
    end

    if not decompressed and text:sub(1, #'{"wishlists":') ~= '{"wishlists":' then
        local compressed = Codec.Base64Decode(text)
        if not compressed or compressed == "" then return nil, "base64" end
        local ok, inflated = pcall(LibDeflate.DecompressZlib, LibDeflate, compressed)
        if not ok or type(inflated) ~= "string" then return nil, "zlib" end
        return check(inflated, LibDeflate, true)
    end

    local data = Codec.JSONDecode(text)
    if type(data) ~= "table" then return nil, "json" end
    if not checkTMB(data) then return nil, "nothing" end
    return "tmb" .. suffix
end

function GargulString.Check(text, LibDeflate)
    if type(text) ~= "string" then return nil, "empty" end
    local format, problem = check(text, LibDeflate, false)
    if not format then return nil, problem end
    return format, trim(text)
end
