--// Lavender Hub - PART 1 (WITH ANTI-LAG & DEBUG) \\--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

-- Configuration
local GRID_SIZE = 6
local CHECK_INTERVAL = 0.2
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
    antiLag = false,
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
    
    -- Pollen tracking
    lastPollenValue = 0,
    lastPollenChangeTime = 0,
    fieldArrivalTime = 0,
    hasCollectedPollen = false,
    
    -- Movement optimization
    isMoving = false,
    currentTarget = nil,
    
    -- Debug info
    objectsDeleted = 0,
    performanceStats = {
        fps = 0,
        memory = 0,
        ping = 0
    }
}

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events", 10)

-- Auto-dig variables
local digRunning = false

-- Console System
local consoleLogs = {}
local maxConsoleLines = 30
local consoleLabel = nil

-- Debug System
local debugLabels = {}

-- Auto-Save System
local saveData = {}

local function addToConsole(message)
    local timestamp = os.date("%H:%M:%S")
    local logEntry = "[" .. timestamp .. "] " .. message
    
    table.insert(consoleLogs, logEntry)
    
    if #consoleLogs > maxConsoleLines then
        table.remove(consoleLogs, 1)
    end
    
    if consoleLabel then
        consoleLabel:SetText(table.concat(consoleLogs, "\n"))
    end
end

-- Auto-Save Functions
local function saveSettings()
    local settingsToSave = {
        field = toggles.field,
        movementMethod = toggles.movementMethod,
        autoFarm = toggles.autoFarm,
        autoDig = toggles.autoDig,
        antiLag = toggles.antiLag,
        tweenSpeed = toggles.tweenSpeed,
        walkspeedEnabled = toggles.walkspeedEnabled,
        walkspeed = toggles.walkspeed
    }
    
    local success, encoded = pcall(function()
        return HttpService:JSONEncode(settingsToSave)
    end)
    
    if success then
        local writeSuccess, writeError = pcall(function()
            writefile("LavenderHub_Settings.txt", encoded)
        end)
        if writeSuccess then
            addToConsole("Settings saved")
        end
    end
end

local function loadSettings()
    local fileSuccess, content = pcall(function()
        if isfile and isfile("LavenderHub_Settings.txt") then
            return readfile("LavenderHub_Settings.txt")
        end
        return nil
    end)
    
    if fileSuccess and content then
        local decodeSuccess, decoded = pcall(function()
            return HttpService:JSONDecode(content)
        end)
        
        if decodeSuccess and decoded then
            toggles.field = decoded.field or toggles.field
            toggles.movementMethod = decoded.movementMethod or toggles.movementMethod
            toggles.autoFarm = decoded.autoFarm or toggles.autoFarm
            toggles.autoDig = decoded.autoDig or toggles.autoDig
            toggles.antiLag = decoded.antiLag or toggles.antiLag
            toggles.tweenSpeed = decoded.tweenSpeed or toggles.tweenSpeed
            toggles.walkspeedEnabled = decoded.walkspeedEnabled or toggles.walkspeedEnabled
            toggles.walkspeed = decoded.walkspeed or toggles.walkspeed
            addToConsole("Settings loaded")
            return true
        end
    end
    addToConsole("No saved settings")
    return false
end

-- Anti-Lag System
local function runAntiLag()
    if not toggles.antiLag then return end
    
    local targets = {
        -- Original fruits
        "mango", "strawberry", "fence", "blueberry", "pear",
        "apple", "orange", "banana", "grape", "pineapple",
        "watermelon", "lemon", "lime", "cherry", "peach",
        "plum", "kiwi", "coconut", "avocado", "raspberry",
        "blackberry", "pomegranate", "fig", "apricot", "melon",
        "fruit", "fruits", "berry", "berries",
        
        -- New additions
        "daisy", "cactus", "forrest", "bamboo", "bear",
        "hive", "hives", "leader", "cave", "crystal"
    }

    local deleted = 0

    for _, obj in pairs(workspace:GetDescendants()) do
        if toggles.antiLag then -- Check if still enabled
            local name = obj.Name:lower()
            for _, target in pairs(targets) do
                if name:find(target) then
                    pcall(function()
                        obj:Destroy()
                        deleted = deleted + 1
                    end)
                    break
                end
            end
        else
            break -- Stop if anti-lag was disabled
        end
    end

    toggles.objectsDeleted = toggles.objectsDeleted + deleted
    addToConsole("🌿 Deleted " .. deleted .. " laggy objects (Total: " .. toggles.objectsDeleted .. ")")
end

-- Auto Claim Hive System
local function autoClaimHive()
    if getOwnedHive() then
        addToConsole("Already have a hive")
        return true
    end
    
    addToConsole("Attempting to claim hive...")
    
    for i = 1, 6 do
        local hiveName = "Hive_" .. i
        local hive = Workspace:FindFirstChild("Hives") and Workspace.Hives:FindFirstChild(hiveName)
        
        if hive then
            local args = {hive}
            local claimRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ClaimHive")
            
            local success, result = pcall(function()
                claimRemote:FireServer(unpack(args))
            end)
            
            if success then
                addToConsole("Claimed " .. hiveName)
                task.wait(1)
                
                if getOwnedHive() then
                    addToConsole("Successfully claimed " .. hiveName)
                    return true
                else
                    addToConsole(hiveName .. " might be taken, trying next...")
                end
            else
                addToConsole("Failed to claim " .. hiveName)
            end
        else
            addToConsole(hiveName .. " not found")
        end
        
        task.wait(0.5)
    end
    
    addToConsole("No available hives found")
    return false
end

-- Performance Monitoring
local function updatePerformanceStats()
    toggles.performanceStats.fps = math.floor(1 / RunService.Heartbeat:Wait())
    
    local stats = game:GetService("Stats")
    local memory = stats:FindFirstChild("Workspace") and stats.Workspace:FindFirstChild("Memory")
    if memory then
        toggles.performanceStats.memory = math.floor(memory:GetValue() / 1024 / 1024) -- Convert to MB
    end
    
    -- Update debug display
    if debugLabels.fps then
        debugLabels.fps:SetText("FPS: " .. toggles.performanceStats.fps)
    end
    if debugLabels.memory then
        debugLabels.memory:SetText("Memory: " .. toggles.performanceStats.memory .. " MB")
    end
    if debugLabels.objects then
        debugLabels.objects:SetText("Objects Deleted: " .. toggles.objectsDeleted)
    end
end

-- Optimized Movement Functions
local function getRandomPositionInField()
    local fieldPos = fieldCoords[toggles.field]
    if not fieldPos then return nil end
    
    local fieldRadius = 25
    local randomX = fieldPos.X + math.random(-fieldRadius, fieldRadius)
    local randomZ = fieldPos.Z + math.random(-fieldRadius, fieldRadius)
    local randomY = fieldPos.Y
    
    return Vector3.new(randomX, randomY, randomZ)
end

local function performContinuousMovement()
    if not toggles.atField or toggles.isConverting or toggles.isMoving then return end
    
    local randomPos = getRandomPositionInField()
    if randomPos then
        toggles.isMoving = true
        toggles.currentTarget = randomPos
        
        local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:MoveTo(randomPos)
            spawn(function()
                task.wait(2)
                toggles.isMoving = false
                toggles.currentTarget = nil
            end)
        else
            toggles.isMoving = false
            toggles.currentTarget = nil
        end
    end
end

-- Utility Functions
local function GetCharacter()
    return player.Character or player.CharacterAdded:Wait()
end

local function SafeCall(func, name)
    local success, err = pcall(func)
    if not success then
        if not name or not name:find("DigLoop") then
            addToConsole("Error in " .. (name or "unknown") .. ": " .. err)
        end
    end
    return success
end

local function formatNumber(num)
    if num < 1000 then return tostring(math.floor(num)) end
    local suffixes = {"K", "M", "B", "T"}
    local i = 1
    while num >= 1000 and i < #suffixes do
        num = num / 1000
        i = i + 1
    end
    return string.format("%.1f%s", num, suffixes[i])
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
            addToConsole("New hive: " .. ownedHive)
            displayHiveName = "Hive"
        elseif not ownedHive and previousHive then
            addToConsole("Hive lost")
            displayHiveName = "None"
        elseif ownedHive and previousHive == nil then
            addToConsole("Hive acquired: " .. ownedHive)
            displayHiveName = "Hive"
        end
        
        toggles.lastHiveCheckTime = tick()
    end
end

-- Improved Pathfinding with Obstacle Avoidance
local function moveToPositionWalk(targetPos)
    local character = player.Character
    local humanoid = character and character:FindFirstChild("Humanoid")
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not humanoidRootPart then return false end
    
    local path = PathfindingService:CreatePath({
        AgentRadius = 3,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 4,
        Cost = {
            Water = 10,
            Lava = math.huge,
            Jump = 5,
        }
    })
    
    local success, errorMessage = pcall(function()
        path:ComputeAsync(humanoidRootPart.Position, targetPos)
    end)
    
    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for i, waypoint in ipairs(waypoints) do
            if i > 1 then
                humanoid:MoveTo(waypoint.Position)
                
                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end
                
                local moveSuccess = humanoid.MoveToFinished:Wait(5)
                if not moveSuccess then
                    addToConsole("Path blocked, finding alternative...")
                    break
                end
            end
        end
        return true
    else
        humanoid:MoveTo(targetPos)
        humanoid.MoveToFinished:Wait(8)
        return true
    end
end

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
                if toolsFired >= 5 then break end
                if tool:IsA("Tool") then
                    local remote = tool:FindFirstChild("ToolRemote") or tool:FindFirstChild("Remote")
                    if remote then
                        remote:FireServer()
                        toolsFired = toolsFired + 1
                    end
                end
            end
            
            task.wait(0.2)
        end, "DigLoop")
    end
    
    digRunning = false
end

-- Token Collection
local function getNearestToken()
    local tokensFolder = workspace:FindFirstChild("Debris") and workspace.Debris:FindFirstChild("Tokens")
    if not tokensFolder then return nil end

    for _, token in pairs(tokensFolder:GetChildren()) do
        if token:IsA("BasePart") and token:FindFirstChild("Token") and token:FindFirstChild("Collecting") and not token.Collecting.Value then
            local distance = (token.Position - player.Character.HumanoidRootPart.Position).Magnitude
            if distance <= 30 and not toggles.visitedTokens[token] then
                return token, distance
            end
        end
    end
    return nil
end

local function areTokensNearby()
    local token = getNearestToken()
    return token ~= nil
end

local function collectTokens()
    if not toggles.autoFarm or toggles.isConverting or not toggles.atField then return end
    
    local token = getNearestToken()
    if token then
        local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:MoveTo(token.Position)
            local startTime = tick()
            while (player.Character.HumanoidRootPart.Position - token.Position).Magnitude > 4 and tick() - startTime < 3 do
                if not token.Parent then break end
                task.wait()
            end
            if token.Parent and (player.Character.HumanoidRootPart.Position - token.Position).Magnitude <= 4 then
                toggles.visitedTokens[token] = true
            end
        end
    end
end

-- Pollen Tracking
local function updatePollenTracking()
    if not toggles.atField then return end
    
    local currentPollen = getCurrentPollen()
    
    if currentPollen > 0 and not toggles.hasCollectedPollen then
        toggles.hasCollectedPollen = true
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
    
    return toggles.hasCollectedPollen and (timeSinceLastChange >= 5 or currentPollen == 0)
end

local function shouldReturnToField()
    if not toggles.isConverting or not toggles.atHive then return false end
    
    local currentPollen = getCurrentPollen()
    return currentPollen == 0
end
--// Lavender Hub - PART 2 (WITH ANTI-LAG & DEBUG) \\--

-- Farming Logic
local function startFarming()
    if not toggles.autoFarm or toggles.isFarming or not ownedHive then return end
    
    local fieldPos = fieldCoords[toggles.field]
    if not fieldPos then return end
    
    toggles.isFarming = true
    toggles.isConverting = false
    toggles.atField = false
    toggles.atHive = false
    toggles.isMoving = false
    
    -- Reset pollen tracking
    toggles.lastPollenValue = getCurrentPollen()
    toggles.lastPollenChangeTime = tick()
    toggles.fieldArrivalTime = tick()
    toggles.hasCollectedPollen = false
    
    addToConsole("Moving to: " .. toggles.field)
    
    -- Move to field
    if moveToPosition(fieldPos) then
        toggles.atField = true
        local initialPollen = getCurrentPollen()
        toggles.lastPollenValue = initialPollen
        toggles.lastPollenChangeTime = tick()
        toggles.fieldArrivalTime = tick()
        toggles.hasCollectedPollen = (initialPollen > 0)
        
        addToConsole("Arrived at field")
        
        -- Start auto-dig if enabled
        if toggles.autoDig then
            spawn(DigLoop)
        end
    else
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
    toggles.isMoving = false
    
    addToConsole("Moving to hive")
    
    -- Move to hive
    if moveToPosition(hivePos) then
        toggles.atHive = true
        addToConsole("At hive")
        
        task.wait(2)
        
        -- Start honey making
        local args = {true}
        local makeHoneyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MakeHoney")
        if makeHoneyRemote then
            makeHoneyRemote:FireServer(unpack(args))
            addToConsole("Converting honey")
        end
    else
        toggles.isConverting = false
    end
end

-- Main Loop
local lastUpdateTime = 0
local function updateFarmState()
    if not toggles.autoFarm then return end
    
    local currentTime = tick()
    if currentTime - lastUpdateTime < CHECK_INTERVAL then return end
    lastUpdateTime = currentTime
    
    -- Check hive ownership periodically
    checkHiveOwnership()
    
    -- Update pollen tracking
    updatePollenTracking()
    
    -- State transitions
    if toggles.isFarming and toggles.atField then
        if shouldConvertToHive() then
            addToConsole("Converting to honey")
            startConverting()
        else
            -- Always try to collect tokens first
            collectTokens()
            
            -- Continuous movement when not collecting tokens
            if not toggles.isMoving and not areTokensNearby() then
                performContinuousMovement()
            end
        end
        
    elseif toggles.isConverting and toggles.atHive then
        if shouldReturnToField() then
            addToConsole("Returning to field")
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
    Title = "Lavender Hub",
    Footer = "v0.2",
    ToggleKeybind = Enum.KeyCode.RightControl,
    Center = true,
    AutoShow = true,
    ShowCustomCursor = false,
    Size = UDim2.fromOffset(650, 500), -- Slightly larger for debug
    Resizable = false
})

-- Home Tab
local HomeTab = Window:AddTab("Home", "house")
local HomeLeftGroupbox = HomeTab:AddLeftGroupbox("Stats")
local WrappedLabel = HomeLeftGroupbox:AddLabel({ Text = "Loading...", DoesWrap = true })

-- Farming Tab
local MainTab = Window:AddTab("Farming", "shovel")

-- Farming Settings
local FarmingGroupbox = MainTab:AddLeftGroupbox("Farming")
local FieldDropdown = FarmingGroupbox:AddDropdown("FieldDropdown", {
    Values = {"Mango Field", "Blueberry Field", "Daisy Field", "Cactus Field", "Strawberry Field", "Apple Field", "Lemon Field", "Grape Field", "Watermelon Field", "Forest Field", "Pear Field", "Mushroom Field", "Clover Field", "Bamboo Field", "Glitch Field", "Cave Field", "Mountain Field"},
    Default = 1,
    Multi = false,
    Text = "Field",
    Callback = function(Value)
        toggles.field = Value
        saveSettings()
    end
})

local AutoFarmToggle = FarmingGroupbox:AddToggle("AutoFarmToggle", {
    Text = "Auto Farm",
    Default = false,
    Callback = function(Value)
        toggles.autoFarm = Value
        saveSettings()
        if Value then
            startFarming()
        else
            toggles.isFarming = false
            toggles.isConverting = false
            toggles.atField = false
            toggles.atHive = false
            toggles.isMoving = false
        end
    end
})

local AutoDigToggle = FarmingGroupbox:AddToggle("AutoDigToggle", {
    Text = "Auto Dig",
    Default = false,
    Callback = function(Value)
        toggles.autoDig = Value
        saveSettings()
    end
})

-- Movement Settings
local MovementGroupbox = MainTab:AddRightGroupbox("Movement")
local MovementMethodDropdown = MovementGroupbox:AddDropdown("MovementMethod", {
    Values = {"Walk", "Tween"},
    Default = 1,
    Multi = false,
    Text = "Method",
    Callback = function(Value)
        toggles.movementMethod = Value
        saveSettings()
    end
})

local TweenSpeedSlider = MovementGroupbox:AddSlider("TweenSpeed", {
    Text = "Tween Speed",
    Default = 6,
    Min = 1,
    Max = 12,
    Rounding = 1,
    Compact = true,
    Callback = function(Value)
        toggles.tweenSpeed = Value
        saveSettings()
    end
})

-- Player Settings
local PlayerGroupbox = MainTab:AddLeftGroupbox("Player")
local WalkspeedToggle = PlayerGroupbox:AddToggle("WalkspeedToggle", {
    Text = "Walkspeed",
    Default = false,
    Callback = function(Value)
        toggles.walkspeedEnabled = Value
        saveSettings()
        if not Value and player.Character then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            if humanoid then humanoid.WalkSpeed = 16 end
        end
    end
})

local WalkspeedSlider = PlayerGroupbox:AddSlider("WalkspeedSlider", {
    Text = "Speed",
    Default = 50,
    Min = 16,
    Max = 100,
    Rounding = 1,
    Compact = true,
    Callback = function(Value)
        toggles.walkspeed = Value
        saveSettings()
    end
})

-- Anti-Lag Settings
local AntiLagGroupbox = MainTab:AddRightGroupbox("Performance")
local AntiLagToggle = AntiLagGroupbox:AddToggle("AntiLagToggle", {
    Text = "Anti Lag",
    Default = false,
    Tooltip = "Delete fruits and nature objects to reduce lag",
    Callback = function(Value)
        toggles.antiLag = Value
        saveSettings()
        if Value then
            addToConsole("Anti-Lag enabled - cleaning objects...")
            runAntiLag()
        else
            addToConsole("Anti-Lag disabled")
        end
    end
})

-- Console Tab
local ConsoleTab = Window:AddTab("Console", "terminal")
local ConsoleGroupbox = ConsoleTab:AddLeftGroupbox("Output")
consoleLabel = ConsoleGroupbox:AddLabel({ Text = "Lavender Hub v0.2 - Ready", DoesWrap = true })

-- Debug Tab
local DebugTab = Window:AddTab("Debug", "bug")
local DebugGroupbox = DebugTab:AddLeftGroupbox("Performance Stats")
debugLabels.fps = DebugGroupbox:AddLabel("FPS: 0")
debugLabels.memory = DebugGroupbox:AddLabel("Memory: 0 MB")
debugLabels.objects = DebugGroupbox:AddLabel("Objects Deleted: 0")

local DebugActionsGroupbox = DebugTab:AddRightGroupbox("Actions")
DebugActionsGroupbox:AddButton("Run Anti-Lag", function()
    if toggles.antiLag then
        runAntiLag()
    else
        addToConsole("Enable Anti-Lag first")
    end
end)

DebugActionsGroupbox:AddButton("Claim Hive", function()
    autoClaimHive()
end)

DebugActionsGroupbox:AddButton("Clear Console", function()
    consoleLogs = {}
    if consoleLabel then
        consoleLabel:SetText("Console cleared")
    end
end)

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

-- Optimized Main Loops
local lastHeartbeatTime = 0
RunService.Heartbeat:Connect(function()
    local currentTime = tick()
    if currentTime - lastHeartbeatTime < 0.1 then return end
    lastHeartbeatTime = currentTime
    
    updateFarmState()
    updateWalkspeed()
    clearVisitedTokens()
    updatePerformanceStats()
    
    -- Update status display
    local statusText = "Idle"
    local currentPollen = getCurrentPollen()
    
    if toggles.autoFarm then
        if toggles.isFarming and toggles.atField then
            statusText = "Farming"
        elseif toggles.isConverting and toggles.atHive then
            statusText = "Converting"
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
local lastStatsUpdate = 0
spawn(function()
    while task.wait(1) do
        local currentPollen = getCurrentPollen()
        
        WrappedLabel:SetText(string.format(
            "Pollen: %s\nField: %s\nHive: %s\nMove: %s\nDig: %s\nAnti-Lag: %s",
            formatNumber(currentPollen),
            toggles.field,
            displayHiveName,
            toggles.movementMethod,
            toggles.autoDig and "ON" or "OFF",
            toggles.antiLag and "ON" or "OFF"
        ))
    end
end)

-- Load settings on startup
loadSettings()

-- Apply loaded settings to GUI
FieldDropdown:Set(toggles.field)
AutoFarmToggle:Set(toggles.autoFarm)
AutoDigToggle:Set(toggles.autoDig)
AntiLagToggle:Set(toggles.antiLag)
MovementMethodDropdown:Set(toggles.movementMethod)
TweenSpeedSlider:Set(toggles.tweenSpeed)
WalkspeedToggle:Set(toggles.walkspeedEnabled)
WalkspeedSlider:Set(toggles.walkspeed)

-- Auto claim hive on startup
spawn(function()
    task.wait(2)
    if not getOwnedHive() then
        addToConsole("No hive detected, auto-claiming...")
        autoClaimHive()
    end
end)

-- Run anti-lag on startup if enabled
spawn(function()
    task.wait(3)
    if toggles.antiLag then
        addToConsole("Running startup Anti-Lag...")
        runAntiLag()
    end
end)

-- Initial console message
addToConsole("Lavender Hub v0.2 loaded")
addToConsole("Auto-save enabled")
addToConsole("Continuous movement enabled")
addToConsole("Anti-Lag system ready")
addToConsole("Debug panel available")
if ownedHive then
    addToConsole("Hive: " .. ownedHive)
else
    addToConsole("No hive detected")
end
