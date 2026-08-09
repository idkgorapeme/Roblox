-- Mining / stage game (PlaceId 74193805629461)

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.MGFarm = false
    env.MGSell = false
    env.MGStrength = false
    env.MGRebirth = false
    env.MGUpgrade = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farm = setdata.farm or false
    setdata.stage = setdata.stage or 30
    setdata.minmoney = setdata.minmoney or 0
    setdata.sell = setdata.sell or false
    setdata.strength = setdata.strength or false
    setdata.rebirth = setdata.rebirth or false
    setdata.upgrade = setdata.upgrade or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local FARM_DELAY = 0.2
    local GRAB_TIME = 1.5
    local SKIP_TIME = 20

    -- the game has an anticheat, so the click loop stays at a human rate
    local CLICK_DELAY = 0.1
    local UPGRADE_DELAY = 0.5

    local stageNumber = math.max(1, math.floor(tonumber(setdata.stage) or 30))
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

    -- ReplicatedStorage.Remotes.Server.<name>
    local function serverRemote(name)
        local remotes = replicatedstorage:FindFirstChild("Remotes")
        local server = remotes and remotes:FindFirstChild("Server")
        return server and server:FindFirstChild(name) or nil
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

    -- workspace.Stages["Stage <n>"].Spawnpoints
    local function spawnFolder()
        local stages = workspace:FindFirstChild("Stages")
        local stage = stages and stages:FindFirstChild("Stage " .. tostring(stageNumber))
        return stage and stage:FindFirstChild("Spawnpoints") or nil
    end

    -- <item>.Primary.ItemStats.BillboardGui.Revenue, something like "$1.2M/s"
    local function revenueOf(item)
        local primary = item:FindFirstChild("Primary")
        local stats = primary and primary:FindFirstChild("ItemStats")
        local gui = stats and stats:FindFirstChild("BillboardGui")
        local label = gui and gui:FindFirstChild("Revenue")

        if not label then
            label = item:FindFirstChild("Revenue", true)
        end

        if not label then return nil end

        local num, suffix = tostring(label.Text or ""):match("([%d%.,]+)%s*([KkMmBbTtQq]?)")
        if not num then return nil end

        num = tonumber((num:gsub(",", "")))
        if not num then return nil end

        local mult = ({
            k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15,
        })[suffix:lower()] or 1

        return num * mult
    end

    -- Spawnpoints holds a guid folder per spot, the item model sits inside.
    -- Returns every item that currently has something spawned.
    local function spawnedItems()
        local folder = spawnFolder()
        if not folder then return {} end

        local out = {}

        for _, point in ipairs(folder:GetChildren()) do
            for _, item in ipairs(point:GetChildren()) do
                -- the model carrying the revenue billboard is the loot
                if item:FindFirstChild("Primary") or item:FindFirstChild("Revenue", true) then
                    out[#out + 1] = item
                end
            end
        end

        return out
    end

    -- items we could not get, mapped to the time they may be tried again
    local skipUntil = {}

    -- Someone else is standing on it. Not proof, but close enough to move on
    -- instead of fighting over the same spawn.
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

    -- the most valuable spawn, ignoring anything below minMoney
    local function bestItem()
        local now = os.clock()
        local best, bestValue = nil, -1

        for _, item in ipairs(spawnedItems()) do
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

    elements:Textbox("Stage (default 30)", section, tostring(stageNumber), function(v)
        local n = tonumber(v)
        if not n then return end
        stageNumber = math.max(1, math.floor(n))
        env.setconfig("stage", stageNumber)
    end)

    -- accepts 5000, 5k, 2.5m and so on
    elements:Textbox("Min Revenue (0 = any)", section, tostring(minMoney), function(v)
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
        env.MGFarm = v
        env.setconfig("farm", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MGFarm do
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

                    if not spawnFolder() then
                        if not warned then
                            warn("[BrainrotPolice] Stages > Stage "
                                .. stageNumber .. " > Spawnpoints not found")
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

                            while env.MGFarm and item.Parent and os.clock() - t < GRAB_TIME do
                                pos = pivotOf(item) or pos
                                holdAt(pos, 0.1)
                                grab(item)

                                task.wait(0.05)
                            end

                            -- still there, someone is sitting on it
                            if item.Parent then
                                skipUntil[item] = os.clock() + SKIP_TIME
                            end

                            task.wait(FARM_DELAY)
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
        env.MGSell = v
        env.setconfig("sell", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MGSell do
                local ev = serverRemote("SellAllLoot")

                if ev then
                    warned = false
                    pcall(function() ev:FireServer() end)
                elseif not warned then
                    warn("[BrainrotPolice] Remotes.Server.SellAllLoot not found")
                    warned = true
                end

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto strength
    ----------------------------------------------------------------

    elements:Toggle("Auto Strength", section, setdata.strength, function(v)
        env.MGStrength = v
        env.setconfig("strength", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MGStrength do
                local ev = serverRemote("Click")

                if ev then
                    warned = false
                    pcall(function() ev:FireServer() end)
                elseif not warned then
                    warn("[BrainrotPolice] Remotes.Server.Click not found")
                    warned = true
                end

                task.wait(CLICK_DELAY)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto upgrade
    ----------------------------------------------------------------

    -- UpgradeSlot:FireServer("Cash")
    elements:Toggle("Auto Upgrade", section, setdata.upgrade, function(v)
        env.MGUpgrade = v
        env.setconfig("upgrade", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MGUpgrade do
                local ev = serverRemote("UpgradeSlot")

                if ev then
                    warned = false
                    -- the server ignores it when there is not enough cash
                    pcall(function() ev:FireServer("Cash") end)
                elseif not warned then
                    warn("[BrainrotPolice] Remotes.Server.UpgradeSlot not found")
                    warned = true
                end

                task.wait(UPGRADE_DELAY)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto rebirth
    ----------------------------------------------------------------

    -- Rebirth:FireServer("Rebirth")
    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.MGRebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MGRebirth do
                local ev = serverRemote("Rebirth")

                if ev then
                    warned = false
                    pcall(function() ev:FireServer("Rebirth") end)
                elseif not warned then
                    warn("[BrainrotPolice] Remotes.Server.Rebirth not found")
                    warned = true
                end

                task.wait(1)
            end
        end)
    end)
end