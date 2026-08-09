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

    -- World 1 only goes up to stage 9, the rest have 10
    local WORLD_MAX = { ["World 1"] = 9 }

    local worldChoice = tostring(setdata.world or "World 1")

    local function maxStage()
        return WORLD_MAX[worldChoice] or 10
    end

    local stageNumber = math.clamp(tonumber(setdata.stage) or 1, 1, maxStage())

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
    local HOP_WAIT = 0.25     -- pause after a hop so the next chunk can load
    local HOP_TIMEOUT = 6     -- max seconds to wait for one stage to appear
    local TP_HOLD = 0.2       -- seconds to keep re-applying a teleport
    local PAD_HOLD = 0.3      -- minimum time to sit on a win pad
    local PAD_TIMEOUT = 2     -- give up waiting for the win to register

    -- Collects every child of a stage that can be stood on, with the known
    -- starting index first, so the chain has something to hop along.
    local function stageHops(stage, firstIndex)
        local kids = stage:GetChildren()
        local out = {}

        local first = kids[firstIndex]
        if first then out[1] = first end

        for _, c in ipairs(kids) do
            -- never hop onto the win pad itself, that would end the stage
            if c ~= first and c.Name ~= "NormalWin" then
                out[#out + 1] = c
            end
        end

        return out
    end

    -- Some stages cannot be reached by jumping straight to the win pad, the
    -- chunk in between has to be touched first. Each entry returns a LIST of
    -- instances that get hopped through one after another until the stage's
    -- win block has streamed in.
    local WAYPOINTS = {
        ["World 1"] = {
            [6] = function(stage)
                -- no known entry point, just sweep the whole stage
                return stageHops(stage, 1)
            end,
            [7] = function(stage)
                return stageHops(stage, 8)
            end,
            [8] = function(stage)
                return stageHops(stage, 17)
            end,
            [9] = function(stage)
                -- the vines are spread over the whole stage, collect them all
                local out = {}

                for _, d in pairs(stage:GetDescendants()) do
                    if d.Name == "Vine" then
                        out[#out + 1] = d
                    end
                end

                if #out > 0 then return out end

                -- fall back to the generic sweep if the names ever change
                return stageHops(stage, 10)
            end,
        },
    }

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

    -- workspace.Map.World<n>.Stages.Stage<n>
    local function stageFolder(n)
        local map = workspace:FindFirstChild("Map")
        local world = map and map:FindFirstChild((worldChoice:gsub("%s", "")))
        local stages = world and world:FindFirstChild("Stages")
        return stages and stages:FindFirstChild("Stage" .. tostring(n))
    end

    -- Models have no .Position, so fall back to the pivot
    local function posOf(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end

        local ok, pivot = pcall(function() return inst:GetPivot() end)
        if ok and pivot then return pivot.Position end

        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position
    end

    -- Holds the character at a position for a while. A single CFrame write
    -- is easy for the game to undo, and a touch only registers if we stay
    -- put for a few frames, so the position is re-applied every frame and
    -- the velocity is wiped so gravity cannot drag us off again.
    local function holdAt(pos, duration)
        local target = CFrame.new(pos)
        local t = os.clock()

        repeat
            local char = getChar()
            local root = getRoot()
            if not char or not root then return false end

            pcall(function()
                -- PivotTo moves every welded part with it
                char:PivotTo(target)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)

            task.wait()
        until os.clock() - t >= duration

        return true
    end

    local function teleportTo(pos)
        return holdAt(pos, TP_HOLD)
    end

    -- Sits on a win pad until the win registers. The server answers a win by
    -- moving the character to the next stage, so a big position jump is the
    -- signal that it worked and we can stop pushing.
    local function touchPad(part)
        local root = getRoot()
        if not root then return false end

        local pos = part.Position
        local target = CFrame.new(pos)
        local t = os.clock()

        while os.clock() - t < PAD_TIMEOUT do
            if not env.MEWin then return false end

            local char = getChar()
            root = getRoot()
            if not char or not root then return false end

            -- the server pulled us somewhere else, the win went through
            if os.clock() - t > PAD_HOLD and (root.Position - pos).Magnitude > 25 then
                return true
            end

            pcall(function()
                char:PivotTo(target)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)

            task.wait()
        end

        -- no reaction, treat it as done anyway so the chain keeps going
        return true
    end

    -- how far a part reaches along a direction, so we can step fully clear
    -- of it instead of landing inside a big win pad
    local function extentAlong(part, dir)
        local cf, size = part.CFrame, part.Size

        return math.abs(cf.RightVector:Dot(dir)) * size.X * 0.5
            + math.abs(cf.UpVector:Dot(dir)) * size.Y * 0.5
            + math.abs(cf.LookVector:Dot(dir)) * size.Z * 0.5
    end

    -- A spot clear of the block, HOP_OFFSET studs to the player's left.
    -- Win pads can be huge, so the block's own size is added on top of the
    -- offset, otherwise we still end up standing inside it.
    local function besidePart(part)
        local root = getRoot()
        local dir

        if root then
            dir = root.CFrame.RightVector
            dir = Vector3.new(dir.X, 0, dir.Z)
        end

        if not dir or dir.Magnitude < 0.05 then
            dir = Vector3.new(1, 0, 0)
        else
            dir = dir.Unit
        end

        -- minus right is left
        local dist = extentAlong(part, dir) + HOP_OFFSET
        return part.Position - dir * dist
    end

    -- waits until workspace.Map.World<n>.Stages.Stage<n> exists
    local function waitForFolder(n)
        local t = os.clock()

        while os.clock() - t < HOP_TIMEOUT do
            if not env.MEWin then return nil end

            local stage = stageFolder(n)
            if stage then return stage end

            task.wait(0.1)
        end

        return nil
    end

    -- waits until a stage win pad has streamed in
    local function waitForStage(n)
        local t = os.clock()

        while os.clock() - t < HOP_TIMEOUT do
            if not env.MEWin then return nil, "cancelled" end

            local part, err = winPartFor(n)
            if part then return part end

            if os.clock() - t >= HOP_TIMEOUT - 0.1 then
                return nil, err
            end

            task.wait(0.1)
        end

        return nil, "Stage" .. n .. " did not load in time"
    end

    -- resolves the waypoint positions for a stage, ordered into a chain that
    -- starts at the player and always continues to the nearest next one
    local function waypointPositions(n)
        local list = WAYPOINTS[worldChoice]
        local fn = list and list[n]
        if not fn then return nil end

        local stage = waitForFolder(n)
        if not stage then return nil end

        -- the children stream in one by one, give them a moment
        local found = nil
        local t = os.clock()

        while os.clock() - t < HOP_TIMEOUT do
            if not env.MEWin then return nil end

            local ok, insts = pcall(fn, stage)

            if ok and type(insts) == "table" and #insts > 0 then
                local out = {}

                for _, inst in ipairs(insts) do
                    local pos = posOf(inst)
                    if pos then out[#out + 1] = pos end
                end

                if #out > 0 then
                    found = out
                    break
                end
            end

            task.wait(0.1)
        end

        if not found then return nil end
        if #found == 1 then return found end

        -- the first entry is the known entry point, keep it in front and
        -- order the rest greedily so we do not zigzag across the stage
        local chain = { found[1] }
        local from = found[1]
        table.remove(found, 1)

        while #found > 0 do
            local best, bestDist = 1, (found[1] - from).Magnitude

            for i = 2, #found do
                local d = (found[i] - from).Magnitude
                if d < bestDist then
                    best, bestDist = i, d
                end
            end

            from = found[best]
            chain[#chain + 1] = from
            table.remove(found, best)
        end

        return chain
    end

    -- walks into one stage: waypoint first if it has one, then the win pad.
    -- Stages on the way only get a stop next to the pad, the wanted stage is
    -- the one we actually land on.
    local function hopTo(n, isTarget)
        local chain = waypointPositions(n)

        if chain then
            for _, pos in ipairs(chain) do
                if not env.MEWin then return false, "cancelled" end

                -- stop hopping as soon as the win block has streamed in
                if winPartFor(n) then break end

                teleportTo(pos)
                task.wait(HOP_WAIT)
            end
        end

        local part, err = waitForStage(n)
        if not part then return false, err end

        if isTarget then
            -- stay on the pad until the win registers
            touchPad(part)
        else
            teleportTo(besidePart(part))
        end

        task.wait(HOP_WAIT)

        return true
    end

    -- steps through stage 1, 2, 3 ... so the map keeps streaming in, then
    -- finishes on the wanted win block
    local function walkStages(target)
        local list = WAYPOINTS[worldChoice]
        local needsWaypoint = list and list[target]

        -- straight teleport whenever the target is already loaded and does
        -- not need to be walked into
        if not needsWaypoint then
            local direct = winPartFor(target)
            if direct then
                touchPad(direct)
                return true
            end
        end

        local lastErr

        for n = STAGE_STEP, target, STAGE_STEP do
            if not env.MEWin then return false, "cancelled" end

            local ok, err = hopTo(n, n == target)

            if not ok then
                lastErr = err

                if n == target then
                    return false, err
                end
                -- a stage in between is skipped, the next one may still load
            end
        end

        return true, lastErr
    end

    elements:Dropdown("World", section, WORLD_OPTIONS, worldChoice, function(v)
        worldChoice = v
        env.setconfig("world", v)

        -- World 1 stops at 9, pull the stage back in if it is out of range
        local capped = math.clamp(stageNumber, 1, maxStage())
        if capped ~= stageNumber then
            stageNumber = capped
            env.setconfig("stage", stageNumber)
        end
    end)

    elements:Textbox("Stage (World 1: 1 - 9, else 1 - 10)", section, tostring(stageNumber), function(v)
        local n = tonumber(v)
        if not n then return end
        stageNumber = math.clamp(math.floor(n), 1, maxStage())
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
                    -- stages stream in one after another, so step through
                    -- Stage 1, 2, 3 ... until the wanted one exists
                    local ok, err = walkStages(stageNumber)

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
