local elements = import("rbxassetid://113037265185555")
local stuff = {}
local gameList = game:GetService("HttpService"):JSONDecode(game:HttpGet(getgitpath("src").. "gameslist.json"))

function stuff:Label(str, king)
    local newLabel = elements.LabelElement:Clone()
    newLabel.Text = str
    newLabel.Parent = king
end

function stuff:Button(str, king, cb)
    local newBtn = elements.ButtonElement:Clone()
    newBtn.TextLabel.Text = str
    newBtn.Parent = king

    newBtn.MouseButton1Click:Connect(cb)
end

-- A real dropdown. The gui asset has no list element, so the popup is built
-- from scratch and parented to the ScreenGui, which keeps it floating above
-- everything instead of stretching the section it lives in.
--
--   stuff:Dropdown(name, parent, options, default, callback)          single
--   stuff:Dropdown(name, parent, options, {"a","b"}, callback, true)  multi
--
-- Single select hands the callback the chosen string, multi hands it the
-- table of everything ticked.
local OPEN_POPUP = nil

local function closeOpenPopup()
    if OPEN_POPUP and OPEN_POPUP.Parent then
        OPEN_POPUP.Visible = false
    end

    OPEN_POPUP = nil
end

function stuff:Dropdown(str, king, options, def, cb, multi)
    options = options or {}

    local selected = {}

    if multi then
        for _, v in ipairs(def or {}) do
            selected[tostring(v)] = true
        end
    elseif def ~= nil then
        selected[tostring(def)] = true
    end

    local function chosen()
        local out = {}

        -- keep the option order, never the hash order
        for _, opt in ipairs(options) do
            if selected[tostring(opt)] then
                out[#out + 1] = opt
            end
        end

        return out
    end

    local trigger = elements.ButtonElement:Clone()
    trigger.Parent = king

    local function label()
        local picked = chosen()

        if multi then
            if #picked == 0 then
                return str .. ": none"
            elseif #picked == 1 then
                return str .. ": " .. tostring(picked[1])
            elseif #picked == #options then
                return str .. ": all (" .. #picked .. ")"
            end

            return str .. ": " .. #picked .. " selected"
        end

        return str .. ": " .. tostring(picked[1] or "none")
    end

    local function render()
        trigger.TextLabel.Text = label() .. "  v"
    end

    render()

    ----------------------------------------------------------------
    -- popup
    ----------------------------------------------------------------

    local screen = king:FindFirstAncestorWhichIsA("ScreenGui")

    local popup = Instance.new("Frame")
    popup.Name = "BPDropdown"
    popup.Visible = false
    popup.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
    popup.BorderSizePixel = 0
    popup.ZIndex = 50
    popup.Size = UDim2.new(0, 200, 0, 0)
    popup.Parent = screen or king

    local pcorner = Instance.new("UICorner")
    pcorner.CornerRadius = UDim.new(0, 6)
    pcorner.Parent = popup

    local pstroke = Instance.new("UIStroke")
    pstroke.Color = Color3.fromRGB(70, 70, 90)
    pstroke.Thickness = 1
    pstroke.Parent = popup

    local scroller = Instance.new("ScrollingFrame")
    scroller.BackgroundTransparency = 1
    scroller.BorderSizePixel = 0
    scroller.Size = UDim2.new(1, -8, 1, -8)
    scroller.Position = UDim2.new(0, 4, 0, 4)
    scroller.ScrollBarThickness = 3
    scroller.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 150)
    scroller.ZIndex = 51
    scroller.Parent = popup

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 2)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroller

    local ROW = 22
    local MAX_ROWS = 7

    local rows = {}

    local function paintRow(row, name)
        local on = selected[name] == true

        row.BackgroundColor3 = on
            and Color3.fromRGB(52, 92, 148)
            or Color3.fromRGB(40, 40, 52)

        row.Text = (multi and (on and "  [x] " or "  [  ] ") or "  ") .. name
    end

    for i, opt in ipairs(options) do
        local name = tostring(opt)

        local row = Instance.new("TextButton")
        row.Name = name
        row.LayoutOrder = i
        row.Size = UDim2.new(1, 0, 0, ROW)
        row.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
        row.BorderSizePixel = 0
        row.AutoButtonColor = true
        row.Font = Enum.Font.Gotham
        row.TextSize = 12
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.TextColor3 = Color3.fromRGB(235, 235, 245)
        row.ZIndex = 52
        row.Parent = scroller

        local rcorner = Instance.new("UICorner")
        rcorner.CornerRadius = UDim.new(0, 4)
        rcorner.Parent = row

        paintRow(row, name)
        rows[name] = row

        row.MouseButton1Click:Connect(function()
            if multi then
                selected[name] = (not selected[name]) or nil
                paintRow(row, name)
            else
                -- single select, clear the rest
                selected = { [name] = true }

                for other, r in pairs(rows) do
                    paintRow(r, other)
                end

                popup.Visible = false
                OPEN_POPUP = nil
            end

            render()

            if cb then
                cb(multi and chosen() or name)
            end
        end)
    end

    local shown = math.min(#options, MAX_ROWS)
    local height = math.max(shown * (ROW + 2) + 8, 30)
    popup.Size = UDim2.new(0, 200, 0, height)
    scroller.CanvasSize = UDim2.new(0, 0, 0, #options * (ROW + 2))

    ----------------------------------------------------------------
    -- open and close
    ----------------------------------------------------------------

    local function place()
        -- follow the trigger, it moves whenever the section scrolls
        local pos = trigger.AbsolutePosition
        local size = trigger.AbsoluteSize

        popup.Size = UDim2.new(0, math.max(size.X, 160), 0, height)
        popup.Position = UDim2.new(0, pos.X, 0, pos.Y + size.Y + 2)
    end

    trigger.MouseButton1Click:Connect(function()
        if #options == 0 then return end

        if popup.Visible then
            popup.Visible = false
            OPEN_POPUP = nil
            return
        end

        closeOpenPopup()
        place()
        popup.Visible = true
        OPEN_POPUP = popup
    end)

    -- keep it glued to the trigger while the list scrolls
    trigger:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
        if popup.Visible then place() end
    end)

    return {
        Get = chosen,
        Refresh = render,
        Close = function()
            popup.Visible = false
            if OPEN_POPUP == popup then OPEN_POPUP = nil end
        end,
    }
end

function stuff:Toggle(str, king, def, cb)
    local newTog = elements.ToggleElement:Clone()
    newTog.TextLabel.Text = str
    newTog.Parent = king

    local isTog = def
    if isTog then
        newTog.togglebg.BackgroundColor3 = Color3.fromRGB(59, 164, 57)
        newTog.togglebg.leftrightlol.AnchorPoint = Vector2.new(1, 0.5)
        newTog.togglebg.leftrightlol.Position = UDim2.new(1, 0, 0.5, 0)
    else
        newTog.togglebg.BackgroundColor3 = Color3.fromRGB(164, 58, 58)
        newTog.togglebg.leftrightlol.AnchorPoint = Vector2.new(0, 0.5)
        newTog.togglebg.leftrightlol.Position = UDim2.new(0, 0, 0.5, 0)
    end
    task.defer(function() cb(isTog) end)

    newTog.MouseButton1Click:Connect(function()
        isTog = not isTog
        if isTog then
            newTog.togglebg.BackgroundColor3 = Color3.fromRGB(59, 164, 57)
            newTog.togglebg.leftrightlol.AnchorPoint = Vector2.new(1, 0.5)
            newTog.togglebg.leftrightlol.Position = UDim2.new(1, 0, 0.5, 0)
        else
            newTog.togglebg.BackgroundColor3 = Color3.fromRGB(164, 58, 58)
            newTog.togglebg.leftrightlol.AnchorPoint = Vector2.new(0, 0.5)
            newTog.togglebg.leftrightlol.Position = UDim2.new(0, 0, 0.5, 0)
        end
        cb(isTog)
    end)
end

function stuff:Textbox(str, king, def, cb)
    local newTb = elements.TextboxElement:Clone()
    newTb.TextLabel.Text = str
    newTb.Parent = king

    -- the default was accepted but never shown, so a box could not display
    -- an existing value
    if def ~= nil and def ~= "" then
        newTb.tbbg.Inp.Text = tostring(def)
    end

    newTb.tbbg.Inp.FocusLost:Connect(function(ep)
        cb(newTb.tbbg.Inp.Text)
    end)
end

function stuff:Unsupported(king, cb)
    local newUs = elements.unsupportElement:Clone()
    newUs.Parent = king

    newUs.suggestbtn.MouseButton1Click:Connect(function()
        setclipboard("https://discord.gg/vaehz")
        newUs.suggestbtn.Text = "Copied Link!"
        wait(1)
        newUs.suggestbtn.Text = "Suggest Game"
    end)

    newUs.glbtn.MouseButton1Click:Connect(cb)
end

function stuff:addGame(king, gname, gstate, cb)
    local newGame = elements.GameElement:Clone()
    newGame.ButtonElement.header.Text = gname
    if gstate == "🟢" then
        newGame.ButtonElement.status.ImageColor3 = Color3.fromRGB(0, 255, 0)
    elseif gstate == "🟡" then
        newGame.ButtonElement.status.ImageColor3 = Color3.fromRGB(255, 255, 0)
    elseif gstate == "🔴" then
        newGame.ButtonElement.status.ImageColor3 = Color3.fromRGB(255, 0, 0)
    end
    newGame.Parent = king

    newGame.ButtonElement.MouseButton1Click:Connect(cb)
end

-- to finish
function stuff:Searchbar(king)
    local newSearch = elements.searchBar:Clone()
    newSearch.Parent = king
    newSearch.searchbar.Inp:GetPropertyChangedSignal("Text"):Connect(function()
        for i, v in pairs(king:GetChildren()) do
            if v.Name == "GameElement" then
                v:Destroy()
            end
        end

        for i, v in pairs(gameList) do
            if v["game"]:lower():find(newSearch.searchbar.Inp.Text:lower()) then
                stuff:addGame(king, v["game"], v["status"], function()
                    game:GetService("ExperienceService"):LaunchExperience({placeId = v["id"]})
                end)
            end
        end
    end)
end


return stuff
