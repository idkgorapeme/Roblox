-- Steal a Brainrot style base game (PlaceId 104339804279870)

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local plr = players.LocalPlayer

    env.STFarm = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farm = setdata.farm or false
    setdata.base = setdata.base or "Base20"
    setdata.minmoney = setdata.minmoney or 0
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- middle of the area, used while nothing is worth grabbing
    local AREA_POS = Vector3.new(-13, 6, 879)
    local FARM_DELAY = 0.2

    local baseName = tostring(setdata.base or "Base20")
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

    -- workspace.Bases.<base>.Slots
    local function slotsFolder()
        local bases = workspace:FindFirstChild("Bases")
        local base = bases and bases:FindFirstChild(baseName)
        return base and base:FindFirstChild("Slots") or nil
    end

    -- <slot>.Spawn.SpawnedItem
    local function itemInSlot(slot)
        local spawn = slot:FindFirstChild("Spawn")
        return spawn and spawn:FindFirstChild("SpawnedItem") or nil
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

    -- the slot holding the richest brainrot, ignoring anything below minMoney
    local function bestItem()
        local slots = slotsFolder()
        if not slots then return nil end

        local best, bestValue = nil, -1

        for _, slot in ipairs(slots:GetChildren()) do
            local item = itemInSlot(slot)
            local value = item and earningsOf(item) or nil

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

    -- the game has no carry attribute here, so a brainrot welded to the
    -- character is what counts as carrying something
    local function carrying()
        if plr:GetAttribute("IsCarryingBrainrot") then return true end

        local char = getChar()
        if not char then return false end

        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Model") and c.Name ~= "Head" then return true end
        end

        return false
    end

    -- your own plot, that is where a carried brainrot has to be dropped off
    local function myPlot()
        local direct = workspace:FindFirstChild("Plot_" .. plr.Name)
        return direct and pivotOf(direct) or nil
    end

    elements:Textbox("Base (default Base20)", section, baseName, function(v)
        v = tostring(v):gsub("^%s+", ""):gsub("%s+$", "")
        if v == "" then return end

        -- accept both "20" and "Base20"
        if v:match("^%d+$") then v = "Base" .. v end

        baseName = v
        env.setconfig("base", v)
    end)

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
        env.STFarm = v
        env.setconfig("farm", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.STFarm do
                if not alive() then
                    task.wait(0.5)
                elseif carrying() then
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
                        -- nothing worth taking, wait in the area
                        holdAt(AREA_POS, 0.1)
                        task.wait(0.3)
                    else
                        warned = false

                        local pos = pivotOf(item)

                        -- sit on it and interact until it is in our hands
                        local t = os.clock()

                        while env.STFarm and item.Parent and os.clock() - t < 2 do
                            if carrying() then break end

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
end
