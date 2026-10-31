local _, ns = ...
local Model = {}
Model.__index = Model
ns.Model = Model

local EPS = 0.0001
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
    self.locks, self.pending, self.shots = {}, nil, 0
    self.flashSerial, self.flashAt = 0, nil
    self.retryAt, self.waitingForShot = 0, false
end

function Model:Stop()
    self.active, self.phase = false, "idle"
    self.pending, self.observedWindStart, self.waitingForShot = nil, nil, false
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

function Model:EndCast(now)
    if self.castKey and self.castEnd > now then
        self:UpsertLock("cast", self.castKey, self.castStart, now)
    end
    self.castStart, self.castEnd, self.castKey = 0, 0, nil
end

function Model:SetCast(start, finish, key, now)
    if not start or not finish or finish <= now then self:EndCast(now); return end
    if self.castKey and self.castKey ~= key then self:EndCast(now) end
    self.castStart, self.castEnd, self.castKey = start, finish, key
    self:UpsertLock("cast", key, start, finish)
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

function Model:QueueWindow(now, moving)
    if not self.active or self.phase ~= "wind" or not self.gcdKnown or moving then return nil end
    local start = max(self.windStart, self.castEnd, self.gcdEnd)
    -- Retain completed action intervals so the full window does not shrink with the cursor.
    for _, lock in ipairs(self.locks) do start = max(start, lock.finish) end
    start = min(start, self.windEnd)
    local duration = max(0, self.windEnd - start)
    return {start = start, finish = self.windEnd, duration = duration,
        left = clamp((start - self.windStart) / (self.windEnd - self.windStart), 0, 1),
        open = duration > EPS and now >= start - EPS and now < self.windEnd + EPS}
end

function Model:Sent(spellID, castGUID, now, eligible)
    if not eligible or (self.pending and now < self.pending.expires) then return end
    self.pending = {spellID = spellID, guid = castGUID, sent = now,
        shots = self.shots, expires = now + 3}
end

function Model:MatchesPending(spellID, castGUID)
    local pending = self.pending
    return pending and pending.spellID == spellID and
        (not pending.guid or not castGUID or pending.guid == castGUID)
end

function Model:Confirm(spellID, castGUID, now)
    if not self:MatchesPending(spellID, castGUID) then return false end
    local pending = self.pending
    if now > pending.expires then self.pending = nil; return false end
    pending.confirmed = true
    if self.shots == pending.shots + 1 then
        self.flashSerial, self.flashAt = self.flashSerial + 1, now
        self.pending = nil
        return true
    end
    return false
end

function Model:Failed(spellID, castGUID)
    if self:MatchesPending(spellID, castGUID) then self.pending = nil end
end

function Model:Shot(now)
    if self.lastShot and now - self.lastShot < 0.08 then return false end
    self.shots = self.shots + 1
    self.active, self.phase = true, "cooldown"
    self.lastShot, self.cooldownStart = now, now
    self.cooldownEnd = now + self.speed - self.wind
    self.observedWindStart, self.waitingForShot, self.retryAt = nil, false, 0
    if self.pending and self.pending.confirmed then
        self:Confirm(self.pending.spellID, self.pending.guid, now)
    end
    return true
end

function Model:AutoFailed(now)
    if not self.active then return end
    -- A failed attempt during cooldown does not erase the weapon's cooldown.
    self.retryAt = now + 0.5
    if self.phase ~= "cooldown" then
        self.phase, self.observedWindStart, self.waitingForShot = "blocked", nil, false
    end
end

function Model:Advance(now, moving)
    if self.pending and now > self.pending.expires then self.pending = nil end
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

function Model:Segments()
    if self.phase ~= "cooldown" and self.phase ~= "blocked" then return {} end
    if not self.cooldownStart or not self.cooldownEnd then return {} end
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
        return {phase = "cooldown", fill = p, cursor = 1 - p, segments = self:Segments()}
    end
    if self.phase == "wind" then
        local p = clamp((now - self.windStart) / (self.windEnd - self.windStart), 0, 1)
        local window = self:QueueWindow(now, moving)
        return {phase = "wind", fill = p, cursor = p, green = window and window.open,
            window = window, segments = {}}
    end
    return {phase = "blocked", fill = 1, cursor = 0, segments = self:Segments()}
end
