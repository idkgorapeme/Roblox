-- Sail Your Boat

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.SBPump = false
    env.SBUpgrade = false
    env.SBLaunch = false
    env.SBFuel = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.pump = setdata.pump or false
    setdata.upgrade = setdata.upgrade or false
    setdata.launch = setdata.launch or false
    setdata.fuel = setdata.fuel or false
    setdata.basename = setdata.basename or ""
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- Knit service lookup.
    -- IMPORTANT: this must never use a blocking WaitForChild at module scope.
    -- If one service name does not match, WaitForChild hangs forever and every
    -- toggle below it is never created, which is why only the first one showed.
    local function knitRemote(serviceName, remoteName)
        local node = replicatedstorage:FindFirstChild("Packages")
        node = node and node:FindFirstChild("_Index")
        if not node then return nil end

        -- the knit version can change, so match on the prefix instead of pinning
        local knitPkg = node:FindFirstChild("sleitnick_knit@1.7.0")
        if not knitPkg then
            for _, child in pairs(node:GetChildren()) do
                if string.sub(child.Name, 1, 15) == "sleitnick_knit@" then
                    knitPkg = child
                    break
                end
            end
        end
        if not knitPkg then return nil end

        local knit = knitPkg:FindFirstChild("knit")
        local services = knit and knit:FindFirstChild("Services")
        local service = services and services:FindFirstChild(serviceName)
        local rf = service and service:FindFirstChild("RF")
        return rf and rf:FindFirstChild(remoteName) or nil
    end

    -- resolved on first use so a missing service can never block the UI
    local function manualTick() return knitRemote("FuelService", "ManualTick") end
    local function levelUp() return knitRemote("FuelPlaceService", "LevelUp") end
    local function launch() return knitRemote("BoatService", "Launch") end
    local function collectFuel() return knitRemote("FuelService", "CollectFuel") end
    local function addFuel() return knitRemote("BoatService", "AddFuel") end

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
                            local rf = manualTick()
                            if rf then rf:InvokeServer(place) end
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
                            local rf = levelUp()
                            if rf then rf:InvokeServer(place, 1) end
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
                        local rf = launch()
                        if rf then rf:InvokeServer(sailPad) end
                    end)
                end

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto fuel
    ----------------------------------------------------------------

    -- fuel models live outside the datamodel tree, so they only show up
    -- through getnilinstances
    local function getNilModels()
        local out = {}

        local fn = getnilinstances or get_nil_instances or getnilobjects
        if not fn then return out end

        local ok, list = pcall(fn)
        if not ok or type(list) ~= "table" then return out end

        for _, v in next, list do
            -- the fuels are Models named with a plain number
            local okc, isModel = pcall(function()
                return v.ClassName == "Model"
            end)
            if okc and isModel and tonumber(v.Name) then
                out[#out + 1] = v
            end
        end

        return out
    end

    elements:Toggle("Auto Fuel", section, setdata.fuel, function(v)
        env.SBFuel = v
        env.setconfig("fuel", v)
        if not v then return end

        if not (getnilinstances or get_nil_instances or getnilobjects) then
            warn("[BrainrotPolice] this executor has no getnilinstances, auto fuel cannot work")
            env.SBFuel = false
            return
        end

        task.spawn(function()
            while env.SBFuel do
                local fuels = getNilModels()

                -- 1. collect every fuel
                local collect = collectFuel()
                if collect then
                    for _, fuel in ipairs(fuels) do
                        if not env.SBFuel then break end
                        pcall(function()
                            collect:InvokeServer(fuel)
                        end)
                    end
                end

                -- 2. feed the same amount into the boat
                local base = getMyBase()
                local sailPad = base and base:FindFirstChild("SailPad")
                local clickProxy = sailPad and sailPad:FindFirstChild("ClickProxy")
                local add = addFuel()

                if clickProxy and add then
                    for _ = 1, math.max(#fuels, 1) do
                        if not env.SBFuel then break end
                        pcall(function()
                            add:InvokeServer(clickProxy)
                        end)
                    end
                end

                task.wait(0.5)
            end
        end)
    end)
end
