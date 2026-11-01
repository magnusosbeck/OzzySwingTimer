local _, ns = ...
local Model = {}
Model.__index = Model
ns.Model = Model

local EPS = 0.0001
-- No real Auto Shot follows another this fast; closer reports are duplicates.
Model.MIN_SHOT_GAP = 0.5
-- Shot-to-shot jitter without clipping was about ±0.1 s in TBC 2.5.6; smaller delays are noise.
Model.DELAY_THRESHOLD = 0.15
-- Observed: a Steady Shot pressed up to 0.16 s before the reported wind-up start was still queued to
-- the shot (the report arrives after latency). Presses within SpellQueueWindow (400 ms) count as queued.
Model.PRESS_LEAD = 0.4
-- Delay an extra spell may cost and still gain DPS (break-even). Measured ~1.3 s for Arcane at 2.29 s.
Model.BREAK_EVEN = 1.3
local min, max = math.min, math.max
local function clamp(value, low, high) return max(low, min(high, value)) end

function Model:New()
    local model = setmetatable({speed = 2.8, wind = 0.5}, self)
    model:Reset()
    return model
end

function Model:Reset()
    self.active, self.phase = false, "idle"
    self.lastShot, self.cooldownStart, self.cooldownEnd = nil, nil, nil
    self.windStart, self.windEnd, self.observedWindStart = nil, nil, nil
    self.castStart, self.castEnd, self.castKey = 0, 0, nil
    self.gcdStart, self.gcdEnd, self.gcdKnown = 0, 0, false
    self.locks, self.shots, self.actions = {}, 0, {}
    self.lastDelay, self.continuous = nil, false
    self.delayWorthIt, self.extraSpellAt, self.shotBefore = false, nil, nil
    self.breakEven = self.breakEven or Model.BREAK_EVEN
    self.retryAt, self.waitingForShot = 0, false
end

function Model:Stop(now)
    self.active, self.phase = false, "idle"
    self.observedWindStart, self.waitingForShot = nil, false
    self.continuous = false
    -- A new run must not paint the previous fight's cycle, locks or delay.
    self.cooldownStart, self.cooldownEnd, self.windStart, self.windEnd = nil, nil, nil, nil
    self.lastDelay, self.delayWorthIt = nil, false
    local keep, keepActions = {}, {}
    for _, lock in ipairs(self.locks) do
        if now and lock.finish > now then keep[#keep + 1] = lock end
    end
    for _, action in ipairs(self.actions) do
        if now and action.finish > now then keepActions[#keepActions + 1] = action end
    end
    self.locks, self.actions = keep, keepActions
end

function Model:SetTiming(speed, wind, now)
    if type(speed) ~= "number" or speed <= 0 then return end
    speed = clamp(speed, 0.1, 15)
    wind = clamp(wind or self.wind, 0.03, min(1.5, speed * 0.95))
    if math.abs(speed - self.speed) < EPS and math.abs(wind - self.wind) < EPS then return end
    if self.phase == "cooldown" and self.cooldownStart then
        local progress = clamp((now - self.cooldownStart) / (self.speed - self.wind), 0, 1)
        self.cooldownStart = now - progress * (speed - wind)
        self.cooldownEnd = self.cooldownStart + speed - wind
    elseif self.phase == "wind" and self.windStart then
        if not self.observedWindStart then
            local progress = clamp((now - self.windStart) / self.wind, 0, 1)
            self.windStart = now - progress * wind
        end
        self.windEnd = self.windStart + wind
    end
    self.speed, self.wind = speed, wind
end

function Model:BeginWind(now, observed, finish)
    self.active, self.phase = true, "wind"
    self.windStart = now
    self.windEnd = finish and max(now + 0.03, finish) or now + self.wind
    self.observedWindStart = observed and now or nil
    self.waitingForShot, self.retryAt = false, 0
end

function Model:Start(now, moving)
    if self.active then return end
    self.active = true
    if moving or self.castEnd > now + EPS then
        self.phase, self.retryAt = "blocked", now
    else
        self:BeginWind(now, false)
    end
end

function Model:UpsertLock(kind, key, start, finish)
    if not start or not finish or finish <= start then return end
    for i = #self.locks, 1, -1 do
        local lock = self.locks[i]
        if lock.kind == kind and lock.key == key then
            lock.start, lock.finish = start, finish
            return
        end
    end
    self.locks[#self.locks + 1] = {kind = kind, key = key, start = start, finish = finish}
    if #self.locks > 64 then table.remove(self.locks, 1) end
end

-- A named spell press for the slow-phase labels: from its start until both its cast and the GCD it
-- triggered are over. gcdEnd is kept so an interrupted cast still occupies its GCD.
function Model:Action(key, name, start, finish, gcdEnd)
    if not key or not start or not finish or finish <= start then return end
    for _, action in ipairs(self.actions) do
        if action.key == key then
            action.name, action.start, action.finish, action.gcdEnd = name, start, finish, gcdEnd
            return action
        end
    end
    local action = {key = key, name = name, start = start, finish = finish, gcdEnd = gcdEnd}
    self.actions[#self.actions + 1] = action
    if #self.actions > 32 then table.remove(self.actions, 1) end
    return action
end
function Model:FindAction(key)
    for _, action in ipairs(self.actions) do if action.key == key then return action end end
end

function Model:EndCast(now)
    if self.castKey and self.castEnd > now then
        self:UpsertLock("cast", self.castKey, self.castStart, now)
        local action = self:FindAction(self.castKey)
        if action then action.finish = max(now, action.gcdEnd or 0) end
    end
    self.castStart, self.castEnd, self.castKey = 0, 0, nil
end

function Model:SetCast(start, finish, key, now)
    if not start or not finish or finish <= now then self:EndCast(now); return end
    if self.castKey and self.castKey ~= key then self:EndCast(now) end
    self.castStart, self.castEnd, self.castKey = start, finish, key
    self:UpsertLock("cast", key, start, finish)
    local action = self:FindAction(key)
    if action then action.finish = max(finish, action.gcdEnd or 0) end
end

function Model:SetGCD(start, duration, now, known)
    self.gcdKnown = known == true
    if not known then return end
    if start and duration and duration > 0 and start + duration > now then
        self.gcdStart, self.gcdEnd = start, start + duration
        self:UpsertLock("gcd", string.format("%.4f", start), start, self.gcdEnd)
    else
        if self.gcdStart > 0 and self.gcdEnd > now then
            self:UpsertLock("gcd", string.format("%.4f", self.gcdStart), self.gcdStart, now)
        end
        self.gcdStart, self.gcdEnd = 0, 0
    end
end

-- Wind-up says "press now" when everything started before it (cast, GCD) ends by the shot.
-- Otherwise the player is out of phase and should let one Auto Shot pass untouched.
-- A press during or just before this wind-up starts a new GCD; that one must not turn the bar red.
function Model:InPhase(moving)
    if not self.gcdKnown or moving or not self.windStart then return false end
    local ready = 0
    for _, lock in ipairs(self.locks) do
        if lock.start < self.windStart - Model.PRESS_LEAD then ready = max(ready, lock.finish) end
    end
    return ready <= self.windEnd + EPS
end

-- A GCD spell besides the main cast (e.g. Arcane Shot) that may justify a delayed shot.
function Model:ExtraSpell(now) self.extraSpellAt = now end

function Model:Shot(now)
    if self.lastShot and now - self.lastShot < Model.MIN_SHOT_GAP then return false end
    -- Delay versus an undisturbed cycle; only between shots of one continuous Auto Shot run.
    local delay = self.continuous and self.lastShot and now - self.lastShot - self.speed
    self.lastDelay = delay and delay >= Model.DELAY_THRESHOLD and delay < self.speed and delay or nil
    -- An extra spell's GCD often costs time only in the following cycle, so look back two cycles.
    local since = self.shotBefore or self.lastShot
    self.delayWorthIt = self.lastDelay ~= nil and self.extraSpellAt ~= nil and since ~= nil and
        self.extraSpellAt > since and self.lastDelay <= self.breakEven
    self.shotBefore = self.continuous and self.lastShot or nil
    self.continuous = true
    self.shots = self.shots + 1
    self.active, self.phase = true, "cooldown"
    self.lastShot, self.cooldownStart = now, now
    self.cooldownEnd = now + self.speed - self.wind
    self.observedWindStart, self.waitingForShot, self.retryAt = nil, false, 0
    return true
end

function Model:AutoFailed(now)
    if not self.active then return end
    -- Observed in TBC 2.5.6: pressing a spell during an observed wind-up reports a failure,
    -- yet the shot still fires. Advance() blocks if no release follows.
    if self.phase == "wind" and self.observedWindStart then return end
    -- A failed attempt during cooldown does not erase the weapon's cooldown.
    self.retryAt = now + 0.5
    if self.phase ~= "cooldown" then
        self.phase, self.observedWindStart, self.waitingForShot = "blocked", nil, false
    end
end

function Model:Advance(now, moving)
    if not self.active then return end
    if self.phase == "cooldown" and now >= self.cooldownEnd then
        if moving or self.castEnd > now + EPS or now < self.retryAt then
            self.phase = "blocked"
        else
            self:BeginWind(self.cooldownEnd, false)
        end
    elseif self.phase == "wind" then
        if moving or (self.castEnd > now + EPS and not self.observedWindStart) then
            self.phase, self.observedWindStart = "blocked", nil
        elseif now > self.windEnd + 0.25 then
            -- Never invent a release or roll into another cooldown without a shot event.
            self.phase, self.waitingForShot = "blocked", true
        end
    elseif self.phase == "blocked" and not self.waitingForShot and
        not moving and self.castEnd <= now + EPS and now >= self.retryAt then
        self:BeginWind(now, false)
    end
end

-- Named actions in the slow phase, one segment each with the spell name. A segment that does not fit
-- before wind-up continues past the bar's left wall as an overflow piece (capped at one slow phase).
function Model:ActionSegments()
    local ws, we = self.cooldownStart, self.cooldownEnd
    local len = we - ws
    local sorted = {}
    for _, action in ipairs(self.actions) do
        if action.start < we and action.finish > ws then sorted[#sorted + 1] = action end
    end
    if #sorted == 0 then return nil end
    table.sort(sorted, function(a, b) return a.start < b.start end)
    local result, previous = {}, ws
    for _, action in ipairs(sorted) do
        local a, b = max(ws, action.start, previous), action.finish
        if b > a + EPS then
            local inside = min(we, b)
            if inside > a + EPS then
                result[#result + 1] = {left = (we - inside) / len, width = (inside - a) / len, name = action.name}
            end
            if b > we + EPS then
                local o0, o1 = max(a, we), min(b, we + len)
                result[#result + 1] = {left = (we - o1) / len, width = (o1 - o0) / len, overflow = true,
                    name = inside <= a + EPS and action.name or nil}
            end
            previous = b
        end
    end
    return result
end

function Model:Segments()
    if self.phase ~= "cooldown" and self.phase ~= "blocked" then return {} end
    if not self.cooldownStart or not self.cooldownEnd then return {} end
    local named = self:ActionSegments()
    if named then return named end
    local start, finish = self.cooldownStart, self.cooldownEnd
    local intervals = {}
    for _, lock in ipairs(self.locks) do
        local a, b = max(start, lock.start), min(finish, lock.finish)
        if b > a then intervals[#intervals + 1] = {start = a, finish = b} end
    end
    table.sort(intervals, function(a, b) return a.start < b.start end)
    local merged = {}
    for _, interval in ipairs(intervals) do
        local last = merged[#merged]
        if last and interval.start <= last.finish + EPS then
            last.finish = max(last.finish, interval.finish)
        else merged[#merged + 1] = interval end
    end
    local result = {}
    for _, interval in ipairs(merged) do
        result[#result + 1] = {left = (finish - interval.finish) / (finish - start),
            width = (interval.finish - interval.start) / (finish - start)}
    end
    return result
end

function Model:View(now, moving)
    if self.phase == "idle" then return {phase = "idle", fill = 0, cursor = 1, segments = {}} end
    if self.phase == "cooldown" then
        local p = clamp((now - self.cooldownStart) / (self.cooldownEnd - self.cooldownStart), 0, 1)
        return {phase = "cooldown", fill = p, cursor = 1 - p, segments = self:Segments(), delay = self.lastDelay,
            delayWorthIt = self.delayWorthIt}
    end
    if self.phase == "wind" then
        local p = clamp((now - self.windStart) / (self.windEnd - self.windStart), 0, 1)
        return {phase = "wind", fill = p, cursor = p, green = self:InPhase(moving), segments = {},
            delay = self.lastDelay, delayWorthIt = self.delayWorthIt}
    end
    -- Before the first shot of a run (opening, still moving) waiting is normal, not a warning:
    -- an empty, calm bar without lock stripes.
    if not self.continuous then
        return {phase = "blocked", fill = 0, cursor = 0, segments = {}, opening = true}
    end
    return {phase = "blocked", fill = 1, cursor = 0, segments = self:Segments(), delay = self.lastDelay,
        delayWorthIt = self.delayWorthIt}
end
