-- AutoFish_Hybrid_Webhook_Fixed.lua
-- Hybrid version: Rayfield GUI with auto-fishing + comprehensive webhook system
-- FIXED: Proper fish name detection, hard rarity gates, watchdog system, no island filters

-- // Services
local Players               = game:GetService("Players")
local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local RunService            = game:GetService("RunService")
local UserInputService      = game:GetService("UserInputService")
local HttpService           = game:GetService("HttpService")
local TeleportService       = game:GetService("TeleportService")
local VirtualUser           = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- Anti-AFK setup
LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
end)

-- // Rayfield UI
local Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"))()
local Window = Rayfield:CreateWindow({
    Name = "Auto Fishing  Fish It (FIXED)",
    LoadingTitle = "Auto Fishing Fixed",
    LoadingSubtitle = "Fish It (Hybrid + Webhook FIXED)",
    Theme = "Amethyst",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local TabFish = Window:CreateTab("Auto Fish", "fish")
local TabWebhook = Window:CreateTab("Webhook", "radio")
local TabUtils = Window:CreateTab("Utilities", "settings")
local function Notify(t, c, d) 
    Rayfield:Notify({Title=t, Content=c or "", Duration=d or 3}) 
end

-- // Remotes
local net = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
local rodRemote      = net:WaitForChild("RF/ChargeFishingRod")
local miniGameRemote = net:WaitForChild("RF/RequestFishingMinigameStarted")
local finishRemote   = net:WaitForChild("RE/FishingCompleted")
local equipRemote    = net:WaitForChild("RE/EquipToolFromHotbar")

-- ========= Auto Fish Variables =========
local autofish = false
local perfectCast = true
local autoRecastDelay = 1.6

-- ===== WATCHDOG / KEEP ALIVE =====
local Watchdog = {
    lastAction = os.clock(),
    retryStreak = 0,
    maxRetries = 3,
    idleThreshold = 120,
    connections = {}
}

-- Connection management
local function addConnection(name, connection)
    if Watchdog.connections[name] then
        Watchdog.connections[name]:Disconnect()
    end
    Watchdog.connections[name] = connection
end

local function cleanupConnections()
    for name, connection in pairs(Watchdog.connections) do
        if connection then
            connection:Disconnect()
        end
    end
    Watchdog.connections = {}
end

-- Update last action timestamp
local function updateLastAction()
    Watchdog.lastAction = os.clock()
    if Watchdog.retryStreak > 0 then
        print("[Watchdog] Activity detected, reset retry streak")
        Watchdog.retryStreak = 0
    end
end

-- Unstuck Camera utility
local function unstuckCamera()
    local cam = workspace.CurrentCamera
    if cam then
        pcall(function()
            local oldType = cam.CameraType
            cam.CameraType = Enum.CameraType.Scriptable
            cam.CFrame = cam.CFrame + Vector3.new(0, 6, 0)
            task.wait(0.1)
            cam.CameraType = Enum.CameraType.Custom
            print("[Camera] Unstuck applied")
        end)
    end
end

-- Recovery system
local function recover()
    print("[Watchdog] Recovery initiated (retry " .. (Watchdog.retryStreak + 1) .. "/" .. Watchdog.maxRetries .. ")")
    
    -- 1. Unstuck camera
    unstuckCamera()
    task.wait(0.2)
    
    -- 2. Cancel any fishing state
    pcall(function()
        finishRemote:FireServer()
    end)
    task.wait(0.1)
    
    -- 3. Equip rod again
    pcall(function()
        equipRemote:FireServer(1)
    end)
    task.wait(0.2)
    
    -- 4. Nudge character
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        pcall(function()
            local hrp = char.HumanoidRootPart
            local nudge = Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))
            hrp.CFrame = hrp.CFrame + nudge
        end)
    end
    task.wait(0.3)
    
    -- 5. Attempt recast
    local success = pcall(function()
        local timestamp = perfectCast and 9999999999 or (tick() + math.random())
        rodRemote:InvokeServer(timestamp)
        task.wait(0.1)
        
        local x = perfectCast and -1.238 or (math.random(-1000, 1000) / 1000)
        local y = perfectCast and 0.969 or (math.random(0, 1000) / 1000)
        miniGameRemote:InvokeServer(x, y)
        
        updateLastAction()
        return true
    end)
    
    if success then
        print("[Watchdog] Recovery successful")
        Watchdog.retryStreak = 0
    else
        Watchdog.retryStreak = Watchdog.retryStreak + 1
        print("[Watchdog] Recovery failed (" .. Watchdog.retryStreak .. "/" .. Watchdog.maxRetries .. ")")
        
        -- Auto-rejoin after max retries
        if Watchdog.retryStreak >= Watchdog.maxRetries then
            print("[Watchdog] Max retries reached, rejoining...")
            pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end)
        end
    end
end

-- Watchdog monitor loop
task.spawn(function()
    while true do
        task.wait(5) -- Check every 5 seconds
        
        local idle = os.clock() - Watchdog.lastAction
        if idle > Watchdog.idleThreshold and autofish then
            print("[Watchdog] Idle detected (" .. math.floor(idle) .. "s), initiating recovery")
            recover()
        end
    end
end)

-- // Auto Fish UI Controls
TabFish:CreateParagraph({
    Title = "Auto Fish Settings",
    Content = "Gunakan toggle & slider di bawah untuk mengatur auto fishing."
})

TabFish:CreateToggle({
    Name = "Enable Auto Fishing",
    CurrentValue = false,
    Flag = "AutoFishingMain",
    Callback = function(val)
        autofish = val
        if val then
            Notify("Auto Fishing", "Started")
            updateLastAction()
            task.spawn(function()
                while autofish do
                    pcall(function()
                        -- Equip fishing rod from hotbar slot 1
                        equipRemote:FireServer(1)
                        task.wait(0.1)

                        -- Charge fishing rod with timestamp
                        local timestamp = perfectCast and 9999999999 or (tick() + math.random())
                        rodRemote:InvokeServer(timestamp)
                        task.wait(0.1)

                        -- Start minigame with coordinates
                        local x = perfectCast and -1.238 or (math.random(-1000, 1000) / 1000)
                        local y = perfectCast and 0.969 or (math.random(0, 1000) / 1000)

                        miniGameRemote:InvokeServer(x, y)
                        task.wait(1.3)
                        
                        -- Complete fishing
                        finishRemote:FireServer()
                        updateLastAction()
                    end)
                    -- Use the configurable delay
                    task.wait(autoRecastDelay)
                end
            end)
        else
            Notify("Auto Fishing", "Stopped")
        end
    end
})

TabFish:CreateToggle({
    Name = "Use Perfect Cast",
    CurrentValue = true,
    Flag = "PerfectCastToggle",
    Callback = function(val)
        perfectCast = val
        if val then
            Notify("Perfect Cast", "Enabled")
        else
            Notify("Perfect Cast", "Disabled - Using Random Cast")
        end
    end
})

TabFish:CreateSlider({
    Name = "Auto Recast Delay (seconds)",
    Range = {0.5, 5},
    Increment = 0.1,
    CurrentValue = autoRecastDelay,
    Flag = "AutoRecastDelay",
    Callback = function(val)
        autoRecastDelay = val
    end
})

-- ===== START: WEBHOOK (FIXED, NO ISLAND FILTER) =====

-- SECTION: Fish Data Index & Configuration
local FishIndex = {
    byName = {},
    byId = {},
    count = 0
}

local WebhookConfig = {
    enabled = false,
    url = "",
    -- ALL RARITY FILTERS DEFAULT OFF (HARD GATE)
    rarityFilters = {
        Common = false,
        Uncommon = false,
        Rare = false,
        Epic = false,
        Legendary = false,
        Mythic = false,
        Secret = false
    },
    lastSent = "None",
    antiDupeCache = {},
    isHooked = false
}

-- Job Queue System (FIFO) to prevent fish name mixing
local JobQueue = {
    items = {},
    processing = false
}

-- Hard gate check - if all rarity toggles are OFF, don't send anything
local function isAnyRarityEnabled()
    for _, v in pairs(WebhookConfig.rarityFilters) do
        if v == true then 
            return true 
        end
    end
    return false
end

-- SECTION: Request Function Detection
local function getRequestFunction()
    local requestFunc = (syn and syn.request) or 
                       (http and http.request) or 
                       http_request or 
                       request
    
    if not requestFunc then
        error("No HTTP request function available. Please use a proper executor.")
    end
    
    return requestFunc
end

-- SECTION: Fetch Fish Index from JSON API
local function fetchFishData()
    local url = "https://raw.githubusercontent.com/deathstrat/namefishfishititit/refs/heads/main/namaikan"
    local success = false
    local errorMessage = ""
    
    Notify("Fish Data", "Loading fish database...")
    
    -- Clear existing index
    FishIndex = {
        byName = {},
        byId = {},
        count = 0
    }
    
    -- Try multiple methods to fetch data
    local attempts = {
        -- Method 1: Custom request function
        function()
            local requestFunc = getRequestFunction()
            local response = requestFunc({
                Url = url,
                Method = "GET",
                Headers = {
                    ["User-Agent"] = "AutoFish-Webhook-Fixed/1.0"
                }
            })
            
            if response and response.StatusCode == 200 and response.Body then
                return response.Body
            elseif response then
                error("HTTP " .. (response.StatusCode or "Unknown"))
            else
                error("No response received")
            end
        end,
        
        -- Method 2: Game HttpGet fallback
        function()
            return game:HttpGet(url)
        end
    }
    
    for i, attempt in ipairs(attempts) do
        local attemptSuccess, result = pcall(attempt)
        if attemptSuccess and result and type(result) == "string" then
            -- Parse Lua data format
            local parseSuccess, count = pcall(function()
                local fishCount = 0
                
                -- Process line by line for fish data
                local currentSection = ""
                local currentFishName = ""
                local currentTier = ""
                local currentAssetId = ""
                local currentChance = ""
                local currentType = ""
                
                for line in string.gmatch(result .. "\n", "([^\n]*)\n") do
                    -- Check for new file section
                    if string.find(line, "-- ===== FILE: ") then
                        -- Save previous fish if valid
                        if currentFishName ~= "" and currentTier ~= "" and currentType == "Fishes" then
                            local rarity = "Common"
                            local tierNum = tonumber(currentTier) or 1
                            if tierNum == 1 then rarity = "Common"
                            elseif tierNum == 2 then rarity = "Uncommon" 
                            elseif tierNum == 3 then rarity = "Rare"
                            elseif tierNum == 4 then rarity = "Epic"
                            elseif tierNum == 5 then rarity = "Legendary"
                            elseif tierNum == 6 then rarity = "Mythic"
                            elseif tierNum == 7 then rarity = "Secret"
                            end
                            
                            -- Normalize name for lookup
                            local normalizedName = string.lower(string.gsub(string.gsub(
                                currentFishName, "^%s*(.-)%s*$", "%1"), "%s+", " "))
                            normalizedName = string.gsub(normalizedName, "[_%-]", " ")
                            
                            local fishItem = {
                                rarity = rarity,
                                assetId = currentAssetId ~= "" and currentAssetId or nil,
                                chance = currentChance ~= "" and tonumber(currentChance) or nil,
                                originalName = currentFishName
                            }
                            
                            -- Store by name and by ID
                            FishIndex.byName[normalizedName] = fishItem
                            if currentAssetId and currentAssetId ~= "" then
                                FishIndex.byId[tostring(currentAssetId)] = fishItem
                            end
                            
                            fishCount = fishCount + 1
                        end
                        
                        -- Reset for new section
                        currentFishName = ""
                        currentTier = ""
                        currentAssetId = ""
                        currentChance = ""
                        currentType = ""
                        
                    -- Extract fish data
                    elseif string.find(line, 'Name = "') then
                        currentFishName = string.match(line, 'Name = "([^"]+)"') or ""
                    elseif string.find(line, "Tier = ") then
                        currentTier = string.match(line, "Tier = (%d+)") or ""
                    elseif string.find(line, 'Icon = "rbxassetid://') then
                        currentAssetId = string.match(line, 'Icon = "rbxassetid://(%d+)"') or ""
                    elseif string.find(line, "Chance = ") then
                        currentChance = string.match(line, "Chance = ([%d%.e%-]+)") or ""
                    elseif string.find(line, 'Type = "') then
                        currentType = string.match(line, 'Type = "([^"]+)"') or ""
                    end
                end
                
                -- Handle last fish
                if currentFishName ~= "" and currentTier ~= "" and currentType == "Fishes" then
                    local rarity = "Common"
                    local tierNum = tonumber(currentTier) or 1
                    if tierNum == 1 then rarity = "Common"
                    elseif tierNum == 2 then rarity = "Uncommon" 
                    elseif tierNum == 3 then rarity = "Rare"
                    elseif tierNum == 4 then rarity = "Epic"
                    elseif tierNum == 5 then rarity = "Legendary"
                    elseif tierNum == 6 then rarity = "Mythic"
                    elseif tierNum == 7 then rarity = "Secret"
                    end
                    
                    local normalizedName = string.lower(string.gsub(string.gsub(
                        currentFishName, "^%s*(.-)%s*$", "%1"), "%s+", " "))
                    normalizedName = string.gsub(normalizedName, "[_%-]", " ")
                    
                    local fishItem = {
                        rarity = rarity,
                        assetId = currentAssetId ~= "" and currentAssetId or nil,
                        chance = currentChance ~= "" and tonumber(currentChance) or nil,
                        originalName = currentFishName
                    }
                    
                    FishIndex.byName[normalizedName] = fishItem
                    if currentAssetId and currentAssetId ~= "" then
                        FishIndex.byId[tostring(currentAssetId)] = fishItem
                    end
                    
                    fishCount = fishCount + 1
                end
                
                FishIndex.count = fishCount
                return fishCount
            end)
            
            if parseSuccess and count and count > 0 then
                success = true
                Notify("Fish Data", "Loaded " .. count .. " fish entries", 3)
                print("[FishData] Successfully loaded " .. count .. " entries using method " .. i)
                break
            else
                errorMessage = "Parse failed - found " .. (count or 0) .. " entries"
                print("[FishData] Method " .. i .. " parse failed: " .. errorMessage)
            end
        else
            errorMessage = tostring(result or "no result")
            print("[FishData] Method " .. i .. " failed: " .. errorMessage)
        end
    end
    
    if not success then
        print("[FishData] All methods failed. Last error: " .. errorMessage)
        Notify("Fish Data", "Failed: " .. (errorMessage:sub(1, 30) or "Unknown error"), 4)
        -- Minimal fallback
        FishIndex = {
            byName = {
                ["unknown fish"] = { 
                    rarity = "Common", 
                    assetId = nil, 
                    originalName = "Unknown Fish",
                    chance = nil
                }
            },
            byId = {},
            count = 1
        }
    end
end

-- SECTION: Fish Data Lookup with Enhanced Heuristics
local function getFishData(fishName)
    if not fishName or fishName == "" then
        return { 
            rarity = "Common", 
            assetId = nil, 
            originalName = "Unknown Fish", 
            chance = nil 
        }
    end
    
    -- Clean the fish name for lookup
    local cleanName = string.gsub(fishName, "%s*%(.-%)%s*", "") -- remove (weight) parts
    cleanName = string.gsub(cleanName, "[%d%.,%s]*kg", "") -- remove weight indicators
    cleanName = string.gsub(cleanName, "[^\32-\126]", "") -- remove non-printable chars
    cleanName = string.gsub(cleanName, "^%s*(.-)%s*$", "%1") -- trim
    
    -- Normalize for lookup
    local normalizedName = string.lower(string.gsub(string.gsub(
        cleanName, "%s+", " "), "[_%-]", " "))
    
    -- Direct lookup
    local fishData = FishIndex.byName[normalizedName]
    if fishData then
        return fishData
    end
    
    -- Heuristic fallback - try partial matches
    for indexName, data in pairs(FishIndex.byName) do
        if string.find(indexName, normalizedName, 1, true) or 
           string.find(normalizedName, indexName, 1, true) then
            return data
        end
    end
    
    -- Final fallback
    return { 
        rarity = "Common", 
        assetId = nil, 
        originalName = cleanName ~= "" and cleanName or "Unknown Fish",
        chance = nil 
    }
end

-- SECTION: Current Location Detection (for embed info only, no filtering)
local islandCoords = {
    ["Fisherman Island"] = Vector3.new(0, 4, 0),
    ["Tropical Grove"] = Vector3.new(-2038, 3, 3650),
    ["Stingray Shores"] = Vector3.new(-32, 4, 2773),
    ["Coral Reefs"] = Vector3.new(-3095, 1, 2177),
    ["Esoteric Depths"] = Vector3.new(3157, -1303, 1439),
    ["Weather Machine"] = Vector3.new(-1471, -3, 1929),
    ["Kohana Volcano"] = Vector3.new(-519, 24, 189),
    ["Crater Island"] = Vector3.new(968, 1, 4854),
    ["Kohana"] = Vector3.new(-658, 3, 719),
    ["Winter Fest"] = Vector3.new(1611, 4, 3280),
    ["Isoteric Island"] = Vector3.new(1987, 4, 1400)
}

local function getCurrentLocation()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then 
        return "Unknown" 
    end
    
    local pos = char.HumanoidRootPart.Position
    local closest = "Unknown"
    local minDistance = math.huge
    
    for islandName, islandPos in pairs(islandCoords) do
        local distance = (pos - islandPos).Magnitude
        if distance < minDistance then
            minDistance = distance
            closest = islandName
        end
    end
    
    return closest
end

-- SECTION: Anti-Dupe System (Enhanced)
local function isDuplicate(fishName, rarity, weight)
    local signature = tostring(fishName) .. "|" .. tostring(rarity) .. "|" .. tostring(weight or "none")
    local timeBucket = math.floor(tick() / 2) -- 2-second buckets for tighter control
    local key = signature .. "|" .. timeBucket
    
    if WebhookConfig.antiDupeCache[key] then
        return true
    end
    
    WebhookConfig.antiDupeCache[key] = true
    
    -- Clean old cache entries (>30 seconds)
    local currentTime = tick()
    for cacheKey, _ in pairs(WebhookConfig.antiDupeCache) do
        local cacheBucket = tonumber(string.match(cacheKey, "|(%d+)$"))
        if cacheBucket and (timeBucket - cacheBucket) > 15 then -- 30 seconds / 2
            WebhookConfig.antiDupeCache[cacheKey] = nil
        end
    end
    
    return false
end

-- SECTION: Build Discord Embed (Enhanced)
local function buildEmbed(fishName, rarity, weight, island, assetId, chance)
    local fields = {
        { name = " Fish", value = tostring(fishName), inline = true },
        { name = " Rarity", value = tostring(rarity), inline = true },
        { name = " Player", value = LocalPlayer.DisplayName .. " (" .. LocalPlayer.Name .. ")", inline = true }
    }
    
    if weight and tostring(weight) ~= "" and tostring(weight) ~= "none" then
        table.insert(fields, { name = " Weight", value = tostring(weight) .. " kg", inline = true })
    end
    
    table.insert(fields, { name = " Location", value = tostring(island or "Unknown"), inline = true })
    
    if chance and tonumber(chance) and tonumber(chance) > 0 then
        local odds = math.max(1, math.floor(1 / tonumber(chance)))
        table.insert(fields, { name = " Odds", value = "1 in " .. tostring(odds), inline = true })
    end
    
    table.insert(fields, { name = " Time", value = os.date("%Y-%m-%d %H:%M:%S"), inline = true })
    
    -- Enhanced rarity color mapping
    local colorMap = {
        Secret = 0xE74C3C,      -- Red
        Mythic = 0x57F287,      -- Green  
        Legendary = 0xF1C40F,   -- Yellow
        Epic = 0x9B59B6,        -- Purple
        Rare = 0x3498DB,        -- Blue
        Uncommon = 0x1ABC9C,    -- Teal
        Common = 0x95A5A6       -- Gray
    }
    
    local embed = {
        title = " New Catch!",
        color = colorMap[rarity] or colorMap.Common,
        fields = fields,
        footer = {
            text = "AutoFish Hybrid Fixed | " .. os.date("%H:%M:%S")
        }
    }
    
    -- Add thumbnail if assetId is available
    if assetId and tostring(assetId) ~= "" and tonumber(assetId) then
        embed.thumbnail = {
            url = "https://www.roblox.com/asset-thumbnail/image?assetId=" .. tostring(assetId) .. "&width=420&height=420&format=png"
        }
    end
    
    return {
        username = "AutoFish Hybrid Fixed",
        embeds = { embed }
    }
end

-- SECTION: HTTP Request Handler
local function safeRequest(payload)
    if not WebhookConfig.url or WebhookConfig.url == "" then
        return false, "No webhook URL set"
    end
    
    -- Validate Discord webhook URL format
    if not string.match(WebhookConfig.url, "^https://discord%.com/api/webhooks/") then
        return false, "Invalid Discord webhook URL format"
    end
    
    local success, result = pcall(function()
        local requestFunc = getRequestFunction()
        return requestFunc({
            Url = WebhookConfig.url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)
    
    if success and result and result.StatusCode then
        if result.StatusCode >= 200 and result.StatusCode < 300 then
            return true, "Success"
        else
            return false, "HTTP " .. tostring(result.StatusCode)
        end
    end
    
    return false, result and tostring(result) or "Request failed"
end

-- SECTION: Enhanced UI Scraping with Retry Logic
local function scrapeFishFromUI()
    local fishName, weight
    local startTime = tick()
    local timeout = 1.2
    local retryInterval = 0.05
    
    -- Retry loop for UI scraping
    while tick() - startTime < timeout do
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            -- Collect all text candidates
            local candidates = {}
            
            for _, gui in pairs(playerGui:GetDescendants()) do
                if gui:IsA("TextLabel") or gui:IsA("TextButton") then
                    local text = gui.Text or ""
                    if text ~= "" then
                        -- Skip system labels
                        local lowerText = string.lower(text)
                        if not string.find(lowerText, "caught") and 
                           not string.find(lowerText, "weight") and 
                           not string.find(lowerText, "new catch") and
                           not string.find(lowerText, "fishing") and
                           not string.find(lowerText, "click") and
                           not string.find(lowerText, "press") and
                           not string.find(lowerText, "tap") then
                            
                            local trimmed = string.gsub(text, "^%s*(.-)%s*$", "%1")
                            if #trimmed >= 3 and #trimmed <= 50 then
                                table.insert(candidates, {text = trimmed, gui = gui})
                            end
                        end
                        
                        -- Look for weight pattern
                        if not weight then
                            local w = string.match(text, "([%d%.,]+)%s*kg")
                            if w then
                                weight = string.gsub(w, ",", ".")
                            end
                        end
                    end
                end
            end
            
            -- Priority selection: fish from index first
            if not fishName then
                -- First priority: fish that match our index with rare+ rarity
                for _, candidate in ipairs(candidates) do
                    local fishData = getFishData(candidate.text)
                    if fishData and fishData.rarity and fishData.rarity ~= "Common" then
                        fishName = candidate.text
                        break
                    end
                end
                
                -- Second priority: text containing fish-like words
                if not fishName then
                    for _, candidate in ipairs(candidates) do
                        local lowerText = string.lower(candidate.text)
                        if string.find(lowerText, "fish") or
                           string.find(lowerText, "bass") or
                           string.find(lowerText, "tuna") or
                           string.find(lowerText, "salmon") or
                           string.find(lowerText, "cod") or
                           string.find(lowerText, "shark") then
                            fishName = candidate.text
                            break
                        end
                    end
                end
                
                -- Final fallback: first reasonable candidate
                if not fishName and #candidates > 0 then
                    fishName = candidates[1].text
                end
            end
        end
        
        -- Break if we have both pieces of info or if we have a fish name
        if (fishName and weight) or (fishName and tick() - startTime > 0.8) then
            break
        end
        
        task.wait(retryInterval)
    end
    
    return fishName, weight
end

-- SECTION: Job Queue Processor (FIFO)
local function processQueue()
    JobQueue.processing = true
    
    while #JobQueue.items > 0 do
        local job = table.remove(JobQueue.items, 1) -- FIFO: first in, first out
        
        -- Job contains: {timestamp, context}
        local jobTimestamp = job.timestamp
        local context = job.context or {}
        
        -- Wait for UI to update (critical timing)
        task.wait(0.20)
        
        -- Scrape UI for current catch (this is isolated per job)
        local fishName, weight = scrapeFishFromUI()
        
        if fishName and fishName ~= "" then
            -- Get fish data using the scraped name (not any global state)
            local fishData = getFishData(fishName)
            local finalName = fishData.originalName or fishName
            local finalRarity = fishData.rarity or "Common"
            local finalAssetId = fishData.assetId
            local finalChance = fishData.chance
            local island = getCurrentLocation()
            
            -- HARD GATE CHECKS (critical)
            if not WebhookConfig.enabled then
                print("[Queue] Webhook disabled, skipping")
                goto continue
            end
            
            if not isAnyRarityEnabled() then
                print("[Queue] No rarity filters enabled, skipping")
                goto continue
            end
            
            if not WebhookConfig.rarityFilters[finalRarity] then
                print("[Queue] Rarity " .. finalRarity .. " not enabled, skipping")
                goto continue
            end
            
            -- Anti-duplicate check
            if isDuplicate(finalName, finalRarity, weight) then
                print("[Queue] Duplicate detected, skipping")
                goto continue
            end
            
            -- Build and send webhook
            local payload = buildEmbed(finalName, finalRarity, weight, island, finalAssetId, finalChance)
            local success, message = safeRequest(payload)
            
            if success then
                WebhookConfig.lastSent = finalName .. " (" .. finalRarity .. ") at " .. os.date("%H:%M:%S")
                print("[Webhook] Sent: " .. finalName .. " (" .. finalRarity .. ") @ " .. os.date("%H:%M:%S"))
            else
                print("[Webhook] Failed: " .. message)
            end
        else
            print("[Queue] No fish name found in UI scrape")
        end
        
        ::continue::
    end
    
    JobQueue.processing = false
end

-- Function to enqueue jobs
local function enqueueJob(jobData)
    table.insert(JobQueue.items, jobData)
    print("[Queue] Enqueued job at " .. os.date("%H:%M:%S") .. " (queue size: " .. #JobQueue.items .. ")")
    
    -- Start processing if not already running
    if not JobQueue.processing then
        task.spawn(processQueue)
    end
end

-- SECTION: Hook Fishing Completion (Enhanced)
local function hookFishingCompletion()
    if WebhookConfig.isHooked then return end
    WebhookConfig.isHooked = true
    
    local mt = getrawmetatable(game)
    if not mt then 
        Notify("Webhook", "Cannot access metatable", 3)
        return 
    end
    
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local result = oldNamecall(self, ...)
        
        -- Hook the fishing completion remote
        if method == "FireServer" and self == finishRemote then
            -- Enqueue job with local context (no global state mixing)
            enqueueJob({
                timestamp = tick(),
                context = {
                    hookTime = os.date("%H:%M:%S")
                }
            })
            updateLastAction() -- Update watchdog
        end
        
        return result
    end)
    
    setreadonly(mt, true)
    Notify("Webhook", "Hook installed successfully")
    print("[Webhook] Hook installed and ready")
end

local function unhookFishingCompletion()
    WebhookConfig.isHooked = false
    -- Note: Cannot easily restore original namecall, but setting flag prevents new hooks
end

-- ====== WEBHOOK UI TAB (NO ISLAND FILTER) ======

TabWebhook:CreateParagraph({
    Title = "Discord Webhook (FIXED)",
    Content = "Kirim notifikasi tangkapan ikan ke Discord dengan filter rarity yang akurat. NO ISLAND FILTER."
})

-- Webhook URL Input
TabWebhook:CreateInput({
    Name = "Webhook URL",
    PlaceholderText = "https://discord.com/api/webhooks/....",
    NumbersOnly = false,
    CharacterLimit = 300,
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
        WebhookConfig.url = text or ""
        print("[Webhook] URL set: " .. (text and "Yes" or "No"))
    end
})

-- Enable Webhook Toggle
TabWebhook:CreateToggle({
    Name = "Enable Webhook",
    CurrentValue = false,
    Flag = "WebhookEnabled",
    Callback = function(val)
        WebhookConfig.enabled = val
        if val then
            hookFishingCompletion()
            Notify("Webhook", "Enabled - Ready to send catches")
        else
            unhookFishingCompletion()
            Notify("Webhook", "Disabled")
        end
    end
})

-- Rarity Filter Section - ALL DEFAULT OFF (HARD GATE)
TabWebhook:CreateSection("Rarity Filter (Hard Gate)")

TabWebhook:CreateParagraph({
    Title = "Hard Gate Rule",
    Content = "Semua rarity toggle DEFAULT OFF. Webhook HANYA mengirim jika toggle rarity tersebut ON. Jika SEMUA OFF = tidak kirim apapun."
})

local rarities = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"}
for _, rarity in ipairs(rarities) do
    TabWebhook:CreateToggle({
        Name = "Send " .. rarity,
        CurrentValue = false, -- ALL DEFAULT OFF
        Flag = "RarityFilter" .. rarity,
        Callback = function(val)
            WebhookConfig.rarityFilters[rarity] = val
            print("[Webhook] " .. rarity .. " filter:", val and "ON" or "OFF")
            
            -- Show current enabled rarities
            local enabled = {}
            for r, v in pairs(WebhookConfig.rarityFilters) do
                if v then table.insert(enabled, r) end
            end
            
            if #enabled > 0 then
                print("[Webhook] Enabled rarities: " .. table.concat(enabled, ", "))
            else
                print("[Webhook] NO rarities enabled - will not send anything")
            end
        end
    })
end

-- Test & Status Section
TabWebhook:CreateSection("Test & Status")

-- Send Test Button
TabWebhook:CreateButton({
    Name = "Send Test",
    Callback = function()
        if WebhookConfig.url == "" then
            Notify("Webhook", "Please set webhook URL first", 3)
            return
        end
        
        -- Create test embed with Epic rarity (always enabled for test)
        local testPayload = buildEmbed(
            "Test Fish",
            "Epic", 
            "12.5",
            getCurrentLocation(),
            nil, -- No asset ID for test
            0.001 -- 1 in 1000 odds
        )
        
        local success, message = safeRequest(testPayload)
        if success then
            Notify("Webhook", "Test sent successfully!")
            WebhookConfig.lastSent = "Test message at " .. os.date("%H:%M:%S")
        else
            Notify("Webhook", "Test failed: " .. message, 4)
        end
    end
})

-- Reload Fish Index Button
TabWebhook:CreateButton({
    Name = "Reload Fish Index",
    Callback = function()
        fetchFishData()
    end
})

-- Last Sent Status Label (updated dynamically)
local LastSentLabel = TabWebhook:CreateLabel("Last Sent: None")

-- Fish Index Info Label
local FishIndexLabel = TabWebhook:CreateLabel("Fish Index: Loading...")

-- Update status labels every 2 seconds
task.spawn(function()
    while task.wait(2) do
        pcall(function()
            LastSentLabel:Set("Last Sent: " .. WebhookConfig.lastSent)
            FishIndexLabel:Set("Fish Index: " .. FishIndex.count .. " entries loaded")
        end)
    end
end)

-- ===== END: WEBHOOK (FIXED) =====

-- ===== UTILITIES TAB =====

TabUtils:CreateParagraph({
    Title = "Utilities & Recovery",
    Content = "Tools untuk recovery dan troubleshooting."
})

-- Unstuck Camera Button
TabUtils:CreateButton({
    Name = "Unstuck Camera",
    Callback = function()
        unstuckCamera()
        Notify("Utilities", "Camera unstuck applied")
    end
})

-- Manual Recovery Button
TabUtils:CreateButton({
    Name = "Manual Recovery",
    Callback = function()
        recover()
        Notify("Utilities", "Manual recovery initiated")
    end
})

-- Reset Watchdog Button
TabUtils:CreateButton({
    Name = "Reset Watchdog",
    Callback = function()
        Watchdog.lastAction = os.clock()
        Watchdog.retryStreak = 0
        Notify("Utilities", "Watchdog reset")
        print("[Watchdog] Manually reset")
    end
})

-- Clear Anti-Dupe Cache Button
TabUtils:CreateButton({
    Name = "Clear Anti-Dupe Cache",
    Callback = function()
        WebhookConfig.antiDupeCache = {}
        Notify("Utilities", "Anti-dupe cache cleared")
        print("[Webhook] Anti-dupe cache cleared")
    end
})

-- Show Debug Info Button
TabUtils:CreateButton({
    Name = "Show Debug Info",
    Callback = function()
        print("=== DEBUG INFO ===")
        print("AutoFish Active:", autofish)
        print("Webhook Enabled:", WebhookConfig.enabled)
        print("Webhook Hooked:", WebhookConfig.isHooked)
        print("Fish Index Count:", FishIndex.count)
        print("Queue Size:", #JobQueue.items)
        print("Queue Processing:", JobQueue.processing)
        print("Last Action:", os.clock() - Watchdog.lastAction .. "s ago")
        print("Retry Streak:", Watchdog.retryStreak)
        
        local enabled = {}
        for r, v in pairs(WebhookConfig.rarityFilters) do
            if v then table.insert(enabled, r) end
        end
        print("Enabled Rarities:", #enabled > 0 and table.concat(enabled, ", ") or "NONE")
        print("=== END DEBUG ===")
        
        Notify("Utilities", "Debug info printed to console")
    end
})

-- Watchdog Status Section
TabUtils:CreateSection("Watchdog Status")

local WatchdogStatusLabel = TabUtils:CreateLabel("Status: Initializing...")
local LastActionLabel = TabUtils:CreateLabel("Last Action: Just now")

-- Update watchdog status every 3 seconds
task.spawn(function()
    while task.wait(3) do
        pcall(function()
            local idle = os.clock() - Watchdog.lastAction
            local idleStr = math.floor(idle) .. "s ago"
            
            local status = "Active"
            if idle > Watchdog.idleThreshold then
                status = "IDLE (will recover)"
            elseif Watchdog.retryStreak > 0 then
                status = "RECOVERING (" .. Watchdog.retryStreak .. "/" .. Watchdog.maxRetries .. ")"
            end
            
            WatchdogStatusLabel:Set("Status: " .. status)
            LastActionLabel:Set("Last Action: " .. idleStr)
        end)
    end
end)

-- Initialize fish data on script startup
task.spawn(function()
    task.wait(2) -- Wait for services to load
    fetchFishData()
end)

-- Cleanup on script end
game:GetService("Players").PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        cleanupConnections()
    end
end)

print("=== AutoFish Hybrid + Webhook (FIXED) Loaded ===")
print("- Fixed: Fish name accuracy with FIFO queue system")
print("- Fixed: Hard rarity gate (all OFF = no send)")
print("- Fixed: Removed island filters completely") 
print("- Fixed: Watchdog system for 24/7 operation")
print("- Fixed: Enhanced anti-duplicate system")
print("- Added: Camera unstuck utilities")
print("- Added: Comprehensive recovery system")
print("=============================================")

Notify("Script Loaded", "AutoFish Hybrid + Webhook (FIXED) ready!", 4)