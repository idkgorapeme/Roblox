-- +1 Shrink per Step

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    env.SSWin = false
    env.SSRebirth = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.autowin = setdata.autowin or false
    setdata.rebirth = setdata.rebirth or false
    setdata.room = setdata.room or "22"
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local MAX_ROOM = 22

    local room = tostring(setdata.room)

    local function getRoot()
        local char = plr.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    -- lazily resolved so a missing remote can never block the UI
    local function eventRemote(name)
        local folder = replicatedstorage:FindFirstChild("Events")
        return folder and folder:FindFirstChild(name) or nil
    end

    -- the Win part of a given room number
    local function getWinPart(number)
        local rooms = workspace:FindFirstChild("Rooms")
        local target = rooms and rooms:FindFirstChild(tostring(number))
        local win = target and target:FindFirstChild("Win")
        if not win then return nil end

        if win:IsA("BasePart") then
            return win
        end

        -- sometimes Win is a model or folder wrapping the actual part
        return win:FindFirstChildWhichIsA("BasePart", true)
    end

    ----------------------------------------------------------------
    -- auto win
    ----------------------------------------------------------------

    elements:Textbox("Win Room (0 - 22)", section, room, function(v)
        local n = tonumber(v)
        if not n then return end

        n = math.clamp(math.floor(n), 0, MAX_ROOM)
        room = tostring(n)
        env.setconfig("room", room)
    end)

    elements:Toggle("Auto Win", section, setdata.autowin, function(v)
        env.SSWin = v
        env.setconfig("autowin", v)
        if not v then return end

        task.spawn(function()
            local warned = false

            while env.SSWin do
                local win = getWinPart(room)
                local root = getRoot()

                if win and root then
                    warned = false

                    pcall(function()
                        -- stand on the win pad, a touch is what triggers it
                        root.CFrame = win.CFrame + Vector3.new(0, 3, 0)
                        root.AssemblyLinearVelocity = Vector3.zero

                        -- also fire the touch directly in case walking on it
                        -- is not registered while teleporting
                        if firetouchinterest then
                            local char = plr.Character
                            local hrp = char and char:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                firetouchinterest(hrp, win, 0)
                                firetouchinterest(hrp, win, 1)
                            end
                        end
                    end)
                elseif not warned then
                    warn("[BrainrotPolice] workspace.Rooms[\"" .. room .. "\"].Win not found")
                    warned = true
                end

                task.wait(0.1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- auto rebirth
    ----------------------------------------------------------------

    elements:Toggle("Auto Rebirth", section, setdata.rebirth, function(v)
        env.SSRebirth = v
        env.setconfig("rebirth", v)
        if not v then return end

        task.spawn(function()
            while env.SSRebirth do
                pcall(function()
                    local rf = eventRemote("Rebirth")
                    if rf then rf:InvokeServer() end
                end)

                task.wait(1)
            end
        end)
    end)

    ----------------------------------------------------------------
    -- dump: lists the Events folder so the remaining features can be added
    ----------------------------------------------------------------

    elements:Button("Dump Events (copies)", section, function()
        local out = {}
        local function add(line)
            out[#out + 1] = line
            print(line)
        end

        add("PlaceId: " .. tostring(game.PlaceId))

        local folder = replicatedstorage:FindFirstChild("Events")
        if folder then
            add("======== ReplicatedStorage.Events ========")
            for _, r in pairs(folder:GetDescendants()) do
                add(r.ClassName .. " | " .. r:GetFullName())
            end
        else
            add("no ReplicatedStorage.Events folder")
        end

        add("======== other remotes ========")
        for _, r in pairs(replicatedstorage:GetDescendants()) do
            if (r:IsA("RemoteEvent") or r:IsA("RemoteFunction"))
                and not r:IsDescendantOf(folder or workspace) then
                add(r.ClassName .. " | " .. r:GetFullName())
            end
        end

        local rooms = workspace:FindFirstChild("Rooms")
        if rooms then
            local names = {}
            for _, rm in pairs(rooms:GetChildren()) do
                names[#names + 1] = rm.Name
            end
            add("======== rooms ========")
            add(table.concat(names, ", "))
        end

        local text = table.concat(out, "\n")
        pcall(function()
            writefile("BrainrotPolice/dump_" .. tostring(game.PlaceId) .. ".txt", text)
        end)
        local copied = pcall(function() setclipboard(text) end)
        print("[BrainrotPolice] dump copied=" .. tostring(copied))
    end)
end
