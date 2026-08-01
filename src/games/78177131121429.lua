-- Drill Blocks for Brainrots

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.DBCollect = false
    env.DBUpgrade = false
    env.DBRebirth = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.collect = setdata.collect or false
    setdata.upgrade = setdata.upgrade or false
    setdata.rebirth = setdata.rebirth or false
    setdata.basenum = setdata.basenum or ""
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local network = replicatedstorage:WaitForChild("Network")
    local remoteEvents = network:WaitForChild("RemoteEvents")

    local collectCash = remoteEvents:WaitForChild("RequestCollectCash")
    local incrementSpeed = remoteEvents:WaitForChild("IncrementSpeed")
    local incrementStrength = remoteEvents:WaitForChild("IncrementStrength")
    local rebirthEvent = remoteEvents:WaitForChild("Rebirth")

    local SLOT_COUNT = 30

    -- manual override, leave empty to auto detect
    local baseOverride = tostring(setdata.basenum or "")

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- work out which base belongs to us
    ----------------------------------------------------------------

    -- checks the usual places a game stores the plot owner
    local function baseBelongsToMe(base)
        for _, key in ipairs({ "Owner", "OwnerUserId", "OwnerName", "Player", "UserId" }) do
            local attr = base:GetAttribute(key)
            if attr ~= nil then
                if attr == plr.Name or attr == plr.UserId
                    or tostring(attr) == tostring(plr.UserId) then
                    return true
                end
            end
        end

        for _, key in ipairs({ "Owner", "OwnerName", "Player", "OwnerValue" }) do
            local val = base:FindFirstChild(key)
            if val and (val:IsA("StringValue") or val:IsA("ObjectValue")
                or val:IsA("IntValue") or val:IsA("NumberValue")) then
                local v = val.Value
                if v == plr or v == plr.Name or v == plr.UserId
                    or tostring(v) == tostring(plr.UserId) then
                    return true
                end
            end
        end

        -- some games put the name on a sign / billboard text
        for _, d in pairs(base:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text and d.Text ~= "" then
                if string.find(d.Text, plr.Name, 1, true)
                    or string.find(d.Text, plr.DisplayName, 1, true) then
                    return true
                end
            end
        end

        return false
    end

    -- returns the Bases child that is ours, falling back to the closest one
    local function getMyBase()
        local bases = workspace:FindFirstChild("Bases")
        if not bases then return nil end

        if baseOverride ~= "" then
            local forced = bases:FindFirstChild(baseOverride)
            if forced then return forced end
        end

        for _, base in pairs(bases:GetChildren()) do
            if baseBelongsToMe(base) then
                return base
            end
        end

        -- no ownership marker found, use whichever base we are standing nearest to
        local root = getRoot()
        if not root then return nil end

        local best, bestDist = nil, math.huge
        for _, base in pairs(bases:GetChildren()) do
            local ok, pivot = pcall(function()
                return base:GetPivot().Position
            end)
            if ok and pivot then
                local dist = (pivot - root.Position).Magnitude
                if dist < bestDist then
                    best, bestDist = base, dist
                end
            end
        end

        return best
    end

    ----------------------------------------------------------------
    -- auto collect
    ----------------------------------------------------------------

    elements:Textbox("Base Number (empty = auto)", section, baseOverride, function(v)
        baseOverride = v and v:gsub("%s", "") or ""
        env.setconfig("basenum", baseOverride)
    end)

    elements:Toggle("Auto Collect", section, setdata.collect, function(v)
        env.DBCollect = v
        env.setconfig("collect", v)
        if not v then return end

        task.spawn(function()
            while env.DBCollect do
                local base = getMyBase()
                local slots = base and base:FindFirstChild("Slots")

                if slots then
                    for i = 1, SLOT_COUNT do
                        if not env.DBCollect then break end

                        local slot = slots:FindFirstChild(tostring(i))
                        local money = slot and slot:FindFirstChild("Money")

                        if money then
                            pcall(function()
                                collectCash:FireServer(money)
                            end)
                            task.wait(0.05)
                        end
                    end
                end

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto upgrade player
    ----------------------------------------------------------------

    elements:Toggle("Auto Upgrade Player", section, setdata.upgrade, function(v)
        env.DBUpgrade = v
        env.setconfig("upgrade", v)
        if not v then return end

        -- strength keeps the fast cadence
        task.spawn(function()
            while env.DBUpgrade do
                pcall(function()
                    incrementStrength:FireServer(10)
                end)

                task.wait(0.5)
            end
        end)

        -- speed only every 10 seconds, on its own thread so it does not
        -- hold up the strength loop
        task.spawn(function()
            while env.DBUpgrade do
                pcall(function()
                    incrementSpeed:FireServer(1)
                end)

                -- sleep in short steps so toggling off stops it quickly
                for _ = 1, 100 do
                    if not env.DBUpgrade then return end
                    task.wait(0.1)
                end
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto rebirth
    ----------------------------------------------------------------

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.DBRebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            while env.DBRebirth do
                pcall(function()
                    rebirthEvent:FireServer()
                end)

                task.wait(1)
            end
        end)
    end)
end
