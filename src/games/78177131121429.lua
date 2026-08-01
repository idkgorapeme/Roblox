-- Drill Blocks for Brainrots

return function(section, data)
    local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.DBCollect = false
    env.DBSell = false
    env.DBRebirth = false
    env.DBDrill = false
    env.DBPickup = false
    env.DBSpy = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.collect = setdata.collect or false
    setdata.sell = setdata.sell or false
    setdata.rebirth = setdata.rebirth or false
    setdata.drill = setdata.drill or false
    setdata.pickup = setdata.pickup or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local network = replicatedstorage:WaitForChild("Network")
    local remoteEvents = network:WaitForChild("RemoteEvents")

    local function remote(name)
        return remoteEvents:FindFirstChild(name)
    end

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- fires a no argument remote on an interval while the flag is set
    local function simpleLoop(flagName, remoteName, interval)
        local ev = remote(remoteName)
        if not ev then
            warn("[BrainrotPolice] remote not found: " .. remoteName)
            return
        end

        while env[flagName] do
            pcall(function()
                ev:FireServer()
            end)
            task.wait(interval)
        end
    end

    ----------------------------------------------------------------
    -- money
    ----------------------------------------------------------------

    elements:Toggle("Auto Collect Cash", section, setdata.collect, function(v)
        env.DBCollect = v
        env.setconfig("collect", v)
        if not v then return end
        task.spawn(function()
            simpleLoop("DBCollect", "RequestCollectCash", 1)
        end)
    end)

    elements:Toggle("Auto Sell All", section, setdata.sell, function(v)
        env.DBSell = v
        env.setconfig("sell", v)
        if not v then return end
        task.spawn(function()
            simpleLoop("DBSell", "SellAll", 3)
        end)
    end)

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.DBRebirth = v
        env.setconfig("rebirth", v)
        if not v then return end
        task.spawn(function()
            simpleLoop("DBRebirth", "Rebirth", 2)
        end)
    end)

    ----------------------------------------------------------------
    -- drilling / mining
    ----------------------------------------------------------------

    -- fires every proximity prompt on blocks near the player
    elements:Toggle("Auto Drill Blocks", section, setdata.drill, function(v)
        env.DBDrill = v
        env.setconfig("drill", v)
        if not v then return end

        task.spawn(function()
            while env.DBDrill do
                pcall(function()
                    local blocks = workspace:FindFirstChild("MiningBlocks")
                    if not blocks then return end

                    local root = getRoot()
                    if not root then return end

                    for _, block in pairs(blocks:GetDescendants()) do
                        if not env.DBDrill then return end

                        if block:IsA("ProximityPrompt") then
                            local part = block.Parent
                            if part and part:IsA("BasePart")
                                and (part.Position - root.Position).Magnitude < 120 then
                                pcall(function()
                                    fireproximityprompt(block)
                                end)
                            end
                        end
                    end
                end)

                task.wait(0.2)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- brainrot pickup
    ----------------------------------------------------------------

    -- walks to loose brainrots and grabs them
    elements:Toggle("Auto Pickup Brainrots", section, setdata.pickup, function(v)
        env.DBPickup = v
        env.setconfig("pickup", v)
        if not v then return end

        task.spawn(function()
            while env.DBPickup do
                pcall(function()
                    local folder = workspace:FindFirstChild("Newbrainrots")
                        or workspace:FindFirstChild("Items")
                    if not folder then return end

                    for _, item in pairs(folder:GetChildren()) do
                        if not env.DBPickup then return end

                        local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if prompt then
                            local root = getRoot()
                            local target = item:IsA("Model") and item:GetPivot().Position
                                or (item:IsA("BasePart") and item.Position)

                            if root and target then
                                root.CFrame = CFrame.new(target + Vector3.new(0, 4, 0))
                                task.wait(0.3)

                                local tries = 0
                                repeat
                                    pcall(function() fireproximityprompt(prompt) end)
                                    task.wait(0.1)
                                    tries = tries + 1
                                until not item.Parent or tries > 15 or not env.DBPickup
                            end
                        end
                    end
                end)

                task.wait(0.5)
            end
        end)
    end)

    elements:Button("Teleport To Base", section, function()
        local ev = remote("TeleportToBase")
        if ev then
            pcall(function() ev:FireServer() end)
        else
            warn("[BrainrotPolice] TeleportToBase not found")
        end
    end)

    ----------------------------------------------------------------
    -- one shot actions
    ----------------------------------------------------------------

    elements:Button("Spin Wheel", section, function()
        local ev = remote("SpinWheel")
        if ev then pcall(function() ev:FireServer() end) end
    end)

    elements:Button("Open Lucky Block", section, function()
        local ev = remote("RequestOpenLuckyBlock")
        if ev then pcall(function() ev:FireServer() end) end
    end)

    elements:Button("Claim World Cup Quest", section, function()
        local ev = remote("ClaimWorldCupQuest")
        if ev then pcall(function() ev:FireServer() end) end
    end)

    ----------------------------------------------------------------
    -- remote spy: capture the exact arguments the game sends
    ----------------------------------------------------------------

    local spyLog = {}
    local spyRestore

    local function describe(v)
        local t = typeof(v)
        if t == "Instance" then
            return "Instance<" .. v.ClassName .. ">(" .. v:GetFullName() .. ")"
        elseif t == "Vector3" then
            return string.format("Vector3.new(%s, %s, %s)", v.X, v.Y, v.Z)
        elseif t == "table" then
            local ok, encoded = pcall(function()
                return game:GetService("HttpService"):JSONEncode(v)
            end)
            return ok and ("table " .. encoded) or "table{...}"
        elseif t == "string" then
            return '"' .. v .. '"'
        end
        return tostring(v)
    end

    elements:Toggle("Remote Spy (logs your actions)", section, false, function(v)
        env.DBSpy = v

        if not v then
            if spyRestore then
                pcall(spyRestore)
                spyRestore = nil
            end
            return
        end

        spyLog = {}

        local ok = pcall(function()
            local mt = getrawmetatable(game)
            local old = mt.__namecall

            setreadonly(mt, false)

            mt.__namecall = newcclosure(function(self, ...)
                local method = getnamecallmethod()

                if env.DBSpy and (method == "FireServer" or method == "InvokeServer") then
                    local args = { ... }
                    local parts = {}
                    for i = 1, select("#", ...) do
                        parts[#parts + 1] = describe(args[i])
                    end

                    local line = self:GetFullName() .. ":" .. method .. "("
                        .. table.concat(parts, ", ") .. ")"

                    -- skip duplicates so the log stays readable
                    if spyLog[#spyLog] ~= line then
                        spyLog[#spyLog + 1] = line
                        print("[spy] " .. line)
                    end
                end

                return old(self, ...)
            end)

            setreadonly(mt, true)

            spyRestore = function()
                setreadonly(mt, false)
                mt.__namecall = old
                setreadonly(mt, true)
            end
        end)

        if not ok then
            warn("[BrainrotPolice] remote spy not supported by this executor")
            env.DBSpy = false
        end
    end)

    elements:Button("Copy Spy Log", section, function()
        if #spyLog == 0 then
            warn("[BrainrotPolice] spy log is empty, enable Remote Spy and do the action")
            return
        end

        local text = table.concat(spyLog, "\n")
        pcall(function()
            writefile("BrainrotPolice/spy_" .. tostring(game.PlaceId) .. ".txt", text)
        end)

        local copied = pcall(function() setclipboard(text) end)
        print("[BrainrotPolice] " .. #spyLog .. " calls logged, copied=" .. tostring(copied))
    end)
end
