-- Character data used to be painted as colored cells. That overlay is off.

local CELL = 2
local COLS = 8
local MAX_BYTES = 72
local SHOW_FOR = 1.4
local HEARTBEAT = 10

-- 3-bit symbols. Index matches the Python decoder.
local PALETTE = {
    { 1, 0.5, 0 }, -- not black: the UI drops a true black texture
    { 1, 0, 0 },
    { 0, 1, 0 },
    { 0, 0, 1 },
    { 1, 1, 0 },
    { 1, 0, 1 },
    { 0, 1, 1 },
    { 1, 1, 1 },
}
local SYNC = { 5, 0, 5, 0, 5, 0, 7, 0 }

local CLASS_KEY = {
    DEATHKNIGHT = "death_knight",
    DEMONHUNTER = "demon_hunter",
    DRUID = "druid",
    EVOKER = "evoker",
    HUNTER = "hunter",
    MAGE = "mage",
    MONK = "monk",
    PALADIN = "paladin",
    PRIEST = "priest",
    ROGUE = "rogue",
    SHAMAN = "shaman",
    WARLOCK = "warlock",
    WARRIOR = "warrior",
}

local parent = CreateFrame("Frame", "KissPresencePixels", UIParent)
parent:SetFrameStrata("TOOLTIP")
parent:SetFrameLevel(1000)
parent:EnableMouse(false)
if parent.SetIgnoreParentScale then
    parent:SetIgnoreParentScale(true)
end
parent:Hide()

local function place()
    -- UI scale pulls UIParent in from the screen edge. Pin the block to
    -- the real top-left so it stays a small corner mark.
    parent:ClearAllPoints()
    local ui = UIParent:GetEffectiveScale() or 1
    if ui > 0 then
        parent:SetScale(1 / ui)
    end
    local gapX = UIParent:GetLeft() or 0
    local gapY = (GetScreenHeight() or 0) - (UIParent:GetTop() or 0)
    parent:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -gapX, gapY)
end
place()

local cells = {}
local hideToken = 0
local lastPayload = nil

local function plain(value)
    if value == nil then
        return nil
    end
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end

local function ensureCells(count)
    while #cells < count do
        local tex = parent:CreateTexture(nil, "ARTWORK")
        tex:SetSize(CELL, CELL)
        tex:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -#cells * CELL)
        cells[#cells + 1] = tex
    end
    parent:SetSize(CELL, count * CELL)
end

local function paint(symbols)
    place()
    local count = #symbols
    local rows = math.ceil(count / COLS)
    ensureCells(count)
    parent:SetSize(COLS * CELL, rows * CELL)
    for i = 1, count do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local color = PALETTE[symbols[i] + 1]
        cells[i]:ClearAllPoints()
        cells[i]:SetSize(CELL, CELL)
        cells[i]:SetPoint("TOPLEFT", parent, "TOPLEFT", col * CELL, -row * CELL)
        cells[i]:SetColorTexture(color[1], color[2], color[3], 1)
        cells[i]:Show()
    end
    for i = count + 1, #cells do
        cells[i]:Hide()
    end
end

local function pushBits(bits, value, width)
    for shift = width - 1, 0, -1 do
        bits[#bits + 1] = bit.band(bit.rshift(value, shift), 1)
    end
end

local function clean(text)
    text = plain(text)
    if not text or text == "" then
        return ""
    end
    text = tostring(text)
    text = text:gsub("[|\r\n]", " ")
    return text
end

local function clip(text, limit)
    text = clean(text)
    if #text > limit then
        return text:sub(1, limit)
    end
    return text
end

local function encode(payload)
    if #payload > MAX_BYTES then
        payload = payload:sub(1, MAX_BYTES)
    end
    local bits = {}
    pushBits(bits, #payload, 8)
    local checksum = 0
    for i = 1, #payload do
        local byte = payload:byte(i)
        pushBits(bits, byte, 8)
        checksum = bit.bxor(checksum, byte)
    end
    pushBits(bits, checksum, 8)
    while #bits % 3 ~= 0 do
        bits[#bits + 1] = 0
    end
    local symbols = {}
    for i = 1, #SYNC do
        symbols[#symbols + 1] = SYNC[i]
    end
    for i = 1, #bits, 3 do
        symbols[#symbols + 1] = bits[i] * 4 + bits[i + 1] * 2 + bits[i + 2]
    end
    return symbols
end

local function flash(_)
    parent:Hide()
end

local function currentPayload()
    local name = clip(UnitName("player"), 18)
    if name == "" or not UnitExists("player") then
        return nil
    end
    local level = plain(UnitLevel("player"))
    if not level or level < 1 then
        return nil
    end
    local localizedClass, englishClass = UnitClass("player")
    localizedClass = clip(localizedClass, 16)
    englishClass = plain(englishClass) or ""
    local classKey = CLASS_KEY[englishClass] or englishClass:lower()
    local faction = clip(select(1, UnitFactionGroup("player")), 12)
    local zone = clip(GetRealZoneText(), 22)
    if zone == "" then
        zone = clip(GetZoneText(), 22)
    end
    local subzone = clip(GetSubZoneText(), 18)
    if subzone == zone then
        subzone = ""
    end
    return table.concat({
        name,
        tostring(level),
        localizedClass,
        classKey,
        faction,
        zone,
        subzone,
    }, "|")
end

local function groupSpec()
    local inRaid = IsInRaid and IsInRaid()
    local inGroup = IsInGroup and IsInGroup()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if inRaid and count > 1 then
        local cap = 40
        if GetRaidDifficultyID and GetRaidDifficultyID() == 16 then
            cap = 20
        end
        return string.format("raid:%d:%d", count, cap)
    end
    if inGroup and not inRaid and count > 1 then
        return string.format("party:%d:5", count)
    end
    return "solo"
end

local function writeGroup()
    local spec = groupSpec()
    KissPresenceDB = KissPresenceDB or {}
    if KissPresenceDB.group == spec then
        return
    end
    KissPresenceDB.group = spec
    if C_CVar and C_CVar.SetCVar then
        pcall(function()
            if C_CVar.RegisterCVar then
                C_CVar.RegisterCVar("KissPresenceGroup", "solo")
            end
            C_CVar.SetCVar("KissPresenceGroup", spec)
        end)
    end
end

local function publish(force)
    if KissPresenceDB and KissPresenceDB.enabled == false then
        parent:Hide()
        return
    end
    local payload = currentPayload()
    if not payload then
        return
    end
    lastPayload = payload
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("ZONE_CHANGED")
driver:RegisterEvent("ZONE_CHANGED_INDOORS")
driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
driver:RegisterEvent("PLAYER_LEVEL_UP")
driver:RegisterEvent("GROUP_ROSTER_UPDATE")
driver:SetScript("OnEvent", function(_, event)
    local delay = (event == "PLAYER_ENTERING_WORLD") and 1.5 or 0.4
    C_Timer.After(delay, function()
        publish(true)
        writeGroup()
    end)
end)

parent:Hide()

SLASH_KISSPRESENCE1 = "/kp"
SLASH_KISSPRESENCE2 = "/kisspresence"
SlashCmdList.KISSPRESENCE = function(message)
    KissPresenceDB = KissPresenceDB or {}
    message = (message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if message == "off" then
        KissPresenceDB.enabled = false
        parent:Hide()
        print("Kiss Presence: in-game signal off. Discord will go quiet once the current status expires.")
        return
    end
    if message == "on" then
        KissPresenceDB.enabled = true
        print("Kiss Presence: overlay stays off.")
        parent:Hide()
        return
    end
    local payload = currentPayload()
    if payload then
        print("Kiss Presence: " .. payload:gsub("|", " | "))
    else
        print("Kiss Presence: not in the world yet.")
    end
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
    KissPresenceDB = KissPresenceDB or { enabled = true }
    if KissPresenceDB.enabled == nil then
        KissPresenceDB.enabled = true
    end
    print("Kiss Presence loaded. /kp off hides the signal. Work hours are the wow-presence command.")
end)
