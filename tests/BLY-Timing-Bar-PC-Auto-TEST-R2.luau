-- BLY Timing Bar TEST R2 | automatic GUI bar recognition | PC / Solara
-- Separate from BLY Smart Survival. Only reads visible UI positions and sends the configured input.
-- Detects visible GUI components only. Cannot see the pixels inside a single raster image.

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
if type(env.BLY_TIMING_R2_STOP) == "function" then pcall(env.BLY_TIMING_R2_STOP) end

local alive = true
local enabled = true
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
gui.Name = "BLY_TimingBar_R2"
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
title.Text = "BLY TIMING BAR  |  R2 AUTO"
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
statusText.Text = "يتعرف تلقائيا على الأخضر والخط المتحرك\nF8 = تشغيل/إيقاف"
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
local autoButton = button("Auto", 114, 102, "Auto: ON")
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
footer.Text = "أبحث عن Timing Bar تلقائيا..."
footer.Parent = panel

local function say(t)
    statusText.Text = tostring(t)
    print("[BLY Timing] " .. tostring(t))
end
-- R2 automatic detector: observe GUI elements over time and match green targets
-- to moving thin indicators in the same horizontal/vertical timing bar.
local tracks = setmetatable({}, {__mode = "k"})
local lastScan = 0
local pairScore = 0
local scanReport = ""
local seenPairs = 0
local lastChange = 0
local lastPosition = nil
local lastGreenPosition = nil

local function hasName(o, words)
    local label = string.lower(o.Name or "")
    for _, word in ipairs(words) do
        if string.find(label, word, 1, true) then return true end
    end
    return false
end

local function paintColors(o)
    local colors = {}
    if o.BackgroundTransparency < 0.90 then table.insert(colors, o.BackgroundColor3) end
    if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and o.ImageTransparency < 0.9 then
        table.insert(colors, o.ImageColor3)
    end
    for _, child in ipairs(o:GetChildren()) do
        if child:IsA("UIGradient") and child.Enabled then
            for _, key in ipairs(child.Color.Keypoints) do
                table.insert(colors, key.Value)
            end
        elseif child:IsA("UIStroke") and child.Enabled and child.Transparency < 0.65 then
            table.insert(colors, child.Color)
        end
    end
    return colors
end

local function looksGreen(c)
    return c.G >= 0.37 and c.G > c.R * 1.30 and c.G > c.B * 1.20
end
local function looksWhite(c)
    return c.R > 0.76 and c.G > 0.76 and c.B > 0.76 and
        math.max(c.R,c.G,c.B)-math.min(c.R,c.G,c.B) < 0.25
end

local function greenScore(o)
    local x1, y1, x2, y2, w, h = rect(o)
    if not w or w < 4 or h < 3 or w > 600 or h > 190 then return nil end
    local found = false
    for _, c in ipairs(paintColors(o)) do
        if looksGreen(c) then found = true break end
    end
    if not found then return nil end
    local result = 80
    if hasName(o, {"target","perfect","success","green","zone","hit","goal"}) then result = result + 30 end
    if w > h * 1.2 then result = result + 8 end
    if o:IsA("Frame") then result = result + 8 end
    return result
end

local function whiteScore(o)
    local x1,y1,x2,y2,w,h = rect(o)
    if not w or w < 1 or h < 1 or w > 500 or h > 500 then return nil end
    local thin = math.min(w,h)
    local long = math.max(w,h)
    if thin > 22 or long < 9 or long < thin*2.1 then return nil end
    local found = false
    for _, c in ipairs(paintColors(o)) do
        if looksWhite(c) then found = true break end
    end
    if not found then return nil end
    local score = 75 + math.min(24,long/math.max(1,thin))
    if hasName(o, {"marker","cursor","needle","line","indicator","pointer","slider"}) then score = score + 30 end
    return score
end

local function ownScan(o)
    if o == gui then return true end
    local ok, mine = pcall(function() return o:IsDescendantOf(gui) end)
    return ok and mine
end

local function getMotion(o, timestamp)
    local p = o.AbsolutePosition
    local now = tracks[o]
    if not now then
        now = { x=p.X, y=p.Y, t=timestamp, moves=0, lastMoving=0 }
        tracks[o] = now
        return now
    end
    local d = math.sqrt((p.X-now.x)^2 + (p.Y-now.y)^2)
    if d > 1.2 and d < 350 and timestamp-now.t <= 1.0 then
        now.moves = math.min(12,now.moves+1)
        now.lastMoving = timestamp
    elseif timestamp - now.lastMoving > 1.1 then
        now.moves = math.max(0,now.moves-1)
    end
    now.x,now.y,now.t = p.X,p.Y,timestamp
    return now
end

local function structuralBonus(a,b)
    local parents = {}
    local current = a
    for i=1,12 do
        if not current or current == pg then break end
        parents[current] = i
        current = current.Parent
    end
    current = b
    for i=1,12 do
        if not current or current == pg then break end
        if parents[current] then
            if current:IsA("ScreenGui") then return 5 end
            return 45 - math.min(25,parents[current]*2+i*2)
        end
        current = current.Parent
    end
    return 0
end

local function geometryScore(g,m)
    local gx1,gy1,gx2,gy2,gw,gh = rect(g)
    local mx1,my1,mx2,my2,mw,mh = rect(m)
    if not gx1 or not mx1 then return nil end
    local vertical = mh >= mw * 2.1
    local horizontal = mw >= mh * 2.1
    if not vertical and not horizontal then return nil end
    local gap, centerDist
    if vertical then
        -- A narrow vertical line crossing a green zone along a horizontal bar.
        gap = math.max(0,gy1-my2,my1-gy2)
        centerDist = math.abs((gx1+gx2-mx1-mx2)/2)
        if gap > math.max(24, gh*1.2) or centerDist > math.max(220,gw*2.8) then return nil end
        if gw < 7 then return nil end
    else
        gap = math.max(0,gx1-mx2,mx1-gx2)
        centerDist = math.abs((gy1+gy2-my1-my2)/2)
        if gap > math.max(24,gw*1.2) or centerDist > math.max(220,gh*2.8) then return nil end
        if gh < 7 then return nil end
    end
    return 22 - math.min(25,gap*0.6) - math.min(22,centerDist*0.045)
end

local function scanAutomatic()
    local now = os.clock()
    local greens, whites = {}, {}
    local nodes = pg:GetDescendants()
    local checked = 0
    for _, object in ipairs(nodes) do
        if checked >= 6500 then break end
        checked = checked + 1
        if object:IsA("GuiObject") and not ownScan(object) and visible(object) then
            -- Avoid green text or white text being mistaken for a bar.
            if not object:IsA("TextLabel") and not object:IsA("TextButton") and
                not object:IsA("TextBox") then
                local gs = greenScore(object)
                if gs then table.insert(greens,{obj=object,score=gs}) end
                local ws = whiteScore(object)
                if ws then table.insert(whites,{obj=object,score=ws}) end
                if gs or ws then getMotion(object,now) end
            end
        end
    end
    local bestG,bestM,best=nil,nil,-10000
    for _, g in ipairs(greens) do
        for _, m in ipairs(whites) do
            if g.obj ~= m.obj then
                local geom = geometryScore(g.obj,m.obj)
                if geom then
                    local gm,mm = tracks[g.obj],tracks[m.obj]
                    local moved = math.max(gm and gm.moves or 0,mm and mm.moves or 0)
                    local motionRecent = (gm and now-gm.lastMoving < 0.9) or
                        (mm and now-mm.lastMoving < 0.9)
                    local point = g.score+m.score+geom+structuralBonus(g.obj,m.obj)+
                        (motionRecent and 38 or 0)+math.min(45,moved*9)
                    if g.obj==green and m.obj==marker then point=point+42 end
                    if point > best then best=point;bestG=g.obj;bestM=m.obj end
                end
            end
        end
    end
    scanReport = "أخضر="..tostring(#greens).." أبيض="..tostring(#whites).." أزواج="..tostring(bestG and 1 or 0)
    if bestG and bestM and best > 165 then
        if bestG~=green or bestM~=marker then
            green,marker=bestG,bestM
            armed=false -- Do not click until line is observed outside the target first.
            lastPosition=nil
            lastGreenPosition=nil
            lastChange=0
            seenPairs=seenPairs+1
        end
        pairScore=best
    else
        if not visible(green) or not visible(marker) then
            green=nil; marker=nil; armed=false; pairScore=0
        end
    end
end

local function barState()
    if not green or not marker or not visible(green) or not visible(marker) then return nil end
    local gx1,gy1,gx2,gy2,gw,gh = rect(green)
    local mx1,my1,mx2,my2,mw,mh = rect(marker)
    if not gx1 or not mx1 then return nil end
    local horizontal = mh >= mw
    local start = horizontal and gx1 or gy1
    local finish = horizontal and gx2 or gy2
    local pos = horizontal and (mx1+mx2)/2 or (my1+my2)/2
    local greenPosition = horizontal and (gx1+gx2)/2 or (gy1+gy2)/2
    local perpendicular = horizontal and (my2 >= gy1-22 and my1 <= gy2+22)
        or (mx2 >= gx1-22 and mx1 <= gx2+22)
    local size = finish-start
    local inset = math.max(1,math.min(4,size*0.08))
    local inside = perpendicular and size >= 5 and pos >= start+inset and pos <= finish-inset
    return inside,pos,greenPosition,size
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
    if env.BLY_TIMING_R2_STOP == shutdown then env.BLY_TIMING_R2_STOP = nil end
end
env.BLY_TIMING_R2_STOP = shutdown

connect(modeButton.MouseButton1Click, function()
    mode = mode % #modes + 1
    modeButton.Text = "Input: " .. modes[mode]
end)
connect(autoButton.MouseButton1Click, function()
    enabled = not enabled
    armed = false
    autoButton.Text = enabled and "Auto: ON" or "Auto: OFF"
    say(enabled and "أبحث عن الخط الأبيض والأخضر تلقائيا..." or "توقف")
end)
connect(stopButton.MouseButton1Click, shutdown)
connect(UIS.InputBegan, function(input)
    if UIS:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F8 then
        enabled = not enabled
        armed = false
        autoButton.Text = enabled and "Auto: ON" or "Auto: OFF"
        say(enabled and "الكشف التلقائي شغال..." or "توقف")
    end
end)

local lastStatus = 0
local lastDiagnostic = 0
connect(RunService.RenderStepped, function()
    if not alive or not enabled then return end
    local now = os.clock()
    if now-lastScan>0.17 then
        lastScan=now
        local ok,err=pcall(scanAutomatic)
        if not ok and now-lastDiagnostic>2 then
            lastDiagnostic=now
            footer.Text="فشل فحص واجهة Roblox: "..tostring(err)
            warn("[BLY Timing R2] "..tostring(err))
        end
    end
    local inside,pos,gpos,size = barState()
    if inside==nil then
        if now-lastStatus>0.6 then
            lastStatus=now
            footer.Text="انتظار ظهور الشريط | "..scanReport
            statusText.Text="أبحث تلقائيا عن منطقة خضراء وخط أبيض متحرك.\nإذا ما تعرفت، قد يكون الشريط مرسوما داخل صورة واحدة."
        end
        return
    end
    local moving=false
    if lastPosition and lastGreenPosition then
        local relative=(pos-gpos)-(lastPosition-lastGreenPosition)
        if math.abs(relative)>0.65 and math.abs(relative)<350 then
            moving=true
            lastChange=now
        end
    end
    lastPosition=pos
    lastGreenPosition=gpos
    local recentMovement=now-lastChange<0.5
    -- Only arm after the moving line leaves the target. Never fire blindly on first sight.
    if not inside then armed=true end
    if now-lastStatus>0.2 then
        lastStatus=now
        statusText.Text="تعرفت على خط ومجال أخضر | "..modes[mode].."\n"..
            (recentMovement and "الحركة مرصودة" or "أنتظر حركة الخط").." | F8 إيقاف/تشغيل"
        footer.Text=(inside and "داخل الأخضر" or "انتظار التقاطع")..
            " | Hits: "..tostring(count).." | "..scanReport
    end
    if inside and armed and recentMovement and now-lastFire>0.35 then
        armed=false
        lastFire=now
        local ok,err=sendAction()
        if ok then
            count=count+1
            footer.Text="HIT "..tostring(count).." / "..modes[mode]
        else
            enabled=false
            autoButton.Text="Auto: OFF"
            say("Solara ما أرسل الضغطة: "..tostring(err)..". جرب Input ثاني.")
        end
    end
end)

say("R2: الكشف عن الأخضر والأبيض تلقائي. ما تحتاج F6/F7. افتح التحدي وانتظر التعرف.")
