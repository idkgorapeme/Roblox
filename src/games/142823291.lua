-- Murder Mystery 2

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.MMCoins = false
    env.MMCoinEsp = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.coins = setdata.coins or false
    setdata.coinesp = setdata.coinesp or false
    setdata.coindelay = setdata.coindelay or 0.12
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local coinDelay = tonumber(setdata.coindelay) or 0.12

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- coins live in <map>.CoinContainer, and the map changes every round
    ----------------------------------------------------------------

    local function coinContainer()
        -- search every top level model for a CoinContainer
        for _, child in pairs(workspace:GetChildren()) do
            if child:IsA("Model") or child:IsA("Folder") then
                local c = child:FindFirstChild("CoinContainer")
                if c then return c end
            end
        end

        -- last resort, anywhere in the tree
        return workspace:FindFirstChild("CoinContainer", true)
    end

    local function coinPart(inst)
        if inst:IsA("BasePart") then return inst end
        if inst:IsA("Model") then
            return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
        end
        return nil
    end

    local function findCoins()
        local out = {}
        local container = coinContainer()
        if not container then return out end

        for _, child in pairs(container:GetChildren()) do
            local part = coinPart(child)
            if part then
                out[#out + 1] = { inst = child, part = part }
            end
        end

        return out
    end

    elements:Button("Count Coins", section, function()
        local container = coinContainer()
        print("[BrainrotPolice] container: "
            .. (container and container:GetFullName() or "NOT FOUND"))

        local coins = findCoins()
        print("[BrainrotPolice] " .. #coins .. " coins")

        for i, c in ipairs(coins) do
            if i > 3 then break end
            print("  " .. c.inst:GetFullName())
        end
    end)

    ----------------------------------------------------------------
    -- coin farm
    ----------------------------------------------------------------

    elements:Textbox("Coin Delay (default 0.12)", section, tostring(coinDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.05 then return end
        coinDelay = n
        env.setconfig("coindelay", n)
    end)

    elements:Toggle("Auto Collect Coins", section, setdata.coins, function(v)
        env.MMCoins = v
        env.setconfig("coins", v)
        if not v then return end

        task.spawn(function()
            local announced = false

            while env.MMCoins do
                local root = getRoot()

                if root then
                    local coins = findCoins()

                    if not announced then
                        print("[BrainrotPolice] coin farm: " .. #coins .. " coins found")
                        if #coins == 0 then
                            warn("[BrainrotPolice] no coins, press Count Coins during a round")
                        end
                        announced = true
                    end

                    -- come back afterwards so we do not end up across the map
                    local origin = root.CFrame

                    for _, c in ipairs(coins) do
                        if not env.MMCoins then break end

                        if c.part and c.part.Parent then
                            local r = getRoot()
                            if r then
                                r.CFrame = CFrame.new(c.part.Position)
                                r.AssemblyLinearVelocity = Vector3.zero

                                if firetouchinterest then
                                    pcall(function()
                                        firetouchinterest(r, c.part, 0)
                                        firetouchinterest(r, c.part, 1)
                                    end)
                                end

                                task.wait(coinDelay)
                            end
                        end
                    end

                    local r = getRoot()
                    if r then
                        r.CFrame = origin
                        r.AssemblyLinearVelocity = Vector3.zero
                    end
                end

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- coin esp
    ----------------------------------------------------------------

    local coinHighlights = {}

    local function clearCoinEsp()
        for inst, hl in pairs(coinHighlights) do
            pcall(function() hl:Destroy() end)
            coinHighlights[inst] = nil
        end
    end

    elements:Toggle("Coin ESP", section, setdata.coinesp, function(v)
        env.MMCoinEsp = v
        env.setconfig("coinesp", v)

        if not v then
            clearCoinEsp()
            return
        end

        task.spawn(function()
            while env.MMCoinEsp do
                pcall(function()
                    local seen = {}

                    for _, c in ipairs(findCoins()) do
                        seen[c.inst] = true

                        if not coinHighlights[c.inst] then
                            local hl = Instance.new("Highlight")
                            hl.Name = "BPCoin"
                            hl.FillColor = Color3.fromRGB(255, 210, 0)
                            hl.FillTransparency = 0.3
                            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            hl.Adornee = c.inst
                            hl.Parent = c.inst

                            coinHighlights[c.inst] = hl
                        end
                    end

                    for inst, hl in pairs(coinHighlights) do
                        if not seen[inst] or not inst.Parent then
                            pcall(function() hl:Destroy() end)
                            coinHighlights[inst] = nil
                        end
                    end
                end)

                task.wait(1)
            end

            clearCoinEsp()
        end)
    end)
end
