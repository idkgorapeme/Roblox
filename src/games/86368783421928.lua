-- Fall For Brainrots!

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.FBGuards = false
    env.FBFarm = false
    env.FBFall = false
    env.FBSpeed = false
    env.FBRebirth = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.guards = setdata.guards or false
    setdata.farm = setdata.farm or false
    setdata.fall = setdata.fall or false
    setdata.speed = setdata.speed or false
    setdata.rebirth = setdata.rebirth or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- fixed settings, no textboxes
    local SPAWNER = "Celestial"
    local CELESTIAL_POS = Vector3.new(155, 5202, -2079)
    local GUARD_DELAY = 0.5
    local FARM_DELAY = 0.2
    local SPEED_AMOUNT = 10
    local SPEED_DELAY = 0.5

    local function getChar() return plr.Character end

    local function getRoot()
        local char = getChar()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getHum()
        local char = getChar()
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function alive()
        local hum = getHum()
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

                    for _, g in ipairs(folder:GetChildren()) do
                        pcall(function() g:Destroy() end)
                    end
                end

                task.wait(GUARD_DELAY)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto farm
    ----------------------------------------------------------------

    -- workspace.DropperParts.ItemSpawners.Celestial
    local function spawnerFolder()
        local dp = workspace:FindFirstChild("DropperParts")
        local spawners = dp and dp:FindFirstChild("ItemSpawners")
        return spawners and spawners:FindFirstChild(SPAWNER) or nil
    end

    local function pivotOf(inst)
        if inst:IsA("BasePart") then return inst.Position end

        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok and cf then return cf.Position end

        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    -- <item>.InfoGUI.TextLabels.Earnings, something like "$12.5K/s"
    local function earningsOf(item)
        local gui = item:FindFirstChild("InfoGUI", true)
        local labels = gui and gui:FindFirstChild("TextLabels")
        local label = labels and labels:FindFirstChild("Earnings")

        if not label then
            label = item:FindFirstChild("Earnings", true)
        end

        if not label then return nil end

        local num, suffix = tostring(label.Text or ""):match("([%d%.,]+)%s*([KMBTqQ]?)")
        if not num then return nil end

        num = tonumber((num:gsub(",", "")))
        if not num then return nil end

        local mult = ({
            K = 1e3, M = 1e6, B = 1e9, T = 1e12, q = 1e15, Q = 1e18,
        })[suffix] or 1

        return num * mult
    end

    -- the richest dropped item first
    local function bestItem()
        local spawner = spawnerFolder()
        if not spawner then return nil end

        local best, bestValue = nil, -1

        for _, item in ipairs(spawner:GetChildren()) do
            local value = earningsOf(item)

            if value and value > bestValue and pivotOf(item) then
                best, bestValue = item, value
            end
        end

        return best
    end

    -- Picking one up needs an actual interaction, standing on it is not
    -- always enough. Prompts and touch events are both tried.
    local function grab(item)
        local root = getRoot()
        if not root then return end

        for _, d in ipairs(item:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                pcall(function()
                    d.HoldDuration = 0
                    d.MaxActivationDistance = math.max(d.MaxActivationDistance, 50)
                end)

                if fireproximityprompt then
                    pcall(function() fireproximityprompt(d) end)
                end
            elseif d:IsA("ClickDetector") then
                if fireclickdetector then
                    pcall(function() fireclickdetector(d) end)
                end
            elseif d:IsA("BasePart") and firetouchinterest then
                -- a fake touch, off and on again so the server sees a hit
                pcall(function()
                    firetouchinterest(root, d, 0)
                    firetouchinterest(root, d, 1)
                end)
            end
        end
    end

    -- holds the character on a spot so a touch has time to register
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
        return direct and pivotOf(direct) or nil
    end

    -- starts off every session, it moves the character
    elements:Toggle("Auto Farm", section, false, function(v)
        env.FBFarm = v
        env.setconfig("farm", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.FBFarm do
                if not alive() then
                    task.wait(0.5)
                elseif plr:GetAttribute("IsCarryingBrainrot") then
                    -- drop it off at home before grabbing the next one
                    local plot = myPlot()

                    if plot then
                        holdAt(plot + Vector3.new(0, 3, 0), 0.4)
                        task.wait(FARM_DELAY)
                    else
                        if not warned then
                            warn("[BrainrotPolice] Plot_" .. plr.Name .. " not found")
                            warned = true
                        end
                        task.wait(1)
                    end
                else
                    local item = bestItem()

                    if not item then
                        -- nothing dropped yet, wait where the items land
                        holdAt(CELESTIAL_POS, 0.1)
                        task.wait(0.3)
                    else
                        warned = false

                        local pos = pivotOf(item)

                        -- sit on it and interact until it is in our hands
                        local t = os.clock()

                        while env.FBFarm and item.Parent and os.clock() - t < 2 do
                            if plr:GetAttribute("IsCarryingBrainrot") then break end

                            pos = pivotOf(item) or pos
                            holdAt(pos, 0.1)
                            grab(item)

                            task.wait(0.05)
                        end

                        task.wait(FARM_DELAY)
                    end
                end
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto fall
    ----------------------------------------------------------------

    -- equips whatever sits in slot 1 of the backpack
    local function equipSlot1()
        local char = getChar()
        local hum = getHum()
        if not char or not hum then return nil end

        -- already holding something, nothing to do
        local held = char:FindFirstChildOfClass("Tool")
        if held then return held end

        local backpack = plr:FindFirstChildOfClass("Backpack")
        local tool = backpack and backpack:FindFirstChildOfClass("Tool")
        if not tool then return nil end

        pcall(function() hum:EquipTool(tool) end)

        return char:FindFirstChildOfClass("Tool")
    end

    -- starts off every session, it moves the character
    elements:Toggle("Auto Fall", section, false, function(v)
        env.FBFall = v
        env.setconfig("fall", v)
        if not v then return end

        task.spawn(function()
            while env.FBFall do
                if not alive() then
                    task.wait(0.5)
                else
                    local tool = equipSlot1()

                    if tool then
                        pcall(function() tool:Activate() end)
                    end

                    task.wait(0.5)
                end
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto upgrade
    ----------------------------------------------------------------

    elements:Toggle("Auto Upgrade", section, setdata.speed, function(v)
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
                    pcall(function() ev:FireServer(SPEED_AMOUNT) end)
                elseif not warned then
                    warn("[BrainrotPolice] BrainrotStorage.Events.PurchaseSpeed not found")
                    warned = true
                end

                task.wait(SPEED_DELAY)
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
