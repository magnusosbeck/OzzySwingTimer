local _, ns = ...
local Display = {}
Display.__index = Display
ns.Display = Display

local function color(texture, r, g, b, a) texture:SetColorTexture(r, g, b, a or 1) end
local function edge(parent, point1, point2, vertical, thickness, r, g, b)
    local texture = parent:CreateTexture(nil, "OVERLAY")
    texture:SetPoint(point1, parent, point1)
    texture:SetPoint(point2, parent, point2)
    if vertical then texture:SetWidth(thickness) else texture:SetHeight(thickness) end
    color(texture, r, g, b)
    return texture
end
local function border(parent, thickness, r, g, b)
    edge(parent, "TOPLEFT", "TOPRIGHT", false, thickness, r, g, b)
    edge(parent, "BOTTOMLEFT", "BOTTOMRIGHT", false, thickness, r, g, b)
    edge(parent, "TOPLEFT", "BOTTOMLEFT", true, thickness, r, g, b)
    edge(parent, "TOPRIGHT", "BOTTOMRIGHT", true, thickness, r, g, b)
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
    color(background, 0.025, 0.035, 0.025)
    border(frame, 1, 0.43, 0.46, 0.36)
    ui.fill = frame:CreateTexture(nil, "ARTWORK")

    ui.lockLayer = CreateFrame("Frame", nil, frame)
    ui.lockLayer:SetAllPoints(frame)
    ui.lockLayer:SetFrameLevel(frame:GetFrameLevel() + 1)
    local cursorFrame = CreateFrame("Frame", nil, frame)
    cursorFrame:SetAllPoints(frame)
    cursorFrame:SetFrameLevel(frame:GetFrameLevel() + 3)
    ui.cursor = cursorFrame:CreateTexture(nil, "OVERLAY")
    color(ui.cursor, 1, 0.98, 0.90)
    -- Auto Shot delay of the last shot, right of the bar, e.g. "+0,8":
    -- yellow when an extra spell caused it and it stays below break-even, red otherwise.
    ui.delay = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.delay:SetPoint("LEFT", frame, "RIGHT", 6, 0)
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
end

function Display:Region(index)
    if self.regions[index] then return self.regions[index] end
    local region = CreateFrame("Frame", nil, self.lockLayer)
    if region.SetClipsChildren then region:SetClipsChildren(true) end
    region.background = region:CreateTexture(nil, "BACKGROUND")
    region.background:SetAllPoints(region)
    color(region.background, 0.29, 0.42, 0.62, 0.95)
    region.stripes = {}
    self.regions[index] = region
    return region
end

function Display:Paint(view, forceVisible)
    if view.phase == "idle" and self.settings.locked and not forceVisible then self.frame:Hide(); return end
    self.frame:Show()
    local width, height = self.settings.width - 4, self.settings.height - 4
    -- Explicit anchors avoid changing the pendulum's endpoint on the phase turn.
    self.fill:ClearAllPoints()
    if view.phase == "cooldown" or view.phase == "blocked" then
        self.fill:SetPoint("RIGHT", self.frame, "RIGHT", -2, 0)
    else self.fill:SetPoint("LEFT", self.frame, "LEFT", 2, 0) end
    self.fill:SetSize(math.max(0.001, width * view.fill), height)
    if view.phase == "wind" then
        if view.green then color(self.fill, 0.76, 0.93, 0.52) else color(self.fill, 0.94, 0.41, 0.41) end
    elseif view.phase == "blocked" then color(self.fill, 1, 0.47, 0.47)
    else color(self.fill, 0.76, 0.93, 0.52) end

    local visible = 0
    for i, segment in ipairs(view.segments or {}) do
        local region = self:Region(i)
        local regionWidth = math.max(0.001, segment.width * width)
        region:ClearAllPoints()
        region:SetPoint("LEFT", self.frame, "LEFT", 2 + segment.left * width, 0)
        region:SetSize(regionWidth, height)
        region:Show()
        local count = math.ceil((regionWidth + height * 2) / 8)
        for stripe = 1, count do
            local texture = region.stripes[stripe]
            if not texture then
                texture = region:CreateTexture(nil, "ARTWORK")
                color(texture, 0.60, 0.77, 0.98, 0.9)
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

    self.cursor:ClearAllPoints()
    self.cursor:SetPoint("CENTER", self.frame, "LEFT", 2 + view.cursor * width, 0)
    self.cursor:SetSize(2, height)
    if view.phase == "idle" then self.cursor:Hide() else self.cursor:Show() end
    if view.delay then
        self.delay:SetText((string.format("+%.1f", view.delay):gsub("%.", ",")))
        if view.delayWorthIt then self.delay:SetTextColor(0.95, 0.80, 0.30)
        else self.delay:SetTextColor(1, 0.35, 0.35) end
        self.delay:Show()
    else self.delay:Hide() end

end
