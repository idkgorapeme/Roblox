if not game:IsLoaded() then
    game.Loaded:Wait()
end
local env = getgenv()

-- if a previous session is still alive (re-execute without rejoining), tear it down first
if env.BrainrotPolice and env.BrainrotPolice.unload then
    pcall(env.BrainrotPolice.unload)
end

-- shared registry so the unload button can undo everything we touch
env.BrainrotPolice = {
    connections = {},
    globals = {}
}

function env.BrainrotPolice.track(conn)
    table.insert(env.BrainrotPolice.connections, conn)
    return conn
end

if not isfolder("BrainrotPolice") then makefolder("BrainrotPolice") end
if not isfile("BrainrotPolice/Config.json") then
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode({
        settings = {
            auto_rejoin_on_kick = false,
            disable_3d_rendering = false
        }
    }))
end

function env.import(id)
    return game:GetObjects(id)[1]
end

function env.getgitpath(where)
    local mainBuild = "https://raw.githubusercontent.com/idkgorapeme/Roblox/refs/heads/arena/019f9f73-roblox/"
    if where == "src" then
        return mainBuild .. "src/"
    elseif where == "games" then
        return mainBuild .. "src/games/"
    end
end

-- raw.githubusercontent caches for several minutes, so a fresh push can keep
-- serving the old file. append a unique query string to bust the cache.
function env.gitfetch(url)
    local sep = string.find(url, "?", 1, true) and "&" or "?"
    return game:HttpGet(url .. sep .. "bp=" .. tostring(tick()) .. "_" .. tostring(math.random(1, 1e6)))
end

function env.setconfig(key, value)
    local httpservice = game:GetService("HttpService")
    local dec = httpservice:JSONDecode(readfile("BrainrotPolice/Config.json"))
    dec[tostring(game.PlaceId)] = dec[tostring(game.PlaceId)] or {}
    dec[tostring(game.PlaceId)][key] = value
    writefile("BrainrotPolice/Config.json", httpservice:JSONEncode(dec))
end

env.BrainrotPolice.track(game:GetService("GuiService").ErrorMessageChanged:Connect(function()
    if env.autorjjjj then
        game:GetService("TeleportService"):Teleport(game.PlaceId)
    end
end))

game:GetService("GuiService"):SetGameplayPausedNotificationEnabled(false)

-- every getgenv key we (or a game module) may set, so unload can wipe them
env.BrainrotPolice.globals = {
    "import", "getgitpath", "setconfig", "autorjjjj", "FileScripts",
    "AddingSpins", "AutoBest", "AutoBuy", "AutoCollect", "AutoDig", "AutoMoney",
    "AutoOg", "AutoRebirth", "AutoSleepy", "AutoSpeed", "Autosell", "ChosenZone",
    "Collect", "CrateRarity", "Fakee", "FarmBrainrots", "FarmEvolve", "FarmRots",
    "FarmWings", "FarmWins", "Farming", "Farminga", "Kill", "MaxPrice", "Rebirth",
    "Selling", "ShowGlass", "Strength", "Upgrade", "WinFarm", "WinStage", "collect", "equip",
    "farming", "stealfromall",
    "AutoWin", "KeyFarm", "KeyHighlight", "World2Help", "World2Destroy",
    "MacroPlaying", "MacroRecording",
    "BPFly", "BPInfJump", "BPNoclip", "AutoPrestige", "AutoClickAttack",
    "DBCollect", "DBUpgrade", "DBRebirth", "SBPump", "SBUpgrade", "SBLaunch", "SBFuel", "MNLock", "MNMerge", "SSWin", "SSRebirth", "KEWin1", "KEWin2", "KEDestroy", "KECoins", "KEBuy", "KSWalk", "KSBuy", "KSWin", "KSDestroy"
}

function env.BrainrotPolice.unload()
    local bp = env.BrainrotPolice
    if bp.unloaded then return end
    bp.unloaded = true

    -- 1. stop every farm loop: their `while getgenv().X do` conditions go false
    for _, key in ipairs(bp.globals) do
        env[key] = nil
    end
    env.autorjjjj = false

    -- 2. drop every signal we connected
    for _, conn in ipairs(bp.connections) do
        pcall(function() conn:Disconnect() end)
    end
    bp.connections = {}

    -- 3. destroy the gui
    if bp.gui then
        pcall(function() bp.gui:Destroy() end)
        bp.gui = nil
    end

    -- 4. undo side effects on the game itself
    pcall(function() game:GetService("RunService"):Set3dRenderingEnabled(true) end)
    pcall(function() game:GetService("GuiService"):SetGameplayPausedNotificationEnabled(true) end)
    pcall(function() workspace.Gravity = 196.2 end)

    -- strip the flight body movers off the character
    pcall(function()
        local char = game:GetService("Players").LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            for _, n in ipairs({"BPFlyPos", "BPFlyGyro"}) do
                local mover = root:FindFirstChild(n)
                if mover then mover:Destroy() end
            end
        end
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
    end)

    -- 5. don't come back after a teleport
    if queue_on_teleport then
        pcall(queue_on_teleport, "")
    end

    -- 6. remove the registry itself
    env.BrainrotPolice = nil
end

loadstring(env.gitfetch(getgitpath("src").."ui.lua"))()

if queue_on_teleport then
    queue_on_teleport('loadstring(game:HttpGet("https://raw.githubusercontent.com/idkgorapeme/Roblox/refs/heads/arena/019f9f73-roblox/src/init.lua"))()')
end
