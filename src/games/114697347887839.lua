-- +1 Speed Monkey Escape

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.MERebirth = false
    env.MEWin = false
    env.MEWinTest = false

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

    -- the map streams in piece by piece, so a far away stage does not
    -- exist yet when you are still standing at the start. these settings
    -- control how the script hops closer stage by stage until the wanted
    -- one has loaded.
    local STAGE_STEP = 1      -- hop over every stage (1, 2, 3, ...)
    local HOP_OFFSET = 10     -- how many studs next to the win block to stop
    local HOP_WAIT = 0.35     -- pause after a hop so the next chunk can load
    local HOP_TIMEOUT = 5     -- max seconds to wait for one stage to appear

    -- resolves workspace.Map.World<n>.Stages.Stage<n>.NormalWin
    local function winPartFor(n)
        local map = workspace:FindFirstChild("Map")
        if not map then return nil, "workspace.Map missing" end

        -- "World 3" -> "World3"
        local worldName = worldChoice:gsub("%s", "")
        local world = map:FindFirstChild(worldName)
        if not world then return nil, "Map." .. worldName .. " missing" end

        local stages = world:FindFirstChild("Stages")
        if not stages then return nil, worldName .. ".Stages missing" end

        local stage = stages:FindFirstChild("Stage" .. tostring(n))
        if not stage then
            return nil, worldName .. ".Stages.Stage" .. n .. " not loaded yet"
        end

        local win = stage:FindFirstChild("NormalWin")
        if not win then
            return nil, "Stage" .. n .. ".NormalWin missing"
        end

        if win:IsA("BasePart") then return win end

        local inner = win:FindFirstChildWhichIsA("BasePart", true)
        if inner then return inner end

        return nil, "NormalWin has no BasePart inside it"
    end

    local function winPart()
        return winPartFor(stageNumber)
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

    -- a spot HOP_OFFSET studs beside the block instead of on top of it,
    -- so passing by does not trigger the win
    local function besidePart(part)
        local dir = part.CFrame.LookVector
        dir = Vector3.new(dir.X, 0, dir.Z)

        if dir.Magnitude < 0.05 then
            dir = Vector3.new(0, 0, 1)
        else
            dir = dir.Unit
        end

        return part.Position - dir * HOP_OFFSET
    end

    -- waits until a stage has streamed in, hopping is what makes it load
    local function waitForStage(n)
        local t = os.clock()

        while os.clock() - t < HOP_TIMEOUT do
            if not env.MEWin and not env.MEWinTest then return nil, "cancelled" end

            local part, err = winPartFor(n)
            if part then return part end

            if os.clock() - t >= HOP_TIMEOUT - 0.1 then
                return nil, err
            end

            task.wait(0.1)
        end

        return nil, "Stage" .. n .. " did not load in time"
    end

    -- hops 10 studs next to stage 1, 2, 3 ... so the map keeps streaming,
    -- then teleports onto the wanted win block
    local function walkStages(target, verbose)
        -- already streamed in, no need to hop at all
        local direct = winPartFor(target)
        if direct then
            teleportTo(direct.Position)
            return true
        end

        for n = STAGE_STEP, target - 1, STAGE_STEP do
            local part, err = waitForStage(n)

            if not part then
                if verbose then
                    warn("[BrainrotPolice] hop stop at Stage" .. n .. ": " .. tostring(err))
                end
                -- the block is not there, try the next one anyway
            else
                if verbose then
                    print("[BrainrotPolice] hop to Stage" .. n)
                end

                teleportTo(besidePart(part))
                task.wait(HOP_WAIT)
            end

            if not env.MEWin and not env.MEWinTest then return false, "cancelled" end
        end

        local part, err = waitForStage(target)
        if not part then return false, err end

        teleportTo(part.Position)
        return true
    end

    elements:Button("Test Win TP", section, function()
        if env.MEWinTest then return end
        env.MEWinTest = true

        task.spawn(function()
            local part, err = winPart()

            if not part then
                print("[BrainrotPolice] Stage" .. stageNumber
                    .. " not loaded yet, hopping closer: " .. tostring(err))
            end

            local root = getRoot()
            print("[BrainrotPolice] before: " .. (root and tostring(root.Position) or "no root"))

            local ok, err2 = walkStages(stageNumber, true)

            if not ok then
                warn("[BrainrotPolice] " .. tostring(err2 or "unknown"))

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
            else
                local final = winPart()
                if final then
                    print("[BrainrotPolice] target: " .. final:GetFullName())
                    print("[BrainrotPolice] position: " .. tostring(final.Position))
                end
            end

            task.wait(0.3)
            root = getRoot()
            print("[BrainrotPolice] after:  " .. (root and tostring(root.Position) or "no root"))

            env.MEWinTest = false
        end)
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
                    -- stages stream in one after another, so hop 10 studs
                    -- next to Stage 1, 2, 3 ... until the wanted one exists
                    local ok, err = walkStages(stageNumber, false)

                    if not ok then
                        if err ~= "cancelled" and not warned then
                            warn("[BrainrotPolice] " .. tostring(err))
                            warned = true
                        end
                        task.wait(1)
                    else
                        warned = false
                        task.wait(0.5)
                    end
                end
            end
        end)
    end)
end
