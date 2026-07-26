local hui = gethui or get_hidden_gui
local getexec = identifyexecutor
local coregui = game:GetService("CoreGui")
local userinputservice = game:GetService("UserInputService")
local httpservice = game:GetService("HttpService")
local exservice = game:GetService("ExperienceService")
local tweenservice = game:GetService("TweenService")

local ui = import("rbxassetid://75281832304062")

ui.Parent = hui and hui() or coregui

local bp = getgenv().BrainrotPolice
local track = bp and bp.track or function(conn) return conn end
if bp then bp.gui = ui end

local ToggleButton = ui.togglebtn
local MainFrame = ui.Frame

local Topbar = MainFrame.TopBar
local SectionContainers = MainFrame.sectionContainers
local TabList = MainFrame.tablist

local HideButton = Topbar.hidebtn

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

makeDraggable(MainFrame)
local toggleWasDragged = makeDraggable(ToggleButton)

track(HideButton.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    ToggleButton.Visible = true
end))

track(ToggleButton.MouseButton1Click:Connect(function()
    -- ignore the click that ends a drag so moving the icon doesn't reopen the menu
    if toggleWasDragged() then return end
    MainFrame.Visible = true
    ToggleButton.Visible = false
end))

Sections.Home.Container.bugsLabel.Text = Sections.Home.Container.bugsLabel.Text:gsub("redacted", "discord.gg/vaehz")
Sections.Home.Container.discan.Text = Sections.Home.Container.discan.Text:gsub("redacted", "discord.gg/vaehz")
Sections.Home.Container.ythead.Text = Sections.Home.Container.ythead.Text:gsub("redacted", "YouTube")
Sections.Home.Container.execLabel.Text = "Executor: " .. getexec()
Sections.Home.Container.versionLabel.Text = "Version: 0.33 BETA"


local ok, gamePath = pcall(function()
    return game:HttpGet(getgitpath("games") .. tostring(game.PlaceId) .. ".lua")
end)
local gameList = httpservice:JSONDecode(game:HttpGet(getgitpath("src").. "gameslist.json"))
local creditsList = httpservice:JSONDecode(game:HttpGet(getgitpath("src").. "credits.json"))
local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
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

elements:Button("Unload Script", Sections.Settings.Container, function()
    if bp and bp.unload then
        bp.unload()
    else
        -- fallback if init.lua is an older build without the registry
        ui:Destroy()
    end
end)
