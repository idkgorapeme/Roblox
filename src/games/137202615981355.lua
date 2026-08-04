-- +1 Height Per Jump

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.JHJump = false
    env.JHRebirth = false
    env.JHEggs = false
    env.JHRewards = false
    env.JHSeason = false
    env.JHPets = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.jump = setdata.jump or false
    setdata.rebirth = setdata.rebirth or false
    setdata.eggs = setdata.eggs or false
    setdata.rewards = setdata.rewards or false
    setdata.season = setdata.season or false
    setdata.pets = setdata.pets or false
    setdata.jumpdelay = setdata.jumpdelay or 0.05
    setdata.ceiling = setdata.ceiling or 3.5
    setdata.eggname = setdata.eggname or ""
    setdata.codelist = setdata.codelist or ""
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local jumpDelay = tonumber(setdata.jumpdelay) or 0.05
    local ceilingHeight = tonumber(setdata.ceiling) or 3.5
    local eggName = tostring(setdata.eggname or "")
    local codeList = tostring(setdata.codelist or "")

    local function getChar() return plr.Character end

    local function getHum()
        local char = getChar()
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function getRoot()
        local char = getChar()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- knit remotes: Packages.Knit.Services.<Service>.RF|RE.<Method>
    ----------------------------------------------------------------

    local function knit(serviceName, kind, methodName)
        local pkgs = replicatedstorage:FindFirstChild("Packages")
        local k = pkgs and pkgs:FindFirstChild("Knit")
        local services = k and k:FindFirstChild("Services")
        local service = services and services:FindFirstChild(serviceName)
        local folder = service and service:FindFirstChild(kind)
        return folder and folder:FindFirstChild(methodName) or nil
    end

    -- invokes a RF, returns ok, result
    local function callRF(serviceName, methodName, ...)
        local rf = knit(serviceName, "RF", methodName)
        if not rf then return false, "remote not found" end

        local args = table.pack(...)
        return pcall(function()
            return rf:InvokeServer(table.unpack(args, 1, args.n))
        end)
    end

    ----------------------------------------------------------------
    -- jump farm
    --
    -- Every jump grants height. A ceiling right above the head means the
    -- jump is cut off instantly, the character lands immediately and can
    -- jump again, so the rate is bound by the delay and not by air time.
    ----------------------------------------------------------------

    local ceilingPart

    local function removeCeiling()
        if ceilingPart then
            pcall(function() ceilingPart:Destroy() end)
            ceilingPart = nil
        end
    end

    -- Placed once, where the player is standing when the farm is switched on,
    -- and then left alone. It does not follow the character.
    local function buildCeiling()
        removeCeiling()

        local root = getRoot()
        if not root then return false end

        local part = Instance.new("Part")
        part.Name = "BPJumpCeiling"
        part.Size = Vector3.new(8, 1, 8)
        part.Anchored = true
        part.CanCollide = true
        part.Transparency = 0.6
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(0, 170, 255)
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.CFrame = CFrame.new(root.Position + Vector3.new(0, ceilingHeight, 0))
        part.Parent = workspace

        ceilingPart = part
        return true
    end

    elements:Textbox("Jump Delay (default 0.05)", section, tostring(jumpDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.01 then return end
        jumpDelay = n
        env.setconfig("jumpdelay", n)
    end)

    elements:Textbox("Ceiling Height (default 3.5)", section, tostring(ceilingHeight), function(v)
        local n = tonumber(v)
        if not n or n < 1 then return end
        ceilingHeight = n
        env.setconfig("ceiling", n)
    end)

    -- starts off every session, it spawns a part and moves the character
    elements:Toggle("Jump Farm", section, false, function(v)
        env.JHJump = v
        env.setconfig("jump", v)

        if not v then
            removeCeiling()
            return
        end

        if not buildCeiling() then
            warn("[BrainrotPolice] no character yet, toggle again once you have spawned")
            env.JHJump = false
            return
        end

        print("[BrainrotPolice] ceiling placed, stand under it and it will farm")

        task.spawn(function()
            while env.JHJump do
                pcall(function()
                    local hum = getHum()
                    if hum and hum.Health > 0 then
                        hum.Jump = true
                    end
                end)

                task.wait(jumpDelay)
            end

            removeCeiling()
        end)
    end)

    ----------------------------------------------------------------
    -- rebirth
    ----------------------------------------------------------------

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.JHRebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            while env.JHRebirth do
                callRF("RebirthService", "TryRebirth")
                task.wait(2)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- eggs
    ----------------------------------------------------------------

    elements:Button("Show Eggs", section, function()
        local ok, res = callRF("EggHatchService", "GetNormalEggs")
        if not ok then
            warn("[BrainrotPolice] GetNormalEggs failed: " .. tostring(res))
            return
        end

        local httpservice = game:GetService("HttpService")
        local okj, enc = pcall(function() return httpservice:JSONEncode(res) end)
        local text = okj and enc or tostring(res)

        print("[BrainrotPolice] eggs: " .. text)
        pcall(function() setclipboard(text) end)
    end)

    elements:Textbox("Egg Name (see Show Eggs)", section, eggName, function(v)
        eggName = v or ""
        env.setconfig("eggname", eggName)
    end)

    elements:Toggle("Auto Hatch Egg", section, setdata.eggs, function(v)
        env.JHEggs = v
        env.setconfig("eggs", v)
        if not v then return end

        if eggName == "" then
            warn("[BrainrotPolice] set an egg name first, press Show Eggs")
            env.JHEggs = false
            return
        end

        task.spawn(function()
            while env.JHEggs do
                callRF("EggHatchService", "HatchNormalEgg", eggName)
                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- rewards
    ----------------------------------------------------------------

    elements:Toggle("Auto Claim Rewards", section, setdata.rewards, function(v)
        env.JHRewards = v
        env.setconfig("rewards", v)
        if not v then return end

        task.spawn(function()
            while env.JHRewards do
                -- online timer rewards, index based
                for i = 1, 12 do
                    if not env.JHRewards then break end
                    callRF("OnlineRewardsService", "ClaimReward", i)
                    task.wait(0.15)
                end

                callRF("DailyRewardsService", "ClaimReward")
                callRF("OnlinePetService", "ClaimOnlineEgg")
                callRF("GroupRewardService", "Claim")
                callRF("AchievementService", "ClaimNextLevel")

                -- pet index milestones
                for i = 1, 20 do
                    if not env.JHRewards then break end
                    callRF("PetIndexRewardService", "ClaimReward", i)
                    task.wait(0.1)
                end

                task.wait(30)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- season pass
    ----------------------------------------------------------------

    elements:Toggle("Auto Season Pass", section, setdata.season, function(v)
        env.JHSeason = v
        env.setconfig("season", v)
        if not v then return end

        task.spawn(function()
            while env.JHSeason do
                for i = 1, 60 do
                    if not env.JHSeason then break end
                    callRF("SeasonPassRewardService", "ClaimReward", i)
                    callRF("SeasonPassRewardService", "ClaimExtraReward", i)
                    task.wait(0.1)
                end

                for i = 1, 20 do
                    if not env.JHSeason then break end
                    callRF("SeasonPassQuestService", "ClaimQuest", i)
                    task.wait(0.1)
                end

                task.wait(60)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- pets
    ----------------------------------------------------------------

    elements:Button("Equip Best Pets", section, function()
        local ok, res = callRF("PetService", "EquipBest")
        print("[BrainrotPolice] EquipBest -> " .. tostring(ok and res or "failed"))
    end)

    elements:Toggle("Auto Equip Best Pets", section, setdata.pets, function(v)
        env.JHPets = v
        env.setconfig("pets", v)
        if not v then return end

        task.spawn(function()
            while env.JHPets do
                callRF("PetService", "EquipBest")
                task.wait(15)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- codes
    ----------------------------------------------------------------

    elements:Textbox("Codes (comma separated)", section, codeList, function(v)
        codeList = v or ""
        env.setconfig("codelist", codeList)
    end)

    elements:Button("Redeem Codes", section, function()
        local n = 0

        for code in string.gmatch(codeList, "[^,]+") do
            code = code:match("^%s*(.-)%s*$")
            if code ~= "" then
                local ok, res = callRF("CodeService", "RedeemCode", code)
                print("[BrainrotPolice] " .. code .. " -> " .. tostring(ok and res or "failed"))
                n = n + 1
                task.wait(0.5)
            end
        end

        if n == 0 then
            warn("[BrainrotPolice] no codes entered")
        end
    end)

    ----------------------------------------------------------------
    -- worlds
    ----------------------------------------------------------------

    elements:Button("Unlock Next World", section, function()
        for i = 2, 5 do
            if plr:GetAttribute("World" .. i .. "Unlocked") == false then
                local ok, res = callRF("WorldService", "UnlockWorld", i)
                print("[BrainrotPolice] unlock world " .. i .. " -> "
                    .. tostring(ok and res or "failed"))
                return
            end
        end

        print("[BrainrotPolice] no locked world found")
    end)
end
