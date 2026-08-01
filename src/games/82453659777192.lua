-- Sail Your Boat

return function(section, data)
    local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.SBPump = false
    env.SBUpgrade = false
    env.SBLaunch = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.pump = setdata.pump or false
    setdata.upgrade = setdata.upgrade or false
    setdata.launch = setdata.launch or false
    setdata.basename = setdata.basename or ""
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- knit service path
    local packages = replicatedstorage:WaitForChild("Packages")
    local index = packages:WaitForChild("_Index")
    local knitPkg = index:WaitForChild("sleitnick_knit@1.7.0")
    local knit = knitPkg:WaitForChild("knit")
    local services = knit:WaitForChild("Services")
    local fuelService = services:WaitForChild("FuelService")
    local fuelRF = fuelService:WaitForChild("RF")
    local manualTick = fuelRF:WaitForChild("ManualTick")

    local fuelPlaceService = services:WaitForChild("FuelPlaceService")
    local fuelPlaceRF = fuelPlaceService:WaitForChild("RF")
    local levelUp = fuelPlaceRF:WaitForChild("LevelUp")

    local boatService = services:WaitForChild("BoatService")
    local boatRF = boatService:WaitForChild("RF")
    local launch = boatRF:WaitForChild("Launch")

    -- manual override, leave empty to auto detect
    local baseOverride = tostring(setdata.basename or "")

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- work out which base belongs to us
    ----------------------------------------------------------------

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

        -- plot signs usually show the owner name
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

    local function getMyBase()
        local bases = workspace:FindFirstChild("Bases")
        if not bases then return nil end

        if baseOverride ~= "" then
            -- accept either "Base8" or just "8"
            local forced = bases:FindFirstChild(baseOverride)
                or bases:FindFirstChild("Base" .. baseOverride)
            if forced then return forced end
        end

        for _, base in pairs(bases:GetChildren()) do
            if baseBelongsToMe(base) then
                return base
            end
        end

        -- fall back to the base we are standing closest to
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
    -- auto manual pump
    ----------------------------------------------------------------

    elements:Textbox("Base (empty = auto)", section, baseOverride, function(v)
        baseOverride = v and v:gsub("%s", "") or ""
        env.setconfig("basename", baseOverride)
    end)

    elements:Toggle("Auto Manual Pump", section, setdata.pump, function(v)
        env.SBPump = v
        env.setconfig("pump", v)
        if not v then return end

        task.spawn(function()
            while env.SBPump do
                local base = getMyBase()
                local fuelPlaces = base and base:FindFirstChild("FuelPlaces")

                if fuelPlaces then
                    -- pump every fuel place this base actually has
                    for _, place in pairs(fuelPlaces:GetChildren()) do
                        if not env.SBPump then break end

                        pcall(function()
                            manualTick:InvokeServer(place)
                        end)
                    end
                end

                task.wait()
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto upgrade
    ----------------------------------------------------------------

    elements:Toggle("Auto Upgrade", section, setdata.upgrade, function(v)
        env.SBUpgrade = v
        env.setconfig("upgrade", v)
        if not v then return end

        task.spawn(function()
            while env.SBUpgrade do
                local base = getMyBase()
                local fuelPlaces = base and base:FindFirstChild("FuelPlaces")

                if fuelPlaces then
                    -- level up every fuel place, not just the first one
                    for _, place in pairs(fuelPlaces:GetChildren()) do
                        if not env.SBUpgrade then break end

                        pcall(function()
                            levelUp:InvokeServer(place, 1)
                        end)
                    end
                end

                task.wait(0.2)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto launch
    ----------------------------------------------------------------

    elements:Toggle("Auto Launch", section, setdata.launch, function(v)
        env.SBLaunch = v
        env.setconfig("launch", v)
        if not v then return end

        task.spawn(function()
            while env.SBLaunch do
                local base = getMyBase()
                local sailPad = base and base:FindFirstChild("SailPad")

                if sailPad then
                    pcall(function()
                        launch:InvokeServer(sailPad)
                    end)
                end

                task.wait(1)
            end
        end)
    end)
end
