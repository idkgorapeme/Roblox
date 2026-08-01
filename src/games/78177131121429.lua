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

    -- Prints the top level structure of the game so we can see what to hook.
    -- Run this in game, then send the console output over.
    elements:Button("Dump Game Structure", section, function()
        print("======== workspace ========")
        for _, child in pairs(workspace:GetChildren()) do
            print(child.ClassName, "|", child.Name)
        end

        print("======== ReplicatedStorage ========")
        for _, child in pairs(replicatedstorage:GetChildren()) do
            print(child.ClassName, "|", child.Name)
        end

        local remotes = replicatedstorage:FindFirstChild("Remotes")
            or replicatedstorage:FindFirstChild("Events")
            or replicatedstorage:FindFirstChild("Network")

        if remotes then
            print("======== remote folder:", remotes.Name, "========")
            for _, r in pairs(remotes:GetDescendants()) do
                if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then
                    print(r.ClassName, "|", r:GetFullName())
                end
            end
        else
            print("no obvious remote folder, scanning ReplicatedStorage")
            local n = 0
            for _, r in pairs(replicatedstorage:GetDescendants()) do
                if r:IsA("RemoteEvent") or r:IsA("RemoteFunction") then
                    n = n + 1
                    if n <= 60 then
                        print(r.ClassName, "|", r:GetFullName())
                    end
                end
            end
            print("total remotes found:", n)
        end

        print("======== leaderstats ========")
        local ls = plr:FindFirstChild("leaderstats")
        if ls then
            for _, stat in pairs(ls:GetChildren()) do
                print(stat.Name, "=", stat.Value)
            end
        else
            print("no leaderstats")
        end
    end)

    -- features go here once we know the remotes
end
