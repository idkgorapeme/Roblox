-- Drill Blocks for Brainrots

return function(section, data)
    local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local replicatedstorage = game:GetService("ReplicatedStorage")
    local plr = players.LocalPlayer

    local setdata = data[tostring(game.PlaceId)] or {}
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local function getRoot(character)
        if not character then return nil end
        return character:FindFirstChild("HumanoidRootPart")
    end

    elements:Label("No features yet, dump the game first", section)

    -- Collects the game structure, copies it to the clipboard and also writes
    -- it to a file in case the executor has no setclipboard.
    elements:Button("Dump Game Structure (copies)", section, function()
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

        add("")
        add("======== workspace ========")
        for _, child in pairs(workspace:GetChildren()) do
            add(child.ClassName, "|", child.Name)
        end

        add("")
        add("======== ReplicatedStorage ========")
        for _, child in pairs(replicatedstorage:GetChildren()) do
            add(child.ClassName, "|", child.Name)
        end

        add("")
        add("======== remotes ========")
        local n = 0
        for _, r in pairs(replicatedstorage:GetDescendants()) do
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
        local ls = plr:FindFirstChild("leaderstats")
        if ls then
            for _, stat in pairs(ls:GetChildren()) do
                add(stat.Name, "=", tostring(stat.Value))
            end
        else
            add("no leaderstats")
        end

        add("")
        add("======== player attributes ========")
        local attrs = plr:GetAttributes()
        if next(attrs) == nil then
            add("none")
        else
            for k, v in pairs(attrs) do
                add(k, "=", tostring(v))
            end
        end

        local text = table.concat(out, "\n")

        -- always print so it is visible in the console too
        print(text)

        -- save a copy on disk, the clipboard can silently fail or get overwritten
        local path = "BrainrotPolice/dump_" .. tostring(game.PlaceId) .. ".txt"
        local savedOk = pcall(function()
            writefile(path, text)
        end)

        local copiedOk = pcall(function()
            setclipboard(text)
        end)

        if copiedOk then
            print("[BrainrotPolice] dump copied to clipboard (" .. #text .. " chars)")
        else
            warn("[BrainrotPolice] setclipboard not available")
        end

        if savedOk then
            print("[BrainrotPolice] dump also saved to " .. path)
        end
    end)

    -- features go here once we know the remotes
end
