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
    env.FBRebirth = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.guards = setdata.guards or false
    setdata.guarddelay = setdata.guarddelay or 0.5
    setdata.farm = setdata.farm or false
    setdata.farmdelay = setdata.farmdelay or 0.2
    setdata.spawner = setdata.spawner or "Celestial"
    setdata.sell = setdata.sell or false
    setdata.selldelay = setdata.selldelay or 1
    setdata.rebirth = setdata.rebirth or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local guardDelay = tonumber(setdata.guarddelay) or 0.5
    local farmDelay = tonumber(setdata.farmdelay) or 0.2
    local spawnerName = tostring(setdata.spawner or "Celestial")

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

    -- true when pos sits inside the zone's own box, rotation included
    local function insideZone(zone, pos)
        local rel = zone.CFrame:PointToObjectSpace(pos)
        local half = zone.Size * 0.5

        return math.abs(rel.X) <= half.X
            and math.abs(rel.Y) <= half.Y
            and math.abs(rel.Z) <= half.Z
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

    -- everything the chosen spawner has dropped, nearest first. Items are
    -- taken from the spawner folder no matter where they are, and from the
    -- other folders only while they sit in a collection zone.
    local function zoneBrainrots()
        local zones = collectionZones()
        local spawner = spawnerFolder()

        local root = getRoot()
        local from = root and root.Position or Vector3.zero
        local out = {}
        local seen = {}

        local function add(item)
            if seen[item] then return end

            local pos = pivotOf(item)
            if not pos then return end

            seen[item] = true
            out[#out + 1] = {
                inst = item,
                pos = pos,
                dist = (pos - from).Magnitude,
            }
        end

        -- straight from the spawner, no zone check needed
        if spawner then
            for _, item in ipairs(spawner:GetChildren()) do
                add(item)
            end
        end

        -- anything else that already landed in a collection zone
        if #zones > 0 then
            for _, folder in ipairs(brainrotFolders()) do
                if folder ~= spawner then
                    for _, item in ipairs(folder:GetChildren()) do
                        local pos = pivotOf(item)

                        if pos then
                            for _, zone in ipairs(zones) do
                                if insideZone(zone, pos) then
                                    add(item)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        table.sort(out, function(a, b) return a.dist < b.dist end)
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
            print("[BrainrotPolice] spawner " .. spawnerName .. ": "
                .. #spawner:GetChildren() .. " items")
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
                            -- the spawner has not dropped anything yet
                            task.wait(0.5)
                        else
                            warned = false

                            -- walk into the nearest one to pick it up
                            holdAt(found[1].pos, 0.3)
                            task.wait(farmDelay)
                        end
                    end
                end
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
