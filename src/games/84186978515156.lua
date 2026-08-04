-- Sell Wheat!

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.SWSell = false
    env.SWRebirth = false
    env.SWCollect = false
    env.SWSpy = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.sell = setdata.sell or false
    setdata.selldelay = setdata.selldelay or 1
    setdata.rebirth = setdata.rebirth or false
    setdata.collect = setdata.collect or false
    setdata.collectdelay = setdata.collectdelay or 0.5
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local sellDelay = tonumber(setdata.selldelay) or 1
    local collectDelay = tonumber(setdata.collectdelay) or 0.5

    -- lazily resolved so a missing remote can never block the UI
    local function remote(name)
        local folder = replicatedstorage:FindFirstChild("Remotes")
        return folder and folder:FindFirstChild(name) or nil
    end

    elements:Textbox("Sell Delay (default 1)", section, tostring(sellDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.1 then return end
        sellDelay = n
        env.setconfig("selldelay", n)
    end)

    elements:Toggle("Auto Sell", section, setdata.sell, function(v)
        env.SWSell = v
        env.setconfig("sell", v)
        if not v then return end

        task.spawn(function()
            while env.SWSell do
                pcall(function()
                    local ev = remote("Sell")
                    if ev then ev:FireServer() end
                end)

                task.wait(sellDelay)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto collect
    ----------------------------------------------------------------

    -- workspace.PlacedObjects.<you> holds everything you have placed
    local function myPlacedObjects()
        local folder = workspace:FindFirstChild("PlacedObjects")
        local mine = folder and folder:FindFirstChild(plr.Name)
        if not mine then return {} end
        return mine:GetChildren()
    end

    elements:Textbox("Collect Delay (default 0.5)", section, tostring(collectDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.05 then return end
        collectDelay = n
        env.setconfig("collectdelay", n)
    end)

    elements:Toggle("Auto Collect", section, setdata.collect, function(v)
        env.SWCollect = v
        env.setconfig("collect", v)
        if not v then return end

        task.spawn(function()
            local announced = false

            while env.SWCollect do
                local objects = myPlacedObjects()

                if not announced then
                    print("[BrainrotPolice] Auto Collect: " .. #objects .. " placed objects")
                    if #objects == 0 then
                        warn("[BrainrotPolice] nothing found in workspace.PlacedObjects." .. plr.Name)
                    end
                    announced = true
                end

                local ev = remote("Collect")

                if ev then
                    -- one Collect call per placed object, mills and harvesters
                    -- alike, the server ignores the ones with nothing ready
                    for _, obj in ipairs(objects) do
                        if not env.SWCollect then break end

                        pcall(function()
                            ev:FireServer(obj)
                        end)
                    end
                end

                task.wait(collectDelay)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto rebirth
    ----------------------------------------------------------------

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.SWRebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            while env.SWRebirth do
                pcall(function()
                    local ev = remote("Rebirth")
                    if ev then ev:FireServer() end
                end)

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- place capture: records the exact PlaceObject call so auto place
    -- can be built from the real arguments instead of a guess
    ----------------------------------------------------------------

    local spyLog = {}
    local spyRestore

    local function describe(v)
        local t = typeof(v)
        if t == "Instance" then
            return "Instance<" .. v.ClassName .. ">(" .. v:GetFullName() .. ")"
        elseif t == "CFrame" then
            local x, y, z = v.X, v.Y, v.Z
            return string.format("CFrame.new(%.2f, %.2f, %.2f)", x, y, z)
        elseif t == "Vector3" then
            return string.format("Vector3.new(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
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

    elements:Toggle("Capture Place Calls", section, false, function(v)
        env.SWSpy = v

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

                if env.SWSpy and (method == "FireServer" or method == "InvokeServer") then
                    local args = { ... }
                    local parts = {}
                    for i = 1, select("#", ...) do
                        parts[#parts + 1] = describe(args[i])
                    end

                    local line = self:GetFullName() .. ":" .. method .. "("
                        .. table.concat(parts, ", ") .. ")"

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
            env.SWSpy = false
        end
    end)

    elements:Button("Copy Capture Log", section, function()
        if #spyLog == 0 then
            warn("[BrainrotPolice] log is empty, enable Capture Place Calls and place an object")
            return
        end

        local text = "PlaceId: " .. tostring(game.PlaceId) .. "\n\n"
            .. table.concat(spyLog, "\n")

        pcall(function()
            writefile("BrainrotPolice/spy_" .. tostring(game.PlaceId) .. ".txt", text)
        end)

        local copied = pcall(function() setclipboard(text) end)
        print("[BrainrotPolice] " .. #spyLog .. " calls logged, copied=" .. tostring(copied))
    end)
end
