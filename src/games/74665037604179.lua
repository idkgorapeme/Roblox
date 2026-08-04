-- Watch Your Money Go Up!

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local runservice = game:GetService("RunService")
    local plr = players.LocalPlayer

    env.WMAutos = false
    env.WMZone = false
    env.WMRebirth = false
    env.WMPrestige = false
    env.WMAscend = false
    env.WMOffline = false
    env.WMPlaytime = false
    env.WMDaily = false
    env.WMBoosts = false
    env.WMPickup = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autos = setdata.autos or false
    setdata.zone = setdata.zone or false
    setdata.rebirth = setdata.rebirth or false
    setdata.prestige = setdata.prestige or false
    setdata.ascend = setdata.ascend or false
    setdata.offline = setdata.offline or false
    setdata.playtime = setdata.playtime or false
    setdata.daily = setdata.daily or false
    setdata.boosts = setdata.boosts or false
    setdata.pickup = setdata.pickup or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- lazily resolved, a missing remote can never block the UI
    local function remote(name)
        local folder = replicatedstorage:FindFirstChild("Remotes")
        return folder and folder:FindFirstChild(name) or nil
    end

    -- fires a RemoteEvent or invokes a RemoteFunction, whichever it is
    local function call(name, ...)
        local ev = remote(name)
        if not ev then return false end

        local args = table.pack(...)

        return (pcall(function()
            if ev:IsA("RemoteFunction") then
                ev:InvokeServer(table.unpack(args, 1, args.n))
            else
                ev:FireServer(table.unpack(args, 1, args.n))
            end
        end))
    end

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- runs a loop in its own thread, never in the toggle callback
    local function loopToggle(label, key, flag, interval, body)
        elements:Toggle(label, section, setdata[key], function(v)
            env[flag] = v
            env.setconfig(key, v)
            if not v then return end

            task.spawn(function()
                while env[flag] do
                    pcall(body)
                    task.wait(interval)
                end
            end)
        end)
    end

    ----------------------------------------------------------------
    -- unlock the game's own automation
    ----------------------------------------------------------------

    elements:Button("Enable Built-in Autos", section, function()
        -- these normally need the AU_ upgrades, worth a try anyway
        call("AutoRebirthSettings", true)
        call("AutoAscendSettings", true)
        call("SetAutoInfinity", true)
        call("AutoDeleteSettings", true)

        print("[BrainrotPolice] requested auto rebirth / ascend / infinity / delete")
        print("  AutoRebirthEnabled = " .. tostring(plr:GetAttribute("AutoRebirthEnabled")))
        print("  AutoAscendEnabled  = " .. tostring(plr:GetAttribute("AutoAscendEnabled")))
        print("  AutoInfinityEnabled = " .. tostring(plr:GetAttribute("AutoInfinityEnabled")))
        print("  AutoDeleteEnabled  = " .. tostring(plr:GetAttribute("AutoDeleteEnabled")))
    end)

    loopToggle("Keep Built-in Autos On", "autos", "WMAutos", 10, function()
        if not plr:GetAttribute("AutoRebirthEnabled") then
            call("AutoRebirthSettings", true)
        end
        if not plr:GetAttribute("AutoAscendEnabled") then
            call("AutoAscendSettings", true)
        end
        if not plr:GetAttribute("AutoInfinityEnabled") then
            call("SetAutoInfinity", true)
        end
    end)

    ----------------------------------------------------------------
    -- money: zone buttons
    ----------------------------------------------------------------

    -- workspace.LocalMoneyZoneButtons_<userid>
    local function zoneButtonFolder()
        local name = "LocalMoneyZoneButtons_" .. tostring(plr.UserId)
        local folder = workspace:FindFirstChild(name)
        if folder then return folder end

        -- fall back to any folder with that prefix
        for _, child in pairs(workspace:GetChildren()) do
            if string.sub(child.Name, 1, 22) == "LocalMoneyZoneButtons_" then
                return child
            end
        end

        return nil
    end

    loopToggle("Auto Zone Button Claim", "zone", "WMZone", 0.5, function()
        local folder = zoneButtonFolder()
        if not folder then return end

        for _, btn in pairs(folder:GetChildren()) do
            if not env.WMZone then break end
            call("ZoneButtonClaim", btn)
        end
    end)

    ----------------------------------------------------------------
    -- progression
    ----------------------------------------------------------------

    loopToggle("Auto Rebirth", "rebirth", "WMRebirth", 1, function()
        call("RebirthButtonPressed")
        call("RebirthConfirm", true)
    end)

    loopToggle("Auto Prestige", "prestige", "WMPrestige", 2, function()
        call("PrestigeRequest")
    end)

    loopToggle("Auto Ascend / Reincarnate", "ascend", "WMAscend", 2, function()
        call("ReincarnationConfirm", true)
    end)

    ----------------------------------------------------------------
    -- rewards
    ----------------------------------------------------------------

    loopToggle("Auto Offline Reward", "offline", "WMOffline", 5, function()
        call("OfflineRewardCollect")
    end)

    -- PTR_Claimed_1 .. PTR_Claimed_16 tell us which ones are still open
    loopToggle("Auto Playtime Rewards", "playtime", "WMPlaytime", 10, function()
        for i = 1, 16 do
            if not env.WMPlaytime then break end

            if plr:GetAttribute("PTR_Claimed_" .. i) == false then
                call("PlaytimeRewardClaim", i)
                task.wait(0.2)
            end
        end
    end)

    loopToggle("Auto Daily + Group Reward", "daily", "WMDaily", 30, function()
        if plr:GetAttribute("DailyClaimedToday") == false then
            call("DailyRewardClaim")
        end
        if plr:GetAttribute("GroupRewardClaimed") == false then
            call("GroupRewardClaim")
        end
    end)

    ----------------------------------------------------------------
    -- world pickups, fully local movement
    ----------------------------------------------------------------

    local function pivotOf(inst)
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then
            if inst.PrimaryPart then return inst.PrimaryPart.Position end
            local ok, cf = pcall(function() return inst:GetPivot() end)
            if ok and cf then return cf.Position end
        end
        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    -- briefly teleports onto a target so its touch fires, then returns
    local function touchCollect(items, keepAlive)
        local root = getRoot()
        if not root then return end

        local origin = root.CFrame

        for _, item in pairs(items) do
            if not keepAlive() then break end

            local pos = item.Parent and pivotOf(item)
            if pos then
                local r = getRoot()
                if r then
                    r.CFrame = CFrame.new(pos)
                    r.AssemblyLinearVelocity = Vector3.zero
                    task.wait(0.15)
                end
            end
        end

        -- go back where we started so the farm is not disruptive
        local r = getRoot()
        if r then
            r.CFrame = origin
            r.AssemblyLinearVelocity = Vector3.zero
        end
    end

    loopToggle("Auto Collect Map Boosts", "boosts", "WMBoosts", 1, function()
        local folder = workspace:FindFirstChild("MapBoosts")
        if not folder then return end

        local items = folder:GetChildren()
        if #items == 0 then return end

        touchCollect(items, function() return env.WMBoosts end)
    end)

    -- sticks and potions lying around the map
    local PICKUP_NAMES = {
        WealthStick = true,
        LuckyStick = true,
        TimeStick = true,
        RebirthPotion = true,
        AscensionPotion = true,
        LuckPotion = true,
    }

    loopToggle("Auto Pickup Sticks + Potions", "pickup", "WMPickup", 3, function()
        local items = {}
        for _, child in pairs(workspace:GetChildren()) do
            if PICKUP_NAMES[child.Name] then
                items[#items + 1] = child
            end
        end

        if #items == 0 then return end

        touchCollect(items, function() return env.WMPickup end)
    end)
end
