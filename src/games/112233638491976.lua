-- Unbox ASMR!

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
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

    elements:Label("No features yet, coming soon", section)

    -- features go here
end
