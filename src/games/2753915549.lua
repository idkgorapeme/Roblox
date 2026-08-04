-- Blox Fruits

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local runservice = game:GetService("RunService")
    local plr = players.LocalPlayer

    env.BFFarm = false
    env.BFSpy = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farm = setdata.farm or false
    setdata.flyspeed = setdata.flyspeed or 120
    setdata.height = setdata.height or 1
    setdata.range = setdata.range or 5000
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local flySpeed = tonumber(setdata.flyspeed) or 120
    local hoverHeight = tonumber(setdata.height) or 1
    local maxRange = tonumber(setdata.range) or 5000

    local function getChar()
        return plr.Character
    end

    local function getRoot()
        local char = getChar()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getHum()
        local char = getChar()
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function alive()
        local hum = getHum()
        return hum ~= nil and hum.Health > 0
    end

    ----------------------------------------------------------------
    -- remotes
    ----------------------------------------------------------------

    local function netRemote(name)
        local modules = replicatedstorage:FindFirstChild("Modules")
        local net = modules and modules:FindFirstChild("Net")
        return net and net:FindFirstChild(name) or nil
    end

    local function commF()
        local remotes = replicatedstorage:FindFirstChild("Remotes")
        return remotes and remotes:FindFirstChild("CommF_") or nil
    end

    ----------------------------------------------------------------
    -- enemies
    ----------------------------------------------------------------

    local function enemyRoot(mob)
        return mob:FindFirstChild("HumanoidRootPart")
            or mob:FindFirstChild("Torso")
            or mob:FindFirstChildWhichIsA("BasePart")
    end

    local function isValidEnemy(mob)
        if not mob or not mob.Parent then return false end
        if not mob:IsA("Model") then return false end

        -- never target a player, only npc mobs
        if players:GetPlayerFromCharacter(mob) then return false end

        local hum = mob:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return false end

        return enemyRoot(mob) ~= nil
    end

    local function nearestEnemy()
        local folder = workspace:FindFirstChild("Enemies")
        if not folder then return nil end

        local myRoot = getRoot()
        if not myRoot then return nil end

        local best, bestDist = nil, maxRange

        for _, mob in pairs(folder:GetChildren()) do
            if isValidEnemy(mob) then
                local root = enemyRoot(mob)
                local dist = (root.Position - myRoot.Position).Magnitude

                if dist < bestDist then
                    best, bestDist = mob, dist
                end
            end
        end

        return best
    end

    ----------------------------------------------------------------
    -- flight, body movers so control returns cleanly
    ----------------------------------------------------------------

    local flyBV, flyBG
    local noclipConn

    local function stopFlight()
        if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
        if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end

        pcall(function()
            local root = getRoot()
            if root then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end

            local hum = getHum()
            if hum then
                hum.PlatformStand = false
            end
        end)
    end

    local function ensureFlight()
        local root = getRoot()
        if not root then return nil end

        if flyBV and flyBV.Parent ~= root then
            pcall(function() flyBV:Destroy() end)
            flyBV = nil
        end
        if flyBG and flyBG.Parent ~= root then
            pcall(function() flyBG:Destroy() end)
            flyBG = nil
        end

        if not flyBV then
            flyBV = Instance.new("BodyVelocity")
            flyBV.Name = "BPFarmFly"
            flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            flyBV.P = 1e4
            flyBV.Velocity = Vector3.zero
            flyBV.Parent = root
        end

        if not flyBG then
            flyBG = Instance.new("BodyGyro")
            flyBG.Name = "BPFarmGyro"
            flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            flyBG.P = 1e4
            flyBG.D = 500
            flyBG.CFrame = root.CFrame
            flyBG.Parent = root
        end

        return root
    end

    local function startNoclip()
        if noclipConn then return end

        noclipConn = runservice.Stepped:Connect(function()
            local char = getChar()
            if not char then return end

            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end)

        if env.BrainrotPolice and env.BrainrotPolice.track then
            env.BrainrotPolice.track(noclipConn)
        end
    end

    local function stopNoclip()
        if noclipConn then
            noclipConn:Disconnect()
            noclipConn = nil
        end

        local char = getChar()
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    pcall(function() part.CanCollide = true end)
                end
            end
        end
    end

    -- moves toward a point at flySpeed, returns true once close enough
    local function glideStep(targetPos, arriveAt)
        local root = ensureFlight()
        if not root or not flyBV then return false end

        arriveAt = arriveAt or 4

        local delta = targetPos - root.Position
        local dist = delta.Magnitude

        -- a zero length vector has no .Unit, it would produce NaN and throw
        -- the character into the void
        if dist < 0.05 then
            flyBV.Velocity = Vector3.zero
            return true
        end

        if dist <= arriveAt then
            flyBV.Velocity = Vector3.zero
            return true
        end

        -- slow down on approach instead of overshooting past the mob
        local speed = math.min(flySpeed, dist * 4)
        flyBV.Velocity = delta.Unit * speed

        if flyBG then
            local look = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
            if (look - root.Position).Magnitude > 0.1 then
                flyBG.CFrame = CFrame.new(root.Position, look)
            end
        end

        return dist <= arriveAt
    end

    ----------------------------------------------------------------
    -- attacking
    ----------------------------------------------------------------

    -- puts the melee or sword back in hand, the server ignores hits
    -- from an unequipped character
    local function equipWeapon()
        local char = getChar()
        local hum = getHum()
        local backpack = plr:FindFirstChildOfClass("Backpack")
        if not char or not hum or not backpack then return end

        -- already holding something
        if char:FindFirstChildOfClass("Tool") then return end

        for _, tool in pairs(backpack:GetChildren()) do
            if tool:IsA("Tool") then
                pcall(function() hum:EquipTool(tool) end)
                return
            end
        end
    end

    -- captured from a real swing: RE/RegisterAttack:FireServer(0.5)
    local ATTACK_ARG = 0.5

    local lastSwing = 0

    -- Resolves the attack remote. The name literally contains a slash, and
    -- some executors choke on that with dot indexing, so we also fall back
    -- to scanning the children by name.
    local function attackRemote()
        local direct = netRemote("RE/RegisterAttack")
        if direct then return direct end

        local modules = replicatedstorage:FindFirstChild("Modules")
        local net = modules and modules:FindFirstChild("Net")

        if net then
            for _, child in pairs(net:GetChildren()) do
                if child.Name == "RE/RegisterAttack" then
                    return child
                end
            end
        end

        -- last resort, anywhere under ReplicatedStorage
        for _, child in pairs(replicatedstorage:GetDescendants()) do
            if child.Name == "RE/RegisterAttack" then
                return child
            end
        end

        return nil
    end

    -- verbose = report every step instead of failing quietly, used by the
    -- test button. The farm calls it silently.
    local function attack(verbose)
        local char = getChar()
        local tool = char and char:FindFirstChildOfClass("Tool")

        -- the remote registers the swing, the tool actually performs it
        if tool then
            local ok, err = pcall(function() tool:Activate() end)
            if verbose then
                print("[BrainrotPolice] Activate " .. tool.Name .. " -> " .. tostring(ok or err))
            end
        elseif verbose then
            warn("[BrainrotPolice] no tool equipped")
        end

        local ra = attackRemote()

        if not ra then
            if verbose then
                warn("[BrainrotPolice] RE/RegisterAttack NOT FOUND")
            end
            return false
        end

        if verbose then
            print("[BrainrotPolice] firing " .. ra:GetFullName())
        end

        local ok, err = pcall(function()
            ra:FireServer(ATTACK_ARG)
        end)

        if verbose then
            if ok then
                print("[BrainrotPolice] FireServer(" .. ATTACK_ARG .. ") sent")
            else
                warn("[BrainrotPolice] FireServer failed: " .. tostring(err))
            end
        end

        return ok
    end

    -- throttled wrapper for the farm loop
    local function attackThrottled()
        local now = tick()
        if now - lastSwing < 0.12 then return end
        lastSwing = now
        attack(false)
    end

    ----------------------------------------------------------------
    -- ui
    ----------------------------------------------------------------

    elements:Textbox("Fly Speed (default 120)", section, tostring(flySpeed), function(v)
        local n = tonumber(v)
        if not n or n <= 0 then return end
        flySpeed = n
        env.setconfig("flyspeed", n)
    end)

    elements:Textbox("Hover Height (default 1)", section, tostring(hoverHeight), function(v)
        local n = tonumber(v)
        if not n then return end
        hoverHeight = n
        env.setconfig("height", n)
    end)

    elements:Textbox("Max Range (default 5000)", section, tostring(maxRange), function(v)
        local n = tonumber(v)
        if not n or n <= 0 then return end
        maxRange = n
        env.setconfig("range", n)
    end)

    elements:Button("Count Enemies", section, function()
        local folder = workspace:FindFirstChild("Enemies")
        print("[BrainrotPolice] workspace.Enemies: " .. tostring(folder ~= nil))

        if not folder then return end

        local n, valid = 0, 0
        for _, mob in pairs(folder:GetChildren()) do
            n = n + 1
            if isValidEnemy(mob) then
                valid = valid + 1
                if valid <= 3 then
                    local hum = mob:FindFirstChildOfClass("Humanoid")
                    print(("  %s  hp %d/%d"):format(mob.Name, hum.Health, hum.MaxHealth))
                end
            end
        end

        print("[BrainrotPolice] " .. n .. " models, " .. valid .. " alive and targetable")
    end)

    elements:Button("Test Attack Once", section, function()
        local char = getChar()
        local backpack = plr:FindFirstChildOfClass("Backpack")

        print("---- BrainrotPolice attack test ----")
        print("character: " .. (char and char.Name or "NONE"))

        if backpack then
            for _, t in pairs(backpack:GetChildren()) do
                if t:IsA("Tool") then
                    print("  backpack tool: " .. t.Name)
                end
            end
        else
            print("  no backpack")
        end

        equipWeapon()
        task.wait(0.4)

        local tool = char and char:FindFirstChildOfClass("Tool")
        print("equipped now: " .. (tool and tool.Name or "NONE"))

        -- list what the Net folder actually contains, the remote name has a
        -- slash in it and is easy to miss
        local modules = replicatedstorage:FindFirstChild("Modules")
        local net = modules and modules:FindFirstChild("Net")
        print("Modules.Net: " .. (net and "found" or "MISSING"))

        if net then
            local n = 0
            for _, child in pairs(net:GetChildren()) do
                if string.find(child.Name, "Attack", 1, true)
                    or string.find(child.Name, "Hit", 1, true) then
                    n = n + 1
                    print("  combat remote: " .. child.ClassName .. " | " .. child.Name)
                end
            end
            if n == 0 then
                print("  no Attack/Hit remotes under Net")
            end
        end

        -- verbose swing, reports every step
        attack(true)
        print("------------------------------------")
    end)

    -- Dumps ClientComponents.WeaponToolClient so the real swing path can be
    -- read off instead of guessed.
    elements:Button("Dump WeaponToolClient", section, function()
        local cc = replicatedstorage:FindFirstChild("ClientComponents")
        local wtc = cc and cc:FindFirstChild("WeaponToolClient")

        if not wtc then
            warn("[BrainrotPolice] ClientComponents.WeaponToolClient not found")
            return
        end

        local out = {}
        local function add(line)
            out[#out + 1] = line
            print(line)
        end

        add("PlaceId: " .. tostring(game.PlaceId))
        add("== " .. wtc:GetFullName() .. " (" .. wtc.ClassName .. ")")

        for _, d in pairs(wtc:GetDescendants()) do
            add("  " .. d.ClassName .. " | " .. d.Name)
        end

        -- the source is what actually tells us how the swing is sent
        local ok, src = pcall(function()
            return decompile and decompile(wtc) or nil
        end)

        if ok and src then
            add("== source ==")
            add(src)
        else
            add("== source not available, executor cannot decompile ==")
        end

        local text = table.concat(out, "\n")

        pcall(function()
            writefile("BrainrotPolice/weapontool_" .. tostring(game.PlaceId) .. ".txt", text)
        end)

        local copied = pcall(function() setclipboard(text) end)
        print("[BrainrotPolice] dump copied=" .. tostring(copied))
    end)

    -- starts off every session, this one moves the character
    elements:Toggle("Auto Farm Enemies", section, false, function(v)
        env.BFFarm = v
        env.setconfig("farm", v)

        if not v then
            stopFlight()
            stopNoclip()
            return
        end

        task.spawn(function()
            local announced = false

            startNoclip()

            while env.BFFarm do
                -- wait out death and respawn instead of flinging the corpse
                if not alive() then
                    -- do not tear the movers down here, they get rebuilt on
                    -- the new character by ensureFlight
                    if flyBV then flyBV.Velocity = Vector3.zero end
                    task.wait(1)
                else
                    local mob = nearestEnemy()

                    if not mob then
                        if not announced then
                            warn("[BrainrotPolice] no enemies in range, press Count Enemies")
                            announced = true
                        end

                        -- keep hovering instead of dropping out of the sky
                        ensureFlight()
                        if flyBV then flyBV.Velocity = Vector3.zero end
                        task.wait(0.5)
                    else
                        announced = false
                        equipWeapon()

                        -- chase and hit until it dies or despawns. the flight
                        -- is never stopped, so we roll straight into the next
                        -- target without falling.
                        --
                        -- the whole body is pcall'd: an unguarded error in
                        -- here kills the thread, which looks exactly like the
                        -- toggle switching itself off when you reach a mob.
                        while env.BFFarm and isValidEnemy(mob) and alive() do
                            local ok, err = pcall(function()
                                local root = enemyRoot(mob)
                                if not root then return end

                                -- stay just beside the mob, close enough for
                                -- melee to actually connect
                                local target = root.Position + Vector3.new(0, hoverHeight, 0)
                                glideStep(target, 4)

                                -- face the mob so the swing lands
                                local myRoot = getRoot()
                                if myRoot and flyBG then
                                    local look = Vector3.new(
                                        root.Position.X, myRoot.Position.Y, root.Position.Z)
                                    if (look - myRoot.Position).Magnitude > 0.1 then
                                        flyBG.CFrame = CFrame.new(myRoot.Position, look)
                                    end
                                end

                                attackThrottled()
                            end)

                            if not ok then
                                warn("[BrainrotPolice] farm error: " .. tostring(err))
                                task.wait(0.2)
                            end

                            runservice.Heartbeat:Wait()
                        end
                    end
                end
            end

            stopFlight()
            stopNoclip()
        end)
    end)

    ----------------------------------------------------------------
    -- attack capture
    --
    -- RegisterHit's real argument shape is not guessable. Record one manual
    -- hit and the farm can be wired to the exact call.
    ----------------------------------------------------------------

    local spyLog = {}
    local spyRestore

    local function describe(v)
        local t = typeof(v)
        if t == "Instance" then
            return "Instance<" .. v.ClassName .. ">(" .. v:GetFullName() .. ")"
        elseif t == "Vector3" then
            return string.format("Vector3.new(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
        elseif t == "CFrame" then
            return string.format("CFrame.new(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
        elseif t == "table" then
            local ok, enc = pcall(function()
                return game:GetService("HttpService"):JSONEncode(v)
            end)
            return ok and ("table " .. enc) or "table{...}"
        elseif t == "string" then
            return '"' .. v .. '"'
        end
        return tostring(v)
    end

    elements:Toggle("Capture Attack Calls", section, false, function(v)
        env.BFSpy = v

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

                if env.BFSpy and (method == "FireServer" or method == "InvokeServer") then
                    local name = self.Name

                    -- only combat traffic, the game is very chatty
                    if string.find(name, "Register", 1, true)
                        or string.find(name, "Attack", 1, true)
                        or string.find(name, "Hit", 1, true) then

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
            warn("[BrainrotPolice] attack capture not supported by this executor")
            env.BFSpy = false
        end
    end)

    elements:Button("Copy Attack Log", section, function()
        if #spyLog == 0 then
            warn("[BrainrotPolice] log empty, enable Capture Attack Calls and hit a mob")
            return
        end

        local text = "PlaceId: " .. tostring(game.PlaceId) .. "\n\n"
            .. table.concat(spyLog, "\n")

        pcall(function()
            writefile("BrainrotPolice/attack_" .. tostring(game.PlaceId) .. ".txt", text)
        end)

        local copied = pcall(function() setclipboard(text) end)
        print("[BrainrotPolice] " .. #spyLog .. " calls logged, copied=" .. tostring(copied))
    end)
end
