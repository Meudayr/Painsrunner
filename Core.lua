local addonName, PR = ...
_G["Plainsrunner"] = PR

-- ============================================================
-- Constants & Configuration (Calibrated to Server Mechanics)
-- ============================================================
PR.MAX_STACKS  = 30
PR.CHARGE_TIME = 5.00 -- 5.0s continuous running per +1 stack
PR.MAX_LEEWAY  = 1.00 -- 1.0s grace window before decay starts
PR.DECAY_TIME  = 1.00 -- 1.0s stationary per stack loss

local DEFAULT_DB = {
    logging = true,
    chatLog = false,
    logs = {},
}

-- ============================================================
-- Runtime State
-- ============================================================
PR.currentStacks = 0
PR.cycleProgress = 0.0
PR.continuousIdle = 0.0
PR.decayProgress = 0.0
PR.isMoving = false
PR.isDecaying = false
PR.isTauren = false
PR.testMode = false
PR.auraTexture = 236717

-- Diagnostic Tracking State
PR.lastMoveState = false
PR.moveStateStartTime = nil
PR.lastGainTime = nil
PR.lastDecayTime = nil
PR.lastLogTime = nil
PR.pausesInCurrentCycle = 0
PR.idleTimeInCurrentCycle = 0.0

-- Simulation / Scan Throttle
local testElapsed = 0.0
local testStage = 0
local scanThrottle = 0.0

-- ============================================================
-- Forward Declarations
-- ============================================================
local InitializeDB
local ScanPlainsrunningAura
local OnUpdateHandler
local PrintMessage
local ToggleTestMode

-- ============================================================
-- Message & Diagnostic Log Helpers
-- ============================================================
function PrintMessage(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100[Plainsrunner]|r " .. tostring(msg))
end

function PR.LogEvent(eventType, details)
    if not (PR.db and PR.db.logging) then return end
    if not PR.db.logs then PR.db.logs = {} end

    local now = GetTime()
    local dt = PR.lastLogTime and (now - PR.lastLogTime) or 0.0
    PR.lastLogTime = now

    local clock = date("%H:%M:%S")
    local entry = string.format("[%s | %.3f | +%.3fs] %-15s : %s", clock, now, dt, eventType, details or "")

    table.insert(PR.db.logs, entry)

    -- Cap circular buffer at 500 lines
    if #PR.db.logs > 500 then
        table.remove(PR.db.logs, 1)
    end

    if PR.db.chatLog then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[PR-LOG]|r " .. entry)
    end
end

-- ============================================================
-- Database Initialization
-- ============================================================
function InitializeDB()
    if not PlainsrunnerDB then
        PlainsrunnerDB = {}
    end
    for k, v in pairs(DEFAULT_DB) do
        if PlainsrunnerDB[k] == nil then
            if type(v) == "table" then
                PlainsrunnerDB[k] = {}
            else
                PlainsrunnerDB[k] = v
            end
        end
    end
    PR.db = PlainsrunnerDB
    if not PR.db.logs then
        PR.db.logs = {}
    end
end

-- ============================================================
-- Aura State Synchronizer & Scanner
-- ============================================================
local function SyncAuraState(found, count, icon)
    if PR.testMode then return end

    local oldStacks = PR.currentStacks

    if not found then
        if oldStacks > 0 then
            PR.LogEvent("AURA_LOST", string.format("Buff dropped to 0 (was %d stacks) | ContinuousIdle: %.3fs", oldStacks, PR.continuousIdle))
            PR.currentStacks = 0
            PR.cycleProgress = 0.0
            PR.decayProgress = 0.0
            PR.isDecaying = false
            PR.lastDecayTime = nil
            PR.pausesInCurrentCycle = 0
            PR.idleTimeInCurrentCycle = 0.0
        end
        return
    end

    local newStacks = math.min(PR.MAX_STACKS, count or 1)

    if newStacks ~= oldStacks then
        local now = GetTime()
        if newStacks > oldStacks then
            local interval = PR.lastGainTime and (now - PR.lastGainTime) or 0.0
            PR.lastGainTime = now
            PR.LogEvent("STACK_GAIN", string.format("%d -> %d (+%d) | Interval: %.3fs | CycleProg: %.3fs | Pauses: %d (%.3fs idle) | ContinuousIdle: %.3fs", oldStacks, newStacks, newStacks - oldStacks, interval, PR.cycleProgress, PR.pausesInCurrentCycle or 0, PR.idleTimeInCurrentCycle or 0.0, PR.continuousIdle))

            -- Server confirmed stack gain (+1): reset charge progress to 0
            PR.cycleProgress = 0.0
            PR.isDecaying = false
            PR.decayProgress = 0.0
            PR.lastDecayTime = nil
            PR.pausesInCurrentCycle = 0
            PR.idleTimeInCurrentCycle = 0.0
        elseif newStacks < oldStacks then
            local interval = PR.lastDecayTime and (now - PR.lastDecayTime) or 0.0
            PR.lastDecayTime = now
            PR.LogEvent("STACK_DECAY", string.format("%d -> %d (-%d) | Interval: %.3fs | ContinuousIdle: %.3fs", oldStacks, newStacks, oldStacks - newStacks, interval, PR.continuousIdle))

            -- Server confirmed stack decay (-1): sync next decay cycle to this exact moment
            PR.decayProgress = 0.0
            PR.cycleProgress = 0.0
            PR.pausesInCurrentCycle = 0
            PR.idleTimeInCurrentCycle = 0.0
            if newStacks == 0 then
                PR.isDecaying = false
                PR.lastDecayTime = nil
            else
                PR.isDecaying = true
            end
        end
        PR.currentStacks = newStacks
    end

    if icon then
        PR.auraTexture = icon
    end
end

function ScanPlainsrunningAura()
    if PR.testMode then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, isSecret = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and isSecret then
            return
        end
    end

    local found = false
    local scanCompleted = false
    local auraName = "Plainsrunning"
    local foundCount = 0
    local foundIcon = nil

    -- Modern C_UnitAuras API
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local i = 1
        while true do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not aura then
                if ok then scanCompleted = true end
                break
            end
            if aura.name == auraName then
                found = true
                scanCompleted = true
                local count = 0
                if aura.applications and type(aura.applications) == "number" then
                    count = aura.applications
                elseif aura.count and type(aura.count) == "number" then
                    count = aura.count
                end
                if count == 0 then count = 1 end
                foundCount = count
                foundIcon = aura.icon
                break
            end
            i = i + 1
        end
    -- Fallback to AuraUtil
    elseif AuraUtil and AuraUtil.FindAuraByName then
        local ok, name, icon, count = pcall(AuraUtil.FindAuraByName, auraName, "player", "HELPFUL")
        if ok then
            scanCompleted = true
            if name then
                found = true
                count = (type(count) == "number" and count) or 0
                if count == 0 then count = 1 end
                foundCount = count
                foundIcon = icon
            end
        end
    -- Fallback to UnitBuff
    elseif UnitBuff then
        local i = 1
        while true do
            local ok, name, icon, count = pcall(UnitBuff, "player", i)
            if not ok or not name then
                if ok then scanCompleted = true end
                break
            end
            if name == auraName then
                found = true
                scanCompleted = true
                count = (type(count) == "number" and count) or 0
                if count == 0 then count = 1 end
                foundCount = count
                foundIcon = icon
                break
            end
            i = i + 1
        end
    end

    if scanCompleted then
        SyncAuraState(found, foundCount, foundIcon)
    end
end

-- ============================================================
-- Test Mode Simulation (Demonstrates all visual states)
-- ============================================================
local function RunTestSimulation(delta)
    testElapsed = testElapsed + delta

    if testStage == 0 then
        -- Stage 0: Running and charging (0 -> 10 stacks)
        PR.isMoving = true
        PR.isDecaying = false
        PR.cycleProgress = PR.cycleProgress + (delta * 2.5)
        if PR.cycleProgress >= PR.CHARGE_TIME then
            PR.cycleProgress = 0.0
            PR.currentStacks = PR.currentStacks + 1
            if PR.currentStacks >= 10 then
                testStage = 1
                testElapsed = 0.0
            end
        end
        PR.UpdateDisplay(PR.currentStacks, PR.MAX_STACKS, PR.cycleProgress, PR.CHARGE_TIME, true, false, false, 0, PR.MAX_LEEWAY)

    elseif testStage == 1 then
        -- Stage 1: Demonstrate pause during charge: yellow bar keeps moving forward, teal tick runs right-to-left
        local inGrace = (testElapsed >= 0.4 and testElapsed <= 1.2)
        if inGrace then
            PR.isMoving = false
            PR.cycleProgress = math.min(PR.CHARGE_TIME, PR.cycleProgress + (delta * 2.5))
            local graceRemaining = math.max(0, 1.2 - testElapsed)
            PR.UpdateDisplay(PR.currentStacks, PR.MAX_STACKS, PR.cycleProgress, PR.CHARGE_TIME, false, false, true, graceRemaining, PR.MAX_LEEWAY)
        else
            PR.isMoving = true
            PR.cycleProgress = PR.cycleProgress + (delta * 3.0)
            if PR.cycleProgress >= PR.CHARGE_TIME then
                PR.cycleProgress = 0.0
                PR.currentStacks = PR.currentStacks + 1
                if PR.currentStacks >= PR.MAX_STACKS then
                    PR.currentStacks = PR.MAX_STACKS
                    testStage = 2
                    testElapsed = 0.0
                end
            end
            PR.UpdateDisplay(PR.currentStacks, PR.MAX_STACKS, PR.cycleProgress, PR.CHARGE_TIME, true, false, false, 0, PR.MAX_LEEWAY)
        end

    elseif testStage == 2 then
        -- Stage 2: Max speed hold (30 stacks)
        PR.isMoving = true
        PR.isDecaying = false
        PR.UpdateDisplay(PR.MAX_STACKS, PR.MAX_STACKS, PR.CHARGE_TIME, PR.CHARGE_TIME, true, false, false, 0, PR.MAX_LEEWAY)
        if testElapsed > 2.5 then
            testStage = 3
            testElapsed = 0.0
            PR.continuousIdle = 0.0
        end

    elseif testStage == 3 then
        -- Stage 3: Stationary - Grace Countdown (1.0s -> 0.0s)
        PR.isMoving = false
        PR.continuousIdle = PR.continuousIdle + delta
        local graceRemaining = math.max(0, PR.MAX_LEEWAY - PR.continuousIdle)
        if PR.continuousIdle < PR.MAX_LEEWAY then
            PR.UpdateDisplay(PR.currentStacks, PR.MAX_STACKS, PR.CHARGE_TIME, PR.CHARGE_TIME, false, false, true, graceRemaining, PR.MAX_LEEWAY)
        else
            testStage = 4
            testElapsed = 0.0
            PR.decayProgress = 0.0
        end

    elseif testStage == 4 then
        -- Stage 4: Stationary - Active Amber Decay Bar (-1 stack per second)
        PR.isMoving = false
        PR.isDecaying = true
        PR.decayProgress = PR.decayProgress + (delta * 1.5)
        local decayRemaining = math.max(0, PR.DECAY_TIME - (PR.decayProgress % PR.DECAY_TIME))
        if PR.decayProgress >= PR.DECAY_TIME then
            PR.decayProgress = 0.0
            PR.currentStacks = math.max(0, PR.currentStacks - 1)
            if PR.currentStacks <= 0 then
                testStage = 0
                testElapsed = 0.0
                PR.currentStacks = 0
                PR.cycleProgress = 0.0
                PR.decayProgress = 0.0
                PR.isDecaying = false
            end
        end
        PR.UpdateDisplay(PR.currentStacks, PR.MAX_STACKS, decayRemaining, PR.DECAY_TIME, false, true, false, 0, PR.MAX_LEEWAY)
    end
end

-- ============================================================
-- Main OnUpdate Processing Loop (Pure Native Frame-Rate Updates)
-- ============================================================
function OnUpdateHandler(self, elapsed)
    local delta = elapsed

    -- 1. In-Combat Lockdown Check: Immediately hide frame in combat
    if InCombatLockdown and InCombatLockdown() then
        if PR.MainFrame and PR.MainFrame:IsShown() then
            PR.MainFrame:Hide()
        end
        return
    end

    -- 2. Test Mode Handler
    if PR.testMode then
        if PR.MainFrame and not PR.MainFrame:IsShown() then
            PR.MainFrame:Show()
        end
        RunTestSimulation(delta)
        return
    end

    -- 3. Character / Mount Eligibility Check
    if not PR.isTauren or (IsMounted and IsMounted()) or (UnitInVehicle and UnitInVehicle("player")) then
        if PR.MainFrame and PR.MainFrame:IsShown() then
            PR.MainFrame:Hide()
        end
        return
    else
        if PR.MainFrame and not PR.MainFrame:IsShown() then
            PR.MainFrame:Show()
        end
    end

    -- 4. Periodic Aura Scan (every 0.25s)
    scanThrottle = scanThrottle + delta
    if scanThrottle >= 0.25 then
        scanThrottle = 0.0
        ScanPlainsrunningAura()
    end

    -- 5. Movement State Tracking
    local isMoving = false
    if IsPlayerMoving then
        isMoving = (IsPlayerMoving() == true)
    elseif C_PlayerInfo and C_PlayerInfo.IsPlayerMoving then
        isMoving = (C_PlayerInfo.IsPlayerMoving() == true)
    end

    -- Movement Transition Logging
    if PR.moveStateStartTime == nil then
        PR.moveStateStartTime = GetTime()
        PR.lastMoveState = isMoving
    elseif isMoving ~= PR.lastMoveState then
        local now = GetTime()
        local durationInPrevState = now - PR.moveStateStartTime
        PR.moveStateStartTime = now

        if isMoving then
            PR.idleTimeInCurrentCycle = (PR.idleTimeInCurrentCycle or 0.0) + durationInPrevState
            PR.pausesInCurrentCycle = (PR.pausesInCurrentCycle or 0) + 1
            PR.LogEvent("MOVE_START", string.format("Was paused for %.3fs | Stacks: %d | CycleProg: %.3fs | TotalIdleInCycle: %.3fs (Pause #%d)", durationInPrevState, PR.currentStacks, PR.cycleProgress, PR.idleTimeInCurrentCycle, PR.pausesInCurrentCycle))
        else
            PR.LogEvent("MOVE_STOP", string.format("Was running for %.3fs | Stacks: %d | CycleProg: %.3fs", durationInPrevState, PR.currentStacks, PR.cycleProgress))
        end
        PR.lastMoveState = isMoving
    end

    -- 6. Movement & Idle Physics Model (Anchored to Server Decay Events)
    local displayVal = 0
    local displayMax = PR.CHARGE_TIME
    local isGrace = false
    local graceRemaining = 0

    if isMoving then
        PR.isMoving = true
        PR.isDecaying = false
        PR.continuousIdle = 0.0
        PR.decayProgress = 0.0
        PR.lastDecayTime = nil

        if PR.currentStacks < PR.MAX_STACKS then
            PR.cycleProgress = math.min(PR.CHARGE_TIME, PR.cycleProgress + delta)
        else
            PR.cycleProgress = PR.CHARGE_TIME
        end

        displayVal = PR.cycleProgress
        displayMax = PR.CHARGE_TIME
    else
        PR.isMoving = false
        PR.continuousIdle = PR.continuousIdle + delta

        if PR.continuousIdle < PR.MAX_LEEWAY and not PR.lastDecayTime then
            -- Grace window: bar continues charging forward, grace tick appears
            isGrace = true
            graceRemaining = math.max(0, PR.MAX_LEEWAY - PR.continuousIdle)
            PR.isDecaying = false

            if PR.currentStacks < PR.MAX_STACKS then
                PR.cycleProgress = math.min(PR.CHARGE_TIME, PR.cycleProgress + delta)
            else
                PR.cycleProgress = PR.CHARGE_TIME
            end

            displayVal = PR.cycleProgress
            displayMax = PR.CHARGE_TIME
        else
            -- Grace expired: reset charge progress, begin active decay anchored to server timestamps
            PR.cycleProgress = 0.0
            PR.pausesInCurrentCycle = 0
            PR.idleTimeInCurrentCycle = 0.0

            if PR.currentStacks > 0 then
                PR.isDecaying = true
                local now = GetTime()
                local decayLeft = 0
                if PR.lastDecayTime then
                    local elapsedSinceLastDecay = now - PR.lastDecayTime
                    local decayCycle = elapsedSinceLastDecay % PR.DECAY_TIME
                    decayLeft = math.max(0, PR.DECAY_TIME - decayCycle)
                else
                    local elapsedInDecay = PR.continuousIdle - PR.MAX_LEEWAY
                    local decayCycle = elapsedInDecay % PR.DECAY_TIME
                    decayLeft = math.max(0, PR.DECAY_TIME - decayCycle)
                end
                displayVal = decayLeft
                displayMax = PR.DECAY_TIME
            else
                PR.isDecaying = false
                PR.decayProgress = 0.0
                PR.lastDecayTime = nil
                displayVal = 0
                displayMax = PR.CHARGE_TIME
            end
        end
    end

    -- 7. Render to Portrait Bar
    PR.UpdateDisplay(
        PR.currentStacks,
        PR.MAX_STACKS,
        displayVal,
        displayMax,
        PR.isMoving,
        PR.isDecaying,
        isGrace,
        graceRemaining,
        PR.MAX_LEEWAY
    )
end

-- ============================================================
-- Test Mode Toggle Helper
-- ============================================================
function ToggleTestMode()
    PR.testMode = not PR.testMode
    if PR.testMode then
        testStage = 0
        testElapsed = 0.0
        PR.currentStacks = 0
        PR.cycleProgress = 0.0
        PR.decayProgress = 0.0
        if PR.MainFrame then
            PR.MainFrame:Show()
        end
        PrintMessage("Test Mode |cff20e040Enabled|r. Simulating portrait bar progression, grace tick, and decay.")
    else
        PR.currentStacks = 0
        PR.cycleProgress = 0.0
        PR.decayProgress = 0.0
        ScanPlainsrunningAura()
        PrintMessage("Test Mode |cffff4444Disabled|r.")
    end
end

-- ============================================================
-- Slash Commands Handler
-- ============================================================
local function HandleSlashCommand(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    arg = arg or ""

    if cmd == "test" then
        ToggleTestMode()
    elseif cmd == "log" then
        local subCmd, subArg = arg:match("^(%S*)%s*(.-)$")
        subCmd = (subCmd or ""):lower()
        if subCmd == "on" or subCmd == "enable" then
            PR.db.logging = true
            PrintMessage("Diagnostic logging |cff20e040Enabled|r.")
        elseif subCmd == "off" or subCmd == "disable" then
            PR.db.logging = false
            PrintMessage("Diagnostic logging |cffff4444Disabled|r.")
        elseif subCmd == "clear" then
            PR.db.logs = {}
            PrintMessage("Diagnostic logs |cffffd100Cleared|r.")
        elseif subCmd == "chat" then
            PR.db.chatLog = not PR.db.chatLog
            PrintMessage("Chat mirror logging " .. (PR.db.chatLog and "|cff20e040Enabled|r." or "|cffff4444Disabled|r."))
        elseif subCmd == "dump" then
            local count = tonumber(subArg) or 15
            local total = PR.db.logs and #PR.db.logs or 0
            PrintMessage(string.format("Dumping last %d logs (total %d):", math.min(count, total), total))
            local startIdx = math.max(1, total - count + 1)
            for i = startIdx, total do
                DEFAULT_CHAT_FRAME:AddMessage("|cff88aaff" .. PR.db.logs[i] .. "|r")
            end
        else
            local status = (PR.db and PR.db.logging) and "|cff20e040Active|r" or "|cffff4444Inactive|r"
            local chatStatus = (PR.db and PR.db.chatLog) and "|cff20e040On|r" or "|cffff4444Off|r"
            local count = PR.db and PR.db.logs and #PR.db.logs or 0
            PrintMessage(string.format("Logging: %s | Chat Mirror: %s | Entries: %d", status, chatStatus, count))
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plainsrun log on|off|r - Enable/disable logging")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plainsrun log clear|r - Clear logged entries")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plainsrun log dump [N]|r - Dump last N logs to chat")
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plainsrun log chat|r - Toggle real-time chat mirror")
        end
    else
        PrintMessage("|cffffd100Plainsrunner v1.0.0|r commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plainsrun test|r - Toggle portrait test simulation")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/plainsrun log|r - Diagnostic logging options")
    end
end

-- Register Unique Slash Commands
SLASH_PLAINSRUNNER1 = "/plainsrunner"
SLASH_PLAINSRUNNER2 = "/plainsrun"
SLASH_PLAINSRUNNER3 = "/prun"
SlashCmdList["PLAINSRUNNER"] = HandleSlashCommand

-- ============================================================
-- Event Listener Frame (Clean, lightweight events only)
-- ============================================================
local eventFrame = CreateFrame("Frame", "PlainsrunnerEventFrame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        InitializeDB()
        PR.CreateUI()

        -- Check if player is Tauren
        local _, raceFile = UnitRace("player")
        PR.isTauren = (raceFile == "Tauren")

        PR.LogEvent("ADDON_LOADED", string.format("Race: %s (isTauren=%s)", tostring(raceFile), tostring(PR.isTauren)))

        ScanPlainsrunningAura()

        -- Attach OnUpdate handler to MainFrame
        if PR.MainFrame then
            PR.MainFrame:SetScript("OnUpdate", OnUpdateHandler)
            if not PR.isTauren and not PR.testMode then
                PR.MainFrame:Hide()
            else
                PR.MainFrame:Show()
            end
        end

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" and not (InCombatLockdown and InCombatLockdown()) then
            ScanPlainsrunningAura()
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat: hide frame completely to prevent taint / distraction
        if PR.MainFrame then
            PR.MainFrame:Hide()
        end
        PR.LogEvent("COMBAT_ENTER", "Entered combat - frame hidden")

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Exited combat: restore frame and resync aura
        if PR.MainFrame and (PR.isTauren or PR.testMode) and not (IsMounted and IsMounted()) then
            PR.MainFrame:Show()
        end
        ScanPlainsrunningAura()
        PR.LogEvent("COMBAT_EXIT", "Exited combat - frame restored")
    end
end)
