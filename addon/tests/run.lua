-- Run from repository root with Lua (or Fengari). No WoW installation required.
local ns, passed = {}, 0
local function load(name) assert(loadfile("addon/OzzySwingTimer/" .. name))("OzzySwingTimer", ns) end
load("Model.lua")
local function near(a, b) assert(math.abs(a - b) < 0.0001, tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. tostring(err)) end
    passed = passed + 1; print("PASS " .. name)
end
local function fresh()
    local m = ns.Model:New(); m:SetGCD(0, 0, 0, true); return m
end
test("pendulum reverses direction", function()
    local m = fresh(); m:Shot(10)
    near(m:View(11.15).cursor, 0.5)
    m:Advance(12.3, false); near(m:View(12.55).cursor, 0.5)
    assert(m:View(12.55).green)
end)
test("cast and GCD occupy their union, not their sum", function()
    local m = fresh(); m:Shot(10)
    m:SetCast(10, 11.5, "cast", 10); m:SetGCD(10, 1, 10, true)
    local segments = m:Segments(); assert(#segments == 1)
    near(segments[1].width, 1.5 / 2.3)
    near(segments[1].left, 0.8 / 2.3)
end)
test("late GCD carries into next cooldown", function()
    local m = fresh(); m:Shot(10); m:SetGCD(12.2, 1, 12.2, true)
    m:Shot(12.8); local s = m:Segments(); assert(#s == 1)
    near(s[1].width, 0.4 / 2.3)
end)
test("GCD restricts queue window but does not stop Auto Shot", function()
    local m = fresh(); m:Shot(10); m:SetGCD(12, 0.6, 12, true)
    m:Advance(12.3, false); assert(m.phase == "wind")
    near(m:QueueWindow(12.4, false).duration, 0.2)
    assert(not m:View(12.4).green); assert(m:View(12.65).green)
end)
test("unknown GCD never offers a green cue", function()
    local m = fresh(); m:BeginWind(10, false); m:SetGCD(nil, nil, 10, false)
    assert(not m:View(10.2).green)
end)
test("no shot events means no invented cycles", function()
    local m = fresh(); m:Start(10, false); m:Advance(11, false); m:Advance(20, false)
    assert(m.shots == 0 and m.phase == "blocked")
end)
test("movement interrupts predicted wind-up", function()
    local m = fresh(); m:Start(10, false); m:Advance(10.2, true)
    assert(m.phase == "blocked"); m:Advance(10.3, false)
    assert(m.phase == "wind"); near(m.windStart, 10.3)
end)
test("cast starting at the release flashes once per shot", function()
    local m = fresh(); m:BeginWind(10, false)
    assert(not m:CastStarted(10.3)); assert(m.flashSerial == 0)
    m:Shot(10.5); assert(m:CastStarted(10.5)); assert(m.flashSerial == 1)
    assert(not m:CastStarted(10.52)); assert(m.flashSerial == 1)
end)
test("cast started later in cooldown never flashes", function()
    local m = fresh(); m:Shot(10); assert(not m:CastStarted(10.5))
    assert(m.flashSerial == 0)
end)
test("failure report during observed wind-up keeps the wind-up", function()
    local m = fresh(); m:Shot(8); m:BeginWind(10, true)
    m:AutoFailed(10.2); assert(m.phase == "wind" and m.observedWindStart == 10)
    m:Advance(10.3, false); assert(m.phase == "wind")
    m:Advance(11, false); assert(m.phase == "blocked")
end)
test("duplicate Auto Shot events are ignored", function()
    local m = fresh(); assert(m:Shot(10)); assert(not m:Shot(10.01))
    assert(not m:Shot(10.215)); assert(m.shots == 1)
end)
test("haste preserves fractional weapon cooldown progress", function()
    local m = fresh(); m:Shot(10); m:SetTiming(1.4, 0.25, 11.15)
    near(m:View(11.15).cursor, 0.5)
end)

-- Minimal native-UI mock: validate calls and exercise full addon event wiring.
local now, speed, cast, cooldown = 100, 3.1, nil, {startTime = 0, duration = 0, modRate = 1}
local object = {}; object.__index = object
local function newObject() return setmetatable({scripts = {}, shown = true}, object) end
function object:SetScript(event, fn) self.scripts[event] = fn end
function object:SetPoint(point) assert(type(point) == "string", "invalid native UI anchor") end
function object:CreateTexture() return newObject() end
function object:CreateFontString() return newObject() end
function object:SetText(text) self.text = text end
function object:IsShown() return self.shown end
function object:GetFrameLevel() return 1 end
function object:GetCenter() return 500, 500 end
function object:Show() self.shown = true end
function object:Hide() self.shown = false end
for _, name in ipairs({"SetColorTexture", "SetWidth", "SetHeight", "SetFrameStrata", "SetClampedToScreen",
    "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "ClearAllPoints", "SetAllPoints",
    "SetFrameLevel", "SetSize", "SetScale", "EnableMouse", "SetClipsChildren", "SetRotation", "SetAlpha", "RegisterEvent",
    "SetJustifyH"}) do
    object[name] = function() end
end
UIParent = newObject()
function CreateFrame() return newObject() end
function GetTime() return now end
function GetUnitSpeed() return 0 end
function UnitRangedDamage() return speed end
function GetInventoryItemID() return 123 end
function UnitClass() return "Hunter", "HUNTER" end
function UnitGUID() return "player-guid" end
function GetBuildInfo() return "2.5.6", "70577" end
function UnitCastingInfo()
    if cast then return "Steady Shot", nil, nil, cast.start * 1000, cast.finish * 1000, nil, nil, nil, 34120 end
end
function UnitChannelInfo() end
C_Spell = {GetSpellCooldown = function() return cooldown end,
    GetSpellInfo = function() return {castTime = 1500} end}
DEFAULT_CHAT_FRAME = {AddMessage = function() end}
SlashCmdList = {}
load("Display.lua"); load("TestPanel.lua"); load("OzzySwingTimer.lua")
local function event(name, ...) ns.driver.scripts.OnEvent(ns.driver, name, ...) end
local function update(time) now = time; ns.driver.scripts.OnUpdate(ns.driver, 0.016) end
test("TOC modules initialize with native UI calls", function()
    event("ADDON_LOADED", "OzzySwingTimer"); update(100)
    assert(ns.model and SlashCmdList.OZZYSWINGTIMER)
end)
test("live GCD duration is read independently of cast duration", function()
    cooldown = {startTime = 100, duration = 0.9, modRate = 1}
    cast = {start = 100, finish = 101.5}; update(100.05)
    near(ns.model.gcdEnd, 100.9); near(ns.model.castEnd, 101.5)
    cast = nil; cooldown = {startTime = 0, duration = 0}; update(102)
end)
test("real shot events drive bar and learned wind-up", function()
    now = 103; event("START_AUTOREPEAT_SPELL")
    event("UNIT_SPELLCAST_START", "player", "auto1", 75)
    now = 103.4; event("UNIT_SPELLCAST_SUCCEEDED", "player", "auto1", 75)
    near(ns.model.wind, 0.4); assert(ns.model.shots == 1); update(104)
    now = 103.41; event("UNIT_SPELLCAST_SUCCEEDED", "player", "auto1", 75)
    assert(ns.model.shots == 1)
end)
test("queue flash survives real event order", function()
    ns.model:BeginWind(106, true); ns.model:SetGCD(0, 0, 106, true)
    update(106.2)
    -- Observed order in TBC 2.5.6: release, then the held Steady Shot is sent and starts.
    now = 106.4; event("UNIT_SPELLCAST_SUCCEEDED", "player", "auto2", 75)
    event("UNIT_SPELLCAST_SENT", "player", "target", "steady1", 34120)
    assert(ns.model.flashSerial == 0)
    cast = {start = 106.4, finish = 107.9}
    event("UNIT_SPELLCAST_START", "player", "steady1", 34120)
    assert(ns.model.flashSerial == 1); update(106.41)
    cast = nil
end)
test("test mode paints both phases and exits", function()
    SlashCmdList.OZZYSWINGTIMER("test")
    update(108); update(108.9); update(111.6)
    SlashCmdList.OZZYSWINGTIMER("test"); update(112)
    SlashCmdList.OZZYSWINGTIMER("lock"); event("STOP_AUTOREPEAT_SPELL"); update(113)
    assert(not ns.display.frame.shown)
end)
test("one noisy wind-up does not move the learned median", function()
    local t = 200
    for _, duration in ipairs({0.32, 0.32, 0.105, 0.48, 0.32}) do
        now = t; event("UNIT_SPELLCAST_START", "player", "a" .. t, 75)
        now = t + duration; event("UNIT_SPELLCAST_SUCCEEDED", "player", "a" .. t, 75)
        t = t + 3.1
    end
    near(ns.model.wind, 0.32)
end)
test("debug log records session, marks, GCD and instant casts", function()
    SlashCmdList.OZZYSWINGTIMER("debug on")
    SlashCmdList.OZZYSWINGTIMER("mark steady early")
    now = 230; cooldown = {startTime = 230, duration = 1.5, modRate = 1}; update(230)
    C_Spell.GetSpellInfo = function() return {castTime = 0} end
    event("UNIT_SPELLCAST_SENT", "player", "target", "arcane1", 27019)
    C_Spell.GetSpellInfo = function() return {castTime = 1500} end
    local seen = {}
    for _, entry in ipairs(OzzySwingTimerDB.events) do seen[entry.event] = entry end
    assert(seen.SESSION and seen.SESSION.build)
    assert(seen.MARK.note == "steady early")
    near(seen.GCD.gcdDuration, 1.5)
    assert(seen.CAST_SENT.spellID == 27019 and seen.CAST_SENT.castTime == 0)
    SlashCmdList.OZZYSWINGTIMER("debug off")
    cooldown = {startTime = 0, duration = 0}; update(232)
end)
test("test panel buttons start a log, mark steps and count shots", function()
    local panel = ns.panel
    assert(not panel.frame.shown); SlashCmdList.OZZYSWINGTIMER("panel"); assert(panel.frame.shown)
    local function click(label)
        for _, child in ipairs(panel.buttons) do
            if child.text == label then child.scripts.OnClick(child); return end
        end
        error("no button " .. label)
    end
    click("Ny logg"); assert(OzzySwingTimerDB.debug)
    click("2 Steady röd")
    local last = OzzySwingTimerDB.events[#OzzySwingTimerDB.events]
    assert(last.event == "MARK" and last.note == "steady röd")
    now = 240; event("UNIT_SPELLCAST_SUCCEEDED", "player", "p1", 75); panel:Refresh(true)
    assert(panel.status.text:find("skott: 1"), panel.status.text)
    assert(panel.instruction.text:find("blir röd"))
    SlashCmdList.OZZYSWINGTIMER("debug off"); SlashCmdList.OZZYSWINGTIMER("panel")
    assert(not panel.frame.shown)
end)
test("GCD is read from a known no-cooldown spell, not 61304", function()
    local asked
    IsPlayerSpell = function(id) return id == 34120 end
    C_Spell.GetSpellCooldown = function(id)
        asked = id
        return id == 34120 and {startTime = 250, duration = 1.5, modRate = 1} or {startTime = 0, duration = 0}
    end
    event("PLAYER_ENTERING_WORLD"); now = 250.1; update(250.1)
    assert(asked == 34120); near(ns.model.gcdEnd, 251.5)
    C_Spell.GetSpellCooldown = function() return {startTime = 252, duration = 6, modRate = 1} end
    now = 252.1; update(252.1); assert(ns.model.gcdEnd == 0)
    IsPlayerSpell = nil; C_Spell.GetSpellCooldown = function() return cooldown end
end)
print(string.format("%d tests passed", passed))
