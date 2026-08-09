-- +1 Muscle to Push Boulder

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.MPTrain = false
    env.MPWin = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.train = setdata.train or false
    setdata.traindelay = setdata.traindelay or 0.1
    setdata.win = setdata.win or false
    setdata.world = setdata.world or "World 1"
    setdata.area = setdata.area or 1
    setdata.windelay = setdata.windelay or 1
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local trainDelay = tonumber(setdata.traindelay) or 0.1
    local winDelay = tonumber(setdata.windelay) or 1
    local areaNumber = tonumber(setdata.area) or 1

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

    ----------------------------------------------------------------
    -- auto win
    --
    -- workspace.Areas["<world folder>"].Area<n>.Win
    ----------------------------------------------------------------

    local WORLD_OPTIONS = { "World 1", "World 2", "World 3", "World 4" }

    local WORLD_FOLDER = {
        ["World 1"] = "Spawn World",
        ["World 2"] = "Future World",
        ["World 3"] = "Heaven World",
        ["World 4"] = "Hell World",
    }

    local worldChoice = tostring(setdata.world or "World 1")
    if not WORLD_FOLDER[worldChoice] then worldChoice = "World 1" end

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- resolves the Win part of the selected world and area
    local function winPart()
        local areas = workspace:FindFirstChild("Areas")
        if not areas then return nil, "workspace.Areas missing" end

        local folderName = WORLD_FOLDER[worldChoice]
        local world = areas:FindFirstChild(folderName)
        if not world then return nil, folderName .. " missing" end

        local area = world:FindFirstChild("Area" .. tostring(areaNumber))
        if not area then return nil, folderName .. ".Area" .. areaNumber .. " missing" end

        local win = area:FindFirstChild("Win")
        if not win then return nil, "Area" .. areaNumber .. ".Win missing" end

        if win:IsA("BasePart") then return win end
        return win:FindFirstChildWhichIsA("BasePart", true), nil
    end

    elements:Dropdown("World", section, WORLD_OPTIONS, worldChoice, function(v)
        worldChoice = v
        env.setconfig("world", v)
        print("[BrainrotPolice] world set to " .. v .. " (" .. WORLD_FOLDER[v] .. ")")
    end)

    elements:Textbox("Area (1 - 10)", section, tostring(areaNumber), function(v)
        local n = tonumber(v)
        if not n then return end
        areaNumber = math.clamp(math.floor(n), 1, 10)
        env.setconfig("area", areaNumber)
    end)

    elements:Textbox("Win Delay (default 1)", section, tostring(winDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.1 then return end
        winDelay = n
        env.setconfig("windelay", n)
    end)

    elements:Button("Test Win Target", section, function()
        local part, err = winPart()

        if not part then
            warn("[BrainrotPolice] " .. tostring(err))
            return
        end

        print("[BrainrotPolice] target: " .. part:GetFullName())
        print("[BrainrotPolice] position: " .. tostring(part.Position))
    end)

    -- starts off every session, it moves the character
    elements:Toggle("Auto Win", section, false, function(v)
        env.MPWin = v
        env.setconfig("win", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MPWin do
                local part, err = winPart()

                if not part then
                    if not warned then
                        warn("[BrainrotPolice] " .. tostring(err))
                        warned = true
                    end
                    task.wait(1)
                else
                    warned = false

                    local root = getRoot()
                    local hum = plr.Character
                        and plr.Character:FindFirstChildOfClass("Humanoid")

                    -- do not fling the corpse around between respawns
                    if root and hum and hum.Health > 0 then
                        pcall(function()
                            root.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
                            root.AssemblyLinearVelocity = Vector3.zero
                        end)
                    end

                    task.wait(winDelay)
                end
            end
        end)
    end)
end
