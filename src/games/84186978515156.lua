-- Sell Wheat!

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.SWSell = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.sell = setdata.sell or false
    setdata.selldelay = setdata.selldelay or 1
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local sellDelay = tonumber(setdata.selldelay) or 1

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
end
