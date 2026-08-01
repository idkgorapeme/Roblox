-- RNG Heroes

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local runservice = game:GetService("RunService")
    local plr = players.LocalPlayer

    env.AutoPrestige = false
    env.AutoClickAttack = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autoprestige = setdata.autoprestige or false
    setdata.autoclick = setdata.autoclick or false
    setdata.zone = setdata.zone or "Forest"
    setdata.maxremotes = setdata.maxremotes or 200
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local remotes = replicatedstorage:WaitForChild("Remotes")
    local prestigeRequested = remotes:WaitForChild("PrestigeRequested")
    local reportClickAttack = remotes:WaitForChild("ReportClickAttack")

    local zone = tostring(setdata.zone)

    ----------------------------------------------------------------
    -- auto click attack
    ----------------------------------------------------------------

    -- hard ceiling on how many ReportClickAttack calls we send per second.
    -- the game lags badly above this, so the sender is rate limited below.
    local MAX_REMOTES_PER_SEC = tonumber(setdata.maxremotes) or 200

    -- enemies can be models, parts or a folder wrapping either
    local function enemyPosition(enemy)
        if enemy:IsA("BasePart") then
            return enemy.Position
        end

        if enemy:IsA("Model") then
            if enemy.PrimaryPart then
                return enemy.PrimaryPart.Position
            end

            local ok, cf = pcall(function()
                return enemy:GetPivot()
            end)
            if ok and cf then return cf.Position end
        end

        local part = enemy:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    ----------------------------------------------------------------
    -- zone detection: pick the zone whose centre is closest to the player
    ----------------------------------------------------------------

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- centre of a zone, works for parts, models and folders of parts
    local function zoneCenter(z)
        if z:IsA("BasePart") then
            return z.Position
        end

        if z:IsA("Model") then
            local ok, cf = pcall(function()
                return z:GetPivot()
            end)
            if ok and cf then return cf.Position end
        end

        -- folder or anything else: average the parts inside it
        local sum, count = Vector3.zero, 0
        for _, d in pairs(z:GetDescendants()) do
            if d:IsA("BasePart") then
                sum = sum + d.Position
                count = count + 1
            end
        end

        if count > 0 then
            return sum / count
        end

        return nil
    end

    -- zone centres barely move, so compute them once and reuse
    local zoneCache

    local function buildZoneCache()
        local folder = workspace:FindFirstChild("Zones")
        if not folder then return nil end

        local cache = {}
        for _, z in pairs(folder:GetChildren()) do
            local center = zoneCenter(z)
            if center then
                cache[#cache + 1] = { name = z.Name, center = center }
            end
        end

        return cache
    end

    -- name of the zone the player is currently closest to
    local function detectZone()
        if not zoneCache or #zoneCache == 0 then
            zoneCache = buildZoneCache()
        end
        if not zoneCache then return nil end

        local root = getRoot()
        if not root then return nil end

        local myPos = root.Position
        local best, bestDist = nil, math.huge

        for _, entry in ipairs(zoneCache) do
            local dist = (entry.center - myPos).Magnitude
            if dist < bestDist then
                best, bestDist = entry.name, dist
            end
        end

        return best
    end

    -- refresh it in the background so walking into a new zone is picked up.
    -- only runs while the farm is on, and dies with the script on unload.
    task.spawn(function()
        while env.BrainrotPolice do
            if env.AutoClickAttack then
                local detected = detectZone()
                if detected and detected ~= zone then
                    zone = detected
                    env.setconfig("zone", detected)
                end
            end
            task.wait(3)
        end
    end)

    elements:Button("Detect Zone Now", section, function()
        local detected = detectZone()
        if detected then
            zone = detected
            env.setconfig("zone", detected)
            print("[BrainrotPolice] zone:", detected)
        else
            warn("[BrainrotPolice] could not detect a zone from workspace.Zones")
        end
    end)

    -- true when the enemy is still alive and rendered
    local function isAlive(enemy)
        if not enemy or not enemy.Parent then return false end

        local hum = enemy:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return false end

        local hp = enemy:GetAttribute("Health") or enemy:GetAttribute("HP")
        if hp and hp <= 0 then return false end

        return true
    end

    -- builds the id -> position map in ONE pass over the folder.
    -- the old code rescanned the whole folder once per id, every frame.
    local function collectTargets()
        local folder = workspace:FindFirstChild("EnemyRender")
        if not folder then return nil, 0 end

        local targets, count = {}, 0

        for index, enemy in ipairs(folder:GetChildren()) do
            if isAlive(enemy) then
                local pos = enemyPosition(enemy)
                if pos then
                    -- prefer an explicit id, otherwise use the render order
                    local id = tonumber(enemy.Name)
                        or tonumber(enemy:GetAttribute("Id"))
                        or tonumber(enemy:GetAttribute("EnemyId"))
                        or tonumber(enemy:GetAttribute("Index"))
                        or index

                    if targets[id] == nil then
                        targets[id] = pos
                        count = count + 1
                    end
                end
            end
        end

        return targets, count
    end

    elements:Textbox("Max Remotes / sec (default 200)", section, tostring(MAX_REMOTES_PER_SEC), function(v)
        local n = tonumber(v)
        if not n or n < 1 then return end
        MAX_REMOTES_PER_SEC = math.floor(n)
        env.setconfig("maxremotes", MAX_REMOTES_PER_SEC)
    end)

    elements:Toggle("Auto Click Attack", section, setdata.autoclick, function(v)
        env.AutoClickAttack = v
        env.setconfig("autoclick", v)
        if not v then return end

        -- make sure we are on the right zone before the first hit
        local detected = detectZone()
        if detected then
            zone = detected
            env.setconfig("zone", detected)
        end

        task.spawn(function()
            -- exact sliding window limiter: we remember the timestamp of the last
            -- MAX_REMOTES_PER_SEC sends. before sending we check the oldest one,
            -- if it is younger than 1s we wait until it ages out. this guarantees
            -- we never exceed the cap in ANY one second window (a token bucket
            -- starting full would allow a double burst on the first second).
            local ring = {}
            local ringSize = MAX_REMOTES_PER_SEC
            local ringIdx = 1

            for i = 1, ringSize do
                ring[i] = -1e9
            end

            local function rateLimitedFire(id, pos)
                -- the cap can be changed at runtime, resize if needed
                if ringSize ~= MAX_REMOTES_PER_SEC then
                    ringSize = MAX_REMOTES_PER_SEC
                    ring = {}
                    for i = 1, ringSize do
                        ring[i] = -1e9
                    end
                    ringIdx = 1
                end

                local oldest = ring[ringIdx]
                local waitFor = 1 - (os.clock() - oldest)

                if waitFor > 0 then
                    task.wait(waitFor)
                end

                if not env.AutoClickAttack then return false end

                ring[ringIdx] = os.clock()
                ringIdx = ringIdx % ringSize + 1

                pcall(function()
                    reportClickAttack:FireServer(zone, id, pos)
                end)

                return true
            end

            while env.AutoClickAttack do
                local targets, count = collectTargets()

                if targets and count > 0 then
                    for id, pos in pairs(targets) do
                        if not env.AutoClickAttack then break end
                        if not rateLimitedFire(id, pos) then break end
                    end
                else
                    -- nothing to hit, idle cheaply
                    task.wait(0.2)
                end

                -- always yield so we never hog a frame
                task.wait()
            end
        end)
    end)

    elements:Toggle("Auto Prestige", section, setdata.autoprestige, function(v)
        env.AutoPrestige = v
        env.setconfig("autoprestige", v)
        if not v then return end

        while env.AutoPrestige do
            pcall(function()
                prestigeRequested:FireServer()
            end)

            task.wait(1)
        end
    end)
end
