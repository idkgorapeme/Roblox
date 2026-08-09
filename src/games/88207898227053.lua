-- Brainrot steal game (PlaceId 88207898227053)

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local plr = players.LocalPlayer

    env.BSFarm = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farm = setdata.farm or false
    setdata.minmoney = setdata.minmoney or 500000
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local FARM_DELAY = 0.2

    local minMoney = tonumber(setdata.minmoney) or 500000

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

    local function pivotOf(inst)
        if inst:IsA("BasePart") then return inst.Position end

        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok and cf then return cf.Position end

        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    ----------------------------------------------------------------
    -- auto farm
    ----------------------------------------------------------------

    -- workspace.Brainrots
    local function brainrotFolder()
        return workspace:FindFirstChild("Brainrots")
    end

    -- <brainrot>.<part>.InfoGui.Frame.CharCash, something like "$1.2M/s"
    local function cashOf(item)
        local gui = item:FindFirstChild("InfoGui", true)
        local frame = gui and gui:FindFirstChild("Frame")
        local label = frame and frame:FindFirstChild("CharCash")

        if not label then
            label = item:FindFirstChild("CharCash", true)
        end

        if not label then return nil end

        local num, suffix = tostring(label.Text or ""):match("([%d%.,]+)%s*([KkMmBbTtQq]?)")
        if not num then return nil end

        num = tonumber((num:gsub(",", "")))
        if not num then return nil end

        local mult = ({
            k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15,
        })[suffix:lower()] or 1

        return num * mult
    end

    -- the richest brainrot on the map, ignoring anything below minMoney
    local function bestItem()
        local folder = brainrotFolder()
        if not folder then return nil end

        local best, bestValue = nil, -1

        for _, item in ipairs(folder:GetChildren()) do
            local value = cashOf(item)

            if value and value >= minMoney and value > bestValue and pivotOf(item) then
                best, bestValue = item, value
            end
        end

        return best
    end

    -- Picking one up needs an actual interaction, standing on it is not
    -- always enough. Prompts, clicks and touches are all tried.
    local function grab(item)
        local root = getRoot()
        if not root then return end

        for _, d in ipairs(item:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                pcall(function()
                    d.HoldDuration = 0
                    d.MaxActivationDistance = math.max(d.MaxActivationDistance, 50)
                end)

                if fireproximityprompt then
                    pcall(function() fireproximityprompt(d) end)
                end
            elseif d:IsA("ClickDetector") then
                if fireclickdetector then
                    pcall(function() fireclickdetector(d) end)
                end
            elseif d:IsA("BasePart") and firetouchinterest then
                -- a fake touch, off and on again so the server sees a hit
                pcall(function()
                    firetouchinterest(root, d, 0)
                    firetouchinterest(root, d, 1)
                end)
            end
        end
    end

    -- holds the character on a spot so a touch has time to register
    local function holdAt(pos, duration)
        local target = CFrame.new(pos)
        local t = os.clock()

        repeat
            local char = getChar()
            local root = getRoot()
            if not char or not root then return false end

            pcall(function()
                char:PivotTo(target)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)

            task.wait()
        until os.clock() - t >= duration

        return true
    end

    -- workspace.Bases.<n>, the one belonging to us. The Base attribute holds
    -- the number the server handed out.
    local function myBase()
        local bases = workspace:FindFirstChild("Bases")
        if not bases then return nil end

        local id = plr:GetAttribute("Base")

        if id then
            local base = bases:FindFirstChild(tostring(id))
                or bases:FindFirstChild("Base" .. tostring(id))

            if base then return pivotOf(base) end
        end

        -- fall back to whichever base carries our name
        for _, b in ipairs(bases:GetChildren()) do
            if b:GetAttribute("Owner") == plr.Name or b.Name == plr.Name then
                return pivotOf(b)
            end
        end

        return nil
    end

    elements:Button("Dump Farm Info", section, function()
        local folder = brainrotFolder()

        if not folder then
            warn("[BrainrotPolice] workspace.Brainrots not found")

            local names = {}
            for _, c in ipairs(workspace:GetChildren()) do
                names[#names + 1] = c.Name
            end
            print("[BrainrotPolice] workspace children: " .. table.concat(names, ", "))
            return
        end

        local kids = folder:GetChildren()
        print("[BrainrotPolice] workspace.Brainrots: " .. #kids .. " children")
        print("[BrainrotPolice] min cash/s set to " .. tostring(minMoney))

        for i = 1, math.min(#kids, 10) do
            local item = kids[i]
            local gui = item:FindFirstChild("InfoGui", true)
            local frame = gui and gui:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("CharCash")
                or item:FindFirstChild("CharCash", true)

            print("  " .. item.ClassName .. " | " .. item.Name
                .. " | InfoGui=" .. tostring(gui and gui:GetFullName() or "nil")
                .. " | CharCash=" .. tostring(label and label.Text or "nil")
                .. " -> " .. tostring(cashOf(item))
                .. " | pos=" .. tostring(pivotOf(item)))
        end

        local best = bestItem()
        print("[BrainrotPolice] best over the floor: "
            .. (best and (best.Name .. " @ " .. tostring(pivotOf(best))) or "none"))

        local bases = workspace:FindFirstChild("Bases")
        if bases then
            local names = {}
            for _, b in ipairs(bases:GetChildren()) do
                names[#names + 1] = b.Name
            end
            print("[BrainrotPolice] workspace.Bases: " .. table.concat(names, ", "))
        end

        print("[BrainrotPolice] Base attribute: " .. tostring(plr:GetAttribute("Base")))
        print("[BrainrotPolice] my base pos: " .. tostring(myBase()))
    end)

    -- accepts 500000, 500k, 2.5m and so on
    elements:Textbox("Min Cash/s (default 500k)", section, tostring(minMoney), function(v)
        local text = tostring(v):gsub("%s", ""):gsub(",", "")
        local num, suffix = text:match("^([%d%.]+)([KkMmBbTtQq]?)$")

        local n = tonumber(num)
        if not n then return end

        local mult = ({
            k = 1e3, m = 1e6, b = 1e9, t = 1e12, q = 1e15,
        })[suffix:lower()] or 1

        minMoney = n * mult
        env.setconfig("minmoney", minMoney)
    end)

    -- starts off every session, it moves the character
    elements:Toggle("Auto Farm", section, false, function(v)
        env.BSFarm = v
        env.setconfig("farm", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.BSFarm do
                if not alive() then
                    task.wait(0.5)
                else
                    local item = bestItem()

                    if not item then
                        -- nothing worth taking yet
                        task.wait(0.5)
                    else
                        warned = false

                        -- grab it
                        local pos = pivotOf(item)
                        local t = os.clock()

                        while env.BSFarm and item.Parent and os.clock() - t < 1 do
                            pos = pivotOf(item) or pos
                            holdAt(pos, 0.1)
                            grab(item)

                            task.wait(0.05)
                        end

                        -- then straight back to base to hand it in
                        local base = myBase()

                        if base then
                            holdAt(base + Vector3.new(0, 3, 0), 0.4)
                        elseif not warned then
                            warn("[BrainrotPolice] your base was not found in workspace.Bases")
                            warned = true
                        end

                        task.wait(FARM_DELAY)
                    end
                end
            end
        end)
    end)
end
