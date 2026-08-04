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
end
