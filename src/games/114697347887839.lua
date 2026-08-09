-- +1 Speed Monkey Escape

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.MERebirth = false
    env.MEWin = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.rebirth = setdata.rebirth or false
    setdata.win = setdata.win or false
    setdata.world = setdata.world or "World 1"
    setdata.stage = setdata.stage or 1
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- workspace.Map.World<n>.Stages.Stage<n>.NormalWin
    local WORLD_OPTIONS = { "World 1", "World 2", "World 3", "World 4", "World 5" }

    local worldChoice = tostring(setdata.world or "World 1")
    local stageNumber = math.clamp(tonumber(setdata.stage) or 1, 1, 10)

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

    ----------------------------------------------------------------
    -- auto rebirth
    ----------------------------------------------------------------

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.MERebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MERebirth do
                local remotes = replicatedstorage:FindFirstChild("Remotes")
                local ev = remotes and remotes:FindFirstChild("Rebirth")

                if ev then
                    warned = false
                    pcall(function() ev:FireServer() end)
                elseif not warned then
                    warn("[BrainrotPolice] Remotes.Rebirth not found")
                    warned = true
                end

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto win
    ----------------------------------------------------------------

    -- resolves workspace.Map.World<n>.Stages.Stage<n>.NormalWin
    local function winPart()
        local map = workspace:FindFirstChild("Map")
        if not map then return nil, "workspace.Map missing" end

        -- "World 3" -> "World3"
        local worldName = worldChoice:gsub("%s", "")
        local world = map:FindFirstChild(worldName)
        if not world then return nil, "Map." .. worldName .. " missing" end

        local stages = world:FindFirstChild("Stages")
        if not stages then return nil, worldName .. ".Stages missing" end

        local stage = stages:FindFirstChild("Stage" .. tostring(stageNumber))
        if not stage then
            return nil, worldName .. ".Stages.Stage" .. stageNumber .. " missing"
        end

        local win = stage:FindFirstChild("NormalWin")
        if not win then
            return nil, "Stage" .. stageNumber .. ".NormalWin missing"
        end

        if win:IsA("BasePart") then return win end

        local inner = win:FindFirstChildWhichIsA("BasePart", true)
        if inner then return inner end

        return nil, "NormalWin has no BasePart inside it"
    end

    -- Moves the whole character, not just the root part. A single CFrame
    -- write is easy for the game to undo, so it is applied over a few
    -- frames and the velocity is cleared each time.
    local function teleportTo(pos)
        local char = getChar()
        local root = getRoot()
        if not char or not root then return false end

        local target = CFrame.new(pos)

        for _ = 1, 3 do
            pcall(function()
                -- PivotTo moves every welded part with it
                char:PivotTo(target)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)

            task.wait()
        end

        return true
    end

    elements:Button("Test Win TP", section, function()
        local part, err = winPart()

        if not part then
            warn("[BrainrotPolice] " .. tostring(err or "unknown"))

            -- show what actually exists so the path can be corrected
            local map = workspace:FindFirstChild("Map")
            if map then
                local names = {}
                for _, c in pairs(map:GetChildren()) do
                    names[#names + 1] = c.Name
                end
                print("[BrainrotPolice] workspace.Map children: "
                    .. table.concat(names, ", "))
            end
            return
        end

        print("[BrainrotPolice] target: " .. part:GetFullName())
        print("[BrainrotPolice] position: " .. tostring(part.Position))

        local root = getRoot()
        print("[BrainrotPolice] before: " .. (root and tostring(root.Position) or "no root"))

        teleportTo(part.Position)
        task.wait(0.3)

        root = getRoot()
        print("[BrainrotPolice] after:  " .. (root and tostring(root.Position) or "no root"))
    end)

    elements:Dropdown("World", section, WORLD_OPTIONS, worldChoice, function(v)
        worldChoice = v
        env.setconfig("world", v)
    end)

    elements:Textbox("Stage (1 - 10)", section, tostring(stageNumber), function(v)
        local n = tonumber(v)
        if not n then return end
        stageNumber = math.clamp(math.floor(n), 1, 10)
        env.setconfig("stage", stageNumber)
    end)

    -- starts off every session, it moves the character
    -- starts off every session, it moves the character
    elements:Toggle("Auto Win", section, false, function(v)
        env.MEWin = v
        env.setconfig("win", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.MEWin do
                if not alive() then
                    -- do not fling the corpse around between respawns
                    task.wait(0.5)
                else
                    local part, err = winPart()

                    if not part then
                        if not warned then
                            warn("[BrainrotPolice] " .. tostring(err))
                            warned = true
                        end
                        task.wait(1)
                    else
                        warned = false

                        pcall(function()
                            teleportTo(part.Position)
                        end)

                        task.wait(0.5)
                    end
                end
            end
        end)
    end)
end
