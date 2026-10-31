local _, ns = ...
local Display = {}
Display.__index = Display
ns.Display = Display

-- Built-in client art only: the casting bar's border and spark, and the classic status bar texture.
local STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"
local BORDER = "Interface\\CastingBar\\UI-CastingBar-Border"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FONT = "Fonts\\FRIZQT__.TTF"
-- Blizzard's casting bar is 195x13 with a 256x64 border anchored 28 px above its top; scale from that.
local CAST_W, CAST_H, BORDER_W, BORDER_H, BORDER_TOP = 195, 13, 256, 64, 28

local COLORS = {
    cooldown = {0.95, 0.72, 0.18},   -- slow phase: casting-bar gold
    ready = {0.25, 0.90, 0.30},      -- wind-up, press now: channel green
    out = {0.95, 0.20, 0.18},        -- wind-up out of phase, or blocked: failed-cast red
    lock = {0.30, 0.52, 1.00, 0.85}, -- cast/GCD occupancy
    stripe = {0.75, 0.86, 1.00, 0.45},
    worth = {1.00, 0.82, 0.25},      -- delay that paid off
    cost = {1.00, 0.30, 0.25},       -- delay that cost DPS
}
local function tint(texture, rgba) texture:SetVertexColor(rgba[1], rgba[2], rgba[3], rgba[4] or 1) end
local function bar(parent, layer)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetTexture(STATUSBAR)
    return texture
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
    ui.border = top:CreateTexture(nil, "ARTWORK")
    ui.border:SetTexture(BORDER)
    ui.spark = top:CreateTexture(nil, "OVERLAY")
    ui.spark:SetTexture(SPARK)
    ui.spark:SetBlendMode("ADD")
    -- Auto Shot delay of the last shot, right of the bar, e.g. "+0,8":
    -- yellow when an extra spell caused it and it stays below break-even, red otherwise.
    ui.delay = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.delay:Hide()

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
    local sx, sy = settings.width / CAST_W, settings.height / CAST_H
    self.border:ClearAllPoints()
    self.border:SetPoint("TOP", frame, "TOP", 0, BORDER_TOP * sy)
    self.border:SetSize(BORDER_W * sx, BORDER_H * sy)
    self.spark:SetSize(32 * sy, 32 * sy)
    self.delay:SetFont(FONT, math.max(11, math.floor(settings.height * 0.8)), "OUTLINE")
    self.delay:ClearAllPoints()
    self.delay:SetPoint("LEFT", frame, "RIGHT", 10 * sx, 0)
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
    else self.delay:Hide() end
end
