--[[ INSERT FILES - FISH IT (BETA) | ASCII SAFE
Features:
- Auto Fish (normal / instant), Freeze while fishing
- Auto Sell (public, minute timer)
- Weather autobuy (select)
- Player Settings: TP, WalkSpeed, Infinite Jump, Anti-AFK, Streamer Mode
- Islands TP
- Performance Boost + HUD
- Rejoin / Server Hop
- Discord Webhook for catches (anti duplicate, correct name/rarity)

Notes:
- This file is ASCII only. No emoji or fancy punctuation.
]]--

-- Services
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local LP = Players.LocalPlayer

-- UI
local Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"))()
local Window = Rayfield:CreateWindow({
    Name = "INSERT FILES - FISH IT (BETA)",
    LoadingTitle = "INSERT FILES",
    LoadingSubtitle = "FISH IT (BETA)",
    Theme = "Amethyst",
    ConfigurationSaving = {Enabled = false},
    KeySystem = false
})

-- Tabs (fixed order)
local TabInfo  = Window:CreateTab("Developer Info", "message-circle")
local TabFish  = Window:CreateTab("Auto Fish", "fish")
local TabSell  = Window:CreateTab("Sell", "dollar-sign")
local TabWeath = Window:CreateTab("Weather", "cloud")
local TabPlay  = Window:CreateTab("Player Settings", "user")
local TabIsles = Window:CreateTab("Islands", "map")
local TabPerf  = Window:CreateTab("Performance", "gauge")
local TabUtil  = Window:CreateTab("Utilities", "wrench")
local TabHook  = Window:CreateTab("Webhook", "bell")

local function Notify(t, c, d) Rayfield:Notify({Title=t, Content=c or "", Duration=d or 3}) end

-- Dev Info
local DISCORD = "https://discord.gg/eSMZkvyZdu"
TabInfo:CreateParagraph({
    Title = "INSERT FILES - FISH IT (BETA)",
    Content = "Auto Fish, Auto Sell, Weather autobuy, Player Settings, FPS Boost, HUD, Hop/Islands, Webhook."
})
TabInfo:CreateButton({
    Name = "JOIN DISCORD (copy to clipboard)",
    Callback = function()
        if setclipboard then pcall(setclipboard, DISCORD); Notify("Discord","Link copied")
        else Notify("Discord","Executor has no setclipboard") end
    end
})

-- Remotes
local net = RS:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
local RE_Equip       = net:WaitForChild("RE/EquipToolFromHotbar")
local RF_Charge      = net:WaitForChild("RF/ChargeFishingRod")
local RF_StartMini   = net:WaitForChild("RF/RequestFishingMinigameStarted")
local RE_Completed   = net:WaitForChild("RE/FishingCompleted")
local RF_BuyWeather  = net:WaitForChild("RF/PurchaseWeatherEvent")

-- State for fishing
local S = {
    autoFish=false, usePerfectCast=true, recastDelay=1.6,
    autoPerfect=false, learnedArgs=nil, inMinigame=false, completeDelay=0.25,
    freezeOnFish=true, _frozen=false
}

local function setFrozen(state)
    local ch = LP.Character
    if not ch then return end
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    if state and not S._frozen then
        S._frozen = true
        hum.PlatformStand = true
        hrp.Anchored = true
    elseif (not state) and S._frozen then
        S._frozen = false
        hum.PlatformStand = false
        hrp.Anchored = false
    end
end

-- Webhook section (config + parser)
local Webhook = {
    enabled=false, url="",
    sendCommon=false, sendUncommon=false, sendRare=true, sendEpic=true,
    sendLegendary=true, sendMythic=true, sendSecret=true,
    debug=false
}
TabHook:CreateToggle({Name="Enable Webhook", CurrentValue=false, Callback=function(v) Webhook.enabled=v end})
TabHook:CreateInput({Name="Webhook URL", PlaceholderText="https://discord.com/api/webhooks/...", RemoveTextAfterFocusLost=false, Callback=function(t) Webhook.url=t or "" end})
local function addT(name,key,def) Webhook[key]=def; TabHook:CreateToggle({Name=name,CurrentValue=def,Callback=function(v) Webhook[key]=v end}) end
TabHook:CreateSection("Filter rarities to send")
addT("Common","sendCommon",false)
addT("Uncommon","sendUncommon",false)
addT("Rare","sendRare",true)
addT("Epic","sendEpic",true)
addT("Legendary","sendLegendary",true)
addT("Mythic","sendMythic",true)
addT("Secret","sendSecret",true)
TabHook:CreateToggle({Name="Debug console", CurrentValue=false, Callback=function(v) Webhook.debug=v end})

local function bestRequest() return (syn and syn.request) or (http and http.request) or http_request or request end
local tierNames = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret"}
local rarityColor = {common=0xA0A0A0,uncommon=0x4CAF50,rare=0x1E90FF,epic=0x9C27B0,legendary=0xFFC107,mythic=0xFF5722,secret=0xE91E63}
local function normStr(v) return typeof(v)=="string" and v or (v~=nil and tostring(v) or nil) end
local function normRarity(r)
    if r==nil then return nil end
    if typeof(r)=="number" then
        local n=math.clamp(math.floor(r+0.5),1,#tierNames); return tierNames[n]
    end
    local s=tostring(r):gsub("_"," "):lower()
    for _,nm in ipairs(tierNames) do if s:find(nm:lower(),1,true) then return nm end end
    return s:gsub("^%l", string.upper)
end
local function extractFishInfo(args)
    local seen,out={}, {name=nil,rarity=nil,weight=nil,value=nil}
    local function walk(v,depth)
        depth=depth or 0; if depth>4 or v==nil then return end
        if typeof(v)=="table" and not seen[v] then
            seen[v]=true
            for k,val in pairs(v) do
                local key=tostring(k):lower()
                if not out.name   and (key=="fish" or key=="fishname" or key=="name" or key=="item" or key=="displayname") then out.name=normStr(val)
                elseif not out.rarity and (key=="rarity" or key=="tier" or key=="tiername" or key=="quality") then out.rarity=normRarity(val)
                elseif not out.weight and (key=="weight" or key=="kg" or key=="mass") then out.weight=normStr(val)
                elseif not out.value  and (key=="value" or key=="price" or key=="coins" or key=="sellprice") then out.value=normStr(val)
                end
            end
            for _,val in pairs(v) do walk(val,depth+1) end
        end
    end
    if typeof(args)=="table" then for _,v in ipairs(args) do walk(v,0) end end
    return out
end
local function shouldSendByRarity(r)
    local k=(r or "Common"):lower()
    if k=="common" then return Webhook.sendCommon end
    if k=="uncommon" then return Webhook.sendUncommon end
    if k=="rare" then return Webhook.sendRare end
    if k=="epic" then return Webhook.sendEpic end
    if k=="legendary" then return Webhook.sendLegendary end
    if k=="mythic" then return Webhook.sendMythic end
    if k=="secret" then return Webhook.sendSecret end
    return true
end
local function sendWebhook(payload)
    if not Webhook.enabled or Webhook.url=="" then return end
    local req = bestRequest(); if not req then return end
    pcall(function()
        req({Url=Webhook.url, Method="POST", Headers={["Content-Type"]="application/json"}, Body=HttpService:JSONEncode(payload)})
    end)
end
local lastSig, lastTime = nil, 0
local function handleCatchFromArgs(args)
    if Webhook.debug then warn("[Webhook Debug]", HttpService:JSONEncode(args)) end
    local info = extractFishInfo(args)
    local fishName = info.name or "Unknown Fish"
    local rarity   = info.rarity or "Unknown"
    local weight   = info.weight
    local value    = info.value
    if not shouldSendByRarity(rarity) then return end
    local sig = HttpService:JSONEncode({fishName,rarity,weight,value})
    local now = tick()
    if sig==lastSig and (now-lastTime)<3 then return end
    lastSig, lastTime = sig, now
    local clr = rarityColor[(tostring(rarity):lower())] or 0x1E90FF
    local desc = ("Name: %s\nRarity: %s"):format(fishName, rarity)
    if weight then desc = desc..("\nWeight: %s"):format(weight) end
    if value  then desc = desc..("\nValue: %s"):format(value) end
    sendWebhook({
        username = "INSERT FILES | Fish It",
        embeds = {{
            title = "New Catch",
            description = desc,
            color = clr,
            footer = { text = ("%s | %s"):format(Players.LocalPlayer.Name, os.date("%Y-%m-%d %H:%M:%S")) }
        }}
    })
end
_G.__IF_FISH_HOOK = handleCatchFromArgs

-- Namecall hook (auto perfect, freeze toggle, webhook trigger)
local originalNamecall
local function installHook()
    if originalNamecall then return end
    local mt = getrawmetatable(game); if not mt then return end
    originalNamecall = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local m = getnamecallmethod()
        local args = {...}
        local n = tostring(self.Name)

        if (m=="FireServer" or m=="InvokeServer") and n=="RE/FishingCompleted" then
            if not S.autoPerfect then S.learnedArgs=args end
            task.spawn(function() RunService.Heartbeat:Wait(); pcall(function() _G.__IF_FISH_HOOK and _G.__IF_FISH_HOOK(args) end) end)
            S.inMinigame=false
            if S.freezeOnFish then setFrozen(false) end
        end

        if (m=="FireServer" or m=="InvokeServer") and n=="RF/RequestFishingMinigameStarted" then
            S.inMinigame=true
            if S.freezeOnFish then setFrozen(true) end
            if S.autoPerfect then
                task.spawn(function()
                    RunService.Heartbeat:Wait()
                    task.wait(S.completeDelay)
                    if S.inMinigame then
                        if S.learnedArgs and #S.learnedArgs>0 then RE_Completed:FireServer(table.unpack(S.learnedArgs)) else RE_Completed:FireServer() end
                        S.inMinigame=false
                        if S.freezeOnFish then setFrozen(false) end
                    end
                end)
            end
        end
        return originalNamecall(self, table.unpack(args))
    end)
    setreadonly(mt, true)
end
installHook()

local function startAutoFish()
    task.spawn(function()
        while S.autoFish do
            pcall(function()
                RE_Equip:FireServer(1)
                task.wait(0.1)
                RF_Charge:InvokeServer(os.clock() + math.random())
                task.wait(0.1)
                local x,y
                if S.usePerfectCast then x=-1.238; y=0.969 else x=math.random(-1000,1000)/1000; y=math.random(0,1000)/1000 end
                RF_StartMini:InvokeServer(x,y)
                task.wait(1.2)
                if S.learnedArgs and #S.learnedArgs>0 then RE_Completed:FireServer(table.unpack(S.learnedArgs)) else RE_Completed:FireServer() end
            end)
            task.wait(S.recastDelay)
        end
    end)
end

TabFish:CreateToggle({ Name="Enable Auto Fishing (normal)", CurrentValue=false, Callback=function(v) S.autoFish=v; if v then S.autoPerfect=false; Notify("Auto Fishing","Started"); startAutoFish() else Notify("Auto Fishing","Stopped"); setFrozen(false) end end })
TabFish:CreateToggle({ Name="Use Perfect Cast values", CurrentValue=true, Callback=function(v) S.usePerfectCast=v end })
TabFish:CreateSlider({ Name="Auto Recast Delay (sec)", Range={0.5,5}, Increment=0.1, CurrentValue=S.recastDelay, Callback=function(v) S.recastDelay=v end })
TabFish:CreateToggle({ Name="Auto-Perfect (instant complete)", CurrentValue=false, Callback=function(v) S.autoPerfect=v; if v then S.autoFish=false; installHook(); Notify("Auto-Perfect","ON") else Notify("Auto-Perfect","OFF") end end })
TabFish:CreateSlider({ Name="Instant Complete Delay (sec)", Range={0.05,0.5}, Increment=0.05, CurrentValue=S.completeDelay, Callback=function(v) S.completeDelay=v end })
TabFish:CreateToggle({ Name="Freeze character while fishing", CurrentValue=true, Callback=function(v) S.freezeOnFish=v; if not v then setFrozen(false) end end })
TabFish:CreateButton({ Name="Reset Learned Args", Callback=function() S.learnedArgs=nil; Notify("Learning","Cleared") end })

-- Auto Sell
local Sell = { on=false, intervalMin=5, r=nil }
local COMMON = {"RF/SellAllItems","RF/SellAllFish","RF/SellAll","RF/SellInventory","RE/SellAllItems","RE/SellAllFish","RE/SellAll","RE/SellInventory","SellAllItems","SellAllFish","SellAll","SellInventory"}
local function findSellRemote()
    local best
    for _,d in ipairs(game:GetDescendants()) do
        if d and (d:IsA("RemoteFunction") or d:IsA("RemoteEvent")) then
            local n=string.lower(d.Name)
            for _,k in ipairs(COMMON) do
                local kk=string.lower(k)
                if n==kk or n:find(kk,1,true) then
                    local score=(n:find("all",1,true) and 100 or 10)
                    if not best or score>(best.score or 0) then best={inst=d,score=score} end
                end
            end
        end
    end
    Sell.r = best and best.inst or nil
    return Sell.r
end
local function doSellOnce()
    local r = Sell.r or findSellRemote()
    if not r then Notify("Auto Sell","No Sell remote found",3); return false end
    local ok
    if r:IsA("RemoteFunction") then ok=pcall(function() r:InvokeServer() end) else ok=pcall(function() r:FireServer() end) end
    if ok then print("[AutoSell] Sent via "..r.Name) else warn("[AutoSell] Fail") end
    return ok
end
TabSell:CreateButton({ Name="Sell Now", Callback=function() doSellOnce() end })
TabSell:CreateSlider({ Name="Auto Sell Interval (minutes)", Range={1,30}, Increment=1, CurrentValue=Sell.intervalMin, Callback=function(v) Sell.intervalMin=math.clamp(math.floor(v+0.5),1,30) end })
TabSell:CreateToggle({ Name="Auto Sell (timer)", CurrentValue=false, Callback=function(v) Sell.on=v; if v then task.spawn(function() while Sell.on do doSellOnce(); local waitSec=(Sell.intervalMin or 5)*60; for i=1,waitSec do if not Sell.on then break end task.wait(1) end end end) end end })

-- Weather
local weatherList = {"Wind","Snow","Cloudy","Storm","Shark Hunt"}
local chosen = {}
for _,w in ipairs(weatherList) do
    TabWeath:CreateToggle({ Name="Select: "..w, CurrentValue=false, Callback=function(v) chosen[w]=v or nil end })
    TabWeath:CreateButton({ Name="Buy "..w, Callback=function() pcall(function() RF_BuyWeather:InvokeServer(w) end) end })
end
local autoBuy=false; local buyDelay=1.5; local cyclePause=8
TabWeath:CreateSlider({ Name="Delay per Purchase (sec)", Range={0.5,5}, Increment=0.1, CurrentValue=buyDelay, Callback=function(v) buyDelay=v end })
TabWeath:CreateSlider({ Name="Pause between cycles (sec)", Range={2,20}, Increment=1, CurrentValue=cyclePause, Callback=function(v) cyclePause=v end })
TabWeath:CreateToggle({
    Name="Auto Buy (only selected)",
    CurrentValue=false,
    Callback=function(v)
        autoBuy=v
        if v then
            task.spawn(function()
                while autoBuy do
                    local list={} for _,w in ipairs(weatherList) do if chosen[w] then table.insert(list,w) end end
                    if #list==0 then list=weatherList end
                    for _,w in ipairs(list) do if not autoBuy then break end; pcall(function() RF_BuyWeather:InvokeServer(w) end); task.wait(buyDelay) end
                    task.wait(cyclePause)
                end
            end)
        end
    end
})

-- Player Settings
local selectedPlayer = LP.Name
local function playerNames() local t={} for _,pl in ipairs(Players:GetPlayers()) do table.insert(t,pl.Name) end table.sort(t) return t end
local dd = TabPlay:CreateDropdown({ Name="Teleport to Player", Options=playerNames(), CurrentOption=selectedPlayer, MultipleOptions=false, Callback=function(opt) selectedPlayer = type(opt)=="table" and opt[1] or opt end })
Players.PlayerAdded:Connect(function() dd:Refresh(playerNames(), true) end)
Players.PlayerRemoving:Connect(function() dd:Refresh(playerNames(), true) end)
TabPlay:CreateButton({ Name="Teleport Now", Callback=function() local target=Players:FindFirstChild(selectedPlayer); local ch=target and target.Character; local hrpT=ch and ch:FindFirstChild("HumanoidRootPart"); local hrp=(LP.Character or {}).HumanoidRootPart; if hrp and hrpT then hrp.CFrame=hrpT.CFrame+Vector3.new(0,2,0); Notify("Teleport","OK") else Notify("Teleport","Target/You not ready",3) end end })

local wsEnabled=false; local wsValue=16
local function applyWS() if wsEnabled then local hum=(LP.Character or {}).Humanoid; if hum then pcall(function() hum.WalkSpeed=wsValue end) end end end
LP.CharacterAdded:Connect(function(c) c:WaitForChild("Humanoid",10); task.wait(0.1); applyWS() end)
TabPlay:CreateToggle({ Name="Enable WalkSpeed Override", CurrentValue=false, Callback=function(v) wsEnabled=v; if not v then local hum=(LP.Character or {}).Humanoid; if hum then pcall(function() hum.WalkSpeed=16 end) end else applyWS() end end })
TabPlay:CreateSlider({ Name="WalkSpeed", Range={8,120}, Increment=1, CurrentValue=wsValue, Callback=function(v) wsValue=v; applyWS() end })

local infJump=false; local IJconn
TabPlay:CreateToggle({ Name="Infinite Jump", CurrentValue=false, Callback=function(v) infJump=v; if IJconn then IJconn:Disconnect(); IJconn=nil end; if v then IJconn = UIS.JumpRequest:Connect(function() local h=(LP.Character or {}).Humanoid if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end end) end end })

local AAconn
TabPlay:CreateToggle({ Name="Anti-AFK", CurrentValue=true, Callback=function(v) if AAconn then AAconn:Disconnect() AAconn=nil end; if v then AAconn=LP.Idled:Connect(function() pcall(function() local vu=game:GetService("VirtualUser"); vu:CaptureController(); vu:ClickButton2(Vector2.new()) end) end) end end })

local streamer=false
local function hidePlatesInCharacter(char) if not char then return end for _,d in ipairs(char:GetDescendants()) do if d:IsA("BillboardGui") then pcall(function() d.Enabled=false end) end end local hum=char:FindFirstChildOfClass("Humanoid"); if hum then pcall(function() hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end) end end
local function restorePlatesInCharacter(char) if not char then return end for _,d in ipairs(char:GetDescendants()) do if d:IsA("BillboardGui") then pcall(function() d.Enabled=true end) end end local hum=char:FindFirstChildOfClass("Humanoid"); if hum then pcall(function() hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.Viewer end) end end
local function setChatVisible(v) pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, v) end); pcall(function() local tcs=game:GetService("TextChatService"); if tcs and tcs.ChatWindowConfiguration then tcs.ChatWindowConfiguration.Enabled = v end end) end
local function applyStreamerToPlayer(pl) if streamer then hidePlatesInCharacter(pl.Character) else restorePlatesInCharacter(pl.Character) end end
TabPlay:CreateToggle({ Name="Streamer Mode (hide names + chat)", CurrentValue=false, Callback=function(v) streamer=v; for _,pl in ipairs(Players:GetPlayers()) do applyStreamerToPlayer(pl) end; setChatVisible(not streamer) end })
for _,pl in ipairs(Players:GetPlayers()) do pl.CharacterAdded:Connect(function(ch) task.wait(0.2); if streamer then hidePlatesInCharacter(ch) end end) end
Players.PlayerAdded:Connect(function(pl) pl.CharacterAdded:Connect(function(ch) task.wait(0.2); if streamer then hidePlatesInCharacter(ch) end end) end)

-- Islands
local islandCoords = {
    ["01"]={name="Weather Machine",position=Vector3.new(-1471,-3,1929)},
    ["02"]={name="Esoteric Depths",position=Vector3.new(3157,-1303,1439)},
    ["03"]={name="Tropical Grove", position=Vector3.new(-2038,3,3650)},
    ["04"]={name="Stingray Shores",position=Vector3.new(-32,4,2773)},
    ["05"]={name="Kohana Volcano", position=Vector3.new(-519,24,189)},
    ["06"]={name="Coral Reefs",    position=Vector3.new(-3095,1,2177)},
    ["07"]={name="Crater Island",  position=Vector3.new(968,1,4854)},
    ["08"]={name="Kohana",         position=Vector3.new(-658,3,719)},
    ["09"]={name="Winter Fest",    position=Vector3.new(1611,4,3280)},
    ["10"]={name="Isoteric Island",position=Vector3.new(1987,4,1400)},
    ["11"]={name="Lost Isle",      position=Vector3.new(-3670.3008,-113.0,-1128.0590)},
    ["12"]={name="Lost Isle [Lost Shore]", position=Vector3.new(-3697,97,-932)},
    ["13"]={name="Lost Isle [Sisyphus]",   position=Vector3.new(-3719.8508,-113.0,-958.6303)},
    ["14"]={name="Lost Isle [Treasure Hall]", position=Vector3.new(-3652,-298.25,-1469)},
    ["15"]={name="Lost Isle [Treasure Room]", position=Vector3.new(-3652,-283.5,-1651.5)}
}
TabIsles:CreateParagraph({Title="Islands Teleport", Content="Spawn slightly above."})
for _,data in pairs(islandCoords) do
    TabIsles:CreateButton({Name=data.name, Callback=function()
        local char = Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LP.Name) or LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame=CFrame.new(data.position + Vector3.new(0,6,0)); Notify("Teleported","Now at "..data.name) else Notify("Teleport Failed","Character/HRP not found",4) end
    end})
end

-- Performance
local _orig={}
local function saveLightingOnce() if next(_orig) then return end _orig.GlobalShadows=Lighting.GlobalShadows; _orig.Brightness=Lighting.Brightness; _orig.ClockTime=Lighting.ClockTime; _orig.FogStart=Lighting.FogStart; _orig.FogEnd=Lighting.FogEnd; _orig.EnvDiff=Lighting.EnvironmentDiffuseScale; _orig.EnvSpec=Lighting.EnvironmentSpecularScale; _orig.Technology=Lighting.Technology end
saveLightingOnce()
local function setPropOnDesc(inst,cls,prop,val) for _,o in ipairs(inst:GetDescendants()) do if o:IsA(cls) then pcall(function() o[prop]=val end) end end end
local function disableClass(inst,cls) for _,o in ipairs(inst:GetDescendants()) do if o:IsA(cls) then pcall(function() if o:IsA("PostEffect") or o:IsA("Beam") or o:IsA("Trail") then o.Enabled=false elseif o:IsA("ParticleEmitter") then o.Rate=0;o.Enabled=false;o.Lifetime=NumberRange.new(0) elseif o:IsA("Smoke") then o.Opacity=0 elseif o:IsA("Fire") then o.Heat=0;o.Size=0;o.Enabled=false elseif o:IsA("SurfaceAppearance") then o.Parent=nil end end) end end end
local function stripTextures() setPropOnDesc(Workspace,"Decal","Transparency",1); setPropOnDesc(Workspace,"Texture","Transparency",1); disableClass(Workspace,"SurfaceAppearance"); for _,p in ipairs(Workspace:GetDescendants()) do if p:IsA("BasePart") then p.Material=Enum.Material.Plastic; p.Reflectance=0; p.CastShadow=false elseif p:IsA("MeshPart") then p.RenderFidelity=Enum.RenderFidelity.Performance end end end
local function killVFX() disableClass(Workspace,"ParticleEmitter"); disableClass(Workspace,"Trail"); disableClass(Workspace,"Beam"); disableClass(Workspace,"PostEffect"); for _,v in ipairs(Lighting:GetChildren()) do if v:IsA("PostEffect") or v:IsA("Atmosphere") or v:IsA("BloomEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("SunRaysEffect") or v:IsA("BlurEffect") or v:IsA("Clouds") then pcall(function() v.Enabled=false end); pcall(function() if not v:IsA("Sky") then v.Parent=nil end end) end end end
local function tuneLightingLow() Lighting.GlobalShadows=false; Lighting.Brightness=1; Lighting.ClockTime=12; Lighting.FogStart=0; Lighting.FogEnd=9e9; Lighting.EnvironmentDiffuseScale=0; Lighting.EnvironmentSpecularScale=0; pcall(function() Lighting.Technology=Enum.Technology.Compatibility end); local ter=Workspace:FindFirstChildOfClass("Terrain"); if ter then pcall(function() ter.WaterWaveSize,ter.WaterWaveSpeed=0,0; ter.WaterReflectance,ter.WaterTransparency=0,1; if typeof(ter.Decoration)=="boolean" then ter.Decoration=false end end) end end
local function setStreamingNear() Workspace.StreamingEnabled=true; Workspace.StreamingTargetRadius=64; Workspace.StreamingMinRadius=32; Workspace.RejectCharacterDeletions=false end
local function setStreamingDefault() Workspace.StreamingEnabled=true; Workspace.StreamingTargetRadius=300; Workspace.StreamingMinRadius=128 end
local function ultraLowAll() tuneLightingLow(); killVFX(); stripTextures(); setStreamingNear(); if setfpscap then pcall(setfpscap,120) end end
local function lowPreset() tuneLightingLow(); disableClass(Workspace,"PostEffect"); disableClass(Workspace,"Trail"); setPropOnDesc(Workspace,"ParticleEmitter","Rate",5); setStreamingDefault(); if setfpscap then pcall(setfpscap,120) end end
local function restoreGraphics() for k,v in pairs(_orig) do pcall(function() Lighting[k]=v end) end end

local _persist={on=false}
local function startPersistent() if _persist.on then return end; _persist.on=true; task.spawn(function() while _persist.on do ultraLowAll(); for i=1,300 do if not _persist.on then break end task.wait(1) end end end) end
local function stopPersistent() _persist.on=false end

TabPerf:CreateParagraph({Title="FPS/Graphics Boost", Content="Ultra Low kills VFX and textures. Persistent reapplies every 5 minutes."})
TabPerf:CreateToggle({Name="Ultra Low (Texture Killer + Near Streaming)", CurrentValue=false, Callback=function(v) if v then ultraLowAll() else restoreGraphics() end end})
TabPerf:CreateToggle({Name="Low Preset", CurrentValue=false, Callback=function(v) if v then lowPreset() else restoreGraphics() end end})
TabPerf:CreateToggle({Name="Persistent Boost (5m)", CurrentValue=false, Callback=function(v) if v then startPersistent() else stopPersistent() end end})
TabPerf:CreateButton({Name="Restore Lighting Defaults", Callback=function() stopPersistent(); restoreGraphics(); Notify("Performance","Lighting restored. Rejoin to restore stripped textures.") end})
TabPerf:CreateButton({Name="Quick GC", Callback=function() if collectgarbage then pcall(collectgarbage,"collect") end; Notify("Performance","GC requested") end})

-- HUD
local hudGui=Instance.new("ScreenGui"); hudGui.Name="FH_InfoHUD"; hudGui.ResetOnSpawn=false; hudGui.IgnoreGuiInset=true
pcall(function() if syn and syn.protect_gui then syn.protect_gui(hudGui) end end) hudGui.Parent=CoreGui
local hframe=Instance.new("Frame"); hframe.Size=UDim2.new(0,180,0,84); hframe.Position=UDim2.new(0,10,0,100); hframe.BackgroundColor3=Color3.fromRGB(18,18,26); hframe.BorderSizePixel=0; hframe.Active=true; hframe.Draggable=true; hframe.Parent=hudGui
Instance.new("UICorner",hframe).CornerRadius=UDim.new(0,10)
local htitle=Instance.new("TextLabel",hframe); htitle.Size=UDim2.new(1,-8,0,18); htitle.BackgroundTransparency=1; htitle.Font=Enum.Font.GothamBold; htitle.TextSize=14; htitle.TextXAlignment=Enum.TextXAlignment.Left; htitle.TextColor3=Color3.fromRGB(200,200,255); htitle.Text="Info HUD"
local htxt=Instance.new("TextLabel",hframe); htxt.Position=UDim2.new(0,0,0,24); htxt.Size=UDim2.new(1,-8,1,-24); htxt.BackgroundTransparency=1; htxt.Font=Enum.Font.Gotham; htxt.TextSize=14; htxt.TextXAlignment=Enum.TextXAlignment.Left; htxt.TextYAlignment=Enum.TextYAlignment.Top; htxt.TextColor3=Color3.fromRGB(230,230,230); htxt.Text="FPS: --\nPing: --\nMem: --\nPlayers: --"
local hudVisible=true; local function setHUDVisible(v) hudVisible=v; hframe.Visible=v end
TabUtil:CreateToggle({ Name="Show Info HUD", CurrentValue=true, Callback=function(v) setHUDVisible(v) end })
local fpsAvg=60; RunService.RenderStepped:Connect(function(dt) local f=1/dt; fpsAvg=fpsAvg*0.9+f*0.1 end)
local function getPingMS() local item=Stats.Network.ServerStatsItem["Data Ping"]; if item then local n=tonumber(string.match(item:GetValueString(),"%d+")); return n or 0 end return 0 end
task.spawn(function() while task.wait(0.5) do if not hudVisible then continue end; local ping=getPingMS(); local mem=math.floor((gcinfo() or collectgarbage("count"))/1024*100)/100; local pc=#Players:GetPlayers(); htxt.Text=string.format("FPS: %d\nPing: %d ms\nMem: %.2f MB\nPlayers: %d", math.clamp(math.floor(fpsAvg+0.5),1,999), ping, mem, pc) end end)

-- Utilities: rejoin / hop
local placeId, currentJob = game.PlaceId, game.JobId
TabUtil:CreateButton({ Name="Rejoin (same server if possible)", Callback=function() Notify("Teleport","Rejoining..."); pcall(function() TeleportService:TeleportToPlaceInstance(placeId,currentJob,LP) end); TeleportService:Teleport(placeId,LP) end })
TabUtil:CreateButton({ Name="Server Hop (random)", Callback=function() Notify("Teleport","Hopping random..."); TeleportService:Teleport(placeId,LP) end })
local function fetchServerPage(cursor) local url="https://games.roblox.com/v1/games/"..placeId.."/servers/Public?sortOrder=Asc&limit=100"; if cursor then url=url.."&cursor="..HttpService:UrlEncode(cursor) end; local body=game:HttpGet(url); return HttpService:JSONDecode(body) end
local function findLowPopServer() local tried,cursor=0,nil; while tried<5 do tried+=1; local ok,data=pcall(fetchServerPage,cursor); if not ok or not data or not data.data then break end; for _,srv in ipairs(data.data) do if srv.playing and srv.maxPlayers and srv.id then local p=tonumber(srv.playing) or 0; local maxp=tonumber(srv.maxPlayers) or 0; if p>=1 and p<=3 and p<maxp and srv.id~=currentJob then return srv.id end end end; cursor=data.nextPageCursor; if not cursor then break end end; return nil end
TabUtil:CreateButton({ Name="Server Hop (low-pop 1-3 players)", Callback=function() Notify("Teleport","Searching low-pop..."); local jobId=nil; local ok=pcall(function() jobId=findLowPopServer() end); if ok and jobId then Notify("Teleport","Found. Hopping..."); TeleportService:TeleportToPlaceInstance(placeId,jobId,LP) else Notify("Teleport","No API/match. Hopping random.",4); TeleportService:Teleport(placeId,LP) end end })

print("[INSERT FILES] Fish It (BETA) ASCII-safe loaded.")