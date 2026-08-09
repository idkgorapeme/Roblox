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

-- Cycles through a list of options. The gui asset has no real dropdown
-- element, so a button is reused: each click advances to the next option
-- and the current one is shown in the label.
function stuff:Dropdown(str, king, options, def, cb)
    local newBtn = elements.ButtonElement:Clone()
    newBtn.Parent = king

    options = options or {}

    local index = 1
    for i, opt in ipairs(options) do
        if opt == def then
            index = i
            break
        end
    end

    local function render()
        local current = options[index]
        newBtn.TextLabel.Text = str .. ": " .. tostring(current)
    end

    render()

    newBtn.MouseButton1Click:Connect(function()
        if #options == 0 then return end

        index = index % #options + 1
        render()

        if cb then
            cb(options[index], index)
        end
    end)

    return newBtn
end

-- A multi select list. The gui asset has no list element, so one toggle is
-- created per option and the callback always receives the full table of
-- everything that is currently ticked.
function stuff:MultiDropdown(str, king, options, def, cb)
    options = options or {}

    local selected = {}
    for _, v in ipairs(def or {}) do
        selected[tostring(v)] = true
    end

    local header = elements.LabelElement:Clone()
    header.Parent = king

    local function chosen()
        local out = {}

        -- keep the order of the option list, not the hash order
        for _, opt in ipairs(options) do
            if selected[tostring(opt)] then
                out[#out + 1] = opt
            end
        end

        return out
    end

    local function render()
        local picked = chosen()
        header.Text = str .. " (" .. #picked .. "/" .. #options .. ")"
    end

    render()

    for _, opt in ipairs(options) do
        local name = tostring(opt)
        local newTog = elements.ToggleElement:Clone()
        newTog.TextLabel.Text = "  " .. name
        newTog.Parent = king

        local on = selected[name] == true

        local function paint()
            if on then
                newTog.togglebg.BackgroundColor3 = Color3.fromRGB(59, 164, 57)
                newTog.togglebg.leftrightlol.AnchorPoint = Vector2.new(1, 0.5)
                newTog.togglebg.leftrightlol.Position = UDim2.new(1, 0, 0.5, 0)
            else
                newTog.togglebg.BackgroundColor3 = Color3.fromRGB(164, 58, 58)
                newTog.togglebg.leftrightlol.AnchorPoint = Vector2.new(0, 0.5)
                newTog.togglebg.leftrightlol.Position = UDim2.new(0, 0, 0.5, 0)
            end
        end

        paint()

        newTog.MouseButton1Click:Connect(function()
            on = not on
            selected[name] = on or nil

            paint()
            render()

            if cb then cb(chosen()) end
        end)
    end

    return {
        Get = chosen,
        Refresh = render,
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

function stuff:CredHead(king, txt)
    local newHead = elements.CreditHeader:Clone()
    newHead.Text = "> " .. txt
    newHead.Parent = king
end

function stuff:CredPerson(king, txt)
    local newCred = elements.CreditPerson:Clone()
    newCred.Text = "      + " .. txt
    newCred.Parent = king
end

return stuff
