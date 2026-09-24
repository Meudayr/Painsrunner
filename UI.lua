local addonName, PR = ...
_G["Plainsrunner"] = PR

-- ============================================================
-- Color Definitions (Matched to Classic Blizzard Unit Frame)
-- ============================================================
local COLORS = {
    CHARGE_YELLOW      = { r = 0.88, g = 0.65, b = 0.15 }, -- Muted golden orange
    CHARGE_MAX         = { r = 0.95, g = 0.75, b = 0.15 }, -- Brighter orange at max stacks
    GRACE_TEAL         = { r = 0.02, g = 0.52, b = 0.50, a = 1.00 }, -- Darker rich teal tick
    DECAY_AMBER        = { r = 0.95, g = 0.45, b = 0.10 }, -- Amber Decay alert
    BORDER_SILVER      = { r = 0.58, g = 0.56, b = 0.53, a = 1.00 }, -- Outer metallic silver stroke (#949088)
    BORDER_BOTTOM      = { r = 0.52, g = 0.50, b = 0.47, a = 1.00 }, -- Bottom outer silver stroke
    BORDER_SHADOW      = { r = 0.29, g = 0.27, b = 0.25, a = 0.95 }, -- Inner 3D bevel shadow (#4B4640)
}

local STATUSBAR_TEXTURE = "Interface\\AddOns\\Plainsrunner\\media\\statusbar.tga"
local CORNER_TEXTURE    = "Interface\\AddOns\\Plainsrunner\\media\\corner.tga"

-- ============================================================
-- UI Frame Creation (Seamless Attached 3D Beveled Unit Bar)
-- ============================================================
function PR.CreateUI()
    if PR.MainFrame then return end

    -- Determine Anchor Target (PlayerFrameManaBar in Classic WoW)
    local anchorTo = PlayerFrameManaBar or (PlayerFrame and PlayerFrame.manabar)
    local parent = anchorTo or PlayerFrame or UIParent

    local frame = CreateFrame("Frame", "PlainsrunnerUnitBarFrame", parent)
    frame:SetFrameStrata(anchorTo and anchorTo:GetFrameStrata() or "LOW")
    frame:SetFrameLevel((anchorTo and anchorTo:GetFrameLevel() or 1) + 3)
    frame:SetHeight(11) -- Exact height matching the bottom edge of the player portrait ornament

    -- Anchor flush with the bottom of the mana bar
    if anchorTo then
        frame:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, 1)
        frame:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 1, 1)
    elseif PlayerFrame then
        frame:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 106, -51)
        frame:SetSize(120, 11)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 106, -51)
        frame:SetSize(120, 11)
    end

    -- ============================================================
    -- Minimalist Soft Drop-Shadow (Straight edges)
    -- ============================================================
    local alphas = { 0.35, 0.15, 0.05 }
    for i, a in ipairs(alphas) do
        local offset = i - 1
        
        -- Bottom line (stops exactly before the chamfer, angled to match)
        local sb = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        sb:SetColorTexture(0, 0, 0, a)
        sb:SetHeight(1)
        sb:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -offset)
        sb:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -4 + offset, -offset)
        
        -- Right line (stops exactly before the chamfer, angled to match)
        local sr = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        sr:SetColorTexture(0, 0, 0, a)
        sr:SetWidth(1)
        sr:SetPoint("TOPLEFT", frame, "TOPRIGHT", offset, 0)
        sr:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", offset, 4 - offset)
    end

    -- ============================================================
    -- 3D Beveled Metallic Frame Borders (Matches Mana & Health)
    -- ============================================================
    
    -- 1. Top border removed so it utilizes the bottom of the mana bar as its top border

    -- 2. Left border removed so the bar runs seamlessly into the portrait ring

    -- 3. Right vertical border
    local borderRightOuter = frame:CreateTexture(nil, "BORDER", nil, 1)
    borderRightOuter:SetColorTexture(COLORS.BORDER_SILVER.r, COLORS.BORDER_SILVER.g, COLORS.BORDER_SILVER.b, COLORS.BORDER_SILVER.a)
    borderRightOuter:SetWidth(1)
    borderRightOuter:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    borderRightOuter:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 4) -- Changed from 5 to 4 to close gap
    frame.borderRightOuter = borderRightOuter

    local borderRightInner = frame:CreateTexture(nil, "BORDER", nil, 1)
    borderRightInner:SetColorTexture(COLORS.BORDER_SHADOW.r, COLORS.BORDER_SHADOW.g, COLORS.BORDER_SHADOW.b, COLORS.BORDER_SHADOW.a)
    borderRightInner:SetWidth(1)
    borderRightInner:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    borderRightInner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 4) -- Changed from 5 to 4 to close gap
    frame.borderRightInner = borderRightInner

    -- 4. Bottom border
    local borderBottomOuter = frame:CreateTexture(nil, "BORDER", nil, 1)
    borderBottomOuter:SetColorTexture(COLORS.BORDER_BOTTOM.r, COLORS.BORDER_BOTTOM.g, COLORS.BORDER_BOTTOM.b, COLORS.BORDER_BOTTOM.a)
    borderBottomOuter:SetHeight(1)
    borderBottomOuter:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    borderBottomOuter:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 0) -- Changed from -5 to -4 to close gap
    frame.borderBottomOuter = borderBottomOuter

    local borderBottomInner = frame:CreateTexture(nil, "BORDER", nil, 1)
    borderBottomInner:SetColorTexture(COLORS.BORDER_SHADOW.r, COLORS.BORDER_SHADOW.g, COLORS.BORDER_SHADOW.b, COLORS.BORDER_SHADOW.a)
    borderBottomInner:SetHeight(1)
    borderBottomInner:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    borderBottomInner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 1) -- Changed from -5 to -4 to close gap
    frame.borderBottomInner = borderBottomInner

    -- ============================================================
    -- 5. Seamless 45-Degree Chamfer & Shadow Integration (Vector Math)
    -- ============================================================
    local function DrawDiagonal(layer, level, color, cx, cy, length, thickness)
        local t = frame:CreateTexture(nil, layer, nil, level)
        t:SetColorTexture(color.r, color.g, color.b, color.a or 1)
        t:SetSize(length, thickness)
        t:SetPoint("CENTER", frame, "BOTTOMRIGHT", cx, cy)
        t:SetRotation(math.rad(45)) -- 45 degrees counter-clockwise (bottom-left to top-right)
        return t
    end

    -- The outer silver border: flawlessly connects the bottom and right borders
    DrawDiagonal("BORDER", 2, COLORS.BORDER_SILVER, -2.25, 2.25, 4.95, 0.7071)

    -- The inner dark bevel: made slightly thicker (1.414) to natively cover the corner of the rectangular status bar
    DrawDiagonal("BORDER", 2, COLORS.BORDER_SHADOW, -2.75, 2.75, 3.5355, 1.414)

    -- The diagonal drop shadow: perfectly merges with the straight drop shadows
    local shadowSize = 2.12 -- Mathematically exact perpendicular thickness to match 3px vertical thickness
    local diagShadow = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    diagShadow:SetColorTexture(1, 1, 1, 1)
    diagShadow:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.35))
    diagShadow:SetSize(5.65, shadowSize) -- Mathematically exact length to connect sb(0) and sr(0)
    diagShadow:SetPoint("CENTER", frame, "BOTTOMRIGHT", -1.5, 1.5)
    diagShadow:SetRotation(math.rad(45))

    -- ============================================================
    -- Charge / Decay Status Bar (Clean High-Resolution Bar)
    -- ============================================================
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -3) -- Moved down to y=-3 to create balanced top margin
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 2) -- Moved down to y=2 to sit cleanly above bottom inner border
    bar:SetMinMaxValues(0, PR.CHARGE_TIME or 5.0)
    bar:SetValue(0)
    bar:SetStatusBarColor(COLORS.CHARGE_YELLOW.r, COLORS.CHARGE_YELLOW.g, COLORS.CHARGE_YELLOW.b)
    frame.bar = bar

    -- Stacks Number on Left Side of the Bar
    local stackText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stackText:SetPoint("LEFT", bar, "LEFT", 3, 0)
    stackText:SetFont(stackText:GetFont(), 8, "OUTLINE")
    stackText:SetText("0")
    stackText:SetTextColor(1, 1, 1, 1)
    frame.stackText = stackText

    -- ============================================================
    -- Grace Tick Marker (Darker Teal Gliding Divider)
    -- ============================================================
    local graceTick = CreateFrame("Frame", nil, bar)
    graceTick:SetSize(2, 8)
    graceTick:SetPoint("CENTER", bar, "LEFT", 0, 0)
    graceTick:SetAlpha(0)

    -- Center glowing spark (using native Casting Bar spark)
    local spark = graceTick:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetSize(24, 24) -- The spark texture is 32x32, 24x24 makes the bright center fit perfectly over our 8px bar
    spark:SetPoint("CENTER", graceTick, "CENTER", 0, 0)
    graceTick.spark = spark

    frame.graceTick = graceTick

    -- Tooltip on Mouseover
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddDoubleLine("Plainsrunning", string.format("%d / %d Stacks (+%d%%)", PR.currentStacks or 0, PR.MAX_STACKS or 30, PR.currentStacks or 0), 1, 0.88, 0.12, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("• +1% speed per 5s running (caps at +30%)", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("• 1.0s grace period when stopped before losing stacks", 0.02, 0.52, 0.50)
        GameTooltip:AddLine("• Decays 1 stack per second while stationary", 0.95, 0.45, 0.1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    PR.MainFrame = frame
end

-- ============================================================
-- Real-Time HUD Display Update (Zero Taint / Clean Rendering)
-- ============================================================
function PR.UpdateDisplay(stacks, maxStacks, displayVal, displayMax, isMoving, isDecaying, isGrace, graceRemaining, maxGrace)
    local frame = PR.MainFrame
    if not frame or not frame:IsShown() then return end

    stacks = stacks or 0
    maxStacks = maxStacks or 30
    displayVal = displayVal or 0
    displayMax = displayMax or 5.0
    if displayMax <= 0 then displayMax = 5.0 end
    maxGrace = maxGrace or 1.00

    -- 1. Stack Number Text
    frame.stackText:SetText(tostring(stacks))

    -- 2. Status Bar Fill & Color (Yellow for charge, Amber for decay)
    frame.bar:SetMinMaxValues(0, displayMax)
    frame.bar:SetValue(math.max(0, math.min(displayMax, displayVal)))

    if stacks >= maxStacks and not isDecaying then
        frame.bar:SetStatusBarColor(COLORS.CHARGE_MAX.r, COLORS.CHARGE_MAX.g, COLORS.CHARGE_MAX.b)
    elseif isDecaying and stacks > 0 then
        frame.bar:SetStatusBarColor(COLORS.DECAY_AMBER.r, COLORS.DECAY_AMBER.g, COLORS.DECAY_AMBER.b)
    else
        frame.bar:SetStatusBarColor(COLORS.CHARGE_YELLOW.r, COLORS.CHARGE_YELLOW.g, COLORS.CHARGE_YELLOW.b)
    end

    -- 3. Grace Indicator (Darker teal tick marker gliding right to left)
    local barWidth = frame.bar:GetWidth()
    if barWidth <= 0 then barWidth = 114 end

    if isGrace and graceRemaining and graceRemaining > 0 then
        local fraction = math.max(0.0, math.min(1.0, graceRemaining / maxGrace))
        local xPos = math.floor(fraction * barWidth)
        
        frame.graceTick:ClearAllPoints()
        frame.graceTick:SetPoint("CENTER", frame.bar, "LEFT", xPos, 0)
        frame.graceTick:SetAlpha(1)
    else
        frame.graceTick:SetAlpha(0)
    end
end
