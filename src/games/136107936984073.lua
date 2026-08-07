-- +1 Muscle to Push Boulder

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.MPTrain = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.train = setdata.train or false
    setdata.traindelay = setdata.traindelay or 0.1
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local trainDelay = tonumber(setdata.traindelay) or 0.1

    ----------------------------------------------------------------
    -- Packages.Net remotes. The names contain a slash, which some
    -- executors mishandle with plain indexing, so fall back to a
    -- name scan over the children.
    ----------------------------------------------------------------

    local function netRemote(name)
        local pkgs = replicatedstorage:FindFirstChild("Packages")
        local net = pkgs and pkgs:FindFirstChild("Net")
        if not net then return nil end

        local direct = net:FindFirstChild(name)
        if direct then return direct end

        for _, child in pairs(net:GetChildren()) do
            if child.Name == name then
                return child
            end
        end

        return nil
    end

    ----------------------------------------------------------------
    -- auto train
    ----------------------------------------------------------------

    elements:Textbox("Train Delay (default 0.1)", section, tostring(trainDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.01 then return end
        trainDelay = n
        env.setconfig("traindelay", n)
    end)

    elements:Button("Test Train Once", section, function()
        local ev = netRemote("RE/ClientTrain")

        if not ev then
            warn("[BrainrotPolice] RE/ClientTrain NOT FOUND")
            return
        end

        print("[BrainrotPolice] firing " .. ev:GetFullName())

        local ok, err = pcall(function() ev:FireServer() end)

        if ok then
            print("[BrainrotPolice] FireServer sent, muscle: "
                .. tostring(plr:FindFirstChild("leaderstats")
                    and plr.leaderstats:FindFirstChild("Muscle 💪")
                    and plr.leaderstats["Muscle 💪"].Value))
        else
            warn("[BrainrotPolice] FireServer failed: " .. tostring(err))
        end
    end)

    elements:Toggle("Auto Train", section, setdata.train, function(v)
        env.MPTrain = v
        env.setconfig("train", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MPTrain do
                local ev = netRemote("RE/ClientTrain")

                if ev then
                    warned = false
                    pcall(function() ev:FireServer() end)
                elseif not warned then
                    warn("[BrainrotPolice] RE/ClientTrain not found")
                    warned = true
                end

                task.wait(trainDelay)
            end
        end)
    end)
end
