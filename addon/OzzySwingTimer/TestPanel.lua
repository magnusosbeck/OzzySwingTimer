local _, ns = ...
local TestPanel = {}
TestPanel.__index = TestPanel
ns.TestPanel = TestPanel

-- In-game test protocol: each button writes a /ozs mark so the log can be split per test.
local STEPS = {
    {note = "auto", label = "1 Auto Shot", short = "Bara Auto Shot, cirka 15 skott.",
        text = "Skjut bara Auto Shot, cirka 15 skott."},
    {note = "steady tidigt", label = "2 Steady tidigt", short = "Steady direkt när wind-up börjar.",
        text = "Tryck Steady Shot direkt när baren vänder till wind-up. En gång per cykel, cirka 5 gånger."},
    {note = "steady sent", label = "3 Steady sent", short = "Steady i slutet av wind-up.",
        text = "Tryck Steady Shot i slutet av wind-up, precis före skottet. En gång per cykel, cirka 5 gånger."},
    {note = "steady långsam", label = "4 Steady långsam", short = "Steady mitt i långsamma fasen.",
        text = "Tryck Steady Shot mitt i den långsamma fasen, cirka 5 gånger."},
    {note = "arcane", label = "5 Arcane", short = "Arcane mitt i långsamma fasen.",
        text = "Tryck Arcane Shot mitt i den långsamma fasen, cirka 5 gånger."},
    {note = "rotation", label = "6 Rotation", short = "Steady + Arcane i samma cykel.",
        text = "Steady Shot och sedan Arcane Shot i samma cykel, cirka 10 cykler."},
    {note = "aimed", label = "7 Aimed", short = "Aimed Shot 2-3 gånger.",
        text = "Tryck Aimed Shot 2-3 gånger. Låt Auto Shot gå emellan."},
    {note = "rörelse", label = "8 Rörelse", short = "Ett steg under wind-up.",
        text = "Ta ett steg under wind-up några gånger."},
}
local WIDTH, PAD, GAP, BUTTON_H = 280, 8, 8, 22
local HALF = (WIDTH - 2 * PAD - GAP) / 2
local THIRD = (WIDTH - 2 * PAD - 2 * GAP) / 3
local GRID_TOP, CELL_H = 104, 52

local function run(command) SlashCmdList.OZZYSWINGTIMER(command) end

function TestPanel:New(settings)
    local panel = setmetatable({settings = settings, step = nil, startShots = 0, nextRefresh = 0, buttons = {}}, self)
    local function button(parent, label, width, onClick)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(width, BUTTON_H)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        panel.buttons[#panel.buttons + 1] = b
        return b
    end
    local function place(widget, x, y) widget:SetPoint("TOPLEFT", panel.frame, "TOPLEFT", x, -y) end

    local frame = CreateFrame("Frame", "OzzySwingTimerTestPanel", UIParent)
    panel.frame = frame
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        settings.panelX, settings.panelY = x - parentX, y - parentY
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", settings.panelX, settings.panelY)
    end)
    local rows = math.ceil(#STEPS / 2)
    frame:SetSize(WIDTH, GRID_TOP + rows * CELL_H + 44)
    frame:SetPoint("CENTER", UIParent, "CENTER", settings.panelX or 300, settings.panelY or 100)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0.03, 0.04, 0.03, 0.92)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    place(title, PAD, PAD)
    title:SetText("Ozzy Swing Timer · Tester")
    local close = button(frame, "X", 24, function() panel:Toggle() end)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    panel.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    place(panel.status, PAD, 28)
    panel.status:SetJustifyH("LEFT")

    -- Log and bar tools: the same commands as /ozs debug on, /reload, test, unlock/lock and status.
    place(button(frame, "Ny logg", HALF, function()
        run("debug on"); panel.step = nil; panel:Refresh(true)
    end), PAD, 44)
    place(button(frame, "Spara (/reload)", HALF, function() ReloadUI() end), PAD + HALF + GAP, 44)
    place(button(frame, "Testläge", THIRD, function() run("test") end), PAD, 70)
    panel.moveButton = button(frame, "Flytta", THIRD, function()
        run(settings.locked and "unlock" or "lock"); panel:Refresh(true)
    end)
    place(panel.moveButton, PAD + THIRD + GAP, 70)
    place(button(frame, "Status", THIRD, function() run("status") end), PAD + 2 * (THIRD + GAP), 70)

    for i, step in ipairs(STEPS) do
        local x = PAD + ((i - 1) % 2) * (HALF + GAP)
        local y = GRID_TOP + math.floor((i - 1) / 2) * CELL_H
        place(button(frame, step.label, HALF, function()
            run("mark " .. step.note)
            panel.step, panel.startShots = step, ns.model and ns.model.shots or 0
            panel:Refresh(true)
        end), x, y)
        local description = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        place(description, x + 2, y + BUTTON_H + 3)
        description:SetWidth(HALF - 4)
        description:SetJustifyH("LEFT")
        description:SetText(step.short)
    end

    panel.instruction = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    place(panel.instruction, PAD, GRID_TOP + rows * CELL_H + 4)
    panel.instruction:SetWidth(WIDTH - 2 * PAD)
    panel.instruction:SetJustifyH("LEFT")

    frame:SetScript("OnUpdate", function() panel:Refresh(false) end)
    frame:Hide()
    return panel
end

function TestPanel:Toggle()
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show(); self:Refresh(true) end
end

function TestPanel:Refresh(force)
    local now = GetTime()
    if not force and now < self.nextRefresh then return end
    self.nextRefresh = now + 0.2
    local logging = self.settings.debug
    local events = self.settings.events and #self.settings.events or 0
    local text = logging and string.format("Logg: på · %d händelser", events) or "Logg: av - tryck Ny logg först"
    if self.step and ns.model then
        text = text .. string.format(" · skott: %d", ns.model.shots - self.startShots)
    end
    self.status:SetText(text)
    self.moveButton:SetText(self.settings.locked and "Flytta" or "Lås")
    self.instruction:SetText(self.step and (self.step.label .. ": " .. self.step.text) or
        "Starta en ny logg, välj ett test och följ instruktionen. Spara med /reload när du är klar.")
end
