local addonName, ns = ...
local AUTO, GCD = 75, 61304
-- 61304 reports no cooldown in TBC 2.5.6. Spells without a cooldown of their own show exactly the GCD:
-- Steady Shot, Hunter's Mark and Serpent Sting (rank 1 stays known).
local GCD_REFERENCES = {34120, 1130, 1978}
local gcdSpell = GCD
local driver = CreateFrame("Frame")
local model, display, settings, demo, lastView
local learned, weaponID, nextPoll, nextSpeed = nil, nil, 0, 0
local samples = {}
local SAMPLES, LOG_LIMIT = 9, 1000
local defaults = {width = 300, height = 20, scale = 1, x = 0, y = -180, locked = false}
local function number(value)
    return type(value) == "number" and (not issecretvalue or not issecretvalue(value))
end
local function say(message) DEFAULT_CHAT_FRAME:AddMessage("|cff9fe870OzzySwingTimer:|r " .. message) end
local function moving() return GetUnitSpeed("player") > 0 end
local function log(event, spellID, extra)
    if not settings or not settings.debug then return end
    settings.events = settings.events or {}
    local list = settings.events
    local entry = {time = GetTime(), event = event, spellID = spellID,
        phase = model.phase, speed = model.speed, wind = model.wind,
        gcdEnd = model.gcdEnd, castEnd = model.castEnd}
    for key, value in pairs(extra or {}) do entry[key] = value end
    list[#list + 1] = entry
    if #list > LOG_LIMIT then table.remove(list, 1) end
end
local function logSession()
    local version, build = GetBuildInfo()
    local extra = {build = version .. " " .. tostring(build)}
    if GetNetStats then
        local _, _, home, world = GetNetStats()
        extra.latencyHome, extra.latencyWorld = home, world
    end
    if GetCVar then extra.spellQueueWindow = GetCVar("SpellQueueWindow") end
    if GetFramerate then extra.fps = GetFramerate() end
    extra.gcdSpell = gcdSpell
    log("SESSION", nil, extra)
end
local function pickGCDSpell()
    gcdSpell = GCD
    local known = IsPlayerSpell or IsSpellKnown
    if not known then return end
    for _, spellID in ipairs(GCD_REFERENCES) do
        if known(spellID) then gcdSpell = spellID; return end
    end
end

-- Median of recent wind-up observations, normalized by weapon speed; one noisy shot cannot move the bar.
local function learnWind(duration, speed)
    samples[#samples + 1] = duration / speed
    if #samples > SAMPLES then table.remove(samples, 1) end
    local sorted = {}
    for i, value in ipairs(samples) do sorted[i] = value end
    table.sort(sorted)
    local middle = math.floor(#sorted / 2) + 1
    local ratio = #sorted % 2 == 1 and sorted[middle] or (sorted[middle - 1] + sorted[middle]) / 2
    learned = {ratio = ratio, count = #sorted}
end

local function refreshSpeed(now)
    local speed = UnitRangedDamage("player")
    if not number(speed) or speed <= 0 then return end
    local item = GetInventoryItemID("player", 18)
    if item ~= weaponID then learned, samples, weaponID = nil, {}, item end
    local wind = 0.5
    ns.windSource = "uppskattad (0,5 s utan haste-korrigering)"
    if GetRangedHaste then
        local haste = GetRangedHaste()
        if number(haste) and haste > -100 then
            wind = 0.5 / (1 + haste / 100)
            ns.windSource = "uppskattad via ranged haste"
        end
    end
    if learned then
        wind = learned.ratio * speed
        ns.windSource = string.format("observerad, median av %d skott, skalad med vapentakt", learned.count)
    end
    if settings.windup then wind = settings.windup; ns.windSource = "manuell" end
    model:SetTiming(speed, wind, now)
end

local function readGCD(now)
    local start, duration, rate
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, gcdSpell)
        if ok and type(info) == "table" then
            start, duration, rate = info.startTime, info.duration, info.modRate
        end
    end
    if not number(start) and GetSpellCooldown then
        local ok, a, b, _, r = pcall(GetSpellCooldown, gcdSpell)
        if ok then start, duration, rate = a, b, r end
    end
    local known = number(start) and number(duration)
    if known and number(rate) and rate > 0 then duration = duration / rate end
    -- Anything longer than a GCD is not one.
    if known and duration > 1.6 then start, duration = 0, 0 end
    local before = model.gcdStart
    model:SetGCD(start, duration, now, known)
    if model.gcdStart > 0 and model.gcdStart ~= before then
        log("GCD", gcdSpell, {gcdStart = model.gcdStart, gcdDuration = model.gcdEnd - model.gcdStart})
    end
end

local function readCast(now)
    local name, _, _, startMS, endMS, _, _, _, spellID = UnitCastingInfo("player")
    if not name and UnitChannelInfo then
        name, _, _, startMS, endMS, _, _, spellID = UnitChannelInfo("player")
    end
    if name and spellID ~= AUTO and number(startMS) and number(endMS) then
        model:SetCast(startMS / 1000, endMS / 1000, tostring(spellID or name) .. ":" .. startMS, now)
    else model:EndCast(now) end
end

local function castTime(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and number(info.castTime) then return math.max(0, info.castTime) end
    end
    if GetSpellInfo then
        local _, _, _, duration = GetSpellInfo(spellID)
        if number(duration) then return math.max(0, duration) end
    end
    return 0
end

local function windStart(now, source)
    -- UNIT and combat-log reports can describe the same start.
    if model.observedWindStart and now - model.observedWindStart < 0.1 then return end
    model:BeginWind(now, true)
    log("AUTO_START", AUTO, {source = source})
end
local function shot(now, source)
    if model.lastShot and now - model.lastShot < ns.Model.MIN_SHOT_GAP then
        -- UNIT and combat-log both report every release; only log the suspicious gaps.
        if now - model.lastShot > 0.08 then
            log("AUTO_DUPLICATE", AUTO, {source = source, sinceLastShot = now - model.lastShot})
        end
        return
    end
    local measured
    if model.observedWindStart then
        local duration = now - model.observedWindStart
        if duration >= 0.03 and duration <= 1.5 then
            measured = duration
            learnWind(duration, model.speed)
            refreshSpeed(now)
        end
    end
    local previous = model.lastShot
    model:Shot(now)
    log("AUTO_RELEASE", AUTO, {source = source, measuredWind = measured,
        sinceLastShot = previous and now - previous})
end

local function demoView(now)
    -- Preview only. No spell is ever requested or cast by this addon.
    local elapsed = now - demo.started
    local cycle = math.floor(elapsed / 2.8)
    local t = elapsed - cycle * 2.8
    local state = ns.Model:New()
    state:SetTiming(2.8, 0.5, now)
    state:SetGCD(0, 0, now, true)
    local release = now - t
    state:Shot(release)
    state:UpsertLock("cast", "preview", release, release + 1.5)
    state:UpsertLock("gcd", "preview", release + 1.5, release + 2.5)
    if t >= 2.3 then state:BeginWind(release + 2.3, false) end
    return state:View(now, false)
end

local function command(message)
    local cmd, rest = message:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "test" then
        demo = not demo and {started = GetTime()} or nil
        say(demo and "Testläge på. /ozs test avslutar." or "Testläge av.")
    elseif cmd == "lock" or cmd == "unlock" then
        settings.locked = cmd == "lock"; display:Layout()
        say(settings.locked and "Baren är låst." or "Dra baren med vänster musknapp. /ozs lock låser.")
    elseif cmd == "reset" then
        for key, value in pairs(defaults) do settings[key] = value end
        settings.windup = nil; display:Layout()
    elseif cmd == "size" then
        local width, height = rest:match("^(%d+)%s+(%d+)$")
        width, height = tonumber(width), tonumber(height)
        if width and width >= 80 and width <= 1200 and height >= 8 and height <= 100 then
            settings.width, settings.height = width, height; display:Layout()
        else say("/ozs size 300 20 (bredd 80–1200, höjd 8–100)") end
    elseif cmd == "scale" then
        local scale = tonumber(rest)
        if scale and scale >= 0.5 and scale <= 3 then settings.scale = scale; display:Layout()
        else say("/ozs scale 1 (0.5–3)") end
    elseif cmd == "windup" then
        local wind = tonumber(rest)
        if rest == "auto" then settings.windup = nil
        elseif wind and wind >= 0.03 and wind <= 1.5 then settings.windup = wind
        else say("/ozs windup auto eller /ozs windup 0.5"); return end
        refreshSpeed(GetTime())
    elseif cmd == "debug" then
        settings.debug = rest == "on"
        if settings.debug then settings.events = {}; logSession() end
        say(settings.debug and "Diagnostik på, ny logg startad (senaste 1000 händelser sparas)." or "Diagnostik av.")
    elseif cmd == "panel" then
        ns.panel:Toggle()
    elseif cmd == "mark" then
        log("MARK", nil, {note = rest})
        say(settings.debug and ("Markering: " .. rest) or "Slå på diagnostik först: /ozs debug on")
    elseif cmd == "status" then
        local version, build = GetBuildInfo()
        say(string.format("Klient %s (%s). Fas: %s. Skott: %d. Speed %.3f, wind-up %.3f.",
            version, build, model.phase, model.shots, model.speed, model.wind))
        say("Wind-up: " .. (ns.windSource or "okänd") .. ". GCD läses från spell " .. gcdSpell ..
            ": " .. (model.gcdKnown and "tillgängligt" or "okänt"))
    else
        say("/ozs test · panel · unlock · lock · size 300 20 · scale 1 · status · debug on/off · mark <text> · windup auto/0.5 · reset")
    end
end

local function initialize()
    OzzySwingTimerDB = type(OzzySwingTimerDB) == "table" and OzzySwingTimerDB or {}
    settings = OzzySwingTimerDB
    for key, value in pairs(defaults) do
        if type(settings[key]) ~= type(value) then settings[key] = value end
    end
    settings.width = math.max(80, math.min(1200, settings.width))
    settings.height = math.max(8, math.min(100, settings.height))
    settings.scale = math.max(0.5, math.min(3, settings.scale))
    if not number(settings.windup) then settings.windup = nil end
    model, display = ns.Model:New(), ns.Display:New(settings)
    ns.model, ns.display = model, display
    ns.panel = ns.TestPanel:New(settings)
    SlashCmdList.OZZYSWINGTIMER = command
    SLASH_OZZYSWINGTIMER1 = "/ozs"
    local _, class = UnitClass("player")
    ns.isHunter = class == "HUNTER"
    pickGCDSpell(); refreshSpeed(GetTime()); readGCD(GetTime())
    say("Laddad. /ozs test visar baren, /ozs unlock flyttar den, /ozs lock låser.")
    if not ns.isHunter then say("Skottspårningen kräver en hunter. Testläget fungerar ändå.") end
    driver:SetScript("OnUpdate", function()
        local now = GetTime()
        if now >= nextPoll then
            nextPoll = now + 0.03
            readCast(now); readGCD(now)
        end
        if now >= nextSpeed then nextSpeed = now + 0.2; refreshSpeed(now) end
        if demo then
            display:Paint(demoView(now), true)
        else
            local isMoving = moving()
            model:Advance(now, isMoving)
            lastView = model:View(now, isMoving)
            display:Paint(lastView)
        end
    end)
end

driver:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == addonName then initialize() end
        return
    end
    if not model or not ns.isHunter then return end
    local now = GetTime()
    if event == "START_AUTOREPEAT_SPELL" then
        readCast(now); readGCD(now); refreshSpeed(now); model:Start(now, moving())
        log("AUTOREPEAT_ON", AUTO)
    elseif event == "STOP_AUTOREPEAT_SPELL" or event == "PLAYER_DEAD" or event == "PLAYER_LEAVING_WORLD" then
        model:Stop()
        log(event == "STOP_AUTOREPEAT_SPELL" and "AUTOREPEAT_OFF" or event, AUTO)
    elseif event == "PLAYER_ENTERING_WORLD" then
        pickGCDSpell(); refreshSpeed(now); readCast(now); readGCD(now); logSession()
    elseif event == "SPELLS_CHANGED" then pickGCDSpell()
    elseif event == "SPELL_UPDATE_COOLDOWN" then readGCD(now)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then learned = nil; refreshSpeed(now); model:Stop()
    elseif event == "UNIT_RANGEDDAMAGE" or event == "UNIT_ATTACK_SPEED" or event == "UNIT_AURA" then
        if ... == "player" then refreshSpeed(now) end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Position 15 is the failure reason for SPELL_CAST_FAILED and the amount for damage events.
        local _, subevent, _, source, _, _, _, _, _, _, _, spellID, _, _, arg15, _, _, _, _, absorbed, critical =
            CombatLogGetCurrentEventInfo()
        -- Only the player's own GUID: pet damage has its own source and is never logged.
        if source ~= UnitGUID("player") then return end
        if spellID == AUTO then
            if subevent == "SPELL_CAST_START" then windStart(now, "combatlog")
            elseif subevent == "SPELL_CAST_SUCCESS" then shot(now, "combatlog") end
        end
        -- The failure reason (e.g. not yet recovered) is only available in the combat log.
        if subevent == "SPELL_CAST_FAILED" then log("CLEU_FAILED", spellID, {reason = arg15}) end
        -- Damage per hit for break-even analysis: Auto Shot is RANGE_DAMAGE, abilities SPELL_DAMAGE.
        -- Multi-Shot logs one entry per target hit. Misses and immunities are not damage events.
        if (subevent == "RANGE_DAMAGE" or subevent == "SPELL_DAMAGE") and number(arg15) then
            log("DAMAGE", spellID, {amount = arg15, crit = critical and true or nil,
                absorbed = number(absorbed) and absorbed > 0 and absorbed or nil})
        end
    else
        local unit, _, arg3, arg4 = ...
        if unit ~= "player" then return end
        local spellID = arg3
        if event == "UNIT_SPELLCAST_SENT" then
            spellID = arg4
            if spellID and spellID ~= AUTO then
                log("CAST_SENT", spellID, {castTime = castTime(spellID) / 1000,
                    sinceShot = model.lastShot and now - model.lastShot,
                    windProgress = model.phase == "wind" and lastView and lastView.fill or nil})
            end
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            if spellID == AUTO then windStart(now, "unit")
            else
                readCast(now); readGCD(now)
                log("CAST_START", spellID, {sinceShot = model.lastShot and now - model.lastShot})
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if spellID == AUTO then shot(now, "unit")
            elseif spellID == 5384 then model:Stop()
            else readGCD(now); log("CAST_SUCCESS", spellID) end
        elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
            if spellID == AUTO then model:AutoFailed(now) end
            log(event, spellID)
        else readCast(now) end
    end
end)

local events = {"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_DEAD",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "SPELL_UPDATE_COOLDOWN",
    "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_SPEED", "UNIT_AURA",
    "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP"}
for _, event in ipairs(events) do pcall(driver.RegisterEvent, driver, event) end
ns.driver = driver
