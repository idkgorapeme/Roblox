-- Brainrot plot game (PlaceId 94416836737659)

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.WCFarm = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farm = setdata.farm or false
    setdata.minmoney = setdata.minmoney or 0
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local FARM_DELAY = 0.2
    local GRAB_TIME = 2.5
    local SKIP_TIME = 20

    -- this game kicks for teleporting, so everything is flown instead
    local FLY_SPEED = 220
    local FLY_TIMEOUT = 8

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

    -- ReplicatedStorage.Remotes.<name>
    local function remote(name)
        local folder = replicatedstorage:FindFirstChild("Remotes")
        return folder and folder:FindFirstChild(name) or nil
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

    -- workspace.Brainrots
    local function brainrotFolder()
        return workspace:FindFirstChild("Brainrots")
    end

    local SUFFIX = {
        k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15,
    }

    local function parseAmount(text)
        local num, suffix = tostring(text or ""):match("([%d%.,]+)%s*([KkMmBbTtQq]?)")
        if not num then return nil end

        num = tonumber((num:gsub(",", "")))
        if not num then return nil end

        return num * (SUFFIX[suffix:lower()] or 1)
    end

    -- The exact label path is unknown for this game, so any text label that
    -- looks like an income readout counts. Named labels win over guesses.
    local NAMES = { "Revenue", "Earnings", "CharCash", "Generation", "Income", "Cash" }

    local function revenueOf(item)
        for _, name in ipairs(NAMES) do
            local label = item:FindFirstChild(name, true)

            if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
                local value = parseAmount(label.Text)
                if value then return value end
            end
        end

        -- fall back to any label reading something per second
        local best = nil

        for _, d in ipairs(item:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                local text = tostring(d.Text or "")

                if text:match("/s") or text:match("%$") then
                    local value = parseAmount(text)

                    if value and (not best or value > best) then
                        best = value
                    end
                end
            end
        end

        return best
    end

    -- items we could not get, mapped to the time they may be tried again
    local skipUntil = {}

    -- Someone else is standing on it, no point fighting over the same one.
    local function contested(item)
        local pos = pivotOf(item)
        if not pos then return false end

        for _, other in ipairs(players:GetPlayers()) do
            if other ~= plr then
                local char = other.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")

                if root and (root.Position - pos).Magnitude < 8 then
                    return true
                end
            end
        end

        return false
    end

    -- the most valuable brainrot around, ignoring anything below minMoney
    local function bestItem()
        local folder = brainrotFolder()
        if not folder then return nil end

        local now = os.clock()
        local best, bestValue = nil, -1

        for _, item in ipairs(folder:GetChildren()) do
            local blocked = skipUntil[item] and skipUntil[item] > now

            if not blocked then
                local value = revenueOf(item)

                if value and value >= minMoney and value > bestValue
                    and pivotOf(item) and not contested(item) then
                    best, bestValue = item, value
                end
            end
        end

        return best
    end

    -- Picking one up needs an actual interaction, standing on it is not
    -- always enough. Prompts, clicks and touches are all tried, plus the
    -- Pickup remote the game exposes.
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

        -- the game has its own pickup remote, the arg shape is a guess
        local ev = remote("Pickup") or remote("TakeBrainrot")

        if ev then
            pcall(function() ev:FireServer(item) end)
        end
    end

    ----------------------------------------------------------------
    -- flight
    ----------------------------------------------------------------
    -- This game kicks for teleporting, so the character is flown there with
    -- movers instead. Never PlatformStand or Anchored, those leave the
    -- character stuck when the flight ends.

    local function stopFlight()
        local char = getChar()
        if not char then return end

        for _, name in ipairs({ "BPFlyPos", "BPFlyGyro" }) do
            local mover = char:FindFirstChild(name, true)
            if mover then mover:Destroy() end
        end
    end

    -- creates the movers once and hands them back on later calls
    local function movers()
        local root = getRoot()
        if not root then return nil, nil end

        local vel = root:FindFirstChild("BPFlyPos")

        if not vel then
            vel = Instance.new("BodyVelocity")
            vel.Name = "BPFlyPos"
            vel.MaxForce = Vector3.new(1, 1, 1) * 1e6
            vel.Velocity = Vector3.zero
            vel.Parent = root
        end

        local gyro = root:FindFirstChild("BPFlyGyro")

        if not gyro then
            gyro = Instance.new("BodyGyro")
            gyro.Name = "BPFlyGyro"
            gyro.MaxTorque = Vector3.new(1, 1, 1) * 1e6
            gyro.P = 8000
            gyro.CFrame = root.CFrame
            gyro.Parent = root
        end

        return vel, gyro
    end

    -- one step towards the target, returns the distance left
    local function glideStep(pos)
        local root = getRoot()
        if not root then return math.huge end

        local vel, gyro = movers()
        if not vel then return math.huge end

        local delta = pos - root.Position
        local dist = delta.Magnitude

        if dist < 0.05 then
            vel.Velocity = Vector3.zero
            return dist
        end

        -- slow down on approach, but never crawl on the last studs
        local speed = math.clamp(dist * 4, 12, FLY_SPEED)
        vel.Velocity = delta.Unit * speed

        if gyro then
            gyro.CFrame = CFrame.new(root.Position, root.Position + delta.Unit)
        end

        return dist
    end

    -- Flies to a spot and stays there for a while so a touch registers.
    -- Returns false when it could not get there in time.
    local function holdAt(pos, duration)
        local root = getRoot()
        if not root then return false end

        -- fly over first, with a timeout so a blocked path cannot stall us
        local t = os.clock()

        while os.clock() - t < FLY_TIMEOUT do
            if not getRoot() then return false end

            local dist = glideStep(pos)
            if dist < 4 then break end

            task.wait()
        end

        -- then sit on it
        t = os.clock()

        repeat
            if not getRoot() then return false end

            glideStep(pos)
            task.wait()
        until os.clock() - t >= duration

        return true
    end

    -- workspace.Plots.<n>, the PlotIndex attribute says which one is ours
    local function myPlot()
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return nil end

        local id = plr:GetAttribute("PlotIndex")

        if id then
            local plot = plots:FindFirstChild(tostring(id))
                or plots:FindFirstChild("Plot" .. tostring(id))
                or plots:FindFirstChild("Plot_" .. tostring(id))

            if plot then return pivotOf(plot) end
        end

        -- fall back to whichever plot carries our name
        for _, p in ipairs(plots:GetChildren()) do
            if p:GetAttribute("Owner") == plr.Name or p.Name == plr.Name then
                return pivotOf(p)
            end
        end

        return nil
    end

    -- accepts 5000, 5k, 2.5m and so on
    elements:Textbox("Min Revenue (0 = any)", section, tostring(minMoney), function(v)
        local text = tostring(v):gsub("%s", ""):gsub(",", "")
        local num, suffix = text:match("^([%d%.]+)([KkMmBbTtQq]?)$")

        local n = tonumber(num)
        if not n then return end

        minMoney = n * (SUFFIX[suffix:lower()] or 1)
        env.setconfig("minmoney", minMoney)
    end)

    -- starts off every session, it moves the character
    elements:Toggle("Auto Farm", section, false, function(v)
        env.WCFarm = v
        env.setconfig("farm", v)

        if not v then
            stopFlight()
            return
        end

        task.spawn(function()
            local warned = false

            while env.WCFarm do
                if not alive() then
                    task.wait(0.5)
                else
                    -- forget stale cooldowns so the table cannot grow forever
                    local now = os.clock()
                    for item, until_ in pairs(skipUntil) do
                        if until_ <= now or not item.Parent then
                            skipUntil[item] = nil
                        end
                    end

                    if not brainrotFolder() then
                        if not warned then
                            warn("[BrainrotPolice] workspace.Brainrots not found")
                            warned = true
                        end

                        task.wait(1)
                    else
                        local item = bestItem()

                        if not item then
                            -- nothing spawned that is worth taking
                            task.wait(0.5)
                        else
                            warned = false

                            local pos = pivotOf(item)
                            local t = os.clock()

                            while env.WCFarm and item.Parent and os.clock() - t < GRAB_TIME do
                                if contested(item) then break end

                                pos = pivotOf(item) or pos
                                holdAt(pos, 0.1)
                                grab(item)

                                task.wait(0.05)
                            end

                            if item.Parent then
                                -- still lying there, leave it alone for a bit
                                skipUntil[item] = os.clock() + SKIP_TIME
                            else
                                -- got it, haul it back to the plot
                                local plot = myPlot()

                                if plot then
                                    holdAt(plot + Vector3.new(0, 3, 0), 0.4)
                                end
                            end

                            task.wait(FARM_DELAY)
                        end
                    end
                end
            end

            -- always hand control back to the player
            stopFlight()
        end)
    end)
end
