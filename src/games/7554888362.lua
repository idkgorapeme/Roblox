-- Squid Game X

return function(section, data)
    local elements = loadstring(game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()

    local players = game:GetService("Players")
    local plr = players.LocalPlayer

    env.Kill = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.kill = setdata.kill or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    -- 3 studs in front of the local player (-Z is forward) and 4 studs up
    local frontOffset = CFrame.new(0, 4, -3)

    local function getRoot(character)
        if not character then return nil end
        return character:FindFirstChild("HumanoidRootPart")
    end

    elements:Toggle("Kill", section, setdata.kill, function(v)
        env.Kill = v
        env.setconfig("kill", v)
        if not env.Kill then return end

        while env.Kill do
            pcall(function()
                local myRoot = getRoot(plr.Character)
                if not myRoot then return end

                local target = myRoot.CFrame * frontOffset

                for _, other in pairs(players:GetPlayers()) do
                    if other ~= plr then
                        local root = getRoot(other.Character)
                        if root then
                            -- fully local, no remotes: client side CFrame only
                            root.CFrame = target
                            root.AssemblyLinearVelocity = Vector3.zero
                            root.AssemblyAngularVelocity = Vector3.zero
                        end
                    end
                end
            end)

            task.wait(0.05)
        end
    end)
end
