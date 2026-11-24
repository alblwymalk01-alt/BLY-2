-- BLY Timing Bar TEST R1 | standalone UI timing assistant | PC / Solara
-- Separate from BLY Smart Survival. Only reads visible UI positions and sends the configured input.
-- If the bar is drawn as pixels inside one image/canvas, object detection may not work.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
assert(player, "BLY Timing: LocalPlayer missing")
local pg = player:WaitForChild("PlayerGui", 12)
assert(pg, "BLY Timing: PlayerGui missing")

local env = _G
pcall(function()
    if type(getgenv) == "function" then
        local g = getgenv()
        if type(g) == "table" then env = g end
    end
end)
if type(env.BLY_TIMING_R1_STOP) == "function" then pcall(env.BLY_TIMING_R1_STOP) end

local alive = true
local enabled = false
local green, marker
local greenPath, markerPath
local lastReacquire = 0
local mode = 1
local modes = {"Mouse", "Space", "E"}
local count = 0
local lastFire = -100
local armed = true
local previous = nil
local connections = {}
local gui = Instance.new("ScreenGui")
gui.Name = "BLY_TimingBar_R1"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 9000
gui.Parent = pg

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end
local function rect(o)
    if not o or not o.Parent or not o:IsA("GuiObject") then return nil end
    local p, s = o.AbsolutePosition, o.AbsoluteSize
    if s.X < 1 or s.Y < 1 then return nil end
    return p.X, p.Y, p.X + s.X, p.Y + s.Y, s.X, s.Y
end
local function visible(o)
    if not rect(o) then return false end
    local n = o
    while n and n ~= pg do
        if n:IsA("GuiObject") and not n.Visible then return false end
        if n:IsA("ScreenGui") and not n.Enabled then return false end
        n = n.Parent
    end
    return true
end
local function isMine(o)
    return o == gui or o:IsDescendantOf(gui)
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(355, 174)
panel.Position = UDim2.new(0, 14, 0, 80)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
panel.BorderSizePixel = 0
panel.Parent = gui
local round = Instance.new("UICorner")
round.CornerRadius = UDim.new(0, 9)
round.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(120, 120, 120)
stroke.Thickness = 1
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.fromOffset(342, 24)
title.Position = UDim2.fromOffset(10, 5)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Color3.new(1, 1, 1)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "BLY TIMING BAR  |  R1"
title.Parent = panel
local statusText = Instance.new("TextLabel")
statusText.BackgroundTransparency = 1
statusText.Size = UDim2.fromOffset(335, 64)
statusText.Position = UDim2.fromOffset(10, 32)
statusText.Font = Enum.Font.Code
statusText.TextSize = 12
statusText.TextWrapped = true
statusText.TextXAlignment = Enum.TextXAlignment.Left
statusText.TextYAlignment = Enum.TextYAlignment.Top
statusText.TextColor3 = Color3.fromRGB(225, 225, 225)
statusText.Text = "F6 = تحديد الأخضر | F7 = تحديد الأبيض\nF8 = تشغيل/إيقاف"
statusText.Parent = panel

local function button(name, x, width, text)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Size = UDim2.fromOffset(width, 29)
    b.Position = UDim2.fromOffset(x, 103)
    b.BackgroundColor3 = Color3.fromRGB(48, 48, 48)
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Text = text
    b.Parent = panel
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = b
    return b
end
local modeButton = button("Mode", 10, 98, "Input: Mouse")
local autoButton = button("Auto", 114, 102, "Auto: OFF")
local stopButton = button("Close", 222, 119, "إغلاق X")
local footer = Instance.new("TextLabel")
footer.BackgroundTransparency = 1
footer.Size = UDim2.fromOffset(337, 31)
footer.Position = UDim2.fromOffset(10, 139)
footer.TextColor3 = Color3.fromRGB(195, 195, 195)
footer.Font = Enum.Font.Code
footer.TextSize = 12
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.TextWrapped = true
footer.Text = "اختار العنصرين قبل تشغيل Auto"
footer.Parent = panel

local function say(t)
    statusText.Text = tostring(t)
    print("[BLY Timing] " .. tostring(t))
end
local function colorOf(o)
    local colors = {}
    if o:IsA("ImageLabel") or o:IsA("ImageButton") then
        if o.ImageTransparency < 0.94 then table.insert(colors, o.ImageColor3) end
    end
    if o.BackgroundTransparency < 0.94 then table.insert(colors, o.BackgroundColor3) end
    if o:IsA("TextLabel") or o:IsA("TextButton") then
        if o.TextTransparency < 0.85 and o.Text ~= "" then table.insert(colors, o.TextColor3) end
    end
    return colors
end
local function greenScore(o)
    local _, _, _, _, w, h = rect(o)
    if not w or w > 1000 or h > 350 then return -999 end
    local best = -999
    for _, c in ipairs(colorOf(o)) do
        if c.G > 0.38 and c.G > c.R * 1.28 and c.G > c.B * 1.20 then
            best = math.max(best, 100 + 0.05 * math.min(250, w) - 0.002 * (w * h))
        end
    end
    return best
end
local function whiteScore(o)
    local _, _, _, _, w, h = rect(o)
    if not w or w > 90 or h > 420 then return -999 end
    local thin = math.min(w, h)
    local long = math.max(w, h)
    if thin > 22 or long < 9 or long < thin * 1.7 then return -999 end
    local light = false
    for _, c in ipairs(colorOf(o)) do
        if c.R > 0.70 and c.G > 0.70 and c.B > 0.70 then light = true break end
    end
    return (light and 130 or 15) + math.min(long / math.max(thin, 1), 30)
end
local function atMouse()
    local p = UIS:GetMouseLocation()
    local hits = {}
    local ok, objects = pcall(function()
        return pg:GetGuiObjectsAtPosition(math.floor(p.X), math.floor(p.Y))
    end)
    if ok and type(objects) == "table" then
        for _, o in ipairs(objects) do
            if o:IsA("GuiObject") and not isMine(o) and visible(o) then
                table.insert(hits, o)
            end
        end
    end
    -- A fallback for executor clients where the hit-testing API is unavailable.
    if #hits == 0 then
        for _, o in ipairs(pg:GetDescendants()) do
            if o:IsA("GuiObject") and not isMine(o) and visible(o) then
                local x1, y1, x2, y2 = rect(o)
                if x1 and p.X >= x1 and p.X <= x2 and
                    ((p.Y >= y1 and p.Y <= y2) or (p.Y - 36 >= y1 and p.Y - 36 <= y2)) then
                    table.insert(hits, o)
                end
            end
        end
    end
    return hits
end
local function pathKey(object)
    local names = {}
    local current = object
    while current and current ~= pg do
        table.insert(names, 1, current.Name)
        current = current.Parent
    end
    return table.concat(names, "/")
end
local function reacquire(kind)
    local wanted = kind == "green" and greenPath or markerPath
    if not wanted then return nil end
    for _, o in ipairs(pg:GetDescendants()) do
        if o:IsA("GuiObject") and not isMine(o) and pathKey(o) == wanted then
            if visible(o) and (kind == "green" and greenScore(o) > 50 or
                kind == "white" and whiteScore(o) > 30) then
                return o
            end
        end
    end
end
local function selectPart(kind)
    local best, bestScore
    for _, o in ipairs(atMouse()) do
        local score = kind == "green" and greenScore(o) or whiteScore(o)
        if not bestScore or score > bestScore then best, bestScore = o, score end
    end
    local threshold = kind == "green" and 50 or 30
    if not best or bestScore < threshold then
        say("ما تعرفت على " .. (kind == "green" and "المنطقة الخضراء" or "الخط الأبيض") ..
            ". حط مؤشر الماوس فوقها مباشرة وجرب من جديد.")
        return
    end
    if kind == "green" then
        green = best
        greenPath = pathKey(best)
    else
        marker = best
        markerPath = pathKey(best)
    end
    armed = true
    enabled = false
    autoButton.Text = "Auto: OFF"
    say((kind == "green" and "Green" or "White") .. " selected: " .. best.Name ..
        "\nF6 فوق الأخضر | F7 فوق الأبيض | F8 تشغيل")
end

local function sendAction()
    local selection = modes[mode]
    if selection == "Mouse" then
        if type(mouse1click) == "function" then
            return pcall(mouse1click)
        end
        local api = rawget(env, "Input")
        if type(api) == "table" and type(api.LeftClick) == "function" then
            return pcall(api.LeftClick)
        end
        local ok, vim = pcall(function() return game:GetService("VirtualInputManager") end)
        if ok and vim then
            local p = UIS:GetMouseLocation()
            return pcall(function()
                vim:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
                vim:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
            end)
        end
        return false, "mouse1click not supported"
    end
    local vk = selection == "Space" and 0x20 or 0x45
    local key = selection == "Space" and Enum.KeyCode.Space or Enum.KeyCode.E
    if type(keyclick) == "function" then return pcall(keyclick, vk) end
    local api = rawget(env, "Input")
    if type(api) == "table" and type(api.KeyPress) == "function" then
        return pcall(api.KeyPress, vk)
    end
    if type(keypress) == "function" then
        local ok, err = pcall(keypress, vk)
        if not ok then return false, err end
        if type(keyrelease) == "function" then
            task.delay(0.05, function() pcall(keyrelease, vk) end)
        end
        return true
    end
    local ok, vim = pcall(function() return game:GetService("VirtualInputManager") end)
    if ok and vim then
        return pcall(function()
            vim:SendKeyEvent(true, key, false, game)
            task.delay(0.05, function() vim:SendKeyEvent(false, key, false, game) end)
        end)
    end
    return false, "key input unsupported"
end

local function shutdown()
    alive = false
    enabled = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if gui and gui.Parent then gui:Destroy() end
    if env.BLY_TIMING_R1_STOP == shutdown then env.BLY_TIMING_R1_STOP = nil end
end
env.BLY_TIMING_R1_STOP = shutdown

connect(modeButton.MouseButton1Click, function()
    mode = mode % #modes + 1
    modeButton.Text = "Input: " .. modes[mode]
end)
connect(autoButton.MouseButton1Click, function()
    if not green or not marker then say("حدد الأخضر F6 والأبيض F7 أول") return end
    enabled = not enabled
    armed = true
    autoButton.Text = enabled and "Auto: ON" or "Auto: OFF"
    say(enabled and "أراقب المنطقة الخضراء..." or "توقف")
end)
connect(stopButton.MouseButton1Click, shutdown)
connect(UIS.InputBegan, function(input, processed)
    if UIS:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F6 then selectPart("green")
    elseif input.KeyCode == Enum.KeyCode.F7 then selectPart("white")
    elseif input.KeyCode == Enum.KeyCode.F8 then
        if not green or not marker then say("حدد الأخضر F6 والأبيض F7 أول") return end
        enabled = not enabled
        armed = true
        autoButton.Text = enabled and "Auto: ON" or "Auto: OFF"
        say(enabled and "أراقب المنطقة الخضراء..." or "توقف")
    end
end)

local lastStatus = 0
connect(RunService.RenderStepped, function()
    if not alive or not enabled then return end
    if not visible(green) or not visible(marker) then
        if os.clock() - lastReacquire >= 0.7 then
            lastReacquire = os.clock()
            if not visible(green) then green = reacquire("green") end
            if not visible(marker) then marker = reacquire("white") end
        end
        if os.clock() - lastStatus > 1.2 then
            lastStatus = os.clock()
            footer.Text = "البار مخفي/اختفى. بانتظار ظهوره..."
        end
        armed = true
        return
    end
    local gx1, gy1, gx2, gy2, gw, gh = rect(green)
    local mx1, my1, mx2, my2, mw, mh = rect(marker)
    if not gx1 or not mx1 then return end
    local verticalLine = mh >= mw
    local axis = verticalLine and "X" or "Y"
    local start = verticalLine and gx1 or gy1
    local finish = verticalLine and gx2 or gy2
    local linePos = verticalLine and (mx1 + mx2) / 2 or (my1 + my2) / 2
    local width = finish - start
    local inner = math.min(width * 0.19, math.max(1.5, width * 0.37))
    local inside = width > 3 and linePos >= start + inner and linePos <= finish - inner
    -- The marker and zone must sit on the same bar, not on unrelated UI rows.
    local perpendicular = verticalLine and
        (my2 >= gy1 - 12 and my1 <= gy2 + 12) or
        (mx2 >= gx1 - 12 and mx1 <= gx2 + 12)
    if not perpendicular then inside = false end
    if not inside then armed = true end
    local now = os.clock()
    if now - lastStatus > 0.15 then
        lastStatus = now
        footer.Text = (inside and "داخل الأخضر" or "انتظار") .. " | " .. axis ..
            " | Input " .. modes[mode] .. " | Hits: " .. tostring(count)
    end
    if inside and armed and now - lastFire > 0.28 then
        armed = false
        lastFire = now
        local ok, err = sendAction()
        if ok then
            count = count + 1
            footer.Text = "HIT " .. tostring(count) .. " / " .. modes[mode]
        else
            enabled = false
            autoButton.Text = "Auto: OFF"
            say("ما قدر يضغط: " .. tostring(err) .. "\nجرب Input ثاني")
        end
    end
end)

say("حط الماوس فوق الأخضر واضغط F6، ثم فوق الأبيض واضغط F7.\nبعدها اختر Mouse/Space/E وشغل F8")
