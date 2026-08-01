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
    local function buyUpgrade() return knitRemote("FuelPlaceService", "BuyUpgrade") end

    -- InvokeServer with a watchdog so a non responding call cannot freeze us
    local function safeInvoke(rf, timeout, ...)
        local args = table.pack(...)
        local finished, succeeded = false, false

        task.spawn(function()
            local ok = pcall(function()
                rf:InvokeServer(table.unpack(args, 1, args.n))
            end)
            succeeded = ok
            finished = true
        end)

        local waited = 0
        while not finished and waited < timeout do
            task.wait(0.05)
            waited = waited + 0.05
        end

        return finished, succeeded
    end


    -- how many upgrade slots each fuel place can have
    local UPGRADE_SLOTS = 5

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
                    local lvl = levelUp()
                    local buy = buyUpgrade()

                    -- run both on every fuel place, not just the first one
                    for _, place in pairs(fuelPlaces:GetChildren()) do
                        if not env.SBUpgrade then break end

                        if lvl then
                            safeInvoke(lvl, 1, place, 1)
                        end

                        if not env.SBUpgrade then break end

                        -- buy every upgrade slot this place offers
                        if buy then
                            for slot = 1, UPGRADE_SLOTS do
                                if not env.SBUpgrade then break end
                                safeInvoke(buy, 1, place, slot)
                            end
                        end
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

                -- give Auto Fuel time to collect and load fuel before the
                -- next launch. stepped so toggling off reacts quickly.
                for _ = 1, 100 do
                    if not env.SBLaunch then return end
                    task.wait(0.1)
                end
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto fuel
    ----------------------------------------------------------------

    -- Fuel models are parented to nil, so they only exist in getnilinstances.
    -- Two things made the old version fail:
    --   1. InvokeServer BLOCKS until the server replies. Firing it at a junk
    --      model could hang the loop forever, so nothing after it ever ran.
    --   2. pcall returning true does not mean the fuel was accepted, so the
    --      AddFuel count was inflated and fired far too often.
    local function nilInstances()
        local fn = getnilinstances or get_nil_instances or getnilobjects
        if not fn then return nil end

        local ok, list = pcall(fn)
        if not ok or type(list) ~= "table" then return nil end
        return list
    end

    -- every nil Model, whatever it is called
    local function getFuelModels()
        local out = {}
        local list = nilInstances()
        if not list then return out end

        for _, v in next, list do
            local ok, isModel = pcall(function()
                return typeof(v) == "Instance" and v.ClassName == "Model"
            end)
            if ok and isModel then
                out[#out + 1] = v
            end
        end

        return out
    end

    -- the proxy is sometimes nested deeper than SailPad's direct children
    local function getClickProxy(base)
        local sailPad = base and base:FindFirstChild("SailPad")
        if not sailPad then return nil end
        return sailPad:FindFirstChild("ClickProxy")
            or sailPad:FindFirstChild("ClickProxy", true)
    end

    elements:Toggle("Auto Fuel", section, setdata.fuel, function(v)
        env.SBFuel = v
        env.setconfig("fuel", v)
        if not v then return end

        if not nilInstances() then
            warn("[BrainrotPolice] this executor has no getnilinstances, Auto Fuel cannot work")
            env.SBFuel = false
            return
        end

        task.spawn(function()
            local announced = false

            while env.SBFuel do
                local fuels = getFuelModels()

                if not announced then
                    print("[BrainrotPolice] Auto Fuel: " .. #fuels .. " nil models visible")
                    announced = true
                end

                -- 1. collect. a model that is still nil after the call was not
                --    a fuel, so it does not count toward the AddFuel total.
                local collected = 0
                local collect = collectFuel()

                if collect then
                    for _, fuel in ipairs(fuels) do
                        if not env.SBFuel then break end

                        local finished, ok = safeInvoke(collect, 1, fuel)

                        if finished and ok then
                            collected = collected + 1
                        end
                    end
                end

                -- 2. load the boat, one call per fuel that went through
                local base = getMyBase()
                local clickProxy = getClickProxy(base)
                local add = addFuel()

                if clickProxy and add and collected > 0 then
                    for _ = 1, collected do
                        if not env.SBFuel then break end
                        safeInvoke(add, 1, clickProxy)
                        task.wait(0.1)
                    end
                end

                task.wait(0.5)
            end
        end)
    end)
end
