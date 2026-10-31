local _, ns = ...
local TestPanel = {}
TestPanel.__index = TestPanel
ns.TestPanel = TestPanel

-- In-game test protocol: each button writes a /ozs mark so the log can be split per test.
local STEPS = {
    {note = "auto", label = "1 Auto Shot", text = "Skjut bara Auto Shot, cirka 15 skott."},
    {note = "steady röd", label = "2 Steady röd", text = "Tryck Steady Shot precis när baren blir röd. En gång per cykel, cirka 5 gånger."},
    {note = "steady grön", label = "3 Steady grön", text = "Tryck Steady Shot i den gröna zonen. En gång per cykel, cirka 5 gånger."},
    {note = "steady långsam", label = "4 Steady långsam", text = "Tryck Steady Shot mitt i den långsamma fasen, cirka 5 gånger."},
    {note = "arcane", label = "5 Arcane", text = "Tryck Arcane Shot mitt i den långsamma fasen, cirka 5 gånger."},
    {note = "rotation", label = "6 Rotation", text = "Steady Shot och sedan Arcane Shot i samma cykel, cirka 10 cykler."},
    {note = "aimed", label = "7 Aimed", text = "Tryck Aimed Shot 2-3 gånger. Låt Auto Shot gå emellan."},
    {note = "rörelse", label = "8 Rörelse", text = "Ta ett steg under wind-up några gånger."},
}
local WIDTH, BUTTON_W, BUTTON_H, PAD = 280, 128, 22, 8

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
    frame:SetSize(WIDTH, 112 + rows * (BUTTON_H + 4) + 48)
    frame:SetPoint("CENTER", UIParent, "CENTER", settings.panelX or 300, settings.panelY or 100)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0.03, 0.04, 0.03, 0.92)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
    title:SetText("Ozzy Swing Timer · Tester")
    local close = button(frame, "X", 24, function() panel:Toggle() end)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    panel.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    panel.status:SetJustifyH("LEFT")

    local newLog = button(frame, "Ny logg", BUTTON_W, function()
        run("debug on"); panel.step = nil; panel:Refresh(true)
    end)
    newLog:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -48)
    local save = button(frame, "Spara (/reload)", BUTTON_W, function() ReloadUI() end)
    save:SetPoint("LEFT", newLog, "RIGHT", 8, 0)

    for i, step in ipairs(STEPS) do
        local b = button(frame, step.label, BUTTON_W, function()
            run("mark " .. step.note)
            panel.step, panel.startShots = step, ns.model and ns.model.shots or 0
            panel:Refresh(true)
        end)
        local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + column * (BUTTON_W + 8), -80 - row * (BUTTON_H + 4))
    end

    panel.instruction = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.instruction:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -88 - rows * (BUTTON_H + 4))
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
    self.instruction:SetText(self.step and (self.step.label .. ": " .. self.step.text) or
        "Starta en ny logg, välj ett test och följ instruktionen. Spara med /reload när du är klar.")
end
