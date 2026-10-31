local addonName, ns = ...
local AUTO, GCD = 75, 61304
local driver = CreateFrame("Frame")
local model, display, settings, demo, lastView, lastViewAt
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
    log("SESSION", nil, extra)
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
        local ok, info = pcall(C_Spell.GetSpellCooldown, GCD)
        if ok and type(info) == "table" then
            start, duration, rate = info.startTime, info.duration, info.modRate
        end
    end
    if not number(start) and GetSpellCooldown then
        local ok, a, b, _, r = pcall(GetSpellCooldown, GCD)
        if ok then start, duration, rate = a, b, r end
    end
    local known = number(start) and number(duration)
    if known and number(rate) and rate > 0 then duration = duration / rate end
    local before = model.gcdStart
    model:SetGCD(start, duration, now, known)
    if model.gcdStart > 0 and model.gcdStart ~= before then
        log("GCD", GCD, {gcdStart = model.gcdStart, gcdDuration = model.gcdEnd - model.gcdStart})
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
        if info and number(info.castTime) then return info.castTime end
    end
    if GetSpellInfo then
        local _, _, _, duration = GetSpellInfo(spellID)
        if number(duration) then return duration end
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
    if model.lastShot and now - model.lastShot < 0.08 then return end
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
    state.flashSerial = cycle + 1
    return state:View(now, false), state
end

local function command(message)
    local cmd, rest = message:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "test" then
        demo = not demo and {started = GetTime()} or nil
        display.lastFlash, display.flashStart = 0, nil
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
    elseif cmd == "mark" then
        log("MARK", nil, {note = rest})
        say(settings.debug and ("Markering: " .. rest) or "Slå på diagnostik först: /ozs debug on")
    elseif cmd == "status" then
        local version, build = GetBuildInfo()
        say(string.format("Klient %s (%s). Fas: %s. Skott: %d. Speed %.3f, wind-up %.3f.",
            version, build, model.phase, model.shots, model.speed, model.wind))
        say("Wind-up: " .. (ns.windSource or "okänd") .. ". GCD-API: " .. (model.gcdKnown and "tillgängligt" or "okänt"))
    else
        say("/ozs test · unlock · lock · size 300 20 · scale 1 · status · debug on/off · mark <text> · windup auto/0.5 · reset")
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
    SlashCmdList.OZZYSWINGTIMER = command
    SLASH_OZZYSWINGTIMER1 = "/ozs"
    local _, class = UnitClass("player")
    ns.isHunter = class == "HUNTER"
    refreshSpeed(GetTime()); readGCD(GetTime())
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
            local view, state = demoView(now)
            display:Paint(view, now, state, true)
        else
            local isMoving = moving()
            model:Advance(now, isMoving)
            lastView, lastViewAt = model:View(now, isMoving), now
            display:Paint(lastView, now, model)
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
        refreshSpeed(now); readCast(now); readGCD(now); logSession()
    elseif event == "SPELL_UPDATE_COOLDOWN" then readGCD(now)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then learned = nil; refreshSpeed(now); model:Stop()
    elseif event == "UNIT_RANGEDDAMAGE" or event == "UNIT_ATTACK_SPEED" or event == "UNIT_AURA" then
        if ... == "player" then refreshSpeed(now) end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, source, _, _, _, _, _, _, _, spellID, _, _, reason = CombatLogGetCurrentEventInfo()
        if source ~= UnitGUID("player") then return end
        if spellID == AUTO then
            if subevent == "SPELL_CAST_START" then windStart(now, "combatlog")
            elseif subevent == "SPELL_CAST_SUCCESS" then shot(now, "combatlog") end
        end
        -- The failure reason (e.g. not yet recovered) is only available in the combat log.
        if subevent == "SPELL_CAST_FAILED" then log("CLEU_FAILED", spellID, {reason = reason}) end
    else
        local unit, arg2, arg3, arg4 = ...
        if unit ~= "player" then return end
        local guid, spellID = arg2, arg3
        if event == "UNIT_SPELLCAST_SENT" then
            guid, spellID = arg3, arg4
            if spellID and spellID ~= AUTO then
                local duration = castTime(spellID)
                local window = model:QueueWindow(now, moving())
                -- SENT can arrive after the client has already applied the new GCD.
                local recent = lastView and lastView.window and lastView.window.open and
                    lastViewAt and now - lastViewAt < 0.1 and now <= lastView.window.finish
                local inWindow = (window and window.open) or recent or false
                if duration > 0 then model:Sent(spellID, guid, now, inWindow) end
                log("CAST_SENT", spellID, {castTime = duration / 1000, inWindow = inWindow,
                    windProgress = model.phase == "wind" and lastView and lastView.fill or nil})
            end
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            if spellID == AUTO then windStart(now, "unit")
            else readCast(now); readGCD(now); model:Confirm(spellID, guid, now); log("CAST_START", spellID) end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if spellID == AUTO then shot(now, "unit")
            elseif spellID == 5384 then model:Stop()
            else model:Confirm(spellID, guid, now); readGCD(now); log("CAST_SUCCESS", spellID) end
        elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
            if spellID == AUTO then model:AutoFailed(now) else model:Failed(spellID, guid) end
            log(event, spellID)
        else readCast(now) end
    end
end)

local events = {"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_DEAD",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "SPELL_UPDATE_COOLDOWN",
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_SPEED", "UNIT_AURA",
    "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP"}
for _, event in ipairs(events) do pcall(driver.RegisterEvent, driver, event) end
ns.driver = driver
