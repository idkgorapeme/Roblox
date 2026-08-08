local hui = gethui or get_hidden_gui
local getexec = identifyexecutor
local coregui = game:GetService("CoreGui")
local players = game:GetService("Players")
local runservice = game:GetService("RunService")
local lp = players.LocalPlayer
local userinputservice = game:GetService("UserInputService")
local httpservice = game:GetService("HttpService")
local exservice = game:GetService("ExperienceService")
local tweenservice = game:GetService("TweenService")

local ui = import("rbxassetid://75281832304062")

ui.Parent = hui and hui() or coregui

local bp = getgenv().BrainrotPolice
local track = bp and bp.track or function(conn) return conn end
if bp then bp.gui = ui end

-- FindFirstChild so a renamed/missing icon in the asset doesn't error out here
local ToggleButton = ui:FindFirstChild("togglebtn")
local MainFrame = ui.Frame

local Topbar = MainFrame.TopBar
local SectionContainers = MainFrame.sectionContainers
local TabList = MainFrame.tablist

local HideButton = Topbar.hidebtn

----------------------------------------------------------------
-- Scripts tab
--
-- The gui is a prebuilt asset with no Scripts tab, so clone an existing
-- tab button and container to inherit the exact styling.
----------------------------------------------------------------

local ScriptsTabBtn, ScriptsContainer

do
    local okTab = pcall(function()
        ScriptsTabBtn = TabList.SettingsTab:Clone()
        ScriptsTabBtn.Name = "ScriptsTab"
        ScriptsTabBtn.BackgroundTransparency = 1
        ScriptsTabBtn.LayoutOrder = 90
        ScriptsTabBtn.Parent = TabList

        -- rename whatever text lives inside the cloned button
        if ScriptsTabBtn:IsA("TextButton") and ScriptsTabBtn.Text ~= "" then
            ScriptsTabBtn.Text = "Scripts"
        end
        for _, d in pairs(ScriptsTabBtn:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                d.Text = "Scripts"
            end
        end
    end)

    local okFrame = pcall(function()
        ScriptsContainer = SectionContainers.settingsFrame:Clone()
        ScriptsContainer.Name = "scriptsFrame"
        ScriptsContainer.Visible = false
        ScriptsContainer.Position = UDim2.new(0.5, 0, 1, 0)
        ScriptsContainer.Parent = SectionContainers

        -- strip the cloned settings widgets, keep the layout objects
        for _, child in pairs(ScriptsContainer:GetChildren()) do
            if not child:IsA("UIListLayout")
                and not child:IsA("UIPadding")
                and not child:IsA("UIGridLayout")
                and not child:IsA("UICorner")
                and not child:IsA("UIStroke") then
                child:Destroy()
            end
        end
    end)

    if not (okTab and okFrame) then
        warn("[BrainrotPolice] could not build the Scripts tab")
        ScriptsTabBtn, ScriptsContainer = nil, nil
    end
end

local Sections = {
    Home = {
        TabBtn = TabList.HomeTab,
        Container = SectionContainers.homeframe
    },

    Game = {
        TabBtn = TabList.GameTab,
        Container = SectionContainers.gameFrame
    },

    GamesList = {
        TabBtn = TabList.GameslistTab,
        Container = SectionContainers.gamelistFrame
    },

    Settings = {
        TabBtn = TabList.SettingsTab,
        Container = SectionContainers.settingsFrame
    },

    Credits = {
        TabBtn = TabList.CreditsTab,
        Container = SectionContainers.creditsFrame
    }
}

if ScriptsTabBtn and ScriptsContainer then
    Sections.Scripts = {
        TabBtn = ScriptsTabBtn,
        Container = ScriptsContainer
    }
end

local CurSection

for _, sect in pairs(Sections) do
    track(sect.TabBtn.MouseEnter:Connect(function()
        for _, stroke in pairs(sect.TabBtn:GetChildren()) do
            if stroke.Name == "InnerShadow" then
                stroke.Transparency = 0.95
            end
        end
    end))

    track(sect.TabBtn.MouseLeave:Connect(function()
        for _, stroke in pairs(sect.TabBtn:GetChildren()) do
            if stroke.Name == "InnerShadow" then
                stroke.Transparency = 1
            end
        end
    end))

    track(sect.TabBtn.MouseButton1Click:Connect(function()
        if CurSection == sect then return end

        if CurSection then
            CurSection.TabBtn.BackgroundTransparency = 1
            CurSection.Container:TweenPosition(UDim2.new(0.5, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2)
        end

        sect.TabBtn.BackgroundTransparency = 0
        sect.Container:TweenPosition(UDim2.new(0.5, 0, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2)
        sect.Container.Visible = true

        CurSection = sect
    end))
end

-- generic dragger, returns a function telling you whether the last press was a drag
local function makeDraggable(frame)
    local dragging = false
    local dragInput, mousePos, framePos
    local moved = 0

    track(frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = 0
            mousePos = input.Position
            framePos = frame.Position

            track(input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end))
        end
    end))

    track(frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    track(userinputservice.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - mousePos
            moved = math.max(moved, math.abs(delta.X) + math.abs(delta.Y))
            frame.Position = UDim2.new(
                framePos.X.Scale,
                framePos.X.Offset + delta.X,
                framePos.Y.Scale,
                framePos.Y.Offset + delta.Y
            )
        end
    end))

    return function()
        return moved > 5
    end
end

-- the toggle icon lives in the gui asset, but it can come through off screen,
-- zero sized or stacked under another gui. build a fallback if it is missing and
-- force it somewhere visible whenever we show it.
if not ToggleButton then
    local fallback = Instance.new("TextButton")
    fallback.Name = "togglebtn"
    fallback.Size = UDim2.new(0, 90, 0, 32)
    fallback.Position = UDim2.new(0, 20, 0, 20)
    fallback.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    fallback.BorderSizePixel = 0
    fallback.Text = "Brainrot"
    fallback.TextColor3 = Color3.fromRGB(255, 255, 255)
    fallback.TextSize = 14
    fallback.Font = Enum.Font.GothamBold
    fallback.AutoButtonColor = true
    fallback.Visible = false
    fallback.Parent = ui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = fallback

    ToggleButton = fallback
end

local function showToggleIcon()
    -- make sure the gui itself is on top of anything else the executor has open
    pcall(function()
        if ui:IsA("ScreenGui") then
            ui.Enabled = true
            ui.DisplayOrder = 9999
            ui.ResetOnSpawn = false
            ui.IgnoreGuiInset = true
        end
    end)

    ToggleButton.Visible = true
    ToggleButton.Active = true
    ToggleButton.ZIndex = 100

    -- a zero sized button is invisible even when Visible is true
    if ToggleButton.AbsoluteSize.X < 5 or ToggleButton.AbsoluteSize.Y < 5 then
        ToggleButton.Size = UDim2.new(0, 90, 0, 32)
    end

    -- if it sits outside the viewport, pull it back to the top left
    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
    if viewport then
        local pos = ToggleButton.AbsolutePosition
        local size = ToggleButton.AbsoluteSize
        if pos.X + size.X < 0 or pos.Y + size.Y < 0
            or pos.X > viewport.X - 5 or pos.Y > viewport.Y - 5 then
            ToggleButton.AnchorPoint = Vector2.new(0, 0)
            ToggleButton.Position = UDim2.new(0, 20, 0, 20)
        end
    end
end

makeDraggable(MainFrame)
local toggleWasDragged = makeDraggable(ToggleButton)

track(HideButton.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    showToggleIcon()
end))

track(ToggleButton.MouseButton1Click:Connect(function()
    -- ignore the click that ends a drag so moving the icon doesn't reopen the menu
    if toggleWasDragged() then return end
    MainFrame.Visible = true
    ToggleButton.Visible = false
end))

-- keybind fallback so the menu is never unreachable if the icon still hides
track(userinputservice.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode ~= Enum.KeyCode.RightControl then return end

    if MainFrame.Visible then
        MainFrame.Visible = false
        showToggleIcon()
    else
        MainFrame.Visible = true
        ToggleButton.Visible = false
    end
end))

Sections.Home.Container.bugsLabel.Text = Sections.Home.Container.bugsLabel.Text:gsub("redacted", "discord.gg/vaehz")
Sections.Home.Container.discan.Text = Sections.Home.Container.discan.Text:gsub("redacted", "discord.gg/vaehz")
Sections.Home.Container.ythead.Text = Sections.Home.Container.ythead.Text:gsub("redacted", "YouTube")
Sections.Home.Container.execLabel.Text = "Executor: " .. getexec()
Sections.Home.Container.versionLabel.Text = "Version: 0.33 BETA"
Sections.Home.Container.execLabel.Text = Sections.Home.Container.execLabel.Text .. "  |  PlaceId: " .. tostring(game.PlaceId)

-- copy the place id straight from the home tab
do
    local copyBtn = Instance.new("TextButton")
    copyBtn.Name = "copyplaceid"
    copyBtn.Size = UDim2.new(0, 110, 0, 22)
    copyBtn.AnchorPoint = Vector2.new(1, 0.5)
    copyBtn.Position = UDim2.new(1, -8, 0.5, 0)
    copyBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
    copyBtn.BorderSizePixel = 0
    copyBtn.Text = "Copy PlaceId"
    copyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    copyBtn.TextSize = 12
    copyBtn.Font = Enum.Font.GothamBold
    copyBtn.AutoButtonColor = true
    copyBtn.ZIndex = 10
    copyBtn.Parent = Sections.Home.Container.execLabel

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = copyBtn

    track(copyBtn.MouseButton1Click:Connect(function()
        local ok = pcall(function()
            setclipboard(tostring(game.PlaceId))
        end)

        copyBtn.Text = ok and "Copied!" or "No clipboard"
        task.delay(1, function()
            if copyBtn and copyBtn.Parent then
                copyBtn.Text = "Copy PlaceId"
            end
        end)
    end))
end


local ok, gamePath = pcall(function()
    return getgenv().gitfetch(getgitpath("games") .. tostring(game.PlaceId) .. ".lua")
end)
local gameList = httpservice:JSONDecode(getgenv().gitfetch(getgitpath("src").. "gameslist.json"))
local creditsList = httpservice:JSONDecode(getgenv().gitfetch(getgitpath("src").. "credits.json"))
local elements = loadstring(getgenv().gitfetch(getgitpath("src").."elements.lua"))()
if not ok or #gamePath == 0 or gamePath == "404: Not Found" then
    local handledLocally = false

    if getgenv().FileScripts then
        if isfile("BrainrotPolice/"..tostring(game.PlaceId)..".lua") then
            local gameModule = loadstring(readfile("BrainrotPolice/"..tostring(game.PlaceId)..".lua"))()
            gameModule(Sections.Game.Container, httpservice:JSONDecode(readfile("BrainrotPolice/Config.json")))
            handledLocally = true
        end
    end

    if not handledLocally then
        elements:Unsupported(Sections.Game.Container, function()
            if CurSection then
                CurSection.TabBtn.BackgroundTransparency = 1
                CurSection.Container:TweenPosition(UDim2.new(0.5, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2)
            end

            Sections.GamesList.TabBtn.BackgroundTransparency = 0
            Sections.GamesList.Container:TweenPosition(UDim2.new(0.5, 0, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2)
            Sections.GamesList.Container.Visible = true

            CurSection = Sections.GamesList
        end)

        -- no script exists for this place, so offer the dump tools instead.
        -- these only ever show up on unsupported games.
        elements:Label("Unsupported game. Dump it and send the output so it can be added.", Sections.Game.Container)

        elements:Button("Dump Game Structure (copies)", Sections.Game.Container, function()
            local out = {}
            local function add(...)
                local parts = {}
                for _, v in ipairs({...}) do
                    parts[#parts + 1] = tostring(v)
                end
                out[#out + 1] = table.concat(parts, " ")
            end

            add("PlaceId:", game.PlaceId)
            add("JobId:", game.JobId)
            add("Executor:", (getexec and getexec()) or "unknown")

            add("")
            add("======== workspace ========")
            for _, child in pairs(workspace:GetChildren()) do
                add(child.ClassName, "|", child.Name)
            end

            add("")
            add("======== ReplicatedStorage ========")
            for _, child in pairs(game:GetService("ReplicatedStorage"):GetChildren()) do
                add(child.ClassName, "|", child.Name)
            end

            add("")
            add("======== remotes ========")
            local n = 0
            for _, r in pairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
                if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then
                    n = n + 1
                    if n <= 200 then
                        add(r.ClassName, "|", r:GetFullName())
                    end
                end
            end
            add("total remotes:", n)

            add("")
            add("======== leaderstats ========")
            local ls = players.LocalPlayer:FindFirstChild("leaderstats")
            if ls then
                for _, stat in pairs(ls:GetChildren()) do
                    add(stat.Name, "=", tostring(stat.Value))
                end
            else
                add("no leaderstats")
            end

            add("")
            add("======== player attributes ========")
            local attrs = players.LocalPlayer:GetAttributes()
            if next(attrs) == nil then
                add("none")
            else
                for k, v in pairs(attrs) do
                    add(k, "=", tostring(v))
                end
            end

            local text = table.concat(out, "\n")
            print(text)

            local path = "BrainrotPolice/dump_" .. tostring(game.PlaceId) .. ".txt"
            local savedOk = pcall(function() writefile(path, text) end)
            local copiedOk = pcall(function() setclipboard(text) end)

            if copiedOk then
                print("[BrainrotPolice] dump copied to clipboard (" .. #text .. " chars, PlaceId included)")
            else
                warn("[BrainrotPolice] setclipboard not available, use " .. path)
            end

            if savedOk then
                print("[BrainrotPolice] dump also saved to " .. path)
            end
        end)

        elements:Button("Copy PlaceId", Sections.Game.Container, function()
            local okc = pcall(function()
                setclipboard(tostring(game.PlaceId))
            end)
            print("[BrainrotPolice] PlaceId " .. tostring(game.PlaceId)
                .. (okc and " copied" or " (clipboard unavailable)"))
        end)
    end
else
    local gameModule = loadstring(gamePath)()
    gameModule(Sections.Game.Container, httpservice:JSONDecode(readfile("BrainrotPolice/Config.json")))
end
elements:Searchbar(Sections.GamesList.Container)
for _, g in ipairs(gameList) do
    elements:addGame(Sections.GamesList.Container, g["game"], g["status"], function()
        exservice:LaunchExperience({placeId = g.id})
    end)
end

for sect, c in pairs(creditsList) do
    elements:CredHead(Sections.Credits.Container, sect)

    for _, person in ipairs(c) do
        elements:CredPerson(Sections.Credits.Container, person)
    end
end

local dec1 = httpservice:JSONDecode(readfile("BrainrotPolice/Config.json"))

elements:Toggle("Disable 3D Rendering", Sections.Settings.Container, dec1.settings.disable_3d_rendering, function(v)
    local dec = httpservice:JSONDecode(readfile("BrainrotPolice/Config.json"))
    dec.settings.disable_3d_rendering = v
    writefile("BrainrotPolice/Config.json", httpservice:JSONEncode(dec))
    game:GetService("RunService"):Set3dRenderingEnabled(not v)
end)

elements:Toggle("Auto Rejoin (when kicked)", Sections.Settings.Container, dec1.settings.auto_rejoin_on_kick, function(v)
    local dec = httpservice:JSONDecode(readfile("BrainrotPolice/Config.json"))
    dec.settings.auto_rejoin_on_kick = v
    writefile("BrainrotPolice/Config.json", httpservice:JSONEncode(dec))
    getgenv().autorjjjj = v
end)

----------------------------------------------------------------
-- player movement cheats
----------------------------------------------------------------

local env = getgenv()

local DEFAULT_WALKSPEED = 16
local DEFAULT_JUMPPOWER = 50
local DEFAULT_GRAVITY = 196.2

local settings = dec1.settings
local moveSpeed = tonumber(settings.fly_speed) or 50
local walkSpeed = tonumber(settings.walk_speed) or DEFAULT_WALKSPEED
local jumpPower = tonumber(settings.jump_power) or DEFAULT_JUMPPOWER

local function saveSetting(key, value)
    local ok, dec = pcall(function()
        return httpservice:JSONDecode(readfile("BrainrotPolice/Config.json"))
    end)
    if not ok or type(dec) ~= "table" then return end
    dec.settings = dec.settings or {}
    dec.settings[key] = value
    writefile("BrainrotPolice/Config.json", httpservice:JSONEncode(dec))
end

local function getChar()
    return lp.Character
end

local function getHum()
    local char = getChar()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local char = getChar()
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- flight -------------------------------------------------------

local flyBP, flyBG, flyConn

local function stopFly()
    if flyConn then flyConn:Disconnect() flyConn = nil end
    if flyBP then pcall(function() flyBP:Destroy() end) flyBP = nil end
    if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end

    local hum = getHum()
    if hum then
        pcall(function() hum.PlatformStand = false end)
    end
end

local function startFly()
    local root = getRoot()
    if not root then return end

    stopFly()

    flyBP = Instance.new("BodyPosition")
    flyBP.Name = "BPFlyPos"
    flyBP.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    flyBP.P = 9e4
    flyBP.D = 1000
    flyBP.Position = root.Position
    flyBP.Parent = root

    flyBG = Instance.new("BodyGyro")
    flyBG.Name = "BPFlyGyro"
    flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    flyBG.P = 9e4
    flyBG.CFrame = root.CFrame
    flyBG.Parent = root

    flyConn = runservice.RenderStepped:Connect(function(dt)
        if not env.BPFly then return end

        local r = getRoot()
        local cam = workspace.CurrentCamera
        if not r or not cam or not flyBP or not flyBG then return end

        -- keep the body movers attached across respawns
        if flyBP.Parent ~= r then
            startFly()
            return
        end

        local dir = Vector3.zero
        local look = cam.CFrame.LookVector
        local right = cam.CFrame.RightVector

        if userinputservice:IsKeyDown(Enum.KeyCode.W) then dir = dir + look end
        if userinputservice:IsKeyDown(Enum.KeyCode.S) then dir = dir - look end
        if userinputservice:IsKeyDown(Enum.KeyCode.D) then dir = dir + right end
        if userinputservice:IsKeyDown(Enum.KeyCode.A) then dir = dir - right end
        if userinputservice:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if userinputservice:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end

        if dir.Magnitude > 0 then
            flyBP.Position = r.Position + dir.Unit * moveSpeed * dt * 10
        else
            flyBP.Position = r.Position
        end

        flyBG.CFrame = cam.CFrame
    end)

    track(flyConn)
end

elements:Textbox("Fly Speed (default 50)", Sections.Settings.Container, tostring(moveSpeed), function(v)
    local n = tonumber(v)
    if not n or n <= 0 then return end
    moveSpeed = n
    saveSetting("fly_speed", n)
end)

elements:Toggle("Flight (WASD / Space / LeftCtrl)", Sections.Settings.Container, false, function(v)
    env.BPFly = v

    if v then
        startFly()

        -- rebuild the movers after a respawn
        track(lp.CharacterAdded:Connect(function(char)
            if not env.BPFly then return end
            char:WaitForChild("HumanoidRootPart", 10)
            task.wait(0.2)
            if env.BPFly then startFly() end
        end))
    else
        stopFly()
    end
end)

-- infinite jump ------------------------------------------------

elements:Toggle("Infinite Jump", Sections.Settings.Container, false, function(v)
    env.BPInfJump = v
end)

track(userinputservice.JumpRequest:Connect(function()
    if not env.BPInfJump then return end
    local hum = getHum()
    if hum then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end))

-- noclip -------------------------------------------------------

local noclipConn

elements:Toggle("Noclip", Sections.Settings.Container, false, function(v)
    env.BPNoclip = v

    if noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
    end

    if v then
        -- reapplied every frame, so it survives respawns automatically
        noclipConn = runservice.Stepped:Connect(function()
            if not env.BPNoclip then return end
            local char = getChar()
            if not char then return end

            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end)

        track(noclipConn)
    else
        local char = getChar()
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    pcall(function() part.CanCollide = true end)
                end
            end
        end
    end
end)

-- walk speed / jump power --------------------------------------

local function applyWalkSpeed()
    local hum = getHum()
    if hum then pcall(function() hum.WalkSpeed = walkSpeed end) end
end

local function applyJumpPower()
    local hum = getHum()
    if not hum then return end
    pcall(function()
        hum.UseJumpPower = true
        hum.JumpPower = jumpPower
    end)
end

elements:Textbox("Walk Speed (default 16)", Sections.Settings.Container, tostring(walkSpeed), function(v)
    local n = tonumber(v)
    if not n or n < 0 then return end
    walkSpeed = n
    saveSetting("walk_speed", n)
    applyWalkSpeed()
end)

elements:Textbox("Jump Power (default 50)", Sections.Settings.Container, tostring(jumpPower), function(v)
    local n = tonumber(v)
    if not n or n < 0 then return end
    jumpPower = n
    saveSetting("jump_power", n)
    applyJumpPower()
end)

-- keep both applied through respawns
track(lp.CharacterAdded:Connect(function(char)
    char:WaitForChild("Humanoid", 10)
    task.wait(0.2)
    if walkSpeed ~= DEFAULT_WALKSPEED then applyWalkSpeed() end
    if jumpPower ~= DEFAULT_JUMPPOWER then applyJumpPower() end
end))

-- gravity ------------------------------------------------------

elements:Textbox("Gravity (default 196.2, affects everyone)", Sections.Settings.Container, tostring(workspace.Gravity), function(v)
    local n = tonumber(v)
    if not n then return end
    pcall(function() workspace.Gravity = n end)
end)

-- rejoin -------------------------------------------------------

-- anti afk ------------------------------------------------------

do
    local vu = game:GetService("VirtualUser")
    local idleConn

    local function saved()
        local ok, dec = pcall(function()
            return httpservice:JSONDecode(readfile("BrainrotPolice/Config.json"))
        end)
        if ok and type(dec) == "table" and dec.settings then
            return dec.settings.anti_afk == true
        end
        return false
    end

    elements:Toggle("Anti AFK", Sections.Settings.Container, saved(), function(v)
        env.BPAntiAFK = v
        saveSetting("anti_afk", v)

        if idleConn then
            idleConn:Disconnect()
            idleConn = nil
        end

        if not v then return end

        -- Roblox kicks after 20 minutes of no input. Idled fires at ~20 min,
        -- so a click through VirtualUser resets the timer without moving you.
        idleConn = lp.Idled:Connect(function()
            if not env.BPAntiAFK then return end

            pcall(function()
                vu:CaptureController()
                vu:ClickButton2(Vector2.new())
            end)
        end)

        track(idleConn)
    end)
end

elements:Button("Rejoin Server", Sections.Settings.Container, function()
    local teleportservice = game:GetService("TeleportService")

    if #players:GetPlayers() <= 1 then
        -- last player in the server, a plain teleport would land us right back
        pcall(function()
            teleportservice:Teleport(game.PlaceId, lp)
        end)
    else
        pcall(function()
            teleportservice:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp)
        end)
    end
end)

----------------------------------------------------------------
-- Scripts tab contents
--
-- Scripts live as .lua files in BrainrotPolice/Scripts. Each one gets a
-- run button and an auto execute toggle. Auto execute state is kept in
-- BrainrotPolice/Scripts/_autoexec.json so it survives rejoins.
----------------------------------------------------------------

if Sections.Scripts then
    local SCRIPT_DIR = "BrainrotPolice/Scripts"
    local AUTO_FILE = SCRIPT_DIR .. "/_autoexec.json"

    if not isfolder(SCRIPT_DIR) then
        pcall(function() makefolder(SCRIPT_DIR) end)
    end

    local function loadAuto()
        local ok, dec = pcall(function()
            if isfile(AUTO_FILE) then
                return httpservice:JSONDecode(readfile(AUTO_FILE))
            end
        end)
        if ok and type(dec) == "table" then return dec end
        return {}
    end

    local function saveAuto(tbl)
        pcall(function()
            writefile(AUTO_FILE, httpservice:JSONEncode(tbl))
        end)
    end

    local autoExec = loadAuto()

    local function listScripts()
        local out = {}

        local ok, files = pcall(function()
            return listfiles(SCRIPT_DIR)
        end)

        if not ok or type(files) ~= "table" then return out end

        for _, path in ipairs(files) do
            -- only .lua, skip the autoexec bookkeeping file
            if string.sub(path, -4) == ".lua" then
                local name = string.match(path, "[^/\\]+$") or path
                out[#out + 1] = { path = path, name = name }
            end
        end

        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end

    local function runScript(entry)
        local ok, src = pcall(function()
            return readfile(entry.path)
        end)

        if not ok or not src then
            warn("[BrainrotPolice] could not read " .. entry.name)
            return false
        end

        local fn, err = loadstring(src, entry.name)

        if not fn then
            warn("[BrainrotPolice] " .. entry.name .. " failed to compile: " .. tostring(err))
            return false
        end

        local ranOk, runErr = pcall(fn)

        if ranOk then
            print("[BrainrotPolice] ran " .. entry.name)
        else
            warn("[BrainrotPolice] " .. entry.name .. " error: " .. tostring(runErr))
        end

        return ranOk
    end

    -- rebuilt whenever the list changes, so new files show up without a rejoin
    local function buildScriptList()
        for _, child in pairs(Sections.Scripts.Container:GetChildren()) do
            if not child:IsA("UIListLayout")
                and not child:IsA("UIPadding")
                and not child:IsA("UIGridLayout")
                and not child:IsA("UICorner")
                and not child:IsA("UIStroke") then
                child:Destroy()
            end
        end

        elements:Label("Put .lua files in workspace/" .. SCRIPT_DIR,
            Sections.Scripts.Container)

        elements:Button("Refresh List", Sections.Scripts.Container, function()
            task.spawn(function()
                buildScriptList()
            end)
        end)

        elements:Button("Open Folder Path", Sections.Scripts.Container, function()
            local ok = pcall(function() setclipboard(SCRIPT_DIR) end)
            print("[BrainrotPolice] script folder: " .. SCRIPT_DIR
                .. (ok and " (copied)" or ""))
        end)

        local scripts = listScripts()

        if #scripts == 0 then
            elements:Label("No scripts found.", Sections.Scripts.Container)
            return
        end

        for _, entry in ipairs(scripts) do
            elements:Button("Run  " .. entry.name, Sections.Scripts.Container, function()
                task.spawn(function()
                    runScript(entry)
                end)
            end)

            elements:Toggle("Auto Exec  " .. entry.name, Sections.Scripts.Container,
                autoExec[entry.name] == true, function(v)
                    autoExec[entry.name] = v or nil
                    saveAuto(autoExec)
                end)
        end
    end

    buildScriptList()

    -- run everything marked for auto execute, once, on load
    task.spawn(function()
        for _, entry in ipairs(listScripts()) do
            if autoExec[entry.name] then
                print("[BrainrotPolice] auto executing " .. entry.name)
                runScript(entry)
                task.wait(0.2)
            end
        end
    end)
end

elements:Button("Unload Script", Sections.Settings.Container, function()
    if bp and bp.unload then
        bp.unload()
    else
        -- fallback if init.lua is an older build without the registry
        ui:Destroy()
    end
end)
