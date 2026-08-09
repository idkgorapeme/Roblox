-- Fall For Brainrots!

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.FBGuards = false
    env.FBFarm = false
    env.FBSell = false
    env.FBSpeed = false
    env.FBRebirth = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.guards = setdata.guards or false
    setdata.guarddelay = setdata.guarddelay or 0.5
    setdata.farm = setdata.farm or false
    setdata.farmdelay = setdata.farmdelay or 0.2
    setdata.spawner = setdata.spawner or "Celestial"
    setdata.speed = setdata.speed or false
    setdata.speedamount = setdata.speedamount or 10
    setdata.speeddelay = setdata.speeddelay or 0.5
    setdata.sell = setdata.sell or false
    setdata.selldelay = setdata.selldelay or 1
    setdata.rebirth = setdata.rebirth or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local guardDelay = tonumber(setdata.guarddelay) or 0.5
    local farmDelay = tonumber(setdata.farmdelay) or 0.2
    local spawnerName = tostring(setdata.spawner or "Celestial")
    local speedAmount = tonumber(setdata.speedamount) or 10
    local speedDelay = tonumber(setdata.speeddelay) or 0.5

    -- middle of the Celestial area, used when nothing is up for grabs so we
    -- stay where the items drop instead of falling out of the zone
    local CELESTIAL_POS = Vector3.new(155, 5202, -2079)

    local function getChar() return plr.Character end

    local function getRoot()
        local char = getChar()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function alive()
        local char = getChar()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        return hum ~= nil and hum.Health > 0
    end

    -- ReplicatedStorage.BrainrotStorage.Events.<name>
    local function event(name)
        local storage = replicatedstorage:FindFirstChild("BrainrotStorage")
        local events = storage and storage:FindFirstChild("Events")
        return events and events:FindFirstChild(name) or nil
    end

    ----------------------------------------------------------------
    -- auto delete guards
    ----------------------------------------------------------------

    -- workspace.DropperParts.Guards holds the guards that chase you
    local function guardFolder()
        local dp = workspace:FindFirstChild("DropperParts")
        return dp and dp:FindFirstChild("Guards") or nil
    end

    elements:Textbox("Guard Delay (default 0.5)", section, tostring(guardDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.05 then return end
        guardDelay = n
        env.setconfig("guarddelay", n)
    end)

    -- starts off every session, it changes the world
    elements:Toggle("Auto Delete Guards", section, false, function(v)
        env.FBGuards = v
        env.setconfig("guards", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.FBGuards do
                local folder = guardFolder()

                if not folder then
                    if not warned then
                        warn("[BrainrotPolice] workspace.DropperParts.Guards not found")
                        warned = true
                    end
                else
                    warned = false

                    -- local only, the server still knows about them, but they
                    -- cannot touch a character that never sees them
                    for _, g in ipairs(folder:GetChildren()) do
                        pcall(function() g:Destroy() end)
                    end
                end

                task.wait(guardDelay)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto farm collection zone brainrots
    ----------------------------------------------------------------

    -- every part named CollectionZone<n> sitting directly in workspace
    local function collectionZones()
        local out = {}

        for _, c in ipairs(workspace:GetChildren()) do
            if c:IsA("BasePart") and c.Name:match("^CollectionZone") then
                out[#out + 1] = c
            end
        end

        return out
    end

    local function pivotOf(inst)
        if inst:IsA("BasePart") then return inst.Position end

        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok and cf then return cf.Position end

        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    -- workspace.DropperParts.ItemSpawners.<tier>
    local function spawnerFolder()
        local dp = workspace:FindFirstChild("DropperParts")
        local spawners = dp and dp:FindFirstChild("ItemSpawners")
        if not spawners then return nil end

        return spawners:FindFirstChild(spawnerName), spawners
    end

    -- the folders a fallen brainrot can end up in
    local function brainrotFolders()
        local out = {}

        -- the chosen spawner tier comes first, that is what we want most
        local spawner = spawnerFolder()
        if spawner then out[#out + 1] = spawner end

        for _, name in ipairs({ "DroppedItems", "zBrainrot", "FallParts" }) do
            local f = workspace:FindFirstChild(name)
            if f then out[#out + 1] = f end
        end

        return out
    end

    -- <item>.InfoGUI.TextLabels.Earnings, something like "$12.5K/s"
    local function earningsOf(item)
        local gui = item:FindFirstChild("InfoGUI", true)
        local labels = gui and gui:FindFirstChild("TextLabels")
        local label = labels and labels:FindFirstChild("Earnings")

        if not label then
            -- the layout can differ, fall back to a deep search by name
            label = item:FindFirstChild("Earnings", true)
        end

        if not label then return nil, nil end

        local text = tostring(label.Text or "")

        -- pull the number and its suffix out of the label
        local num, suffix = text:match("([%d%.,]+)%s*([KMBTqQ]?)")
        if not num then return nil, text end

        num = tonumber((num:gsub(",", "")))
        if not num then return nil, text end

        local mult = ({
            K = 1e3, M = 1e6, B = 1e9, T = 1e12, q = 1e15, Q = 1e18,
        })[suffix] or 1

        return num * mult, text
    end

    -- Everything the chosen spawner has dropped that carries an earnings
    -- label, sorted by earnings, highest first.
    local function zoneBrainrots()
        local spawner = spawnerFolder()
        if not spawner then return {} end

        local out = {}

        for _, item in ipairs(spawner:GetChildren()) do
            local value, text = earningsOf(item)

            if value then
                local pos = pivotOf(item)

                if pos then
                    out[#out + 1] = {
                        inst = item,
                        pos = pos,
                        value = value,
                        text = text,
                    }
                end
            end
        end

        -- richest first, that is the whole point
        table.sort(out, function(a, b) return a.value > b.value end)
        return out
    end

    -- holds the character on a spot for a few frames so a touch registers
    local function holdAt(pos, duration)
        local target = CFrame.new(pos)
        local t = os.clock()

        repeat
            local char = getChar()
            local root = getRoot()
            if not char or not root then return false end

            pcall(function()
                char:PivotTo(target)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)

            task.wait()
        until os.clock() - t >= duration

        return true
    end

    -- your own plot, that is where a carried brainrot has to be dropped off
    local function myPlot()
        local direct = workspace:FindFirstChild("Plot_" .. plr.Name)
        if direct then return pivotOf(direct) end

        for _, c in ipairs(workspace:GetChildren()) do
            if c.Name:match("^Plot_") and c.Name:sub(6) == plr.Name then
                return pivotOf(c)
            end
        end

        return nil
    end

    elements:Button("Dump Brainrot Info", section, function()
        local spawner, all = spawnerFolder()

        if all then
            local names = {}
            for _, c in ipairs(all:GetChildren()) do
                names[#names + 1] = c.Name .. " (" .. #c:GetChildren() .. ")"
            end
            print("[BrainrotPolice] ItemSpawners: " .. table.concat(names, ", "))
        else
            warn("[BrainrotPolice] workspace.DropperParts.ItemSpawners not found")
        end

        if spawner then
            local kids = spawner:GetChildren()
            print("[BrainrotPolice] spawner " .. spawnerName .. ": " .. #kids .. " children")

            for i = 1, math.min(#kids, 8) do
                local k = kids[i]
                local value, text = earningsOf(k)
                print("  " .. k.ClassName .. " | " .. k.Name
                    .. " | earnings=" .. tostring(text)
                    .. " -> " .. tostring(value)
                    .. " | " .. tostring(pivotOf(k)))
            end
        else
            warn("[BrainrotPolice] spawner " .. spawnerName .. " not found")
        end

        local zones = collectionZones()
        print("[BrainrotPolice] collection zones: " .. #zones)

        for _, z in ipairs(zones) do
            print("  " .. z.Name .. " @ " .. tostring(z.Position) .. " size " .. tostring(z.Size))
        end

        for _, folder in ipairs(brainrotFolders()) do
            local kids = folder:GetChildren()
            print("[BrainrotPolice] " .. folder.Name .. ": " .. #kids .. " children")

            for i = 1, math.min(#kids, 5) do
                print("  " .. kids[i].ClassName .. " | " .. kids[i].Name)
            end
        end

        local found = zoneBrainrots()
        print("[BrainrotPolice] in a collection zone right now: " .. #found)

        local plot = myPlot()
        print("[BrainrotPolice] my plot: " .. (plot and tostring(plot) or "not found"))
        print("[BrainrotPolice] carrying: " .. tostring(plr:GetAttribute("IsCarryingBrainrot")))
    end)

    elements:Textbox("Spawner (default Celestial)", section, spawnerName, function(v)
        v = tostring(v):gsub("^%s+", ""):gsub("%s+$", "")
        if v == "" then return end
        spawnerName = v
        env.setconfig("spawner", v)
    end)

    elements:Textbox("Farm Delay (default 0.2)", section, tostring(farmDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.05 then return end
        farmDelay = n
        env.setconfig("farmdelay", n)
    end)

    -- starts off every session, it moves the character
    elements:Toggle("Auto Farm Brainrots", section, false, function(v)
        env.FBFarm = v
        env.setconfig("farm", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.FBFarm do
                if not alive() then
                    task.wait(0.5)
                else
                    local carrying = plr:GetAttribute("IsCarryingBrainrot")

                    if carrying then
                        -- drop it off at home before grabbing the next one
                        local plot = myPlot()

                        if plot then
                            holdAt(plot + Vector3.new(0, 3, 0), 0.4)
                            task.wait(farmDelay)
                        elseif not warned then
                            warn("[BrainrotPolice] your plot was not found, cannot drop off")
                            warned = true
                            task.wait(1)
                        else
                            task.wait(1)
                        end
                    else
                        local found = zoneBrainrots()

                        if #found == 0 then
                            -- nothing to grab, wait in the zone so we do not
                            -- drift off while the next batch spawns
                            holdAt(CELESTIAL_POS, 0.1)
                            task.wait(0.3)
                        else
                            warned = false

                            -- the one with the highest earnings
                            holdAt(found[1].pos, 0.3)
                            task.wait(farmDelay)
                        end
                    end
                end
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto upgrade speed
    ----------------------------------------------------------------

    elements:Textbox("Speed Amount (default 10)", section, tostring(speedAmount), function(v)
        local n = tonumber(v)
        if not n or n < 1 then return end
        speedAmount = math.floor(n)
        env.setconfig("speedamount", speedAmount)
    end)

    elements:Textbox("Speed Delay (default 0.5)", section, tostring(speedDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.05 then return end
        speedDelay = n
        env.setconfig("speeddelay", n)
    end)

    elements:Toggle("Auto Upgrade Speed", section, setdata.speed, function(v)
        env.FBSpeed = v
        env.setconfig("speed", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.FBSpeed do
                local ev = event("PurchaseSpeed")

                if ev then
                    warned = false
                    -- the server ignores it when there is not enough money
                    pcall(function() ev:FireServer(speedAmount) end)
                elseif not warned then
                    warn("[BrainrotPolice] BrainrotStorage.Events.PurchaseSpeed not found")
                    warned = true
                end

                task.wait(speedDelay)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto sell
    ----------------------------------------------------------------

    elements:Toggle("Auto Sell", section, setdata.sell, function(v)
        env.FBSell = v
        env.setconfig("sell", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.FBSell do
                local ev = event("RequestSell")

                if ev then
                    warned = false
                    pcall(function() ev:FireServer() end)
                elseif not warned then
                    warn("[BrainrotPolice] BrainrotStorage.Events.RequestSell not found")
                    warned = true
                end

                task.wait(tonumber(setdata.selldelay) or 1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto rebirth
    ----------------------------------------------------------------

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.FBRebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.FBRebirth do
                local ev = event("RequestRebirth")

                if ev then
                    warned = false
                    pcall(function() ev:FireServer() end)
                elseif not warned then
                    warn("[BrainrotPolice] BrainrotStorage.Events.RequestRebirth not found")
                    warned = true
                end

                task.wait(1)
            end
        end)
    end)
end
