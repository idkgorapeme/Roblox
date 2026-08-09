-- Entity plot game (PlaceId 123822115505881)

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.EPFarm = false
    env.EPCash = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farm = setdata.farm or false
    setdata.cash = setdata.cash or false
    setdata.minmoney = setdata.minmoney or 0
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local FARM_DELAY = 0.2
    local GRAB_TIME = 1.5
    local SKIP_TIME = 20
    local CASH_DELAY = 1

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

    -- ReplicatedStorage.Utilities.TypedRemote.<name>
    local function remote(name)
        local utils = replicatedstorage:FindFirstChild("Utilities")
        local typed = utils and utils:FindFirstChild("TypedRemote")
        return typed and typed:FindFirstChild(name) or nil
    end

    local function pivotOf(inst)
        if inst:IsA("BasePart") then return inst.Position end

        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok and cf then return cf.Position end

        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    ----------------------------------------------------------------
    -- shared helpers
    ----------------------------------------------------------------

    local SUFFIX = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15 }

    local function parseAmount(text)
        local num, suffix = tostring(text or ""):match("([%d%.,]+)%s*([KkMmBbTtQq]?)")
        if not num then return nil end

        num = tonumber((num:gsub(",", "")))
        if not num then return nil end

        return num * (SUFFIX[suffix:lower()] or 1)
    end

    -- The label path is not known for this game, so any text that reads like
    -- an income figure counts. Named labels win over guesses.
    local NAMES = { "Revenue", "Earnings", "Income", "Generation", "CharCash", "Cash", "Amount" }

    local function valueOf(item)
        for _, name in ipairs(NAMES) do
            local label = item:FindFirstChild(name, true)

            if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
                local value = parseAmount(label.Text)
                if value then return value end
            end
        end

        local best = nil

        for _, d in ipairs(item:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                local text = tostring(d.Text or "")

                if text:match("/s") or text:match("%$") then
                    local value = parseAmount(text)
                    if value and (not best or value > best) then best = value end
                end
            end
        end

        return best
    end

    -- teleports the whole character and keeps it there for a moment
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

    ----------------------------------------------------------------
    -- auto farm
    ----------------------------------------------------------------

    -- workspace.EntitiesFolder holds the loose entities on the map
    local function entityFolder()
        return workspace:FindFirstChild("EntitiesFolder")
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

    -- the most valuable entity around, ignoring anything below minMoney
    local function bestItem()
        local folder = entityFolder()
        if not folder then return nil end

        local now = os.clock()
        local best, bestValue = nil, -1

        for _, item in ipairs(folder:GetChildren()) do
            local blocked = skipUntil[item] and skipUntil[item] > now

            if not blocked and pivotOf(item) and not contested(item) then
                local value = valueOf(item) or 0

                if value >= minMoney and value > bestValue then
                    best, bestValue = item, value
                end
            end
        end

        return best
    end

    -- workspace.Plots, the one that belongs to us
    local function myPlot()
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return nil end

        for _, p in ipairs(plots:GetChildren()) do
            if p:GetAttribute("Owner") == plr.Name
                or p:GetAttribute("Player") == plr.Name
                or p.Name == plr.Name
                or p.Name == "Plot_" .. plr.Name then
                return pivotOf(p)
            end
        end

        -- the server hands the plot over on request
        local ev = remote("GetPlot")

        if ev and ev:IsA("RemoteFunction") then
            local ok, plot = pcall(function() return ev:InvokeServer() end)

            if ok and typeof(plot) == "Instance" then
                return pivotOf(plot)
            end
        end

        return nil
    end

    -- accepts 5000, 5k, 2.5m and so on
    elements:Textbox("Min Value (0 = any)", section, tostring(minMoney), function(v)
        local text = tostring(v):gsub("%s", ""):gsub(",", "")
        local num, suffix = text:match("^([%d%.]+)([KkMmBbTtQq]?)$")

        local n = tonumber(num)
        if not n then return end

        minMoney = n * (SUFFIX[suffix:lower()] or 1)
        env.setconfig("minmoney", minMoney)
    end)

    -- starts off every session, it moves the character
    elements:Toggle("Auto Farm", section, false, function(v)
        env.EPFarm = v
        env.setconfig("farm", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.EPFarm do
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

                    if not entityFolder() then
                        if not warned then
                            warn("[BrainrotPolice] workspace.EntitiesFolder not found")
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

                            while env.EPFarm and item.Parent and os.clock() - t < GRAB_TIME do
                                if contested(item) then break end

                                holdAt(pivotOf(item) or pos, 0.1)
                                grab(item)

                                task.wait(0.05)
                            end

                            if item.Parent then
                                -- still lying there, leave it alone for a bit
                                skipUntil[item] = os.clock() + SKIP_TIME
                            else
                                -- got it, take it home to the plot
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
        end)
    end)

    ----------------------------------------------------------------
    -- auto collect cash
    ----------------------------------------------------------------

    elements:Toggle("Auto Collect Cash", section, setdata.cash, function(v)
        env.EPCash = v
        env.setconfig("cash", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.EPCash do
                local ev = remote("CollectAllCash")

                if ev then
                    warned = false

                    pcall(function()
                        if ev:IsA("RemoteFunction") then
                            ev:InvokeServer()
                        else
                            ev:FireServer()
                        end
                    end)
                elseif not warned then
                    warn("[BrainrotPolice] TypedRemote.CollectAllCash not found")
                    warned = true
                end

                task.wait(CASH_DELAY)
            end
        end)
    end)
end
