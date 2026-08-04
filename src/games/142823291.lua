-- Murder Mystery 2

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.MMCoins = false
    env.MMCoinEsp = false
    env.MMMyRole = false
    env.MMAllRoles = false
    env.MMCoinMoveMode = "Teleport"   -- "Teleport" or "Walk"

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.coins = setdata.coins or false
    setdata.coinesp = setdata.coinesp or false
    setdata.coindelay = setdata.coindelay or 0.12
    setdata.myrole = setdata.myrole or false
    setdata.allroles = setdata.allroles or false
    setdata.coinmovemode = setdata.coinmovemode or "Teleport"
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local coinDelay = tonumber(setdata.coindelay) or 0.12
    local coinMoveMode = setdata.coinmovemode or "Teleport"

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    ----------------------------------------------------------------
    -- coins live in <map>.CoinContainer, and the map changes every round
    ----------------------------------------------------------------

    local function coinContainer()
        -- search every top level model for a CoinContainer
        for _, child in pairs(workspace:GetChildren()) do
            if child:IsA("Model") or child:IsA("Folder") then
                local c = child:FindFirstChild("CoinContainer")
                if c then return c end
            end
        end

        -- last resort, anywhere in the tree
        return workspace:FindFirstChild("CoinContainer", true)
    end

    local function coinPart(inst)
        if inst:IsA("BasePart") then return inst end
        if inst:IsA("Model") then
            return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
        end
        return nil
    end

    local function findCoins()
        local out = {}
        local container = coinContainer()
        if not container then return out end

        for _, child in pairs(container:GetChildren()) do
            local part = coinPart(child)
            if part then
                out[#out + 1] = { inst = child, part = part }
            end
        end

        return out
    end

    elements:Button("Count Coins", section, function()
        local container = coinContainer()
        print("[BrainrotPolice] container: "
            .. (container and container:GetFullName() or "NOT FOUND"))

        local coins = findCoins()
        print("[BrainrotPolice] " .. #coins .. " coins")

        for i, c in ipairs(coins) do
            if i > 3 then break end
            print("  " .. c.inst:GetFullName())
        end
    end)

    ----------------------------------------------------------------
    -- coin farm
    ----------------------------------------------------------------

    elements:Textbox("Coin Delay (default 0.12)", section, tostring(coinDelay), function(v)
        local n = tonumber(v)
        if not n or n < 0.05 then return end
        coinDelay = n
        env.setconfig("coindelay", n)
    end)

    -- Movement mode dropdown
    elements:Dropdown("Movement Mode", section, {"Teleport", "Walk"}, coinMoveMode, function(v)
        coinMoveMode = v
        env.setconfig("coinmovemode", v)
    end)

    elements:Toggle("Auto Collect Coins", section, setdata.coins, function(v)
        env.MMCoins = v
        env.setconfig("coins", v)
        if not v then return end

        task.spawn(function()
            local announced = false

            while env.MMCoins do
                local root = getRoot()
                local humanoid = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")

                if root and humanoid then
                    local coins = findCoins()

                    if not announced then
                        print("[BrainrotPolice] coin farm: " .. #coins .. " coins found")
                        if #coins == 0 then
                            warn("[BrainrotPolice] no coins, press Count Coins during a round")
                        end
                        announced = true
                    end

                    local origin = root.CFrame

                    for _, c in ipairs(coins) do
                        if not env.MMCoins then break end

                        if c.part and c.part.Parent then
                            if coinMoveMode == "Teleport" then
                                -- Instant teleport (original behaviour)
                                root.CFrame = CFrame.new(c.part.Position)
                                root.AssemblyLinearVelocity = Vector3.zero

                                if firetouchinterest then
                                    pcall(function()
                                        firetouchinterest(root, c.part, 0)
                                        firetouchinterest(root, c.part, 1)
                                    end)
                                end

                                task.wait(coinDelay)
                            else
                                -- Walk to coin
                                humanoid:MoveTo(c.part.Position)
                                -- Wait until close to coin or timeout
                                local timeout = 5
                                local start = tick()
                                while env.MMCoins and c.part and c.part.Parent and root do
                                    local dist = (root.Position - c.part.Position).Magnitude
                                    if dist < 4 then break end
                                    if tick() - start > timeout then break end
                                    task.wait(0.1)
                                end
                                -- Small pause to ensure touch triggers
                                task.wait(coinDelay)
                            end
                        end
                    end

                    -- Return to start if teleporting, but not if walking (you'll be where you last walked)
                    if coinMoveMode == "Teleport" then
                        local r = getRoot()
                        if r then
                            r.CFrame = origin
                            r.AssemblyLinearVelocity = Vector3.zero
                        end
                    end
                end

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- coin esp
    ----------------------------------------------------------------

    local coinHighlights = {}

    local function clearCoinEsp()
        for inst, hl in pairs(coinHighlights) do
            pcall(function() hl:Destroy() end)
            coinHighlights[inst] = nil
        end
    end

    elements:Toggle("Coin ESP", section, setdata.coinesp, function(v)
        env.MMCoinEsp = v
        env.setconfig("coinesp", v)

        if not v then
            clearCoinEsp()
            return
        end

        task.spawn(function()
            while env.MMCoinEsp do
                pcall(function()
                    local seen = {}

                    for _, c in ipairs(findCoins()) do
                        seen[c.inst] = true

                        if not coinHighlights[c.inst] then
                            local hl = Instance.new("Highlight")
                            hl.Name = "BPCoin"
                            hl.FillColor = Color3.fromRGB(255, 210, 0)
                            hl.FillTransparency = 0.3
                            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            hl.Adornee = c.inst
                            hl.Parent = c.inst

                            coinHighlights[c.inst] = hl
                        end
                    end

                    for inst, hl in pairs(coinHighlights) do
                        if not seen[inst] or not inst.Parent then
                            pcall(function() hl:Destroy() end)
                            coinHighlights[inst] = nil
                        end
                    end
                end)

                task.wait(1)
            end

            clearCoinEsp()
        end)
    end)

    ----------------------------------------------------------------
    -- role detection (works on any player)
    ----------------------------------------------------------------
    local function getPlayerRole(player)
        local char = player.Character
        local backpack = player:FindFirstChildOfClass("Backpack")

        local function scan(container)
            if not container then return nil end
            for _, tool in pairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    local n = string.lower(tool.Name)
                    if string.find(n, "knife", 1, true)
                        or string.find(n, "blade", 1, true) then
                        return "MURDERER"
                    end
                    if string.find(n, "gun", 1, true)
                        or string.find(n, "revolver", 1, true)
                        or string.find(n, "pistol", 1, true) then
                        return "SHERIFF"
                    end
                end
            end
            return nil
        end

        return scan(char) or scan(backpack) or "INNOCENT"
    end

    ----------------------------------------------------------------
    -- own role display (unchanged, but using common function)
    ----------------------------------------------------------------
    local roleGui

    local function clearRoleGui()
        if roleGui then
            pcall(function() roleGui:Destroy() end)
            roleGui = nil
        end
    end

    local ROLE_COLOR = {
        MURDERER = Color3.fromRGB(255, 60, 60),
        SHERIFF  = Color3.fromRGB(60, 140, 255),
        INNOCENT = Color3.fromRGB(120, 255, 120),
    }

    local function buildRoleGui()
        local char = plr.Character
        local head = char and char:FindFirstChild("Head")
        if not head then return nil end

        local gui = Instance.new("BillboardGui")
        gui.Name = "BPMyRole"
        gui.Size = UDim2.new(0, 200, 0, 40)
        gui.StudsOffset = Vector3.new(0, 3, 0)
        gui.AlwaysOnTop = true
        gui.MaxDistance = 1000
        gui.Adornee = head
        gui.Parent = head

        local label = Instance.new("TextLabel")
        label.Name = "Role"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 20
        label.TextStrokeTransparency = 0
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.Text = ""
        label.Parent = gui

        return gui
    end

    elements:Toggle("Show My Role", section, setdata.myrole, function(v)
        env.MMMyRole = v
        env.setconfig("myrole", v)

        if not v then
            clearRoleGui()
            return
        end

        task.spawn(function()
            while env.MMMyRole do
                pcall(function()
                    if not roleGui or not roleGui.Parent then
                        clearRoleGui()
                        roleGui = buildRoleGui()
                    end

                    if roleGui then
                        local label = roleGui:FindFirstChild("Role")
                        if label then
                            local role = getPlayerRole(plr)
                            label.Text = role
                            label.TextColor3 = ROLE_COLOR[role] or Color3.new(1, 1, 1)
                        end
                    end
                end)

                task.wait(0.5)
            end

            clearRoleGui()
        end)
    end)

    ----------------------------------------------------------------
    -- all players role ESP (new)
    ----------------------------------------------------------------
    local allRoleGuis = {}   -- [player] = gui

    local function clearAllRoleGuis()
        for player, gui in pairs(allRoleGuis) do
            pcall(function() gui:Destroy() end)
            allRoleGuis[player] = nil
        end
    end

    local function buildPlayerRoleGui(player)
        local char = player.Character
        local head = char and char:FindFirstChild("Head")
        if not head then return nil end

        local gui = Instance.new("BillboardGui")
        gui.Name = "BPPlayerRole"
        gui.Size = UDim2.new(0, 200, 0, 40)
        gui.StudsOffset = Vector3.new(0, 3, 0)
        gui.AlwaysOnTop = true
        gui.MaxDistance = 1000
        gui.Adornee = head
        gui.Parent = head

        local label = Instance.new("TextLabel")
        label.Name = "Role"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 20
        label.TextStrokeTransparency = 0
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.Text = ""
        label.Parent = gui

        return gui
    end

    elements:Toggle("Show All Players Roles", section, setdata.allroles, function(v)
        env.MMAllRoles = v
        env.setconfig("allroles", v)

        if not v then
            clearAllRoleGuis()
            return
        end

        task.spawn(function()
            while env.MMAllRoles do
                pcall(function()
                    -- update guis for current players
                    for _, player in ipairs(players:GetPlayers()) do
                        if player == plr then continue end   -- leave local player's own gui if wanted

                        local gui = allRoleGuis[player]
                        local char = player.Character
                        local head = char and char:FindFirstChild("Head")

                        if not head then
                            -- player dead/reset, remove gui
                            if gui then
                                pcall(function() gui:Destroy() end)
                                allRoleGuis[player] = nil
                            end
                            continue
                        end

                        -- create gui if missing or adornee changed
                        if not gui or gui.Adornee ~= head then
                            if gui then
                                pcall(function() gui:Destroy() end)
                            end
                            gui = buildPlayerRoleGui(player)
                            if gui then
                                allRoleGuis[player] = gui
                            end
                        end

                        -- update text
                        if gui then
                            local label = gui:FindFirstChild("Role")
                            if label then
                                local role = getPlayerRole(player)
                                label.Text = role
                                label.TextColor3 = ROLE_COLOR[role] or Color3.new(1, 1, 1)
                            end
                        end
                    end

                    -- clean up guis for players that left
                    for player, gui in pairs(allRoleGuis) do
                        if not players:FindFirstChild(player.Name) then
                            pcall(function() gui:Destroy() end)
                            allRoleGuis[player] = nil
                        end
                    end
                end)

                task.wait(0.5)
            end

            clearAllRoleGuis()
        end)
    end)

    -- Debug button (updated to use common function)
    elements:Button("Debug My Role", section, function()
        local char = plr.Character
        local backpack = plr:FindFirstChildOfClass("Backpack")

        print("[BrainrotPolice] character: " .. (char and char.Name or "NONE"))
        print("[BrainrotPolice] head: "
            .. tostring(char and char:FindFirstChild("Head") ~= nil))

        local function list(label, container)
            if not container then
                print("  " .. label .. ": missing")
                return
            end

            local n = 0
            for _, c in pairs(container:GetChildren()) do
                if c:IsA("Tool") then
                    n = n + 1
                    print("  " .. label .. " tool: " .. c.Name)
                end
            end

            if n == 0 then
                print("  " .. label .. ": no tools")
            end
        end

        list("character", char)
        list("backpack", backpack)

        print("[BrainrotPolice] detected role: " .. getPlayerRole(plr))
        print("[BrainrotPolice] gui exists: " .. tostring(roleGui ~= nil and roleGui.Parent ~= nil))
    end)
end
