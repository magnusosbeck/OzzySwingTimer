local _, ns = ...
local Display = {}
Display.__index = Display
ns.Display = Display

-- Built-in client art only: the casting bar's border and spark, and the classic status bar texture.
local STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"
local BORDER = "Interface\\CastingBar\\UI-CastingBar-Border"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FONT = "Fonts\\FRIZQT__.TTF"
-- Blizzard's casting bar is 195x13 inside a 256x64 border anchored 28 px above its top. The border is
-- cut into nine slices at the bar opening, so its thickness (settings.border) is independent of bar size.
local CAST_W, CAST_H, BORDER_W, BORDER_H, BORDER_TOP = 195, 13, 256, 64, 28
local SIDE = (BORDER_W - CAST_W) / 2
-- Only the metal edge above and below the opening; the rest of the texture is padding and shadow.
local EDGE = 10
-- Action-button art for the Auto Shot badge: Blizzard draws a 36 px icon in a 66 px slot frame.
local SLOT = "Interface\\Buttons\\UI-Quickslot2"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local FALLBACK_ICON = "Interface\\Icons\\INV_Weapon_Bow_07"
Display.BORDER = 0.8

local COLORS = {
    cooldown = {0.95, 0.72, 0.18},   -- slow phase: casting-bar gold
    ready = {0.25, 0.90, 0.30},      -- wind-up, press now: channel green
    out = {0.95, 0.20, 0.18},        -- wind-up out of phase, or blocked: failed-cast red
    lock = {0.30, 0.52, 1.00, 0.85}, -- cast/GCD occupancy
    stripe = {0.75, 0.86, 1.00, 0.45},
    melee = {0.80, 0.80, 0.85},       -- melee swing timer: steel
    worth = {1.00, 0.82, 0.25},      -- delay that paid off
    cost = {1.00, 0.30, 0.25},       -- delay that cost DPS
}
local function tint(texture, rgba) texture:SetVertexColor(rgba[1], rgba[2], rgba[3], rgba[4] or 1) end
local function bar(parent, layer)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetTexture(STATUSBAR)
    return texture
end
-- Slim secondary bar: dark 1 px edge, black background and a status bar fill.
local function subBar(parent)
    local f = CreateFrame("Frame", nil, parent)
    local edge = f:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.32, 0.32, 0.30, 0.9)
    local background = f:CreateTexture(nil, "BORDER")
    background:SetAllPoints(f)
    background:SetColorTexture(0, 0, 0, 0.75)
    f.fill = bar(f, "ARTWORK")
    f.fill:SetPoint("LEFT", f, "LEFT", 0, 0)
    f:Hide()
    return f
end

function Display:New(settings)
    local ui = setmetatable({settings = settings, regions = {}}, self)
    local frame = CreateFrame("Frame", "OzzySwingTimerBar", UIParent)
    ui.frame = frame
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        settings.x, settings.y = x - parentX, y - parentY
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
    end)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0, 0, 0, 0.6)
    ui.fill = bar(frame, "ARTWORK")

    ui.lockLayer = CreateFrame("Frame", nil, frame)
    ui.lockLayer:SetAllPoints(frame)
    ui.lockLayer:SetFrameLevel(frame:GetFrameLevel() + 1)
    local top = CreateFrame("Frame", nil, frame)
    top:SetAllPoints(frame)
    top:SetFrameLevel(frame:GetFrameLevel() + 3)
    ui.border = {}
    -- All nine slices: the centre carries the metal lip that overlaps the bar's own edge.
    for row = 1, 3 do
        for col = 1, 3 do
            local slice = top:CreateTexture(nil, "ARTWORK")
            slice:SetTexture(BORDER)
            local u = {0, SIDE, SIDE + CAST_W, BORDER_W}
            local v = {BORDER_TOP - EDGE, BORDER_TOP, BORDER_TOP + CAST_H, BORDER_TOP + CAST_H + EDGE}
            slice:SetTexCoord(u[col] / BORDER_W, u[col + 1] / BORDER_W, v[row] / BORDER_H, v[row + 1] / BORDER_H)
            slice.row, slice.col = row, col
            ui.border[#ui.border + 1] = slice
        end
    end
    ui.spark = top:CreateTexture(nil, "OVERLAY")
    ui.spark:SetTexture(SPARK)
    ui.spark:SetBlendMode("ADD")
    -- Auto Shot badge right of the bar, styled as an action button. On a delayed shot the icon greys,
    -- glows yellow (paid off, below break-even) or red (cost DPS) and shows the delay, e.g. "+0,8".
    ui.badge = CreateFrame("Frame", nil, frame)
    ui.badge:SetFrameLevel(frame:GetFrameLevel() + 4)
    ui.icon = ui.badge:CreateTexture(nil, "ARTWORK")
    ui.icon:SetAllPoints(ui.badge)
    ui.icon:SetTexture(GetSpellTexture and GetSpellTexture(75) or FALLBACK_ICON)
    ui.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ui.slot = ui.badge:CreateTexture(nil, "OVERLAY")
    ui.slot:SetTexture(SLOT)
    ui.slot:SetPoint("CENTER", ui.badge, "CENTER", 0, 0)
    ui.glow = ui.badge:CreateTexture(nil, "OVERLAY", nil, 1)
    ui.glow:SetTexture(GLOW)
    ui.glow:SetBlendMode("ADD")
    ui.glow:SetPoint("CENTER", ui.badge, "CENTER", 0, 0)
    ui.glow:Hide()
    ui.delay = ui.badge:CreateFontString(nil, "OVERLAY", "GameFontNormal", 2)
    ui.delay:SetPoint("CENTER", ui.badge, "CENTER", 0, 0)
    ui.delay:Hide()
    -- Below: a half-height cast bar with the spell name, then a thin melee swing timer,
    -- drawn above the border so nothing of it shows between the bars.
    ui.cast = subBar(frame)
    ui.cast:SetFrameLevel(frame:GetFrameLevel() + 4)
    tint(ui.cast.fill, COLORS.cooldown)
    ui.castText = ui.cast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.castText:SetPoint("CENTER", ui.cast, "CENTER", 0, 0)
    ui.melee = subBar(frame)
    ui.melee:SetFrameLevel(frame:GetFrameLevel() + 4)
    tint(ui.melee.fill, COLORS.melee)

    ui:Layout()
    return ui
end

function Display:Layout()
    local frame, settings = self.frame, self.settings
    frame:SetSize(settings.width, settings.height)
    frame:SetScale(settings.scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
    frame:EnableMouse(not settings.locked)
    local w, h, k = settings.width, settings.height, settings.border or Display.BORDER
    local xs = {-SIDE * k, 0, w, w + SIDE * k}
    local ys = {EDGE * k, 0, -h, -h - EDGE * k}
    for _, slice in ipairs(self.border) do
        slice:ClearAllPoints()
        slice:SetPoint("TOPLEFT", frame, "TOPLEFT", xs[slice.col], ys[slice.row])
        slice:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", xs[slice.col + 1], ys[slice.row + 1])
    end
    self.spark:SetSize(32 * h / CAST_H, 32 * h / CAST_H)
    local icon = math.floor(h * 1.6)
    self.badge:ClearAllPoints()
    self.badge:SetPoint("LEFT", frame, "RIGHT", 6 + 10 * k, 0)
    self.badge:SetSize(icon, icon)
    self.slot:SetSize(icon * 66 / 36, icon * 66 / 36)
    self.glow:SetSize(icon * 70 / 36, icon * 70 / 36)
    self.delay:SetFont(FONT, math.max(10, math.floor(icon * 0.42)), "OUTLINE")
    local castH, meleeH = math.max(6, math.floor(h / 2)), math.max(3, math.floor(h / 5))
    self.cast:ClearAllPoints()
    self.cast:SetPoint("TOP", frame, "BOTTOM", 0, -(2 + 3 * k))
    self.cast:SetSize(w, castH)
    self.cast.fill:SetHeight(castH)
    self.castText:SetFont(FONT, math.max(8, castH - 2), "OUTLINE")
    self.melee:ClearAllPoints()
    self.melee:SetPoint("TOP", self.cast, "BOTTOM", 0, -3)
    self.melee:SetSize(w, meleeH)
    self.melee.fill:SetHeight(meleeH)
end

-- cast: {name = , progress = 0..1} or nil; melee: swing progress 0..1 or nil.
function Display:PaintExtras(cast, melee)
    local w = self.settings.width
    if cast then
        self.cast.fill:SetWidth(math.max(0.001, w * cast.progress))
        self.castText:SetText(cast.name or "")
        self.cast:Show()
    else self.cast:Hide() end
    if melee then
        self.melee.fill:SetWidth(math.max(0.001, w * melee))
        self.melee:Show()
    else self.melee:Hide() end
end

function Display:Region(index)
    if self.regions[index] then return self.regions[index] end
    local region = CreateFrame("Frame", nil, self.lockLayer)
    if region.SetClipsChildren then region:SetClipsChildren(true) end
    region.background = bar(region, "BACKGROUND")
    region.background:SetAllPoints(region)
    tint(region.background, COLORS.lock)
    region.stripes = {}
    self.regions[index] = region
    return region
end

function Display:Paint(view, forceVisible)
    if view.phase == "idle" and self.settings.locked and not forceVisible then self.frame:Hide(); return end
    self.frame:Show()
    local width, height = self.settings.width, self.settings.height
    -- Explicit anchors avoid changing the pendulum's endpoint on the phase turn.
    self.fill:ClearAllPoints()
    if view.phase == "cooldown" or view.phase == "blocked" then
        self.fill:SetPoint("RIGHT", self.frame, "RIGHT", 0, 0)
    else self.fill:SetPoint("LEFT", self.frame, "LEFT", 0, 0) end
    self.fill:SetSize(math.max(0.001, width * view.fill), height)
    if view.phase == "wind" then tint(self.fill, view.green and COLORS.ready or COLORS.out)
    elseif view.phase == "blocked" then tint(self.fill, COLORS.out)
    else tint(self.fill, COLORS.cooldown) end

    local visible = 0
    for i, segment in ipairs(view.segments or {}) do
        local region = self:Region(i)
        local regionWidth = math.max(0.001, segment.width * width)
        region:ClearAllPoints()
        region:SetPoint("LEFT", self.frame, "LEFT", segment.left * width, 0)
        region:SetSize(regionWidth, height)
        region:Show()
        local count = math.ceil((regionWidth + height * 2) / 8)
        for stripe = 1, count do
            local texture = region.stripes[stripe]
            if not texture then
                texture = region:CreateTexture(nil, "ARTWORK")
                texture:SetColorTexture(1, 1, 1)
                tint(texture, COLORS.stripe)
                texture:SetBlendMode("ADD")
                texture:SetRotation(-math.pi / 4)
                region.stripes[stripe] = texture
            end
            texture:ClearAllPoints()
            texture:SetPoint("CENTER", region, "LEFT", (stripe - 1) * 8 - height, 0)
            texture:SetSize(3, height * 2)
            texture:Show()
        end
        for stripe = count + 1, #region.stripes do region.stripes[stripe]:Hide() end
        visible = i
    end
    for i = visible + 1, #self.regions do self.regions[i]:Hide() end

    self.spark:ClearAllPoints()
    self.spark:SetPoint("CENTER", self.frame, "LEFT", view.cursor * width, 0)
    if view.phase == "idle" then self.spark:Hide() else self.spark:Show() end
    if view.delay then
        self.delay:SetText((string.format("+%.1f", view.delay):gsub("%.", ",")))
        local c = view.delayWorthIt and COLORS.worth or COLORS.cost
        self.delay:SetTextColor(c[1], c[2], c[3])
        self.delay:Show()
        self.glow:SetVertexColor(c[1], c[2], c[3], 1)
        self.glow:Show()
        self.icon:SetDesaturated(true)
    else
        self.delay:Hide(); self.glow:Hide()
        self.icon:SetDesaturated(false)
    end
    -- The badge belongs to the running timer, not to an idle bar shown for casting or melee only.
    if view.phase == "idle" then self.badge:Hide() else self.badge:Show() end
end
