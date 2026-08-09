-- Grow a Garden 2 (PlaceId 97598239454123)

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.GGCollect = false
    env.GGSell = false
    env.GGSellFull = false
    env.GGBuy = false
    env.GGPlant = false
    env.GGPets = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.collect = setdata.collect or false
    setdata.mutated = setdata.mutated or false
    setdata.fruits = setdata.fruits or ""
    setdata.sell = setdata.sell or false
    setdata.sellfull = setdata.sellfull or false
    setdata.selldelay = setdata.selldelay or 60
    setdata.buy = setdata.buy or false
    setdata.seeds = setdata.seeds or ""
    setdata.plant = setdata.plant or false
    setdata.pets = setdata.pets or false
    setdata.petnames = setdata.petnames or ""
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    ----------------------------------------------------------------
    -- game modules and storage
    ----------------------------------------------------------------

    -- everything is resolved lazily and guarded, a missing child must never
    -- abort the module load or the whole tab stays empty
    local Networking = nil

    local function net()
        if Networking then return Networking end

        local shared = replicatedstorage:FindFirstChild("SharedModules")
        local mod = shared and shared:FindFirstChild("Networking")
        if not mod then return nil end

        local ok, result = pcall(function() return require(mod) end)
        if ok then Networking = result end

        return Networking
    end

    -- fires Networking.<a>.<b> whatever shape it turns out to have
    local function fire(a, b, ...)
        local n = net()
        if not n then return false end

        local group = n[a]
        local ev = group and group[b]
        if not ev then return false end

        local args = table.pack(...)

        local ok = pcall(function()
            if ev.Fire then
                ev:Fire(table.unpack(args, 1, args.n))
            elseif ev.FireServer then
                ev:FireServer(table.unpack(args, 1, args.n))
            end
        end)

        return ok
    end

    local function fruitsFolder()
        local f = replicatedstorage:FindFirstChild("PlantGenerationModules")
        return f and f:FindFirstChild("Fruits") or nil
    end

    local function seedShopItems()
        local sv = replicatedstorage:FindFirstChild("StockValues")
        local shop = sv and sv:FindFirstChild("SeedShop")
        return shop and shop:FindFirstChild("Items") or nil
    end

    local function petAssets()
        local assets = replicatedstorage:FindFirstChild("Assets")
        return assets and assets:FindFirstChild("Pets") or nil
    end

    local function wildPetSpawns()
        local map = workspace:FindFirstChild("Map")
        return map and map:FindFirstChild("WildPetSpawns") or nil
    end

    -- workspace.Gardens, the one with our name on it
    local function localPlot()
        local gardens = workspace:FindFirstChild("Gardens")
        if not gardens then return nil end

        for _, plot in ipairs(gardens:GetChildren()) do
            if plot:GetAttribute("Owner") == plr.Name then
                return plot
            end
        end

        return nil
    end

    local function plotPlants()
        local plot = localPlot()
        return plot and plot:FindFirstChild("Plants") or nil
    end

    local function plantRegions()
        local plot = localPlot()
        local visual = plot and plot:FindFirstChild("Visual")
        if not visual then return nil end

        local a = visual:FindFirstChild("PlantAreaColumn1")
        local b = visual:FindFirstChild("PlantAreaColumn2")

        return a, b
    end

    ----------------------------------------------------------------
    -- allow lists, stored as comma separated text
    ----------------------------------------------------------------

    local function parseList(text)
        local out = {}

        for word in tostring(text or ""):gmatch("[^,]+") do
            word = word:gsub("^%s+", ""):gsub("%s+$", "")
            if word ~= "" then out[#out + 1] = word end
        end

        return out
    end

    local function inList(list, name)
        for _, v in ipairs(list) do
            if v:lower() == tostring(name):lower() then return true end
        end

        return false
    end

    local allowedFruits = parseList(setdata.fruits)
    local allowedSeeds = parseList(setdata.seeds)
    local allowedPets = parseList(setdata.petnames)
    local allowMutated = setdata.mutated and true or false
    local sellDelay = tonumber(setdata.selldelay) or 60

    ----------------------------------------------------------------
    -- sell when full
    ----------------------------------------------------------------

    do
        local n = net()
        local notif = n and n.Notification

        if notif and notif.OnClientEvent then
            local conn = notif.OnClientEvent:Connect(function(msg)
                if msg == "Your inventory is full" and env.GGSellFull then
                    fire("NPCS", "SellAll")
                end
            end)

            env.BrainrotPolice = env.BrainrotPolice or {}
            if env.BrainrotPolice.track then
                env.BrainrotPolice.track(conn)
            end
        end
    end

    ----------------------------------------------------------------
    -- name dumps, the lists are far too long for a dropdown
    ----------------------------------------------------------------

    local function dumpNames(title, folder)
        if not folder then
            warn("[BrainrotPolice] " .. title .. " folder not found")
            return
        end

        local names = {}
        for _, c in ipairs(folder:GetChildren()) do
            names[#names + 1] = c.Name
        end

        table.sort(names)

        local text = table.concat(names, ", ")
        print("[BrainrotPolice] " .. title .. " (" .. #names .. "): " .. text)

        if setclipboard then
            pcall(function() setclipboard(text) end)
            print("[BrainrotPolice] copied to clipboard")
        end
    end

    ----------------------------------------------------------------
    -- auto collect
    ----------------------------------------------------------------

    elements:Label("Auto Collect", section)

    elements:Button("Copy Fruit Names", section, function()
        dumpNames("Fruits", fruitsFolder())
    end)

    elements:Textbox("Allowed Fruits (comma separated)", section, setdata.fruits, function(v)
        allowedFruits = parseList(v)
        env.setconfig("fruits", tostring(v))
    end)

    elements:Toggle("Collect Mutated", section, setdata.mutated, function(v)
        allowMutated = v
        env.setconfig("mutated", v)
    end)

    elements:Toggle("Auto Collect", section, setdata.collect, function(v)
        env.GGCollect = v
        env.setconfig("collect", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.GGCollect do
                local plants = plotPlants()

                if not plants then
                    if not warned then
                        warn("[BrainrotPolice] your garden was not found in workspace.Gardens")
                        warned = true
                    end

                    task.wait(2)
                else
                    warned = false

                    for _, plant in ipairs(plants:GetChildren()) do
                        if not env.GGCollect then break end

                        local fruits = plant:FindFirstChild("Fruits")

                        if fruits then
                            for _, fruit in ipairs(fruits:GetChildren()) do
                                if not env.GGCollect then break end

                                local mutated = fruit:GetAttribute("Mutation")
                                local skip = mutated and not allowMutated

                                if not skip and inList(allowedFruits, fruit:GetAttribute("CorePartName")) then
                                    local hp = fruit:FindFirstChild("HarvestPart")
                                    local prompt = hp and hp:FindFirstChild("HarvestPrompt")

                                    if prompt and fireproximityprompt then
                                        pcall(function() fireproximityprompt(prompt) end)
                                    end
                                end
                            end
                        end
                    end

                    task.wait(1)
                end
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto sell
    ----------------------------------------------------------------

    elements:Label("Auto Sell", section)

    elements:Button("Sell All Now", section, function()
        if not fire("NPCS", "SellAll") then
            warn("[BrainrotPolice] Networking.NPCS.SellAll not reachable")
        end
    end)

    elements:Toggle("Auto Sell When Full", section, setdata.sellfull, function(v)
        env.GGSellFull = v
        env.setconfig("sellfull", v)
    end)

    elements:Textbox("Sell Delay (default 60)", section, tostring(sellDelay), function(v)
        local n = tonumber(v)
        if not n or n < 1 then return end
        sellDelay = n
        env.setconfig("selldelay", n)
    end)

    elements:Toggle("Auto Sell", section, setdata.sell, function(v)
        env.GGSell = v
        env.setconfig("sell", v)
        if not v then return end

        task.spawn(function()
            while env.GGSell do
                fire("NPCS", "SellAll")
                task.wait(sellDelay)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto buy seeds
    ----------------------------------------------------------------

    elements:Label("Auto Buy Seeds", section)

    elements:Button("Copy Seed Names", section, function()
        dumpNames("Seeds", seedShopItems())
    end)

    elements:Textbox("Allowed Seeds (comma separated)", section, setdata.seeds, function(v)
        allowedSeeds = parseList(v)
        env.setconfig("seeds", tostring(v))
    end)

    elements:Toggle("Auto Buy", section, setdata.buy, function(v)
        env.GGBuy = v
        env.setconfig("buy", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.GGBuy do
                local shop = seedShopItems()

                if not shop then
                    if not warned then
                        warn("[BrainrotPolice] StockValues.SeedShop.Items not found")
                        warned = true
                    end

                    task.wait(2)
                else
                    warned = false

                    for _, seed in ipairs(allowedSeeds) do
                        if not env.GGBuy then break end

                        local val = shop:FindFirstChild(seed)

                        -- names are case sensitive in the shop, be forgiving
                        if not val then
                            for _, c in ipairs(shop:GetChildren()) do
                                if c.Name:lower() == seed:lower() then
                                    val = c
                                    break
                                end
                            end
                        end

                        if val and tonumber(val.Value) and val.Value >= 1 then
                            for _ = 1, val.Value do
                                if not env.GGBuy then break end

                                fire("SeedShop", "PurchaseSeed", val.Name)
                                task.wait()
                            end
                        end
                    end

                    task.wait(1)
                end
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto plant
    ----------------------------------------------------------------

    elements:Label("Auto Plant", section)

    elements:Toggle("Auto Plant", section, setdata.plant, function(v)
        env.GGPlant = v
        env.setconfig("plant", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.GGPlant do
                local a, b = plantRegions()
                local backpack = plr:FindFirstChildOfClass("Backpack")
                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")

                if not a or not b or not backpack or not hum then
                    if not warned then
                        warn("[BrainrotPolice] plant areas or character not ready")
                        warned = true
                    end

                    task.wait(1)
                else
                    warned = false

                    for _, tool in ipairs(backpack:GetChildren()) do
                        if not env.GGPlant then break end

                        if tool:GetAttribute("MainCategory") == "Seed" then
                            local region = math.random(1, 2) == 1 and a or b

                            pcall(function() hum:EquipTool(tool) end)
                            task.wait(0.1)

                            local size = region.Size
                            local pos = region.Position + Vector3.new(
                                (math.random() - 0.5) * size.X,
                                0,
                                (math.random() - 0.5) * size.Z
                            )

                            fire("Plant", "PlantSeed", pos, tool:GetAttribute("SeedTool"), tool)
                            task.wait(0.1)
                        end
                    end

                    task.wait(0.1)
                end
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto buy pets
    ----------------------------------------------------------------

    elements:Label("Auto Buy Pets", section)

    elements:Button("Copy Pet Names", section, function()
        dumpNames("Pets", petAssets())
    end)

    elements:Textbox("Allowed Pets (comma separated)", section, setdata.petnames, function(v)
        allowedPets = parseList(v)
        env.setconfig("petnames", tostring(v))
    end)

    -- starts off every session, it walks the character across the map
    elements:Toggle("Auto Buy Pets", section, false, function(v)
        env.GGPets = v
        env.setconfig("pets", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.GGPets do
                local spawns = wildPetSpawns()

                if not spawns then
                    if not warned then
                        warn("[BrainrotPolice] workspace.Map.WildPetSpawns not found")
                        warned = true
                    end

                    task.wait(2)
                else
                    warned = false

                    for _, pet in ipairs(spawns:GetChildren()) do
                        if not env.GGPets then break end

                        if inList(allowedPets, pet:GetAttribute("PetName")) and pet.PrimaryPart then
                            local char = plr.Character
                            local hum = char and char:FindFirstChildOfClass("Humanoid")

                            if hum then
                                pcall(function()
                                    hum:MoveTo(pet.PrimaryPart.Position)
                                end)

                                -- never block forever if the path is broken
                                local done = false

                                task.spawn(function()
                                    pcall(function() hum.MoveToFinished:Wait() end)
                                    done = true
                                end)

                                local t = os.clock()
                                while not done and os.clock() - t < 15 and env.GGPets do
                                    task.wait(0.1)
                                end

                                local prompt = pet.PrimaryPart
                                    and pet.PrimaryPart:FindFirstChild("BuyPrompt")

                                if prompt and fireproximityprompt then
                                    pcall(function() fireproximityprompt(prompt) end)
                                    task.wait()
                                end

                                fire("TeleportButton", "Request", "Garden")
                            end
                        end
                    end

                    task.wait(5)
                end
            end
        end)
    end)

    ----------------------------------------------------------------
    -- misc
    ----------------------------------------------------------------

    elements:Label("Misc", section)

    elements:Button("Teleport To Garden", section, function()
        fire("TeleportButton", "Request", "Garden")
    end)

    elements:Button("Show Sheckles", section, function()
        local stats = plr:FindFirstChild("leaderstats")
        local sheckles = stats and stats:FindFirstChild("Sheckles")

        print("[BrainrotPolice] Sheckles: "
            .. tostring(sheckles and sheckles.Value or "not found"))
    end)
end
