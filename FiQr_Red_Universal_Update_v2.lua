--[[
    FiQr Red Universal - developer test panel (v2)
    Install as a LocalScript in StarterPlayer > StarterPlayerScripts.

    SAFETY / SCOPE:
    - This client panel has no local UserId allowlist. Only add it to your own experience.
    - It is intended for your own Roblox experience, not for use in other experiences.
    - Client-only effects (Godmode, Invisible, Hitbox Test Area, etc.) are local simulations.
      For multiplayer-authoritative behavior, implement matching server-side checks in a
      Script under ServerScriptService and validate every request there.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local COLORS = {
    Background = Color3.fromRGB(12, 12, 16),
    Panel = Color3.fromRGB(20, 20, 26),
    Section = Color3.fromRGB(27, 27, 35),
    Section2 = Color3.fromRGB(33, 33, 42),
    Red = Color3.fromRGB(235, 45, 65),
    RedDark = Color3.fromRGB(130, 25, 40),
    RedSoft = Color3.fromRGB(255, 83, 98),
    ESPWhite = Color3.fromRGB(245, 248, 255),
    Tracer = Color3.fromRGB(80, 220, 255),
    Text = Color3.fromRGB(245, 245, 248),
    Muted = Color3.fromRGB(155, 155, 168),
    Track = Color3.fromRGB(55, 55, 66),
    Green = Color3.fromRGB(87, 220, 145),
}

local state = {
    playerESP = false,
    npcESP = false,
    nameESP = false,
    skeletonESP = false,
    aimAssist = false,
    aimPart = "Head",
    aimHold = false,
    aimKey = Enum.KeyCode.LeftAlt,
    aimFOV = 160,
    aimSmoothness = 12,
    wallCheck = true,
    infiniteJump = false,
    tracers = false,
    loopTeleport = false,
    antiAFK = false,
    hitbox = false,
    hitboxScale = 2,
    speed = false,
    speedValue = 32,
    jump = false,
    jumpValue = 80,
    fly = false,
    flySpeed = 45,
    noclip = false,
    clickTeleport = false,
    fullbright = false,
    customTime = false,
    timeValue = 14,
    showStats = true,
    fov = false,
    fovValue = 90,
    swimAir = false,
    spinbot = false,
    spinSpeed = 10,
    godmode = false,
    invisible = false,
    spectating = false,
}

local selectedTarget = nil
local savedWaypoint = nil
local cachedTargets = {}
local espRegistry = {}
local tracerGui = {}
local hitboxAdornments = {}
local savedTransparency = {}
local savedCollision = {}
local flyAttachment = nil
local flyVelocity = nil
local fullbrightOriginal = nil
local originalClockTime = Lighting.ClockTime
local characterDefaults = nil
local currentSpectateHumanoid = nil
local updateStatus

local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid(model)
    return model and model:FindFirstChildOfClass("Humanoid") or nil
end

local function getRoot(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
end

local function getHead(model)
    return model and model:FindFirstChild("Head") or nil
end

local function getBodyPart(model)
    if not model then return nil end
    return model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or getRoot(model)
end

local function isAliveModel(model)
    local hum = getHumanoid(model)
    local root = getRoot(model)
    return model and model:IsA("Model") and hum and root and hum.Health > 0
end

local function refreshTargetCache()
    local result = {}
    local seen = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and isAliveModel(player.Character) then
            seen[player.Character] = true
            table.insert(result, { model = player.Character, player = player, kind = "PLAYER" })
        end
    end
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("Model") and not seen[inst] and inst ~= getCharacter() and isAliveModel(inst) then
            if not Players:GetPlayerFromCharacter(inst) then
                seen[inst] = true
                table.insert(result, { model = inst, player = nil, kind = "NPC" })
            end
        end
    end
    table.sort(result, function(a, b)
        local an = a.player and a.player.DisplayName or a.model.Name
        local bn = b.player and b.player.DisplayName or b.model.Name
        return string.lower(an) < string.lower(bn)
    end)
    cachedTargets = result
    return result
end

local function getAllTargets()
    if #cachedTargets == 0 then
        return refreshTargetCache()
    end
    return cachedTargets
end

local function findSelectedEntry()
    if not selectedTarget or not selectedTarget.Parent or not isAliveModel(selectedTarget) then
        selectedTarget = nil
        return nil
    end
    local player = Players:GetPlayerFromCharacter(selectedTarget)
    return {
        model = selectedTarget,
        player = player,
        kind = player and "PLAYER" or "NPC",
    }
end

local function getSelectedName()
    local entry = findSelectedEntry()
    if not entry then return "No target selected" end
    local name = entry.player and (entry.player.DisplayName .. " (" .. entry.player.Name .. ")") or entry.model.Name
    return entry.kind .. ": " .. name
end

local function getAimPart(model)
    if state.aimPart == "Head" then
        return getHead(model) or getBodyPart(model)
    end
    return getBodyPart(model) or getHead(model)
end

local function setStatus(message, good)
    if updateStatus then
        updateStatus(message, good)
    end
end

-- UI -------------------------------------------------------------------------
local oldGui = PlayerGui:FindFirstChild("FiQrRedUniversal")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "FiQrRedUniversal"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PlayerGui

-- Performance Stats Overlay (FPS & Ping)
local statsLabel = Instance.new("TextLabel")
statsLabel.Name = "FiQrStats"
statsLabel.Size = UDim2.fromOffset(145, 26)
statsLabel.Position = UDim2.new(1, -165, 0, 14)
statsLabel.BackgroundColor3 = COLORS.Panel
statsLabel.BackgroundTransparency = 0.15
statsLabel.TextColor3 = COLORS.Green
statsLabel.Font = Enum.Font.GothamBold
statsLabel.TextSize = 11
statsLabel.Text = "FPS: 60  |  0 ms"
statsLabel.Visible = state.showStats
statsLabel.ZIndex = 10
statsLabel.Parent = gui
Instance.new("UICorner", statsLabel).CornerRadius = UDim.new(0, 7)
local statsStroke = Instance.new("UIStroke")
statsStroke.Color = COLORS.RedDark
statsStroke.Thickness = 1
statsStroke.Parent = statsLabel

-- Aimbot FOV Circle Overlay
local fovCircle = Instance.new("Frame")
fovCircle.Name = "FiQrAimFOV"
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Position = UDim2.fromScale(0.5, 0.5)
fovCircle.Size = UDim2.fromOffset(state.aimFOV * 2, state.aimFOV * 2)
fovCircle.BackgroundTransparency = 1
fovCircle.Visible = false
fovCircle.ZIndex = 3
fovCircle.Parent = gui
Instance.new("UICorner", fovCircle).CornerRadius = UDim.new(1, 0)
local fovStroke = Instance.new("UIStroke")
fovStroke.Color = COLORS.RedSoft
fovStroke.Thickness = 1.2
fovStroke.Transparency = 0.45
fovStroke.Parent = fovCircle

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(365, 590)
main.Position = UDim2.new(0, 28, 0.5, -295)
main.BackgroundColor3 = COLORS.Background
main.BorderSizePixel = 0
main.ZIndex = 5
main.Parent = gui
local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = main
local mainStroke = Instance.new("UIStroke")
mainStroke.Color = COLORS.RedDark
mainStroke.Thickness = 1.4
mainStroke.Transparency = 0.08
mainStroke.Parent = main

local top = Instance.new("Frame")
top.Name = "TopBar"
top.Size = UDim2.new(1, 0, 0, 54)
top.BackgroundColor3 = COLORS.Panel
top.BorderSizePixel = 0
top.Parent = main
local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 12)
topCorner.Parent = top
local topCover = Instance.new("Frame")
topCover.Size = UDim2.new(1, 0, 0, 12)
topCover.Position = UDim2.new(0, 0, 1, -12)
topCover.BackgroundColor3 = COLORS.Panel
topCover.BorderSizePixel = 0
topCover.Parent = top

local accent = Instance.new("Frame")
accent.Size = UDim2.new(0, 4, 0, 26)
accent.Position = UDim2.new(0, 14, 0, 14)
accent.BackgroundColor3 = COLORS.Red
accent.BorderSizePixel = 0
accent.Parent = top
local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(1, 0)
accentCorner.Parent = accent

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 27, 0, 7)
title.Size = UDim2.new(0, 180, 0, 25)
title.Font = Enum.Font.GothamBold
title.Text = "FiQr"
title.TextColor3 = COLORS.Text
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = top

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.new(0, 28, 0, 31)
subtitle.Size = UDim2.new(0, 210, 0, 14)
subtitle.Font = Enum.Font.GothamMedium
subtitle.Text = "RED UNIVERSAL v2  •  STUDIO TEST"
subtitle.TextColor3 = COLORS.RedSoft
subtitle.TextSize = 9
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = top

local minimize = Instance.new("TextButton")
minimize.Size = UDim2.fromOffset(28, 28)
minimize.Position = UDim2.new(1, -70, 0, 13)
minimize.BackgroundColor3 = COLORS.Section2
minimize.Text = "—"
minimize.TextColor3 = COLORS.Text
minimize.Font = Enum.Font.GothamBold
minimize.TextSize = 16
minimize.AutoButtonColor = true
minimize.Parent = top
Instance.new("UICorner", minimize).CornerRadius = UDim.new(0, 7)

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(28, 28)
close.Position = UDim2.new(1, -36, 0, 13)
close.BackgroundColor3 = COLORS.RedDark
close.Text = "×"
close.TextColor3 = COLORS.Text
close.Font = Enum.Font.GothamBold
close.TextSize = 19
close.AutoButtonColor = true
close.Parent = top
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 7)
close.MouseButton1Click:Connect(function()
    main.Visible = not main.Visible
end)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
    end
end)

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Content"
scroll.Position = UDim2.new(0, 0, 0, 62)
scroll.Size = UDim2.new(1, 0, 1, -99)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = COLORS.Red
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main

local content = Instance.new("Frame")
content.Name = "ContentHolder"
content.BackgroundTransparency = 1
content.Size = UDim2.new(1, -14, 0, 0)
content.Position = UDim2.fromOffset(7, 0)
content.AutomaticSize = Enum.AutomaticSize.Y
content.Parent = scroll
local contentLayout = Instance.new("UIListLayout")
contentLayout.Padding = UDim.new(0, 8)
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Parent = content
local contentPadding = Instance.new("UIPadding")
contentPadding.PaddingTop = UDim.new(0, 5)
contentPadding.PaddingBottom = UDim.new(0, 9)
contentPadding.PaddingLeft = UDim.new(0, 3)
contentPadding.PaddingRight = UDim.new(0, 3)
contentPadding.Parent = content

local footer = Instance.new("Frame")
footer.Position = UDim2.new(0, 0, 1, -32)
footer.Size = UDim2.new(1, 0, 0, 32)
footer.BackgroundColor3 = COLORS.Panel
footer.BorderSizePixel = 0
footer.Parent = main
local footerCorner = Instance.new("UICorner")
footerCorner.CornerRadius = UDim.new(0, 10)
footerCorner.Parent = footer
local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(12, 0)
status.Size = UDim2.new(1, -24, 1, 0)
status.Font = Enum.Font.GothamMedium
status.Text = "● READY  •  Studio developer tools"
status.TextColor3 = COLORS.Green
status.TextSize = 10
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = footer
updateStatus = function(message, good)
    status.Text = "● " .. string.upper(message)
    status.TextColor3 = good == false and COLORS.RedSoft or COLORS.Green
end

local function makeSection(label)
    local section = Instance.new("Frame")
    section.Name = label:gsub("%W", "")
    section.BackgroundColor3 = COLORS.Panel
    section.BorderSizePixel = 0
    section.Size = UDim2.new(1, 0, 0, 0)
    section.AutomaticSize = Enum.AutomaticSize.Y
    section.Parent = content
    Instance.new("UICorner", section).CornerRadius = UDim.new(0, 9)
    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.Section2
    stroke.Thickness = 1
    stroke.Transparency = 0.25
    stroke.Parent = section

    local inner = Instance.new("Frame")
    inner.BackgroundTransparency = 1
    inner.Position = UDim2.fromOffset(10, 8)
    inner.Size = UDim2.new(1, -20, 0, 0)
    inner.AutomaticSize = Enum.AutomaticSize.Y
    inner.Parent = section
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 7)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = inner
    local pad = Instance.new("UIPadding")
    pad.PaddingBottom = UDim.new(0, 10)
    pad.Parent = inner

    local heading = Instance.new("TextLabel")
    heading.BackgroundTransparency = 1
    heading.Size = UDim2.new(1, 0, 0, 18)
    heading.Font = Enum.Font.GothamBold
    heading.Text = string.upper(label)
    heading.TextColor3 = COLORS.RedSoft
    heading.TextSize = 10
    heading.TextXAlignment = Enum.TextXAlignment.Left
    heading.Parent = inner
    return inner
end

local function makeButton(parent, text, callback, width)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(width or 1, width and 0 or 0, 0, 32)
    button.BackgroundColor3 = COLORS.Section2
    button.BorderSizePixel = 0
    button.AutoButtonColor = true
    button.Font = Enum.Font.GothamSemibold
    button.Text = text
    button.TextColor3 = COLORS.Text
    button.TextSize = 11
    button.Parent = parent
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.Track
    stroke.Thickness = 1
    stroke.Transparency = 0.25
    stroke.Parent = button
    button.MouseButton1Click:Connect(callback)
    return button
end

local toggleSetters = {}

local function makeToggle(parent, label, initial, callback)
    local row = Instance.new("Frame")
    row.BackgroundColor3 = COLORS.Section
    row.BorderSizePixel = 0
    row.Size = UDim2.new(1, 0, 0, 34)
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Position = UDim2.fromOffset(10, 0)
    text.Size = UDim2.new(1, -75, 1, 0)
    text.Font = Enum.Font.GothamMedium
    text.Text = label
    text.TextColor3 = COLORS.Text
    text.TextSize = 11
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.Parent = row

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.fromOffset(48, 22)
    toggle.Position = UDim2.new(1, -58, 0.5, -11)
    toggle.BackgroundColor3 = initial and COLORS.Red or COLORS.Track
    toggle.BorderSizePixel = 0
    toggle.Text = initial and "ON" or "OFF"
    toggle.TextColor3 = COLORS.Text
    toggle.TextSize = 9
    toggle.Font = Enum.Font.GothamBold
    toggle.Parent = row
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(1, 0)

    local enabled = initial
    local function render()
        toggle.BackgroundColor3 = enabled and COLORS.Red or COLORS.Track
        toggle.Text = enabled and "ON" or "OFF"
    end
    local function setValue(value)
        enabled = value
        render()
        callback(enabled)
    end
    toggle.MouseButton1Click:Connect(function()
        setValue(not enabled)
    end)
    toggleSetters[label] = setValue
    return setValue
end

local function makeSlider(parent, label, minimum, maximum, initial, callback)
    local wrap = Instance.new("Frame")
    wrap.BackgroundColor3 = COLORS.Section
    wrap.BorderSizePixel = 0
    wrap.Size = UDim2.new(1, 0, 0, 52)
    wrap.Parent = parent
    Instance.new("UICorner", wrap).CornerRadius = UDim.new(0, 7)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.fromOffset(10, 4)
    titleLabel.Size = UDim2.new(1, -70, 0, 17)
    titleLabel.Font = Enum.Font.GothamMedium
    titleLabel.Text = label
    titleLabel.TextColor3 = COLORS.Text
    titleLabel.TextSize = 10
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = wrap

    local valueLabel = Instance.new("TextLabel")
    valueLabel.BackgroundTransparency = 1
    valueLabel.Position = UDim2.new(1, -58, 0, 4)
    valueLabel.Size = UDim2.fromOffset(48, 17)
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.Text = tostring(initial)
    valueLabel.TextColor3 = COLORS.RedSoft
    valueLabel.TextSize = 10
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = wrap

    local track = Instance.new("TextButton")
    track.Text = ""
    track.AutoButtonColor = false
    track.Position = UDim2.new(0, 10, 0, 30)
    track.Size = UDim2.new(1, -20, 0, 8)
    track.BackgroundColor3 = COLORS.Track
    track.BorderSizePixel = 0
    track.Parent = wrap
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = COLORS.Red
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new((initial - minimum) / (maximum - minimum), 0, 1, 0)
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local dragging = false
    local value = initial
    local function update(x)
        local width = math.max(track.AbsoluteSize.X, 1)
        local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
        value = math.floor(minimum + (maximum - minimum) * alpha + 0.5)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        valueLabel.Text = tostring(value)
        callback(value)
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    return function(newValue)
        value = math.clamp(newValue, minimum, maximum)
        local alpha = (value - minimum) / (maximum - minimum)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        valueLabel.Text = tostring(value)
        callback(value)
    end
end

-- Drag the window from its top bar.
do
    local dragging = false
    local dragStart, startPosition
    top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local minimized = false
minimize.MouseButton1Click:Connect(function()
    minimized = not minimized
    scroll.Visible = not minimized
    footer.Visible = not minimized
    main.Size = minimized and UDim2.fromOffset(365, 54) or UDim2.fromOffset(365, 590)
    minimize.Text = minimized and "+" or "—"
end)

-- Character effect helpers ---------------------------------------------------
local function captureCharacterDefaults()
    local character = getCharacter()
    local hum = getHumanoid(character)
    if hum then
        characterDefaults = {
            WalkSpeed = hum.WalkSpeed,
            UseJumpPower = hum.UseJumpPower,
            JumpPower = hum.JumpPower,
            JumpHeight = hum.JumpHeight,
            AutoRotate = hum.AutoRotate,
        }
    end
end

local function applyMovement()
    local hum = getHumanoid(getCharacter())
    if not hum then return end
    if not characterDefaults then captureCharacterDefaults() end
    local defaults = characterDefaults or { WalkSpeed = 16, UseJumpPower = true, JumpPower = 50, JumpHeight = 7.2 }
    hum.WalkSpeed = state.speed and state.speedValue or defaults.WalkSpeed
    if state.jump then
        hum.UseJumpPower = true
        hum.JumpPower = state.jumpValue
    else
        hum.UseJumpPower = defaults.UseJumpPower
        hum.JumpPower = defaults.JumpPower
        hum.JumpHeight = defaults.JumpHeight
    end
end

local function clearFly()
    if flyVelocity then flyVelocity:Destroy(); flyVelocity = nil end
    if flyAttachment then flyAttachment:Destroy(); flyAttachment = nil end
    local hum = getHumanoid(getCharacter())
    if hum then hum.PlatformStand = false end
end

local function enableFly()
    clearFly()
    local root = getRoot(getCharacter())
    local hum = getHumanoid(getCharacter())
    if not root or not hum then return end
    local attachment = Instance.new("Attachment")
    attachment.Name = "FiQrFlyAttachment"
    attachment.Parent = root
    local velocity = Instance.new("LinearVelocity")
    velocity.Name = "FiQrFlyVelocity"
    velocity.Attachment0 = attachment
    velocity.RelativeTo = Enum.ActuatorRelativeTo.World
    velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    velocity.VectorVelocity = Vector3.zero
    velocity.MaxForce = math.huge
    velocity.Parent = root
    flyAttachment = attachment
    flyVelocity = velocity
    hum:ChangeState(Enum.HumanoidStateType.Physics)
end

local function setInvisible(enabled)
    local character = getCharacter()
    if not character then return end
    if enabled then
        for _, inst in ipairs(character:GetDescendants()) do
            if inst:IsA("BasePart") then
                if savedTransparency[inst] == nil then
                    savedTransparency[inst] = inst.LocalTransparencyModifier
                end
                inst.LocalTransparencyModifier = 1
            elseif inst:IsA("Decal") or inst:IsA("Texture") then
                if savedTransparency[inst] == nil then
                    savedTransparency[inst] = inst.Transparency
                end
                inst.Transparency = 1
            end
        end
    else
        for inst, value in pairs(savedTransparency) do
            if inst and inst.Parent then
                if inst:IsA("BasePart") then
                    inst.LocalTransparencyModifier = value
                elseif inst:IsA("Decal") or inst:IsA("Texture") then
                    inst.Transparency = value
                end
            end
        end
        table.clear(savedTransparency)
    end
end

local function setFullbright(enabled)
    if enabled then
        if not fullbrightOriginal then
            fullbrightOriginal = {
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
                Brightness = Lighting.Brightness,
                ClockTime = Lighting.ClockTime,
                GlobalShadows = Lighting.GlobalShadows,
            }
        end
        Lighting.Ambient = Color3.fromRGB(235, 235, 235)
        Lighting.OutdoorAmbient = Color3.fromRGB(235, 235, 235)
        Lighting.Brightness = 3
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
    elseif fullbrightOriginal then
        for property, value in pairs(fullbrightOriginal) do
            Lighting[property] = value
        end
        fullbrightOriginal = nil
    end
end

local function clearHitboxAdornments()
    for _, adornment in ipairs(hitboxAdornments) do
        if adornment and adornment.Parent then adornment:Destroy() end
    end
    table.clear(hitboxAdornments)
end

local function updateHitboxAdornments()
    clearHitboxAdornments()
    if not state.hitbox then return end
    local entry = findSelectedEntry()
    if not entry then return end
    local model = entry.model
    local parts = { getHead(model), getBodyPart(model) }
    local used = {}
    for _, part in ipairs(parts) do
        if part and part:IsA("BasePart") and not used[part] then
            used[part] = true
            local box = Instance.new("BoxHandleAdornment")
            box.Name = "FiQrHitboxTestArea"
            box.Adornee = part
            box.Size = part.Size * state.hitboxScale
            box.Color3 = COLORS.RedSoft
            box.Transparency = 0.65
            box.AlwaysOnTop = true
            box.ZIndex = 8
            box.Parent = Workspace
            table.insert(hitboxAdornments, box)
        end
    end
end

-- ESP (Fixed Skeleton & Optimized) -------------------------------------------
local SKELETON_R15 = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
}
local SKELETON_R6 = {
    {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
    {"Torso", "Left Leg"}, {"Torso", "Right Leg"},
}

local function clearSkeletonParts(record)
    for _, attachment in ipairs(record.attachments) do
        if attachment and attachment.Parent then attachment:Destroy() end
    end
    table.clear(record.attachments)
    for _, beam in ipairs(record.beams) do
        if beam and beam.Parent then beam:Destroy() end
    end
    table.clear(record.beams)
    record.expectedLinks = 0
end

local function removeESP(model)
    local record = espRegistry[model]
    if not record then return end
    if record.billboard then record.billboard:Destroy() end
    if record.folder then record.folder:Destroy() end
    clearSkeletonParts(record)
    espRegistry[model] = nil
end

local function makeSkeleton(model, record)
    clearSkeletonParts(record)

    local isR15 = model:FindFirstChild("UpperTorso") ~= nil
    local joints = isR15 and SKELETON_R15 or SKELETON_R6
    record.expectedLinks = #joints

    for _, link in ipairs(joints) do
        local partA = model:FindFirstChild(link[1])
        local partB = model:FindFirstChild(link[2])
        if partA and partB and partA:IsA("BasePart") and partB:IsA("BasePart") then
            local a0 = Instance.new("Attachment")
            a0.Name = "FiQrSkeletonA"
            a0.Parent = partA
            local a1 = Instance.new("Attachment")
            a1.Name = "FiQrSkeletonB"
            a1.Parent = partB
            local beam = Instance.new("Beam")
            beam.Name = "FiQrSkeletonBeam"
            beam.Attachment0 = a0
            beam.Attachment1 = a1
            beam.Width0 = 0.14
            beam.Width1 = 0.14
            beam.FaceCamera = true
            beam.LightInfluence = 0
            beam.LightEmission = 1
            beam.Transparency = NumberSequence.new(0)
            beam.Color = ColorSequence.new(COLORS.ESPWhite)
            beam.ZOffset = 0.5
            beam.Parent = record.folder
            table.insert(record.attachments, a0)
            table.insert(record.attachments, a1)
            table.insert(record.beams, beam)
        end
    end
end

local function updateModelESP(model)
    if not model or not model.Parent or model == getCharacter() then
        removeESP(model)
        return
    end
    local hum = getHumanoid(model)
    local root = getRoot(model)
    if not hum or not root or hum.Health <= 0 then
        removeESP(model)
        return
    end

    local player = Players:GetPlayerFromCharacter(model)
    local isPlayer = player ~= nil
    local categoryEnabled = isPlayer and state.playerESP or ((not isPlayer) and state.npcESP)
    local anyEnabled = categoryEnabled or state.nameESP or state.skeletonESP
    if not anyEnabled then
        removeESP(model)
        return
    end

    local record = espRegistry[model]
    if not record then
        local folder = Instance.new("Folder")
        folder.Name = "FiQrESP"
        folder.Parent = model
        record = { folder = folder, attachments = {}, beams = {}, billboard = nil, expectedLinks = 0 }
        espRegistry[model] = record
    end

    local highlight = record.folder:FindFirstChild("Highlight")
    if categoryEnabled then
        if not highlight then
            highlight = Instance.new("Highlight")
            highlight.Name = "Highlight"
            highlight.Adornee = model
            highlight.FillTransparency = 0.82
            highlight.OutlineTransparency = 0.05
            highlight.Parent = record.folder
        end
        highlight.FillColor = COLORS.ESPWhite
        highlight.OutlineColor = COLORS.ESPWhite
        highlight.Enabled = true
    elseif highlight then
        highlight:Destroy()
    end

    if state.nameESP then
        local adornee = getHead(model) or root
        if not record.billboard then
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "FiQrNameESP"
            billboard.Size = UDim2.fromOffset(170, 25)
            billboard.StudsOffset = Vector3.new(0, 2.6, 0)
            billboard.AlwaysOnTop = true
            billboard.MaxDistance = 1500
            billboard.Parent = PlayerGui
            local label = Instance.new("TextLabel")
            label.Name = "Name"
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.GothamBold
            label.TextSize = 12
            label.TextStrokeTransparency = 0.3
            label.TextColor3 = COLORS.ESPWhite
            label.Parent = billboard
            record.billboard = billboard
        end
        record.billboard.Adornee = adornee
        local label = record.billboard:FindFirstChild("Name")
        if label then
            label.Text = player and (player.DisplayName .. "  •  " .. math.floor(hum.Health) .. " HP") or (model.Name .. "  •  NPC")
        end
    elseif record.billboard then
        record.billboard:Destroy()
        record.billboard = nil
    end

    if state.skeletonESP then
        -- Rebuild if not built yet or if limbs loaded after initial spawn
        local validBeams = 0
        for _, b in ipairs(record.beams) do
            if b and b.Parent and b.Attachment0 and b.Attachment0.Parent and b.Attachment1 and b.Attachment1.Parent then
                validBeams += 1
            end
        end
        if validBeams == 0 or (record.expectedLinks > 0 and validBeams < record.expectedLinks) then
            makeSkeleton(model, record)
        end
    elseif #record.beams > 0 then
        clearSkeletonParts(record)
    end
end

local function refreshESP()
    local targets = refreshTargetCache()
    local present = {}
    for _, entry in ipairs(targets) do
        present[entry.model] = true
        updateModelESP(entry.model)
    end
    for model in pairs(espRegistry) do
        if not present[model] then
            removeESP(model)
        end
    end
end

-- Target actions -------------------------------------------------------------
local function teleportToSelected(offset)
    local entry = findSelectedEntry()
    local root = getRoot(getCharacter())
    local targetRoot = entry and getRoot(entry.model)
    if not root or not targetRoot then
        setStatus("Select a living target first", false)
        return
    end
    root.CFrame = targetRoot.CFrame * CFrame.new(offset)
    setStatus("Teleported to " .. entry.model.Name, true)
end

local function toggleSpectate()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    if state.spectating then
        state.spectating = false
        local hum = getHumanoid(getCharacter())
        camera.CameraSubject = hum
        currentSpectateHumanoid = nil
        setStatus("Spectate disabled", true)
        return
    end
    local entry = findSelectedEntry()
    local hum = entry and getHumanoid(entry.model)
    if not hum then
        setStatus("Select a living target first", false)
        return
    end
    state.spectating = true
    currentSpectateHumanoid = hum
    camera.CameraSubject = hum
    setStatus("Spectating " .. entry.model.Name, true)
end

-- Developer test helpers ------------------------------------------------------
local function isFriendlyPlayer(player)
    if not player then return false end
    if LocalPlayer.Team ~= nil and player.Team ~= nil then
        return LocalPlayer.Team == player.Team
    end
    if LocalPlayer.TeamColor and player.TeamColor then
        return LocalPlayer.TeamColor == player.TeamColor
    end
    return false
end

local function hasLineOfSight(model, targetPart)
    local camera = Workspace.CurrentCamera
    if not camera or not targetPart then return false end
    local origin = camera.CFrame.Position
    local direction = targetPart.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { getCharacter() }
    params.IgnoreWater = true
    local result = Workspace:Raycast(origin, direction, params)
    return result ~= nil and result.Instance ~= nil and result.Instance:IsDescendantOf(model)
end

local function canAimAt(entry, part)
    if not entry or not part then return false end
    if entry.player and isFriendlyPlayer(entry.player) then return false end
    if state.wallCheck and not hasLineOfSight(entry.model, part) then return false end
    return true
end

-- Optimized & Fixed Tracers (uses cachedTargets + midpoint AnchorPoint)
local function clearAllTracers()
    for model, line in pairs(tracerGui) do
        if line then line:Destroy() end
        tracerGui[model] = nil
    end
end

local function updateTracers()
    if not state.tracers then
        if next(tracerGui) ~= nil then clearAllTracers() end
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then return end

    local viewport = camera.ViewportSize
    local inset = GuiService:GetGuiInset()
    local origin = Vector2.new(viewport.X * 0.5, viewport.Y - 12)
    local activeModels = {}

    for _, entry in ipairs(cachedTargets) do
        local model = entry.model
        if model and model.Parent then
            local root = getRoot(model)
            local hum = getHumanoid(model)
            if root and hum and hum.Health > 0 then
                local point, onScreen = camera:WorldToViewportPoint(root.Position)
                if onScreen and point.Z > 0 then
                    activeModels[model] = true
                    local line = tracerGui[model]
                    if not line then
                        line = Instance.new("Frame")
                        line.Name = "FiQrTracer"
                        line.AnchorPoint = Vector2.new(0.5, 0.5)
                        line.BorderSizePixel = 0
                        line.BackgroundColor3 = COLORS.Tracer
                        line.ZIndex = 2
                        line.Parent = gui
                        tracerGui[model] = line
                    end
                    local target = Vector2.new(point.X, point.Y + inset.Y)
                    local delta = target - origin
                    local mid = (origin + target) * 0.5
                    line.Position = UDim2.fromOffset(mid.X, mid.Y)
                    line.Size = UDim2.fromOffset(delta.Magnitude, 1.5)
                    line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                    line.Visible = true
                end
            end
        end
    end

    for model, line in pairs(tracerGui) do
        if not activeModels[model] then
            if line then line:Destroy() end
            tracerGui[model] = nil
        end
    end
end

-- UI sections and controls ---------------------------------------------------
local targetSection = makeSection("Target")
local targetButton
local function cycleTarget()
    local targets = refreshTargetCache()
    if #targets == 0 then
        selectedTarget = nil
        if targetButton then targetButton.Text = "TARGET  •  NONE FOUND" end
        setStatus("No players or NPCs found", false)
        updateHitboxAdornments()
        return
    end
    local currentIndex = 0
    for index, entry in ipairs(targets) do
        if entry.model == selectedTarget then currentIndex = index break end
    end
    local nextIndex = currentIndex % #targets + 1
    selectedTarget = targets[nextIndex].model
    local entry = targets[nextIndex]
    local targetName = entry.player and entry.player.DisplayName or entry.model.Name
    targetButton.Text = "TARGET  •  " .. entry.kind .. "  •  " .. targetName
    updateHitboxAdornments()
    setStatus("Selected " .. targetName, true)
end

targetButton = makeButton(targetSection, "TARGET  •  CLICK TO SELECT", cycleTarget)
makeButton(targetSection, "SPECTATE / RETURN", toggleSpectate)
makeButton(targetSection, "TELEPORT TO SELECTED", function()
    teleportToSelected(Vector3.new(0, 0, -4))
end)
makeButton(targetSection, "TELEPORT BEHIND SELECTED", function()
    teleportToSelected(Vector3.new(0, 0, 3.5))
end)
makeButton(targetSection, "STAND ABOVE SELECTED", function()
    local entry = findSelectedEntry()
    local head = entry and getHead(entry.model)
    if not head then
        setStatus("Selected target has no Head", false)
        return
    end
    local root = getRoot(getCharacter())
    if root then
        root.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 2.5, 0)
        setStatus("Moved above " .. entry.model.Name, true)
    end
end)

local espSection = makeSection("ESP")
makeToggle(espSection, "Player ESP  •  Highlight", state.playerESP, function(value)
    state.playerESP = value; refreshESP()
end)
makeToggle(espSection, "NPC ESP  •  Highlight", state.npcESP, function(value)
    state.npcESP = value; refreshESP()
end)
makeToggle(espSection, "Name ESP", state.nameESP, function(value)
    state.nameESP = value; refreshESP()
end)
makeToggle(espSection, "Skeleton ESP", state.skeletonESP, function(value)
    state.skeletonESP = value; refreshESP()
end)
makeToggle(espSection, "Tracers  •  Cyan", state.tracers, function(value)
    state.tracers = value
    if value then
        refreshTargetCache()
        updateTracers()
    else
        clearAllTracers()
    end
    setStatus(value and "Tracers enabled" or "Tracers disabled", true)
end)

local movementSection = makeSection("Movement")
makeToggle(movementSection, "Speed Boost", state.speed, function(value)
    state.speed = value; applyMovement(); setStatus(value and "Speed enabled" or "Speed disabled", true)
end)
makeSlider(movementSection, "WALK SPEED", 16, 100, state.speedValue, function(value)
    state.speedValue = value; if state.speed then applyMovement() end
end)
makeToggle(movementSection, "Jump Boost", state.jump, function(value)
    state.jump = value; applyMovement(); setStatus(value and "Jump boost enabled" or "Jump boost disabled", true)
end)
makeToggle(movementSection, "Infinite Jump", state.infiniteJump, function(value)
    state.infiniteJump = value; setStatus(value and "Infinite jump enabled" or "Infinite jump disabled", true)
end)
makeSlider(movementSection, "JUMP POWER", 50, 150, state.jumpValue, function(value)
    state.jumpValue = value; if state.jump then applyMovement() end
end)
makeToggle(movementSection, "Fly", state.fly, function(value)
    state.fly = value
    if value then enableFly() else clearFly() end
    setStatus(value and "Fly enabled  •  WASD + Space/Ctrl" or "Fly disabled", true)
end)
makeSlider(movementSection, "FLY SPEED", 10, 100, state.flySpeed, function(value)
    state.flySpeed = value
end)
makeToggle(movementSection, "Noclip", state.noclip, function(value)
    state.noclip = value
    if not value then
        for part, oldValue in pairs(savedCollision) do
            if part and part.Parent then part.CanCollide = oldValue end
        end
        table.clear(savedCollision)
    end
    setStatus(value and "Noclip enabled" or "Noclip disabled", true)
end)
makeToggle(movementSection, "Swim in Air  •  Test", state.swimAir, function(value)
    state.swimAir = value; setStatus(value and "Air swim enabled" or "Air swim disabled", true)
end)
makeToggle(movementSection, "Spinbot  •  Test", state.spinbot, function(value)
    state.spinbot = value
    if not value then
        local root = getRoot(getCharacter())
        if root then root.AssemblyAngularVelocity = Vector3.zero end
    end
    setStatus(value and "Spin test enabled" or "Spin test disabled", true)
end)
makeSlider(movementSection, "SPIN SPEED", 1, 35, state.spinSpeed, function(value)
    state.spinSpeed = value
end)

local visualSection = makeSection("Visuals")
makeToggle(visualSection, "Fullbright", state.fullbright, function(value)
    state.fullbright = value; setFullbright(value); setStatus(value and "Fullbright enabled" or "Lighting restored", true)
end)
makeToggle(visualSection, "Custom Time", state.customTime, function(value)
    state.customTime = value
    if value then
        originalClockTime = Lighting.ClockTime
        Lighting.ClockTime = state.timeValue
    else
        Lighting.ClockTime = originalClockTime
    end
    setStatus(value and "Custom time enabled" or "Time sync restored", true)
end)
makeSlider(visualSection, "CLOCK TIME", 0, 24, state.timeValue, function(value)
    state.timeValue = value
    if state.customTime then Lighting.ClockTime = value end
end)
makeToggle(visualSection, "FOV Override", state.fov, function(value)
    state.fov = value
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = value and state.fovValue or 70 end
    setStatus(value and "FOV override enabled" or "FOV reset to 70", true)
end)
makeSlider(visualSection, "FIELD OF VIEW", 70, 120, state.fovValue, function(value)
    state.fovValue = value
    if state.fov and Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = value end
end)
makeToggle(visualSection, "FPS & Ping Overlay", state.showStats, function(value)
    state.showStats = value
    statsLabel.Visible = value
    setStatus(value and "Stats overlay shown" or "Stats overlay hidden", true)
end)
makeToggle(visualSection, "Invisible  •  Local Test", state.invisible, function(value)
    state.invisible = value; setInvisible(value)
    setStatus(value and "Local invisibility enabled" or "Visibility restored", true)
end)

local testSection = makeSection("Targeting / Test Tools")
makeToggle(testSection, "Aim Assist  •  Hold Left Alt", state.aimAssist, function(value)
    state.aimAssist = value
    fovCircle.Visible = value
    setStatus(value and "Aim assist ready  •  hold Left Alt" or "Aim assist disabled", true)
end)
makeSlider(testSection, "AIM FOV RADIUS", 50, 400, state.aimFOV, function(value)
    state.aimFOV = value
    fovCircle.Size = UDim2.fromOffset(value * 2, value * 2)
end)
makeSlider(testSection, "AIM SMOOTHNESS", 2, 30, state.aimSmoothness, function(value)
    state.aimSmoothness = value
end)
makeToggle(testSection, "Wall Check", state.wallCheck, function(value)
    state.wallCheck = value; setStatus(value and "Wall check enabled" or "Wall check disabled", true)
end)
local aimPartButton
aimPartButton = makeButton(testSection, "AIM PART  •  HEAD", function()
    state.aimPart = state.aimPart == "Head" and "Body" or "Head"
    aimPartButton.Text = "AIM PART  •  " .. string.upper(state.aimPart)
    setStatus("Aim part: " .. state.aimPart, true)
end)
makeToggle(testSection, "Hitbox Test Area  •  Visual", state.hitbox, function(value)
    state.hitbox = value; updateHitboxAdornments()
    setStatus(value and "Hitbox overlay enabled" or "Hitbox overlay disabled", true)
end)
makeSlider(testSection, "HITBOX VISUAL SCALE", 1, 5, state.hitboxScale, function(value)
    state.hitboxScale = value; if state.hitbox then updateHitboxAdornments() end
end)
makeToggle(testSection, "Godmode  •  Local Test", state.godmode, function(value)
    state.godmode = value
    setStatus(value and "Local health test enabled" or "Local health test disabled", true)
end)

local utilitySection = makeSection("Utility")
makeButton(utilitySection, "SAVE CURRENT POSITION", function()
    local root = getRoot(getCharacter())
    if root then
        savedWaypoint = root.CFrame
        setStatus("Waypoint saved!", true)
    else
        setStatus("Character root not found", false)
    end
end)
makeButton(utilitySection, "TELEPORT TO WAYPOINT", function()
    local root = getRoot(getCharacter())
    if root and savedWaypoint then
        root.CFrame = savedWaypoint
        setStatus("Teleported to waypoint", true)
    else
        setStatus("No waypoint saved yet", false)
    end
end)
makeToggle(utilitySection, "Loop Teleport  •  Selected Target", state.loopTeleport, function(value)
    state.loopTeleport = value
    setStatus(value and "Loop teleport enabled for selected test target" or "Loop teleport disabled", true)
end)
makeToggle(utilitySection, "Anti-AFK", state.antiAFK, function(value)
    state.antiAFK = value; setStatus(value and "Anti-AFK enabled" or "Anti-AFK disabled", true)
end)
makeToggle(utilitySection, "Click Teleport", state.clickTeleport, function(value)
    state.clickTeleport = value
    setStatus(value and "Click a location to teleport" or "Click teleport disabled", true)
end)
makeButton(utilitySection, "REFRESH TARGETS / ESP", function()
    local targets = refreshTargetCache()
    if selectedTarget and not findSelectedEntry() then selectedTarget = nil end
    refreshESP()
    updateHitboxAdornments()
    if targetButton then
        targetButton.Text = selectedTarget and ("TARGET  •  " .. getSelectedName()) or "TARGET  •  CLICK TO SELECT"
    end
    setStatus("Refreshed  •  " .. #targets .. " targets", true)
end)
makeButton(utilitySection, "RESET LOCAL TEST SETTINGS", function()
    for _, setter in pairs(toggleSetters) do
        setter(false)
    end
    if state.spectating then
        toggleSpectate()
    end
    clearFly()
    applyMovement()
    setInvisible(false)
    setFullbright(false)
    clearHitboxAdornments()
    clearAllTracers()
    fovCircle.Visible = false
    local root = getRoot(getCharacter())
    if root then root.AssemblyAngularVelocity = Vector3.zero end
    local hum = getHumanoid(getCharacter())
    if hum then
        hum.PlatformStand = false
        if Workspace.CurrentCamera then Workspace.CurrentCamera.CameraSubject = hum end
    end
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = 70 end
    for part, oldValue in pairs(savedCollision) do
        if part and part.Parent then part.CanCollide = oldValue end
    end
    table.clear(savedCollision)
    for model in pairs(espRegistry) do removeESP(model) end
    refreshESP()
    setStatus("Local test settings reset", true)
end)

-- Runtime loops --------------------------------------------------------------
local mouse = LocalPlayer:GetMouse()
LocalPlayer.Idled:Connect(function()
    if not state.antiAFK then return end
    local ok, virtualUser = pcall(function() return game:GetService("VirtualUser") end)
    if ok and virtualUser then
        pcall(function()
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end
end)
mouse.Button1Down:Connect(function()
    if not state.clickTeleport then return end
    local x, y = mouse.X, mouse.Y
    local p, s = main.AbsolutePosition, main.AbsoluteSize
    if main.Visible and x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then
        return
    end
    local character = getCharacter()
    local root = getRoot(character)
    if not root then return end
    local hit = mouse.Hit
    if hit then
        root.CFrame = CFrame.new(hit.Position + Vector3.new(0, 3, 0))
        setStatus("Click teleport complete", true)
    end
end)

local aimHeld = false
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == state.aimKey then aimHeld = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == state.aimKey then aimHeld = false end
end)

UserInputService.JumpRequest:Connect(function()
    if not state.infiniteJump then return end
    local hum = getHumanoid(getCharacter())
    if hum and hum.Health > 0 then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

local statsTimer = 0
local frameCounter = 0

RunService.RenderStepped:Connect(function(dt)
    local character = getCharacter()
    local root = getRoot(character)
    local hum = getHumanoid(character)

    -- FPS & Ping Counter
    if state.showStats then
        statsTimer += dt
        frameCounter += 1
        if statsTimer >= 0.4 then
            local fps = math.floor(frameCounter / statsTimer + 0.5)
            local ping = math.floor(LocalPlayer:GetNetworkPing() * 1000)
            statsLabel.Text = string.format("FPS: %d  |  %d ms", fps, ping)
            statsTimer = 0
            frameCounter = 0
        end
    end

    if state.customTime then
        Lighting.ClockTime = state.timeValue
    end

    if state.fly and root and flyVelocity then
        local camera = Workspace.CurrentCamera
        if camera then
            local direction = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction += camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction -= camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction += camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction -= camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then direction -= Vector3.yAxis end
            if direction.Magnitude > 0 then direction = direction.Unit end
            flyVelocity.VectorVelocity = direction * state.flySpeed
        end
    end

    -- Improved Aim Assist (FOV-bound + Smoothness so you can freely turn away or switch targets)
    if state.aimAssist and aimHeld then
        local camera = Workspace.CurrentCamera
        if camera then
            local center = Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.5)
            local bestPart = nil
            local bestDistance = state.aimFOV

            for _, candidate in ipairs(cachedTargets) do
                if candidate.model and candidate.model.Parent and isAliveModel(candidate.model) then
                    local part = getAimPart(candidate.model)
                    if part and canAimAt(candidate, part) then
                        local screenPoint, onScreen = camera:WorldToViewportPoint(part.Position)
                        if onScreen and screenPoint.Z > 0 then
                            local distance = (Vector2.new(screenPoint.X, screenPoint.Y) - center).Magnitude
                            if distance <= bestDistance then
                                bestDistance = distance
                                bestPart = part
                            end
                        end
                    end
                end
            end

            if bestPart then
                local desired = CFrame.lookAt(camera.CFrame.Position, bestPart.Position)
                local alpha = math.clamp(1 / math.max(state.aimSmoothness, 1), 0.02, 0.5)
                camera.CFrame = camera.CFrame:Lerp(desired, alpha)
            end
        end
    end

    updateTracers()

    if state.loopTeleport then
        local entry = findSelectedEntry()
        local myRoot = getRoot(character)
        local targetRoot = entry and getRoot(entry.model)
        if myRoot and targetRoot then
            myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3.5)
        end
    end

    if state.spinbot and root then
        root.AssemblyAngularVelocity = Vector3.new(0, state.spinSpeed, 0)
    end

    if state.godmode and hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
        hum.Health = hum.MaxHealth
    end
end)

RunService.Stepped:Connect(function()
    local character = getCharacter()
    if state.noclip and character then
        for _, inst in ipairs(character:GetDescendants()) do
            if inst:IsA("BasePart") then
                if savedCollision[inst] == nil then savedCollision[inst] = inst.CanCollide end
                inst.CanCollide = false
            end
        end
    end
end)

RunService.Heartbeat:Connect(function()
    local hum = getHumanoid(getCharacter())
    if state.swimAir and hum and hum.Health > 0 then
        hum:ChangeState(Enum.HumanoidStateType.Swimming)
    end
    if state.spectating and currentSpectateHumanoid and currentSpectateHumanoid.Parent then
        local camera = Workspace.CurrentCamera
        if camera and camera.CameraSubject ~= currentSpectateHumanoid then
            camera.CameraSubject = currentSpectateHumanoid
        end
    end
end)

-- Keep target cache & ESP synced periodically without lagging RenderStepped.
task.spawn(function()
    while gui.Parent do
        refreshESP()
        if selectedTarget and not findSelectedEntry() then
            selectedTarget = nil
            if targetButton then targetButton.Text = "TARGET  •  CLICK TO SELECT" end
            updateHitboxAdornments()
        end
        task.wait(1.5)
    end
end)

LocalPlayer.CharacterAdded:Connect(function(character)
    character:WaitForChild("Humanoid", 10)
    character:WaitForChild("HumanoidRootPart", 10)
    task.wait(0.15)
    characterDefaults = nil
    savedTransparency = {}
    captureCharacterDefaults()
    applyMovement()
    if state.fly then enableFly() end
    if state.invisible then setInvisible(true) end
    if state.spectating then
        state.spectating = false
        currentSpectateHumanoid = nil
    end
end)

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.5)
        refreshTargetCache()
        if player.Character then updateModelESP(player.Character) end
    end)
end)

-- First refresh + initial state.
captureCharacterDefaults()
refreshESP()
setStatus("Ready  •  Studio test panel v2 loaded", true)
print("[FiQr] Red Universal v2 developer panel loaded in Studio.")
