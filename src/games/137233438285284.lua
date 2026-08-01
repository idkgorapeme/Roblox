-- chicken farm

return function(section, data)
    local elements = loadstring(getgenv().gitfetch and getgenv().gitfetch(getgitpath("src").."elements.lua") or game:HttpGet(getgitpath("src").."elements.lua"))()
    local env = getgenv()
    local plr = game:GetService("Players").LocalPlayer

    env.Farming = false

    local setdata = data[tostring(game.PlaceId)] or {}
    setdata.farming = setdata.farming or false
    data[tostring(game.PlaceId)] = setdata
    writefile("BrainrotPolice/Config.json", game:GetService("HttpService"):JSONEncode(data))

    local cashval = plr.PlayerGui.Main.Currencies.Cash.List.Amount

    local mainEvent = game:GetService("ReplicatedStorage").Paper.Remotes.__remoteevent
    local mainFunction = game:GetService("ReplicatedStorage").Paper.Remotes.__remotefunction
    local buyBtns = workspace.Plots[plr.Name].Buttons.BuyChickens

    -- workspace.Plots.<you>.Buttons.UpgradeBuyTier
    local function getTierBtn()
        local plots = workspace:FindFirstChild("Plots")
        local plot = plots and plots:FindFirstChild(plr.Name)
        local buttons = plot and plot:FindFirstChild("Buttons")
        return buttons and buttons:FindFirstChild("UpgradeBuyTier") or nil
    end

    local addedCon

    local suffixes = {
        "K","M","B","T","Qd","Qn","Sx","Sp","Oc","No","De",
        "UDe","DDe","TDe","QdDe","QnDe","SxDe","SpDe","OcDe","NoDe","Vt",
        "UVt","DVt","TVt","QdVt","QnVt","SxVt","SpVt","OcVt","NoVt","Tg",
        "UTg","DTg","TTg","QdTg","QnTg","SxTg","SpTg","OcTg","NoTg","qg",
        "Uqg","Dqg","Tqg","Qdqg","Qnqg","Sxqg","Spqg","Ocqg","Noqg","Qg",
        "UQg","DQg","TQg","QdQg","QnQg","SxQg","SpQg","OcQg","NoQg","sg",
        "Usg","Dsg","Tsg","Qdsg","Qnsg","Sxsg","Spsg","Ocsg","Nosg","Sg",
        "USg","DSg","TSg","QdSg","QnSg","SxSg","SpSg","OcSg","NoSg","Og",
        "UOg","DOg","TOg","QdOg","QnOg","SxOg","SpOg","OcOg","NoOg","Ng",
        "UNg","DNg","TNg","QdNg","QnNg","SxNg","SpNg","OcNg","NoNg","Ce","UCe"
    }

    local suffixValue = {}
    for i, suf in ipairs(suffixes) do
        suffixValue[suf] = 1000 ^ i
    end

    local function parseSuffixedNumber(str)
        str = str:gsub("[%$,%s]", "")

        local numberPart, suffixPart = str:match("^(-?%d*%.?%d+)(%a*)$")

        local base = tonumber(numberPart)

        if suffixPart == "" then
            return base
        end

        local multiplier = suffixValue[suffixPart]

        return base * multiplier
    end

    local suffixValue = {}
    for i, suf in ipairs(suffixes) do
        suffixValue[suf] = 1000 ^ i
    end

    elements:Label("BUY YOUR FIRST CHICKEN BEFORE AUTOFARMING (OTHERWISE WHOLE GAME BREAKS)")

    elements:Toggle("Autofarm", section, setdata.farming, function(v)
        env.setconfig("farmrots", v)

        env.Farming = v

        if not env.Farming then addedCon:Disconnect() return end

        for i, v in pairs(workspace.Eggs:GetChildren()) do
            mainEvent:FireServer(
                "Collect Egg",
                v.Name
            )
            task.wait()
            v:Destroy()
        end

        task.wait()

        mainFunction:InvokeServer(
            "Deposit Eggs"
        )

        addedCon = workspace.Eggs.ChildAdded:Connect(function(c)
            task.wait(1)
            mainEvent:FireServer(
                "Collect Egg",
                c.Name
            )
            task.wait()
            c:Destroy()
            mainFunction:InvokeServer(
                "Deposit Eggs"
            )
        end)

        while env.Farming do
            mainFunction:InvokeServer(
                "Collect Cash"
            )
            task.wait()
            mainFunction:InvokeServer(
                "Upgrade Process Level"
            )
            task.wait()
            local tobuy = 0
            local result = parseSuffixedNumber(cashval.Text)
            if parseSuffixedNumber(buyBtns.Buy100.Button.UI.Cost.Text) <= result  then
                tobuy = 100
            elseif parseSuffixedNumber(buyBtns.Buy25.Button.UI.Cost.Text) <= result then
                tobuy = 25
            elseif parseSuffixedNumber(buyBtns.Buy5.Button.UI.Cost.Text) <= result then
                tobuy = 5
            elseif parseSuffixedNumber(buyBtns.Buy1.Button.UI.Cost.Text) <= result then
                tobuy = 1
            end
            mainFunction:InvokeServer(
                "Buy Chickens",
                tobuy
            )
            task.wait()
            mainFunction:InvokeServer(
                "Merge Chickens"
            )
            task.wait()

            -- upgrade the buy tier once we can actually afford it
            pcall(function()
                local tierBtn = getTierBtn()
                if not tierBtn then return end

                local costLabel = tierBtn:FindFirstChild("Cost", true)
                local cost = costLabel and parseSuffixedNumber(costLabel.Text)

                -- if the cost label is unreadable just try anyway
                if not cost or cost <= parseSuffixedNumber(cashval.Text) then
                    mainFunction:InvokeServer(
                        "Upgrade Buy Tier Level"
                    )
                end
            end)

            task.wait(1)
        end
    end)
end
