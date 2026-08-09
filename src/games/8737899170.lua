-- Pet simulator style game (PlaceId 8737899170)
-- The game ships its own automation, so this module drives those remotes
-- instead of moving the character around. Safer and far more reliable.

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.PSFarm = false
    env.PSHatch = false
    env.PSRaid = false
    env.PSOrbs = false
    env.PSClaim = false
    env.PSRebirth = false
    env.PSPets = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farm = setdata.farm or false
    setdata.hatch = setdata.hatch or false
    setdata.raid = setdata.raid or false
    setdata.orbs = setdata.orbs or false
    setdata.claim = setdata.claim or false
    setdata.rebirth = setdata.rebirth or false
    setdata.pets = setdata.pets or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local ORB_DELAY = 0.5
    local CLAIM_DELAY = 30
    local REBIRTH_DELAY = 2
    local PETS_DELAY = 5

    ----------------------------------------------------------------
    -- remotes
    ----------------------------------------------------------------

    -- Names contain spaces and colons ("Orbs: Collect"), so plain indexing
    -- never works here, everything goes through FindFirstChild.
    local function net(name)
        local folder = replicatedstorage:FindFirstChild("Network")
        return folder and folder:FindFirstChild(name) or nil
    end

    -- fires an event or invokes a function, whichever it turns out to be
    local function call(name, ...)
        local r = net(name)
        if not r then return false, "missing" end

        local args = table.pack(...)

        local ok, err = pcall(function()
            if r:IsA("RemoteFunction") then
                return r:InvokeServer(table.unpack(args, 1, args.n))
            else
                r:FireServer(table.unpack(args, 1, args.n))
            end
        end)

        return ok, err
    end

    -- tries a list of names, stops at the first one that exists
    local function callAny(names, ...)
        for _, name in ipairs(names) do
            if net(name) then
                local ok = call(name, ...)
                if ok then return true, name end
            end
        end

        return false
    end

    ----------------------------------------------------------------
    -- stats
    ----------------------------------------------------------------

    -- leaderstats children carry emoji prefixes, so match on a substring
    local function stat(word)
        local stats = plr:FindFirstChild("leaderstats")
        if not stats then return nil end

        for _, s in ipairs(stats:GetChildren()) do
            if s.Name:lower():find(word:lower(), 1, true) then
                return s.Value
            end
        end

        return nil
    end

    ----------------------------------------------------------------
    -- diagnostics
    ----------------------------------------------------------------

    elements:Button("Dump Remotes", section, function()
        local folder = replicatedstorage:FindFirstChild("Network")

        if not folder then
            warn("[BrainrotPolice] ReplicatedStorage.Network not found")
            return
        end

        local wanted = {
            "AutoFarm_Enable", "AutoFarm_Disable", "AutoFarm_GetInitialPositions",
            "AutoRaid_Enable", "AutoRaid_Disable",
            "AutoHatch_Enable", "AutoHatch_Toggle", "AutoHatch_Disable",
            "ChargedHatch_Toggle", "GoldenHatch_Toggle",
            "Orbs: Collect", "Rebirth_Request", "Upgrades_Purchase",
            "Ranks_ClaimReward", "EventGoals_Claim", "Mailbox: Claim All",
            "InstanceChests_Claim", "Pets_EquipBest", "Eggs_RequestPurchase",
        }

        print("[BrainrotPolice] Network children: " .. #folder:GetChildren())

        for _, name in ipairs(wanted) do
            local r = net(name)
            print("  " .. name .. " -> " .. (r and r.ClassName or "MISSING"))
        end

        local stats = plr:FindFirstChild("leaderstats")

        if stats then
            for _, s in ipairs(stats:GetChildren()) do
                print("  stat " .. s.Name .. " = " .. tostring(s.Value))
            end
        end
    end)

    ----------------------------------------------------------------
    -- auto farm
    ----------------------------------------------------------------

    -- The game's own auto farm. It is a real feature, so this just switches
    -- it on and keeps it on instead of moving the character.
    elements:Toggle("Auto Farm", section, setdata.farm, function(v)
        env.PSFarm = v
        env.setconfig("farm", v)

        if not v then
            call("AutoFarm_Disable")
            return
        end

        task.spawn(function()
            local warned = false

            while env.PSFarm do
                local ok = call("AutoFarm_Enable")

                if not ok and not warned then
                    warn("[BrainrotPolice] Network.AutoFarm_Enable not found")
                    warned = true
                end

                -- re-arm now and then, it drops on zone changes and respawns
                task.wait(10)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto hatch
    ----------------------------------------------------------------

    elements:Toggle("Auto Hatch", section, setdata.hatch, function(v)
        env.PSHatch = v
        env.setconfig("hatch", v)

        if not v then
            call("AutoHatch_Disable")
            return
        end

        task.spawn(function()
            local warned = false

            while env.PSHatch do
                local ok = callAny({ "AutoHatch_Enable", "AutoHatch_Toggle" })

                if not ok and not warned then
                    warn("[BrainrotPolice] Network.AutoHatch_Enable not found")
                    warned = true
                end

                task.wait(10)
            end
        end)
    end)

    elements:Button("Toggle Charged Hatch", section, function()
        if not call("ChargedHatch_Toggle") then
            warn("[BrainrotPolice] Network.ChargedHatch_Toggle not found")
        end
    end)

    elements:Button("Toggle Golden Hatch", section, function()
        if not call("GoldenHatch_Toggle") then
            warn("[BrainrotPolice] Network.GoldenHatch_Toggle not found")
        end
    end)

    ----------------------------------------------------------------
    -- auto raid
    ----------------------------------------------------------------

    elements:Toggle("Auto Raid", section, setdata.raid, function(v)
        env.PSRaid = v
        env.setconfig("raid", v)

        if not v then
            call("AutoRaid_Disable")
            return
        end

        task.spawn(function()
            local warned = false

            while env.PSRaid do
                local ok = call("AutoRaid_Enable")

                if not ok and not warned then
                    warn("[BrainrotPolice] Network.AutoRaid_Enable not found")
                    warned = true
                end

                task.wait(10)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto collect orbs
    ----------------------------------------------------------------

    elements:Toggle("Auto Collect Orbs", section, setdata.orbs, function(v)
        env.PSOrbs = v
        env.setconfig("orbs", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.PSOrbs do
                local ok = call("Orbs: Collect")

                if not ok and not warned then
                    warn("[BrainrotPolice] Network.Orbs: Collect not found")
                    warned = true
                end

                task.wait(ORB_DELAY)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto claim rewards
    ----------------------------------------------------------------

    local CLAIMS = {
        "Mailbox: Claim All",
        "Ranks_ClaimReward",
        "EventGoals_Claim",
        "InstanceChests_Claim",
    }

    local function claimAll()
        for _, name in ipairs(CLAIMS) do
            if net(name) then
                call(name)
                task.wait(0.3)
            end
        end
    end

    elements:Button("Claim Rewards Now", section, function()
        task.spawn(claimAll)
    end)

    elements:Toggle("Auto Claim Rewards", section, setdata.claim, function(v)
        env.PSClaim = v
        env.setconfig("claim", v)
        if not v then return end

        task.spawn(function()
            while env.PSClaim do
                claimAll()
                task.wait(CLAIM_DELAY)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto equip best pets
    ----------------------------------------------------------------

    elements:Toggle("Auto Equip Best Pets", section, setdata.pets, function(v)
        env.PSPets = v
        env.setconfig("pets", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.PSPets do
                local ok = call("Pets_EquipBest")

                if not ok and not warned then
                    warn("[BrainrotPolice] Network.Pets_EquipBest not found")
                    warned = true
                end

                task.wait(PETS_DELAY)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto rebirth
    ----------------------------------------------------------------

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.PSRebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.PSRebirth do
                local ok = call("Rebirth_Request")

                if not ok and not warned then
                    warn("[BrainrotPolice] Network.Rebirth_Request not found")
                    warned = true
                end

                task.wait(REBIRTH_DELAY)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- travel
    ----------------------------------------------------------------

    elements:Button("Travel to Main World", section, function()
        if not call("Travel to Main World") then
            warn("[BrainrotPolice] travel remote not found")
        end
    end)

    elements:Button("Travel to Trading Plaza", section, function()
        if not call("Travel to Trading Plaza") then
            warn("[BrainrotPolice] travel remote not found")
        end
    end)

    elements:Label("Diamonds: " .. tostring(stat("Diamonds") or "?"), section)
end
