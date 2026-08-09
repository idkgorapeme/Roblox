-- Brainrot base game (PlaceId 122526789002601)

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local plr = players.LocalPlayer

    env.BRFarm = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farm = setdata.farm or false
    setdata.minmoney = setdata.minmoney or 0
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local SPAWNER = "CelestialBest"
    local FARM_DELAY = 0.2

    -- the wall run that happens once every time auto farm is switched on
    local WALL_ZONE = "Zone22"
    local WALL_INDEX = 9
    local WALL_ROUNDS = 8
    local WALL_WAIT = 3

    local minMoney = tonumber(setdata.minmoney) or 0

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

    local function pivotOf(inst)
        if inst:IsA("BasePart") then return inst.Position end

        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok and cf then return cf.Position end

        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    ----------------------------------------------------------------
    -- auto farm
    ----------------------------------------------------------------

    -- workspace.ItemSpawners.CelestialBest
    local function spawnerFolder()
        local spawners = workspace:FindFirstChild("ItemSpawners")
        return spawners and spawners:FindFirstChild(SPAWNER) or nil
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

    -- every SpawnedItem sitting in the spawner, however deep it is nested
    local function spawnedItems()
        local spawner = spawnerFolder()
        if not spawner then return {} end

        local out = {}

        for _, d in ipairs(spawner:GetDescendants()) do
            if d.Name == "SpawnedItem" then
                out[#out + 1] = d
            end
        end

        -- the spawner may hold the item directly instead
        if #out == 0 then
            for _, c in ipairs(spawner:GetChildren()) do
                if c:IsA("Model") then out[#out + 1] = c end
            end
        end

        return out
    end

    -- the richest one, ignoring anything below minMoney
    local function bestItem()
        local best, bestValue = nil, -1

        for _, item in ipairs(spawnedItems()) do
            local value = earningsOf(item)

            if value and value >= minMoney and value > bestValue and pivotOf(item) then
                best, bestValue = item, value
            end
        end

        return best
    end

    -- Picking one up needs an actual interaction, standing on it is not
    -- always enough. Prompts, clicks and touches are all tried.
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

    -- workspace.Zones.Zone22.Walls:GetChildren()[9], the part holding the
    -- Script, resolved fresh every round because the walls get replaced
    local function wallPart()
        local zones = workspace:FindFirstChild("Zones")
        local zone = zones and zones:FindFirstChild(WALL_ZONE)
        local walls = zone and zone:FindFirstChild("Walls")
        if not walls then return nil end

        local wall = walls:GetChildren()[WALL_INDEX]
        if not wall then return nil end

        if wall:IsA("BasePart") then return wall end

        -- a model, take the part that actually carries the script
        for _, d in ipairs(wall:GetDescendants()) do
            if d:IsA("BasePart") and d:FindFirstChildOfClass("Script") then
                return d
            end
        end

        return wall:FindFirstChildWhichIsA("BasePart", true)
    end

    -- teleports onto that wall WALL_ROUNDS times, waiting in between
    local function wallRun()
        for i = 1, WALL_ROUNDS do
            if not env.BRFarm then return end

            local part = wallPart()

            if not part then
                warn("[BrainrotPolice] workspace.Zones." .. WALL_ZONE
                    .. ".Walls[" .. WALL_INDEX .. "] not found")
                return
            end

            holdAt(part.Position, 0.2)

            -- stay on it, the wall only pays out while we are standing there
            local t = os.clock()

            while env.BRFarm and os.clock() - t < WALL_WAIT do
                local now = wallPart()
                holdAt(now and now.Position or part.Position, 0.1)
                task.wait(0.05)
            end
        end
    end

    -- workspace.Plot_<your name>
    local function myPlot()
        local plot = workspace:FindFirstChild("Plot_" .. plr.Name)
        return plot and pivotOf(plot) or nil
    end

    -- accepts 5000, 5k, 2.5m and so on
    elements:Textbox("Min Earnings (0 = any)", section, tostring(minMoney), function(v)
        local text = tostring(v):gsub("%s", ""):gsub(",", "")
        local num, suffix = text:match("^([%d%.]+)([KkMmBbTtQq]?)$")

        local n = tonumber(num)
        if not n then return end

        local mult = ({
            k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15,
        })[suffix:lower()] or 1

        minMoney = n * mult
        env.setconfig("minmoney", minMoney)
    end)

    -- starts off every session, it moves the character
    elements:Toggle("Auto Farm", section, false, function(v)
        env.BRFarm = v
        env.setconfig("farm", v)
        if not v then return end

        task.spawn(function()
            local warned = false
            local home = nil

            -- the wall run comes first, only once per activation
            wallRun()

            while env.BRFarm do
                if not alive() then
                    task.wait(0.5)
                else
                    local item = bestItem()

                    if not item then
                        local spawner = spawnerFolder()

                        if not spawner then
                            if not warned then
                                warn("[BrainrotPolice] workspace.ItemSpawners." .. SPAWNER .. " not found")
                                warned = true
                            end
                            task.wait(1)
                        else
                            -- nothing worth taking, wait at the spawner
                            home = home or pivotOf(spawner)

                            if home then
                                holdAt(home + Vector3.new(0, 3, 0), 0.1)
                            end

                            task.wait(0.3)
                        end
                    else
                        warned = false

                        -- grab it
                        local pos = pivotOf(item)
                        local t = os.clock()

                        while env.BRFarm and item.Parent and os.clock() - t < 1 do
                            pos = pivotOf(item) or pos
                            holdAt(pos, 0.1)
                            grab(item)

                            task.wait(0.05)
                        end

                        -- then straight back to the plot to hand it in
                        local plot = myPlot()

                        if plot then
                            holdAt(plot + Vector3.new(0, 3, 0), 0.4)
                        elseif not warned then
                            warn("[BrainrotPolice] workspace.Plot_" .. plr.Name .. " not found")
                            warned = true
                        end

                        task.wait(FARM_DELAY)
                    end
                end
            end
        end)
    end)
end