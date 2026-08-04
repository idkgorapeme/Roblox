-- +1 speed keyboard escape

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = game:GetService("Players").LocalPlayer

    env.KSWalk = false
    env.KSBuy = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.walk = setdata.walk or false
    setdata.autobuy = setdata.autobuy or false
    setdata.buy_mysterious = setdata.buy_mysterious ~= false
    setdata.buy_rare = setdata.buy_rare ~= false
    setdata.buy_uncommon = setdata.buy_uncommon ~= false
    setdata.buy_common = setdata.buy_common ~= false
    setdata.buycount = setdata.buycount or 5
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    ----------------------------------------------------------------
    -- speed farm
    ----------------------------------------------------------------

    elements:Toggle("Auto Walk Speed", section, setdata.walk, function(v)
        env.KSWalk = v
        env.setconfig("walk", v)
        if not v then return end

        task.spawn(function()
            while env.KSWalk do
                pcall(function()
                    local remotes = replicatedstorage:FindFirstChild("Remotes")
                    local ev = remotes and remotes:FindFirstChild("UpdateSpeed")
                    if ev then
                        ev:FireServer("Walking")
                    end
                end)

                task.wait()
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto buy system
    ----------------------------------------------------------------

    local BUY_ORDER = { "Mysterious", "Rare", "Uncommon", "Common" }
    local BUY_KEY = {
        Mysterious = "buy_mysterious",
        Rare       = "buy_rare",
        Uncommon   = "buy_uncommon",
        Common     = "buy_common",
    }

    local DELAY_BETWEEN_FIRES = 0.2
    local DELAY_BETWEEN_ITEMS = 1.0

    local buyCount = tonumber(setdata.buycount) or 5

    local buySelected = {}
    for _, name in ipairs(BUY_ORDER) do
        buySelected[name] = setdata[BUY_KEY[name]] ~= false
    end

    -- the remo container holds either real RemoteEvents or remo tables
    local function remoContainer()
        local pkgs = replicatedstorage:FindFirstChild("Packages")
        local index = pkgs and pkgs:FindFirstChild("_Index")
        if not index then return nil end

        local remoPkg = index:FindFirstChild("littensy_remo@1.5.3")
        if not remoPkg then
            -- version can change, match on the prefix
            for _, child in pairs(index:GetChildren()) do
                if string.sub(child.Name, 1, 14) == "littensy_remo@" then
                    remoPkg = child
                    break
                end
            end
        end
        if not remoPkg then return nil end

        local remo = remoPkg:FindFirstChild("remo")
        return remo and remo:FindFirstChild("container") or nil
    end

    -- works with both the remo table api and a plain RemoteEvent
    local function fireBuy(itemName)
        local container = remoContainer()
        local buyWins = container and container:FindFirstChild("BuyWins")
        if not buyWins then return end

        pcall(function()
            if typeof(buyWins) == "Instance" and buyWins:IsA("RemoteEvent") then
                buyWins:FireServer(itemName)
            elseif typeof(buyWins) == "table" and type(buyWins.fire) == "function" then
                buyWins:fire(itemName)
            end
        end)
    end

    local buyRunning = false

    local function runBuySequence()
        if buyRunning or not env.KSBuy then return end
        buyRunning = true

        pcall(function()
            for _, itemName in ipairs(BUY_ORDER) do
                if not env.KSBuy then break end

                if buySelected[itemName] then
                    for _ = 1, buyCount do
                        if not env.KSBuy then break end
                        fireBuy(itemName)
                        task.wait(DELAY_BETWEEN_FIRES)
                    end

                    task.wait(DELAY_BETWEEN_ITEMS)
                end
            end
        end)

        buyRunning = false
    end

    elements:Textbox("Buy Amount (default 5)", section, tostring(buyCount), function(v)
        local n = tonumber(v)
        if not n or n < 1 then return end
        buyCount = math.floor(n)
        env.setconfig("buycount", buyCount)
    end)

    for _, itemName in ipairs(BUY_ORDER) do
        elements:Toggle("Buy " .. itemName, section, buySelected[itemName], function(v)
            buySelected[itemName] = v
            env.setconfig(BUY_KEY[itemName], v)
        end)
    end

    local shopConn

    elements:Toggle("Auto Buy (on restock)", section, setdata.autobuy, function(v)
        env.KSBuy = v
        env.setconfig("autobuy", v)

        if shopConn then
            shopConn:Disconnect()
            shopConn = nil
        end

        if not v then return end

        local container = remoContainer()
        local shopUpdate = container and container:FindFirstChild("ShopUpdate")

        if shopUpdate and typeof(shopUpdate) == "Instance" and shopUpdate:IsA("RemoteEvent") then
            shopConn = shopUpdate.OnClientEvent:Connect(function()
                if env.KSBuy then
                    task.spawn(runBuySequence)
                end
            end)

            if env.BrainrotPolice and env.BrainrotPolice.track then
                env.BrainrotPolice.track(shopConn)
            end
        elseif shopUpdate and typeof(shopUpdate) == "table" then
            pcall(function()
                local fn = shopUpdate.connect or shopUpdate.listen
                if type(fn) == "function" then
                    fn(shopUpdate, function()
                        if env.KSBuy then
                            task.spawn(runBuySequence)
                        end
                    end)
                end
            end)
        else
            warn("[BrainrotPolice] ShopUpdate not found, auto buy only runs on the timer")
        end

        -- buy immediately, then keep buying so a missed restock event does
        -- not stall the whole thing
        task.spawn(function()
            while env.KSBuy do
                runBuySequence()
                task.wait(5)
            end
        end)
    end)
end
