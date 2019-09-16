-- Major, Minor, Patch
local VFM_VERSION = {0, 5, 4};
local VFM_DEBUG = false;
local DEFAULT_UPDATE_FREQUENCY = 60
local last_sent_progress = {}

-- Set to true if addon prefixes were successfully registered
local canCommunicate = false

local CHAT_COLOR = {
    ["white"]  = "ffffff",
    ["black"]  = "000000",
    ["red"]    = "dd3e3e",
    ["green"]  = "13a347",
    ["blue"]   = "2977d3",
    ["lblue"]  = "1d82b2",
    ["yellow"] = "ffce00",
    ["debug"]  = "ff6f00",
}

local MAX_XP = {
    400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800,
    10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200, 25200,
    27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800,
    54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800,
    101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
    153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800, 494000
};

-- Time related
local SECONDS_PER_DAY   = 3600 * 24
local SECONDS_PER_MONTH = SECONDS_PER_DAY * 365 / 12
local SECONDS_PER_YEAR  = SECONDS_PER_MONTH * 12
local TIME_COMPONENT_NAMES = {
    "year", "month", "day", "hour", "minute", "second"
}

local function getDateSeconds()
    local s = tonumber(date("%Y")) * SECONDS_PER_YEAR
    s = s + tonumber(date("%m")) * SECONDS_PER_MONTH
    s = s + tonumber(date("%d")) * SECONDS_PER_DAY

    return s
end

local function getCurrentDateSeconds()
    local s = tonumber(date("%H")) * 3600
    s = s + tonumber(date("%M")) * 60
    s = s + tonumber(date("%S"))

    return s
end

local function now()
    return getDateSeconds() + getCurrentDateSeconds()
end

local function extractTimeComponents(sec)
    local years = math.floor(sec / SECONDS_PER_YEAR)
    sec = sec - years * SECONDS_PER_YEAR

    local months = math.floor(sec / SECONDS_PER_MONTH)
    sec = sec - months * SECONDS_PER_MONTH

    local days = math.floor(sec / SECONDS_PER_DAY)
    sec = sec - days * SECONDS_PER_DAY

    local hours = math.floor(sec / 3600)
    sec = sec - hours * 3600

    local minutes = math.floor(sec / 60)
    local seconds = sec - minutes * 60

    return { years, months, days, hours, minutes, seconds }
end

local version_check_timeout = 0;
local last_full_update   = 0;
local updateTimerActive  = false;

local frame, LoginFrame = CreateFrame("Frame"), CreateFrame("frame")
frame:SetScript("OnEvent", function(self, event, ...) VFMeventHandler(event, ...) end);
frame:RegisterEvent("CHAT_MSG_ADDON");

local function createTimeString(sec)
    local timeParts = extractTimeComponents(sec)

    return ("%02i:%02i:%02i"):format(timeParts[4], timeParts[5], timeParts[6])
end

local function createReadableTimeString(sec)
    local timeParts = extractTimeComponents(sec)
    local str = ""

    for i, val in ipairs(timeParts) do
        if val > 0 then
            if #str > 0 then
                if i == #timeParts then
                    str = str .. " and "
                else
                    str = str .. ", "
                end
            end

            str = str .. val .. " " .. TIME_COMPONENT_NAMES[i] .. (val > 1 and "s" or "")
            i = i + 1
        end
    end

    return str
end

-- getGrayColor and getConColor are based on informatiom from
-- https://wowwiki.fandom.com/wiki/Formulas:Mob_XP

local function getGrayLevel(targetLevel)
    local ownLevel = UnitLevel("player")

    if ownLevel <= 5 then
        return  0
    elseif ownLevel <= 49 then
        return ownLevel - math.floor(ownLevel / 10) - 5
    elseif ownLevel <= 50 then
        return 40
    elseif ownLevel <= 59 then
        return ownLevel - math.floor(ownLevel / 5) - 1
    end

    -- Level 60
    return 51
end

local function getConColor(targetLevel)
    if targetLevel == 0 or targetLevel == nil then
        return
    end

    local lDiff = targetLevel - UnitLevel("player")

    if lDiff >= 5 then
        return "ff0000" -- Red
    elseif lDiff >= 3 then
        return "ff8000" -- Orange
    elseif lDiff >= -2 then
        return "ffff00" -- Yellow
    elseif lDiff <= -3 and targetLevel > getGrayLevel(targetLevel) then
        return "1eff00" -- Gray
    end

    return "9d9d9d"
end

local function normalizeName(str)
    str = str:lower();
    if str:find("-") ~= nil then
        return str:sub(0, str:find('-') - 1);
    end

    return str;
end

local function createPlayerNameString(name, level, class)
    if name:len() == 0 then
        return "[Unknown]"
    end

    name = normalizeName(name)
    local out = "\124Hplayer:" .. name .. "\124h\124cffffffff["
    
    if level ~= nil and level ~= 0 then
        local conColor = getConColor(level)
        out = out .. "\124cff".. conColor .. level .. "\124cffffffff:"
    end
    
    if class ~= nil then
        out = out .. "\124c" .. select(4, GetClassColor(class))
    end

    return  out .. name:sub(1, 1):upper() .. name:sub(2) .. "\124cffffffff]\124h"
end

local function numberToDigitGroupedString(n)
    if n < 999 then
        return tostring(n)
    end

    local xpStr = ""
    local length = #tostring(n)
    local i = 1

    while i <= length do
        local a = math.floor(n / (10^(length - i)))

        xpStr = xpStr .. tostring(a)

        if (length - i) % 3 == 0 and i ~= length and i ~= 0 then
            xpStr = xpStr .. ","
        end

        n = n - a * (10^(length - i))
        i = i + 1
    end

    return xpStr
end

local function createVersionNumber(tbl)
    return tbl[1] * 1e4 + tbl[2] * 1e2 + tbl[3]
end

local function getCurrentVersion()
    return createVersionNumber(VFM_VERSION)
end

local function vfmPrint(msg, color)
    print("\124cffffde00VFM" .. (color == "debug" and " (debug)" or "") .. ": \124cffffffff" .. (CHAT_COLOR[color] ~= nil and "\124cff" .. CHAT_COLOR[color] or "") .. msg);
end

local function indexOf(tbl, needle)
    for i, v in ipairs(tbl) do
        if v == needle then
            return i;
        end
    end

    return 0;
end

local function saveIsSameVersion()
    return vfmdb["version"][1] == VFM_VERSION[1] and
           vfmdb["version"][2] == VFM_VERSION[2] and
           vfmdb["version"][3] == VFM_VERSION[3];
end

local function setupdb(reset)
    if vfmdb == nil or reset == true then
        vfmdb = {}
    elseif vfmdb["whitelist"] ~= nil then
        -- Perform version-to-version updates

        if vfmdb["version"][2] <= 3 then
            for k, v in pairs(vfmdb["whitelist"]) do
                if type(k) == "string" then
                    local a,b,c,d = unpack(v)
                    vfmdb["whitelist"][k] = {
                        ["level"] = a,
                        ["currentXP"] = b,
                        ["lastUpdate"] = c,
                        ["restedXP"] = 0,
                        ["hasAccepted"] = d,
                        ["class"] = nil
                    }
                end
            end
        end

        if vfmdb["version"][2] <= 4 then
            for k, v in pairs(vfmdb["whitelist"]) do
                if type(k) == "string" then
                    vfmdb["whitelist"][k].meanXPPerHour = 0
                end
            end
        end

        if vfmdb["version"][2] < 4 or (vfmdb["version"][2] == 4 and vfmdb["version"][3] < 1) then
            for k, v in pairs(vfmdb["whitelist"]) do
                if type(k) == "string" then
                    vfmdb["whitelist"][k].lastUpdate = now()
                end
            end
        end
    end

    if vfmdb["hasSetup"] == nil then
        vfmdb["hasSetup"] = true
    end

    if vfmdb["version"] == nil or saveIsSameVersion() == false then
        vfmdb["version"] = VFM_VERSION
    end

    -- Prevent needless version checking
    if vfmdb["latestVersion"] ~= nil then
        vfmdb["latestVersion"] = nil
    end

    if vfmdb["whitelist"] == nil then
        vfmdb["whitelist"] = {}
    end

    if vfmdb["pending"] == nil then
        vfmdb["pending"] = {}
    end

    if vfmdb["updateFrequency"] == nil or vfmdb["updateFrequency"] <= 10 or vfmdb["updateFrequency"] >= 600 then
        vfmdb["updateFrequency"] = DEFAULT_UPDATE_FREQUENCY
    end
end

local function versionCheck(n, silent)
    local isOutdated = false
    local isNewer    = false

    if vfmdb["latestVersion"] ~= nil then
        isOutdated = true

        if n ~= nil then
            if createVersionNumber(vfmdb["latestVersion"]) < n then
                isNewer = true
            end
        end
    elseif getCurrentVersion() < n then
        isNewer    = true
        isOutdated = true
    end

    if isNewer then
        local a = math.floor(n / 1e4)
        local b = math.floor(n / 1e2 - a * 1e2)
        local c = math.floor(n - a * 1e4 - b * 1e2)
        vfmdb["latestVersion"] = {a, b, c}
    end

    if isOutdated and not silent then
        vfmPrint(string.format("A newer version, %i.%i.%i, of VFM was found!", a, b ,c), "yellow");
    end

    return isNewer
end

local function acceptRequest(pname)
    if VFM_DEBUG then
        vfmPrint(string.format("ACCEPT REQUEST (pname=%q)", pname), "debug")
    end

    C_ChatInfo.SendAddonMessage("VFMXPaddon", "REQUEST_ACCEPTED " .. ({UnitClass("player")})[2], "WHISPER", pname);
end

function VFMeventHandler(event, ...)
    local prefix, message, channel, from = ...;

    if (VFM_DEBUG) then
        vfmPrint(string.format("RECIEVED { type=%s, message=%q, channel=%s, from=%s }", prefix, message, channel, from), "debug");
    end

    if prefix ~= "VFMXPaddon" then
        return
    end

    if version_check_timeout < GetTime() and message:find("^VER") then
        local n = tonumber(message:match("(%d+)"))

        if n == nil then
            return
        end

        versionCheck(n, true)

        -- Respond if their version is lower than ours
        if n < getCurrentVersion() then
            C_ChatInfo.SendAddonMessage("VFMXPaddon", "VER " .. getCurrentVersion(), nil, nil);
        end

        version_check_timeout = GetTime() + 8
        return
    end

    local name = normalizeName(from);

    if message == "REQUEST_ADD" and vfmdb["pending"][name] == nil then
        if vfmdb["whitelist"][name] == nil then
            table.insert(vfmdb["pending"], name);
            vfmPrint("You have a new pending request from '\124c0c5f94ff" .. name .. "\124cffffffff'!")
        else
            acceptRequest(name)
        end
    elseif message:find("REQUEST_ACCEPTED") then
        vfmPrint("'\124c0c5f94ff" .. name .. "\124cffffffff' added you to their whitelist.");

        vfmdb["whitelist"][name].class = message:match("^REQUEST_ACCEPTED (%S+)")
        vfmdb["whitelist"][name].hasAccepted = true
        C_ChatInfo.SendAddonMessage("VFMXPaddon", "GET_PROGRESS", "WHISPER", name);
    elseif message == "REQUEST_REJECTED"  and vfmdb["whitelist"][name] == nil then
        vfmPrint("'\124c0c5f94ff" .. name .. "\124cffffffff' rejected your request.");
    end

    if vfmdb["whitelist"][name] == nil then
        if (message ~= "DENY" and channel == "WHISPER") then
            C_ChatInfo.SendAddonMessage("VFMXPaddon", "DENY", "WHISPER", name);
        end

        return
    elseif message == "DENY" and channel == "WHISPER" then
        vfmdb["whitelist"][name].hasAccepted = false
        return
    end

    local tDiff = now() - vfmdb["whitelist"][name].lastUpdate

    if (message == "GET_PROGRESS" or message == "GET_PROGRESS_BROADCAST") then
        -- Make sure we don't spam
        if tDiff <= 5 or (last_sent_progress[from] and last_sent_progress[from] + 5 >= now()) then
            return
        end

        last_sent_progress[from] = now()

        C_ChatInfo.SendAddonMessage("VFMXPaddon", "PROG " .. UnitLevel("player") .. ":" .. UnitXP("player") .. ":" .. (GetXPExhaustion() == nil and 0 or GetXPExhaustion()), "WHISPER", from);
    elseif message:find("^PROG") ~= nil then
        local n_lvl, n_cxp, n_rxp = message:gmatch("PROG (%d+):(%d+):(%d+)", function(x) return x end)()
        n_lvl, n_cxp, n_rxp = tonumber(n_lvl), tonumber(n_cxp), tonumber(n_rxp)
        local mxp = MAX_XP[n_lvl]

        -- Ignore bogus data
        if n_lvl == 0 or n_lvl > 60 or n_cxp > mxp or n_cxp == 0 then
            if VFM_DEBUG then
                vfmPrint(string.format("BOGUS DATA (n_lvl=%d, n_cxp=%d, mxp=%d, n_rxp=%d)", n_lvl, n_cxp, mxp, n_rxp), "debug")
            end

            return
        end

        if vfmdb["whitelist"][name].level ~= 0 and n_lvl > vfmdb["whitelist"][name].level then
            vfmPrint(string.format("%s has reached level %i!", createPlayerNameString(name, vfmdb["whitelist"][name].level, vfmdb["whitelist"][name].class), n_lvl), "lblue")
        end

        if tDiff > 0 and vfmdb["whitelist"][name].level ~= 0 and n_lvl - vfmdb["whitelist"][name].level <= 1 then
            local n_xph = 3600 / tDiff

            if vfmdb["whitelist"][name].level == n_lvl then
                n_xph = n_xph * (n_cxp - vfmdb["whitelist"][name].currentXP)
            else
                n_xph = n_xph * (n_cxp + MAX_XP[n_lvl - 1] - vfmdb["whitelist"][name].currentXP)
            end

            if tDiff > 3600 then
                vfmdb["whitelist"][name].meanXPPerHour = n_xph
            else
                vfmdb["whitelist"][name].meanXPPerHour = (19 * vfmdb["whitelist"][name].meanXPPerHour + n_xph) / 20
            end
        end

        vfmdb["whitelist"][name].level      = n_lvl
        vfmdb["whitelist"][name].currentXP  = n_cxp
        vfmdb["whitelist"][name].restedXP   = n_rxp
        vfmdb["whitelist"][name].lastUpdate = now()

        -- Respondent has already whitelisted us
        if not vfmdb["whitelist"][name].hasAccepted then
            vfmdb["whitelist"][name].hasAccepted = true
        end
    end
end

local function removeFromPending(name)
    if (vfmdb["pending"][name] == nil) then
        return;
    end

    local idx = indexOf(vfmdb["pending"], name);
    table.remove(vfmdb["pending"], idx);
end

local function addToWhitelist(name)
    name = normalizeName(name);

    if indexOf(vfmdb["whitelist"], name) > 0 then
        vfmPrint(createPlayerNameString(name) .. "is already whitelisted.");
        return false;
    end

    removeFromPending(name);
    table.insert(vfmdb["whitelist"], name);

    vfmdb["whitelist"][name] = {
        ["level"]         = 0,
        ["currentXP"]     = 0,
        ["restedXP"]      = 0,
        ["lastUpdate"]    = 0,
        ["meanXPPerHour"] = 0,
        ["class"]         = nil,
        ["hasAccepted"]   = false
    };

    vfmPrint("Added " .. createPlayerNameString(name) .. " to whitelist.");

    -- Tell the other person we added them
    if canCommunicate then
        C_ChatInfo.SendAddonMessage("VFMXPaddon", "REQUEST_ADD", "WHISPER", name);
    end

    return true;
end

local function removeFromWhitelist(name)
    name = normalizeName(name);

    if vfmdb["whitelist"][name] == nil then
        vfmPrint(createPlayerNameString(name) .. " is not on your whitelist.");
        return false;
    end

    local idx = indexOf(vfmdb["whitelist"], name);

    if idx == 0 then
        vfmPrint("Could not find index of " .. createPlayerNameString(name) .. ".");
        return false;
    end

    removeFromPending(name);
    vfmPrint("Removing " .. createPlayerNameString(name, vfmdb["whitelist"][idx].level, vfmdb["whitelist"][idx].class) .. " from whitelist.");
    vfmdb["whitelist"][name] = nil;
    table.remove(vfmdb["whitelist"], idx);
    return true;
end

local function broadcastProgressRequest()
    if not canCommunicate then
        return false
    end

    last_full_update = GetTime();

    if IsInGuild() then
        C_ChatInfo.SendAddonMessage("VFMXPaddon", "GET_PROGRESS_BROADCAST", "GUILD");
    end

    C_ChatInfo.SendAddonMessage("VFMXPaddon", "GET_PROGRESS_BROADCAST");

    -- Whisper ourselves for debugging purposes
    if VFM_DEBUG and vfmdb["whitelist"][({UnitName("player")})[1]] ~= nil then
        if not UnitInRaid("player") and not UnitInParty("player") and not UnitInBattleground("player") and not UnitInGuild("player") then
            C_ChatInfo.SendAddonMessage("VFMXPaddon", "GET_PROGRESS", "WHISPER", ({UnitName("player")})[1]);
        end
    end
end

local function performUpdateInterval()
    if not canCommunicate then
        return false
    end

    if (VFM_DEBUG) then
        vfmPrint("UPDATE TICK", "debug");
    end

    if GetTime() - last_full_update > vfmdb["updateFrequency"] - 1 then
        broadcastProgressRequest();
    end

    -- Queue the next update interval
    C_Timer.After(vfmdb["updateFrequency"], performUpdateInterval);
end

local function listDataEntries(filter)
    local showNew   = (filter == "recent" or filter == "") -- Default
    local showOld   = (filter == "old")
    local showEmpty = (filter == "empty")

    local secondsFresh = 3600 * 12
    local displayCount = 0

    for k, v in ipairs(vfmdb["whitelist"]) do
        local tDiff = now() - vfmdb["whitelist"][v].lastUpdate
        local isFresh = tDiff <= secondsFresh

        if filter == "all" or
           (vfmdb["whitelist"][v].hasAccepted and ((showNew and isFresh) or (showOld and not isFresh))) or
           (not vfmdb["whitelist"][v].hasAccepted and showEmpty) then
            local str = ("[%i] %s"):format(tostring(k), createPlayerNameString(v, vfmdb["whitelist"][v].level, vfmdb["whitelist"][v].class))

            displayCount = displayCount + 1

            if not vfmdb["whitelist"][v].hasAccepted then
                str = str .. " \124caa999999REQUEST PENDING\124cffffffff"
            end            

            if vfmdb["whitelist"][v].level > 0 then
                local mxp = MAX_XP[vfmdb["whitelist"][v].level];
                str = str .. "\n" .. string.format("  XP: %s/%s, %.2f%% done", numberToDigitGroupedString(vfmdb["whitelist"][v].currentXP), numberToDigitGroupedString(mxp), 100 * vfmdb["whitelist"][v].currentXP / mxp)

                if (vfmdb["whitelist"][v].restedXP > 0) then
                    local rxp = 100 * math.min(mxp - vfmdb["whitelist"][v].currentXP, vfmdb["whitelist"][v].restedXP) / (mxp - vfmdb["whitelist"][v].currentXP)
                    str = str .. string.format(" (rested: %s, %.2f%% of level)", numberToDigitGroupedString(vfmdb["whitelist"][v].restedXP), rxp)
                end

                if vfmdb["whitelist"][v].level < 60 and vfmdb["whitelist"][v].meanXPPerHour > 0 then
                    local secondsToDing = math.ceil(3600 * (mxp - vfmdb["whitelist"][v].currentXP) / vfmdb["whitelist"][v].meanXPPerHour) - tDiff

                    if secondsToDing < 0 then
                        secondsToDing = 0
                    end

                    str = str .. "\n" .. string.format("  XP/Hour: %s, %s till level %i", numberToDigitGroupedString(math.ceil(vfmdb["whitelist"][v].meanXPPerHour)),
                            (secondsToDing > 86400 and "more than 1 day" or createTimeString(secondsToDing)), vfmdb["whitelist"][v].level + 1)
                end

                str = str .. "\n  Updated " .. (vfmdb["whitelist"][v].lastUpdate > 0 and createReadableTimeString(tDiff) .. " ago" or "N/A")
                print(str)
            else
                print("No data.")
            end
        end
    end

    vfmPrint("Displaying " .. displayCount .. " out of " .. #vfmdb["whitelist"] .. " entries.")
end

local function slashHandler(msg, editbox)
    local command, rest = msg:match("^(%S*)%s*(.-)$");

    if command == "reset" then
        setupdb(true);
        vfmPrint("All settings have been reset to default.");
    elseif command == "list" then
        if rest == "requests" then
            if (#vfmdb["pending"] == 0) then
                vfmPrint("You have no pending requests.");
            else
                vfmPrint("Pending requests:");
                for i, v in ipairs(vfmdb["pending"]) do
                    print(string.format("[%i] %s", i, v));
                end
                vfmPrint("To \124c13a347ffaccept\124cffffffff a request use '/vfm accept <index>', where index is the number next to the player name above. Alternatively, add the player using '/vfm add <player name>'.");
                vfmPrint("To \124cdd3e3effreject\124cffffffff a request use '/vfm reject <index>'.");
            end
        else
            listDataEntries(rest)
        end
    elseif command == "update" then
        if rest ~= "" then
            if vfmdb["whitelist"][rest] == nil then
                vfmPrint(createPlayerNameString(rest) .. " is not on your whitelist.")
            else
                vfmPrint("Requesting update from " .. createPlayerNameString(rest, vfmdb["whitelist"][rest].level, vfmdb["whitelist"][rest].class) .. ".")
                C_ChatInfo.SendAddonMessage("VFMXPaddon", "GET_PROGRESS", "WHISPER", rest);
            end
        else
            vfmPrint("Broadcasting update request.")
            broadcastProgressRequest();
        end
    elseif command == "add" then
        if rest ~= "" then
            addToWhitelist(rest)
        else
            vfmPrint("Please provide a player name to add.");
        end
    elseif command == "remove" then
        if rest ~= "" then
            removeFromWhitelist(rest)
        else
            vfmPrint("Please provide a player name to remove.");
        end
    elseif command == "accept" then
        local idx = tonumber(rest);
        if idx == 0 then
            idx = 1;
        end

        if (#vfmdb["pending"] == 0) then
            vfmPrint("There are no pending requests.");
        elseif (#vfmdb["pending"] < idx) then
            vfmPrint("Index out-of-bounds.", "red");
        else
            if addToWhitelist(vfmdb["pending"][idx]) then
                if canCommunicate then
                    acceptRequest(vfmdb["pending"][idx])
                end
                table.remove(vfmdb["pending"], idx);
            end
        end
    elseif command == "reject" then
        local idx = tonumber(rest);
        if idx == 0 then
            idx = 1;
        end

        if (#vfmdb["pending"] == 0) then
            vfmPrint("There are no pending requests.");
        elseif (#vfmdb["pending"] < idx) then
            vfmPrint("Index out-of-bounds.", "red");
        else
            vfmPrint("Request from " .. createPlayerNameString(vfmdb["pending"][idx]) .. " rejected.");

            if canCommunicate then
                C_ChatInfo.SendAddonMessage("VFMXPaddon", "REQUEST_REJECTED", "WHISPER", vfmdb["pending"][idx]);
            end
            table.remove(vfmdb["pending"], idx);
        end
    elseif command == "debug" then
        VFM_DEBUG = not VFM_DEBUG;
        vfmPrint("Debug mode " .. (VFM_DEBUG and "\124cff13a347enabled\124cffffffff" or "\124cffdd3e3edisabled\124cffffffff"))
    elseif command == "updatedelay" or command == "interval" then
        local n = tonumber(rest)

        if n == nil or n <= 10 or n >= 600 then
            vfmPrint("Syntax: /vfm updatedelay <number>")
            vfmPrint("Sets the delay between updates in seconds. Must satisfy [10 <= X <= 600]. Default: " .. DEFAULT_UPDATE_FREQUENCY .. ".")
            return
        end

        vfmdb["updateFrequency"] = n
        vfmPrint("Update frequency set to \124cff0c5f94" .. n .. "\124cffffffff.")
    else
        print(string.format("\124cff1d82b2VFM\124cffffffff %i.%i.%i", VFM_VERSION[1], VFM_VERSION[2], VFM_VERSION[3]));
        print("\124c0c5f94ffReset\124cffffffff - Resets all settings, including added characters. Only affects current character.");
        print("\124c0c5f94ffList [recent | old | empty | requests]\124cffffffff - Lists characters and their associated data. Default: recent.");
        print("  \124c0c5f94ffRecent\124cffffffff - List entries from less than up until 12 hours ago.");
        print("  \124c0c5f94ffOld\124cffffffff - List entries from more than 12 hours ago.");
        print("  \124c0c5f94ffEmpty\124cffffffff - List entries without any data.");
        print("  \124c0c5f94ffRequests\124cffffffff - List requests other players have made to be accepted on your whitelist.");
        print("\124c0c5f94ffUpdate\124cffffffff - Forcefully update progression data. This is NOT necessary nor recommended, as VFM updates itself automatically.");
        print("\124c0c5f94ffAdd <character name>\124cffffffff - Adds a character to your whitelist and sends a request to the affected character.");
        print("\124c0c5f94ffRemove <character name>\124cffffffff - Removes a character from your whitelist.");
        print("\124c0c5f94ffAccept <index>\124cffffffff - Accepts a pending requests and adds the character to your whitelist.");
        print("\124c0c5f94ffReject <index>\124cffffffff - Reject pending requests with index <index>.");
        print("\124c0c5f94ffUpdatedelay <number>\124cffffffff - Sets the time between updates. Default: 60.");
        print("\124c0c5f94ffInterval\124cffffffff - Macro for 'updatedelay'.");
        print("\124c0c5f94ffDebug\124cffffffff - Toggles debug mode for the current session.");
        print("\124cffffffffNote: VFM will deny any character data queries from characters not currently on your whitelist.");
    end
end

LoginFrame:SetScript("OnEvent", function(self, e, ...)
    if e == "PLAYER_ENTERING_WORLD" then
        if vfmdb == nil then
            vfmPrint("First-time setup.")
            setupdb(true)
        elseif not saveIsSameVersion() then
            vfmPrint(string.format("Performing non-destructive upgrade from version %i.%i.%i to %i.%i.%i.",
                vfmdb["version"][1], vfmdb["version"][2], vfmdb["version"][3],
                VFM_VERSION[1], VFM_VERSION[2], VFM_VERSION[3]))
            setupdb(false)
        end

        performUpdateInterval()
        C_ChatInfo.SendAddonMessage("VFMXPaddon", "VER " .. getCurrentVersion())
        LoginFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

do
    -- Register addon prefix
    if C_ChatInfo.IsAddonMessagePrefixRegistered("VFMXPaddon") == false then
        local didRegister = C_ChatInfo.RegisterAddonMessagePrefix("VFMXPaddon");
        canCommunicate = true

        if didRegister == false then
            canCommunicate = false
            vfmPrint("Could not register addon prefix!", "red");
        end
    end

    -- Slash Handler
    SLASH_VFM1 = "/vfm"
    SlashCmdList.VFM = slashHandler
    LoginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end