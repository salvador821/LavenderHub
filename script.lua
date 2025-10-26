--// Bee Swarm Simulator Farm Bot - PART 1 (FIXED) \\--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

-- Configuration
local GRID_SIZE = 6
local JUMP_HEIGHT = 150
local CHECK_INTERVAL = 0.1
local OBSTACLE_CHECK_DISTANCE = 5
local MOVETO_TIMEOUT = 5
local TOKEN_CLEAR_INTERVAL = 5
local HIVE_CHECK_INTERVAL = 10

-- Field Coordinates
local fieldCoords = {
    ["Mango Field"] = Vector3.new(-1895.27, 73.50, -141.94),
    ["Blueberry Field"] = Vector3.new(-2074.56, 73.50, -188.62),
    ["Daisy Field"] = Vector3.new(-2166.29, 73.50, 41.82),
    ["Cactus Field"] = Vector3.new(-2398.86, 109.04, 42.60),
    ["Strawberry Field"] = Vector3.new(-1758.79, 73.50, -69.91),
    ["Apple Field"] = Vector3.new(-1967.78, 94.43, -344.20),
    ["Lemon Field"] = Vector3.new(-1832.23, 94.43, -310.76),
    ["Grape Field"] = Vector3.new(-2113.74, 94.43, -347.57),
    ["Watermelon Field"] = Vector3.new(-2220.26, 146.85, -507.15),
    ["Forest Field"] = Vector3.new(-2351.29, 95.15, -178.81),
    ["Pear Field"] = Vector3.new(-1814.76, 146.85, -488.39),
    ["Mushroom Field"] = Vector3.new(-1779.69, 146.85, -652.93),
    ["Clover Field"] = Vector3.new(-1638.08, 146.85, -487.75),
    ["Bamboo Field"] = Vector3.new(-1638.96, 117.49, -163.70),
    ["Glitch Field"] = Vector3.new(-2568.07, 168.00, -429.88),
    ["Cave Field"] = Vector3.new(-1995.52, 71.78, -63.91),
    ["Mountain Field"] = Vector3.new(-1995.52, 71.78, -63.91)
}

-- Hive Coordinates
local hiveCoords = {
    ["Hive_1"] = Vector3.new(-2059.47, 75.35, 17.14),
    ["Hive_2"] = Vector3.new(-2033.00, 75.35, 17.16),
    ["Hive_3"] = Vector3.new(-2008.25, 75.35, 16.89),
    ["Hive_4"] = Vector3.new(-1983.14, 75.35, 17.00),
    ["Hive_5"] = Vector3.new(-1958.10, 75.35, 17.28),
    ["Hive_6"] = Vector3.new(-1932.45, 75.35, 17.85)
}

-- Toggles and State
local toggles = {
    field = "Mango Field",
    movementMethod = "Walk",
    autoFarm = false,
    autoDig = false,
    tweenSpeed = 6,
    walkspeedEnabled = false,
    walkspeed = 50,
    isFarming = false,
    isConverting = false,
    atField = false,
    atHive = false,
    visitedTokens = {},
    lastTokenClearTime = tick(),
    lastHiveCheckTime = tick(),
    
    -- Pollen tracking - FIXED: Proper initialization
    lastPollenValue = 0,
    lastPollenChangeTime = 0,
    fieldArrivalTime = 0,
    hasCollectedPollen = false -- NEW: Track if we've collected any pollen at all
}

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events", 10)

-- Auto-dig variables
local digRunning = false

-- Utility Functions
local function GetCharacter()
    return player.Character or player.CharacterAdded:Wait()
end

local function LightWait(duration)
    local start = tick()
    while tick() - start < duration do
        RunService.Heartbeat:Wait()
    end
end

local function SafeCall(func, name)
    local success, err = pcall(func)
    if not success then
        warn("Error in " .. (name or "unknown") .. ": " .. err)
    end
    return success
end

local function formatNumber(num)
    local suffixes = {"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td", "Qad", "Qid"}
    local i = 1
    while num >= 1000 and i < #suffixes do
        num = num / 1000
        i = i + 1
    end
    return i == 1 and tostring(num) or string.format("%.1f%s", num, suffixes[i])
end

-- Get current pollen value
local function getCurrentPollen()
    local pollenValue = player:FindFirstChild("Pollen")
    if pollenValue and pollenValue:IsA("NumberValue") then
        return pollenValue.Value
    end
    return 0
end

-- Auto-detect owned hive
local function getOwnedHive()
    local hiveObject = player:FindFirstChild("Hive")
    if hiveObject and hiveObject:IsA("ObjectValue") and hiveObject.Value then
        local hiveName = hiveObject.Value.Name
        if hiveCoords[hiveName] then
            return hiveName
        end
    end
    return nil
end

local ownedHive = getOwnedHive()
local displayHiveName = ownedHive and "Hive" or "None"

-- Periodic hive checking function
local function checkHiveOwnership()
    if tick() - toggles.lastHiveCheckTime >= HIVE_CHECK_INTERVAL then
        local previousHive = ownedHive
        ownedHive = getOwnedHive()
        
        if ownedHive and ownedHive ~= previousHive then
            print("🎯 New hive detected: " .. ownedHive)
            displayHiveName = "Hive"
        elseif not ownedHive and previousHive then
            print("❌ Hive ownership lost")
            displayHiveName = "None"
        elseif ownedHive and previousHive == nil then
            print("🎯 Hive ownership acquired: " .. ownedHive)
            displayHiveName = "Hive"
        end
        
        toggles.lastHiveCheckTime = tick()
    end
end

-- Movement Functions
local function moveToPositionTween(targetPos)
    local character = player.Character
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return false end

    local distance = (humanoidRootPart.Position - targetPos).Magnitude
    local baseSpeed = 20
    local speedMultiplier = (toggles.tweenSpeed / 6) * 1.5
    local duration = distance / (baseSpeed * speedMultiplier)
    
    local tweenInfo = TweenInfo.new(
        duration,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out,
        0,
        false,
        0
    )
    
    local tween = TweenService:Create(humanoidRootPart, tweenInfo, {CFrame = CFrame.new(targetPos)})
    tween:Play()
    tween.Completed:Wait()
    
    return true
end

local function moveToPositionWalk(targetPos)
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not humanoidRootPart then return false end
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = GRID_SIZE
    })
    
    local success, errorMessage = pcall(function()
        path:ComputeAsync(humanoidRootPart.Position, targetPos)
    end)
    
    if not success or path.Status ~= Enum.PathStatus.Success then
        humanoid:MoveTo(targetPos)
        humanoid.MoveToFinished:Wait(10)
        return true
    end
    
    local waypoints = path:GetWaypoints()
    for _, waypoint in ipairs(waypoints) do
        humanoid:MoveTo(waypoint.Position)
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        humanoid.MoveToFinished:Wait(5)
    end
    
    return true
end

local function moveToPosition(targetPos)
    if toggles.movementMethod == "Tween" then
        return moveToPositionTween(targetPos)
    else
        return moveToPositionWalk(targetPos)
    end
end

-- Auto-dig function
local function DigLoop()
    if digRunning then return end
    digRunning = true
    
    while toggles.autoDig and toggles.atField and not toggles.isConverting do
        SafeCall(function()
            local char = GetCharacter()
            local toolsFired = 0
            
            for _, tool in pairs(char:GetChildren()) do
                if toolsFired >= 10 then break end
                if tool:IsA("Tool") then
                    local remote = tool:FindFirstChild("ToolRemote") or tool:FindFirstChild("Remote")
                    if remote then
                        remote:FireServer()
                        toolsFired = toolsFired + 1
                    end
                end
            end
            
            LightWait(0.15)
        end, "DigLoop Cycle")
    end
    
    digRunning = false
end

-- Token Collection
local function getNearestToken()
    local closestToken = nil
    local shortestDistance = math.huge

    local tokensFolder = workspace:FindFirstChild("Debris") and workspace.Debris:FindFirstChild("Tokens")
    if not tokensFolder then return nil end

    for _, token in pairs(tokensFolder:GetChildren()) do
        if token:IsA("BasePart") and token:FindFirstChild("Token") and token:FindFirstChild("Collecting") and not token.Collecting.Value then
            local distance = (token.Position - player.Character.HumanoidRootPart.Position).Magnitude
            if distance < shortestDistance and not toggles.visitedTokens[token] then
                shortestDistance = distance
                closestToken = token
            end
        end
    end

    return closestToken, shortestDistance
end

local function collectTokens()
    if not toggles.autoFarm or toggles.isConverting or not toggles.atField then return end
    
    local token, dist = getNearestToken()
    if token and dist <= 50 then
        local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:MoveTo(token.Position)
            local startTime = tick()
            while (player.Character.HumanoidRootPart.Position - token.Position).Magnitude > 4 and tick() - startTime < 5 do
                if not token.Parent then
                    toggles.visitedTokens[token] = nil
                    break
                end
                RunService.Heartbeat:Wait()
            end
            if token.Parent and (player.Character.HumanoidRootPart.Position - token.Position).Magnitude <= 4 then
                toggles.visitedTokens[token] = true
            end
        end
    end
end

-- Pollen Tracking - FIXED: Better logic
local function updatePollenTracking()
    if not toggles.atField then return end
    
    local currentPollen = getCurrentPollen()
    
    -- Track if we've collected any pollen at all
    if currentPollen > 0 and not toggles.hasCollectedPollen then
        toggles.hasCollectedPollen = true
        print("🌸 First pollen collected: " .. currentPollen)
    end
    
    if currentPollen ~= toggles.lastPollenValue then
        toggles.lastPollenValue = currentPollen
        toggles.lastPollenChangeTime = tick()
    end
end

local function shouldConvertToHive()
    if not toggles.isFarming or not toggles.atField or not ownedHive then return false end
    
    local currentPollen = getCurrentPollen()
    local timeSinceLastChange = tick() - toggles.lastPollenChangeTime
    
    -- FIXED: Only convert if we've collected pollen AND it's stagnant for 5 seconds
    -- OR if we have pollen and it reaches 0 (shouldn't happen but safety)
    local shouldConvert = toggles.hasCollectedPollen and (timeSinceLastChange >= 5 or currentPollen == 0)
    
    if shouldConvert then
        print("🔍 Converting - Pollen: " .. currentPollen .. ", Stagnant: " .. string.format("%.1f", timeSinceLastChange) .. "s, HasCollected: " .. tostring(toggles.hasCollectedPollen))
    end
    
    return shouldConvert
end

local function shouldReturnToField()
    if not toggles.isConverting or not toggles.atHive then return false end
    
    local currentPollen = getCurrentPollen()
    return currentPollen == 0
end
--// Bee Swarm Simulator Farm Bot - PART 2 (FIXED) \\--

-- Farming Logic (COMPLETELY FIXED)
local function startFarming()
    if not toggles.autoFarm or toggles.isFarming or not ownedHive then 
        print("❌ Cannot start farming: autoFarm=" .. tostring(toggles.autoFarm) .. ", isFarming=" .. tostring(toggles.isFarming) .. ", ownedHive=" .. tostring(ownedHive))
        return 
    end
    
    local fieldPos = fieldCoords[toggles.field]
    if not fieldPos then return end
    
    toggles.isFarming = true
    toggles.isConverting = false
    toggles.atField = false
    toggles.atHive = false
    
    -- FIXED: Reset pollen tracking completely
    toggles.lastPollenValue = getCurrentPollen() -- Start with current pollen
    toggles.lastPollenChangeTime = tick()
    toggles.fieldArrivalTime = tick()
    toggles.hasCollectedPollen = false -- Reset collection flag
    
    print("🚶 Moving to field: " .. toggles.field)
    
    -- Move to field
    if moveToPosition(fieldPos) then
        toggles.atField = true
        -- FIXED: Start fresh pollen tracking
        local initialPollen = getCurrentPollen()
        toggles.lastPollenValue = initialPollen
        toggles.lastPollenChangeTime = tick()
        toggles.fieldArrivalTime = tick()
        toggles.hasCollectedPollen = (initialPollen > 0) -- Set flag if we already have pollen
        
        print("🎯 Arrived at field! Pollen: " .. initialPollen .. ", HasCollected: " .. tostring(toggles.hasCollectedPollen))
        
        -- Start auto-dig if enabled
        if toggles.autoDig then
            coroutine.wrap(DigLoop)()
        end
    else
        print("❌ Failed to move to field")
        toggles.isFarming = false
    end
end

local function startConverting()
    if toggles.isConverting or not ownedHive then return end
    
    local hivePos = hiveCoords[ownedHive]
    if not hivePos then return end
    
    toggles.isFarming = false
    toggles.isConverting = true
    toggles.atField = false
    toggles.atHive = false
    
    print("🚶 Moving to hive for conversion")
    
    -- Move to hive
    if moveToPosition(hivePos) then
        toggles.atHive = true
        print("🏠 Arrived at hive, starting conversion in 2 seconds")
        
        -- Wait 2 seconds then start conversion
        task.wait(2)
        
        -- Start honey making
        local args = {true}
        local makeHoneyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MakeHoney")
        if makeHoneyRemote then
            makeHoneyRemote:FireServer(unpack(args))
            print("🍯 Started honey conversion")
        end
    else
        print("❌ Failed to move to hive")
        toggles.isConverting = false
    end
end

-- Main Loop
local function updateFarmState()
    if not toggles.autoFarm then return end
    
    -- Check hive ownership periodically
    checkHiveOwnership()
    
    -- Update pollen tracking (only tracks when at field)
    updatePollenTracking()
    
    -- Check if we should transition between states
    if toggles.isFarming and toggles.atField then
        if shouldConvertToHive() then
            print("🔄 Pollen stagnant or ready to convert, moving to hive")
            startConverting()
        else
            -- Collect tokens while farming
            collectTokens()
        end
        
    elseif toggles.isConverting and toggles.atHive then
        if shouldReturnToField() then
            print("✅ Pollen converted, returning to field")
            startFarming()
        end
    end
end

-- Walkspeed Management
local function updateWalkspeed()
    if not toggles.walkspeedEnabled then return end
    local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
    if humanoid then 
        humanoid.WalkSpeed = toggles.walkspeed 
    end
end

-- Token Management
local function clearVisitedTokens()
    if tick() - toggles.lastTokenClearTime >= TOKEN_CLEAR_INTERVAL then
        toggles.visitedTokens = {}
        toggles.lastTokenClearTime = tick()
    end
end

-- GUI Setup
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/SaveManager.lua"))()

local Window = Library:CreateWindow({
    Title = "Bee Farm Bot",
    Footer = "v2.7 - Fixed Pollen Logic",
    ToggleKeybind = Enum.KeyCode.RightControl,
    Center = true,
    AutoShow = true,
    ShowCustomCursor = false,
    Size = UDim2.fromOffset(720, 400),
    Resizable = false
})

-- Home Tab
local HomeTab = Window:AddTab("Home", "house")
local HomeLeftGroupbox = HomeTab:AddLeftGroupbox("Stats")
local WrappedLabel = HomeLeftGroupbox:AddLabel({ Text = "Waiting for data...", DoesWrap = true })

-- Farming Tab
local MainTab = Window:AddTab("Farming", "shovel")

-- Farming Settings
local FarmingGroupbox = MainTab:AddLeftGroupbox("Farming Settings")
FarmingGroupbox:AddDropdown("FieldDropdown", {
    Values = {"Mango Field", "Blueberry Field", "Daisy Field", "Cactus Field", "Strawberry Field", "Apple Field", "Lemon Field", "Grape Field", "Watermelon Field", "Forest Field", "Pear Field", "Mushroom Field", "Clover Field", "Bamboo Field", "Glitch Field", "Cave Field", "Mountain Field"},
    Default = 1,
    Multi = false,
    Text = "Field",
    Tooltip = "Select field to farm",
    Callback = function(Value)
        toggles.field = Value
    end
})

FarmingGroupbox:AddToggle("AutoFarmToggle", {
    Text = "Auto Farm",
    Default = false,
    Tooltip = "Start automated farming",
    Callback = function(Value)
        toggles.autoFarm = Value
        if Value then
            startFarming()
        else
            toggles.isFarming = false
            toggles.isConverting = false
            toggles.atField = false
            toggles.atHive = false
        end
    end
})

FarmingGroupbox:AddToggle("AutoDigToggle", {
    Text = "Auto Dig",
    Default = false,
    Tooltip = "Automatically use tools to collect pollen",
    Callback = function(Value)
        toggles.autoDig = Value
        if Value and toggles.atField and not toggles.isConverting then
            coroutine.wrap(DigLoop)()
        end
    end
})

-- Movement Settings
local MovementGroupbox = MainTab:AddRightGroupbox("Movement Settings")
MovementGroupbox:AddDropdown("MovementMethod", {
    Values = {"Walk", "Tween"},
    Default = 1,
    Multi = false,
    Text = "Movement Method",
    Tooltip = "How to move between locations",
    Callback = function(Value)
        toggles.movementMethod = Value
    end
})

MovementGroupbox:AddSlider("TweenSpeed", {
    Text = "Tween Speed",
    Default = 6,
    Min = 1,
    Max = 12,
    Rounding = 1,
    Compact = false,
    Tooltip = "Tween movement speed (higher = faster)",
    Callback = function(Value)
        toggles.tweenSpeed = Value
    end
})

-- Player Settings
local PlayerGroupbox = MainTab:AddLeftGroupbox("Player Settings")
PlayerGroupbox:AddToggle("WalkspeedToggle", {
    Text = "Enable Walkspeed",
    Default = false,
    Tooltip = "Enable custom walkspeed",
    Callback = function(Value)
        toggles.walkspeedEnabled = Value
        if not Value and player.Character then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            if humanoid then humanoid.WalkSpeed = 16 end
        end
    end
})

PlayerGroupbox:AddSlider("WalkspeedSlider", {
    Text = "Walkspeed",
    Default = 50,
    Min = 16,
    Max = 100,
    Rounding = 1,
    Compact = false,
    Tooltip = "Player walkspeed",
    Callback = function(Value)
        toggles.walkspeed = Value
    end
})

-- Status Groupbox
local StatusGroupbox = MainTab:AddRightGroupbox("Status")
local StatusLabel = StatusGroupbox:AddLabel("Status: Idle")
local PollenLabel = StatusGroupbox:AddLabel("Pollen: 0")

-- UI Settings Tab
local UISettingsTab = Window:AddTab("UI Settings", "settings")
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
SaveManager:BuildConfigSection(UISettingsTab)
ThemeManager:ApplyToTab(UISettingsTab)
SaveManager:LoadAutoloadConfig()

-- Anti-AFK
player.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
end)

-- Main Loops
RunService.Heartbeat:Connect(function()
    updateFarmState()
    updateWalkspeed()
    clearVisitedTokens()
    
    -- Update status display
    local statusText = "Idle"
    local currentPollen = getCurrentPollen()
    
    if toggles.autoFarm then
        if toggles.isFarming and toggles.atField then
            statusText = "Farming at " .. toggles.field
        elseif toggles.isConverting and toggles.atHive then
            statusText = "Converting at Hive"
        elseif toggles.isFarming then
            statusText = "Moving to Field"
        elseif toggles.isConverting then
            statusText = "Moving to Hive"
        end
    end
    
    StatusLabel:SetText("Status: " .. statusText)
    PollenLabel:SetText("Pollen: " .. formatNumber(currentPollen))
end)

-- Stats Update Loop
coroutine.wrap(function()
    while task.wait(0.5) do
        local currentPollen = getCurrentPollen()
        
        WrappedLabel:SetText(string.format(
            "Pollen 🌸: %s\nField: %s\nOwned Hive: %s\nMovement: %s\nAuto Dig: %s",
            formatNumber(currentPollen),
            toggles.field,
            displayHiveName,
            toggles.movementMethod,
            toggles.autoDig and "ON" or "OFF"
        ))
    end
end)()

print("🎯 Bee Farm Bot loaded successfully!")
print("🔍 Hive detection active - checking every 10 seconds")
if ownedHive then
    print("🏠 Initial hive detected: " .. ownedHive)
else
    print("❌ No hive owned yet - waiting for hive acquisition...")
end
