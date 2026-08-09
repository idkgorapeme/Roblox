-- Zoo steal game (PlaceId 123822115505881)

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local plr = players.LocalPlayer

    env.ZOBuy = false
    env.ZOSteal = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.buy = setdata.buy or false
    setdata.steal = setdata.steal or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- workspace.Map.Bases["1"] .. Bases["11"]
    local BASE_FROM, BASE_TO = 1, 11

    local BUY_DELAY = 1
    local STEAL_DELAY = 0.2
    local GRAB_TIME = 1.5
    local SKIP_TIME = 20

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
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end

        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok and cf then return cf.Position end

        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local SUFFIX = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15 }

    local function parseAmount(text)
        local num, suffix = tostring(text or ""):match("([%d%.,]+)%s*([KkMmBbTtQq]?)")
        if not num then return nil end

        num = tonumber((num:gsub(",", "")))
        if not num then return nil end

        return num * (SUFFIX[suffix:lower()] or 1)
    end

    local function myCash()
        local stats = plr:FindFirstChild("leaderstats")
        local cash = stats and stats:FindFirstChild("Cash")
        return cash and tonumber(cash.Value) or 0
    end

    ----------------------------------------------------------------
    -- bases
    ----------------------------------------------------------------

    -- workspace.Map.Bases["<n>"]
    local function baseFolder(n)
        local map = workspace:FindFirstChild("Map")
        local bases = map and map:FindFirstChild("Bases")
        return bases and bases:FindFirstChild(tostring(n)) or nil
    end

    -- <base>.Button.Main, the buy pad. Gone once the base is owned.
    local function buyButton(n)
        local base = baseFolder(n)
        local button = base and base:FindFirstChild("Button")
        return button and button:FindFirstChild("Main") or nil
    end

    -- no buy button left means the base belongs to somebody, so it can be
    -- robbed
    local function isUnlocked(n)
        return baseFolder(n) ~= nil and buyButton(n) == nil
    end

    -- <button>.Attachment.BillboardGui.PriceLabel
    local function priceOf(n)
        local main = buyButton(n)
        if not main then return nil end

        local att = main:FindFirstChild("Attachment")
        local gui = att and att:FindFirstChild("BillboardGui")
        local label = gui and gui:FindFirstChild("PriceLabel")

        if not label then
            label = main:FindFirstChild("PriceLabel", true)
        end

        if not label then return nil end

        return parseAmount(label.Text)
    end

    ----------------------------------------------------------------
    -- movement
    ----------------------------------------------------------------

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

    -- Prompts, clicks and touches are all tried, standing on something is
    -- not always enough on its own.
    local function interact(inst)
        local root = getRoot()
        if not root then return end

        for _, d in ipairs(inst:GetDescendants()) do
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

        if inst:IsA("BasePart") and firetouchinterest then
            pcall(function()
                firetouchinterest(root, inst, 0)
                firetouchinterest(root, inst, 1)
            end)
        end
    end

    ----------------------------------------------------------------
    -- auto buy zoos
    ----------------------------------------------------------------

    -- the cheapest base we can currently afford
    local function affordableBase()
        local cash = myCash()
        local best, bestPrice = nil, nil

        for n = BASE_FROM, BASE_TO do
            local price = priceOf(n)

            if price and price <= cash then
                if not bestPrice or price < bestPrice then
                    best, bestPrice = n, price
                end
            end
        end

        return best, bestPrice
    end

    elements:Button("Dump Bases", section, function()
        print("[BrainrotPolice] cash: " .. tostring(myCash()))

        for n = BASE_FROM, BASE_TO do
            local base = baseFolder(n)

            if not base then
                print("  Base " .. n .. ": missing")
            else
                local price = priceOf(n)
                print("  Base " .. n
                    .. " | owned=" .. tostring(isUnlocked(n))
                    .. " | price=" .. tostring(price)
                    .. " | button=" .. tostring(pivotOf(buyButton(n))))
            end
        end
    end)

    -- starts off every session, it moves the character
    elements:Toggle("Auto Buy Zoos", section, false, function(v)
        env.ZOBuy = v
        env.setconfig("buy", v)
        if not v then return end

        task.spawn(function()
            while env.ZOBuy do
                if not alive() then
                    task.wait(0.5)
                else
                    local n = affordableBase()

                    if not n then
                        -- nothing we can pay for yet
                        task.wait(BUY_DELAY)
                    else
                        local main = buyButton(n)
                        local pos = pivotOf(main)

                        if pos then
                            -- stand on the pad until the button disappears
                            local t = os.clock()

                            while env.ZOBuy and buyButton(n) and os.clock() - t < 3 do
                                holdAt(pos, 0.1)
                                interact(main)
                                task.wait(0.05)
                            end
                        end

                        task.wait(BUY_DELAY)
                    end
                end
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto steal
    ----------------------------------------------------------------

    -- everything worth taking inside a base we own
    local function lootIn(n)
        local base = baseFolder(n)
        if not base then return {} end

        local out = {}

        -- the animals sit in whatever holder the base uses
        for _, name in ipairs({ "Animals", "Entities", "Stands", "Slots", "Plots" }) do
            local holder = base:FindFirstChild(name)

            if holder then
                for _, item in ipairs(holder:GetChildren()) do
                    if pivotOf(item) then out[#out + 1] = item end
                end
            end
        end

        -- nothing named, take any model that is not scenery
        if #out == 0 then
            for _, item in ipairs(base:GetChildren()) do
                if item:IsA("Model") and item.Name ~= "Button" and pivotOf(item) then
                    out[#out + 1] = item
                end
            end
        end

        return out
    end

    local skipUntil = {}

    -- The best base we own is simply the highest numbered one, they get
    -- more expensive as they go up.
    local function bestOwnedBase()
        for n = BASE_TO, BASE_FROM, -1 do
            if isUnlocked(n) and #lootIn(n) > 0 then
                return n
            end
        end

        return nil
    end

    -- starts off every session, it moves the character
    elements:Toggle("Auto Steal", section, false, function(v)
        env.ZOSteal = v
        env.setconfig("steal", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.ZOSteal do
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

                    local n = bestOwnedBase()

                    if not n then
                        if not warned then
                            warn("[BrainrotPolice] no unlocked base with anything in it")
                            warned = true
                        end

                        task.wait(1)
                    else
                        warned = false

                        local target = nil

                        for _, item in ipairs(lootIn(n)) do
                            if not (skipUntil[item] and skipUntil[item] > now) then
                                target = item
                                break
                            end
                        end

                        if not target then
                            task.wait(0.5)
                        else
                            local pos = pivotOf(target)
                            local t = os.clock()

                            while env.ZOSteal and target.Parent and os.clock() - t < GRAB_TIME do
                                holdAt(pivotOf(target) or pos, 0.1)
                                interact(target)
                                task.wait(0.05)
                            end

                            if target.Parent then
                                skipUntil[target] = os.clock() + SKIP_TIME
                            end

                            task.wait(STEAL_DELAY)
                        end
                    end
                end
            end
        end)
    end)
end
