local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local lp = Players.LocalPlayer
local pg = lp:WaitForChild("PlayerGui")
if pg:FindFirstChild("VortexHub") then pg.VortexHub:Destroy() end
if pg:FindFirstChild("VortexESP") then pg.VortexESP:Destroy() end

local VERSION = "1"
local running = true

_G.VortexUI = { toggles = {}, sliders = {} }

local hasDrawing = false
pcall(function() local d = Drawing.new("Line"); d:Remove(); hasDrawing = true end)
local hasCircles = false
pcall(function() local c = Drawing.new("Circle"); c:Remove(); hasCircles = true end)

local C = {
    bg = Color3.fromRGB(8,8,8), card = Color3.fromRGB(20,20,20),
    text = Color3.fromRGB(255,255,255), dim = Color3.fromRGB(130,130,130),
    stroke = Color3.fromRGB(40,40,40),
    vis = Color3.fromRGB(50,255,100), occ = Color3.fromRGB(255,50,50),
    friend = Color3.fromRGB(0, 170, 255)
}

local hubColor1H, hubColor2H = 0, 0.6
local espColor1H, espColor2H = 0.3, 0.8
local blur = Instance.new("BlurEffect", Lighting)
blur.Size = 0; blur.Enabled = false

-- States
local aimEnabled, aimFov, rmbHeld = false, 150, false
local espEnabled, tracerEnabled, skeletonEnabled, arrowsEnabled = false, false, false, false
local targetHudEnabled, chamsEnabled, fullbrightEnabled = false, false, false
local bigHeadScale, zoomEnabled, zoomLevel, isZooming = 1, false, 1, false
local camFov, thirdPersonEnabled, thirdPersonDist = 70, false, 12
local distEspEnabled = false

-- Crosshair Vars
local crosshairEnabled = false
local chColor = Color3.fromRGB(255, 255, 255)
local chLength, chGap, chThickness, chDotSize = 6, 4, 1, 2

local espBoxes, tracerDrawings, skeletonDrawings, arrowDrawings = {}, {}, {}, {}
local chamsHighlights = {}
local cachedTargets, origHeadSizes = {}, {}
local currentAimTargetChar = nil
local defaultFov = 70
local origLighting = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local SKELETON_PAIRS = {
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"UpperTorso","LowerTorso"},{"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},
    {"LeftLowerLeg","LeftFoot"},{"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},
    {"RightLowerLeg","RightFoot"},{"Torso","Left Arm"},{"Torso","Right Arm"},{"Torso","Left Leg"},{"Torso","Right Leg"}
}
local SKELETON_COUNT = #SKELETON_PAIRS

-- Friends Logic
local friends = {}
local friendsFile = "VortexHub_Friends.json"
local function saveFriends() if not writefile then return end local list = {} for name, _ in pairs(friends) do table.insert(list, name) end pcall(writefile, friendsFile, HttpService:JSONEncode(list)) end
local function loadFriends() if not readfile or not isfile then return end if not isfile(friendsFile) then return end local ok, data = pcall(readfile, friendsFile) if not ok or not data then return end local decOk, list = pcall(function() return HttpService:JSONDecode(data) end) if not decOk or not list then return end for _, name in ipairs(list) do friends[name] = true end end
loadFriends()

local function isFriend(model)
    if not model then return false end
    local p = Players:GetPlayerFromCharacter(model)
    if p then if friends[p.Name] or friends[p.DisplayName] then return true end end
    if friends[model.Name] then return true end
    return false
end
local function addFriend(name) if not name or name == "" then return end friends[name] = true saveFriends() end
local function removeFriend(name) friends[name] = nil saveFriends() end

local function getLocalChar()
    local char = lp.Character
    if char then return char end
    local cam = workspace.CurrentCamera
    if cam then local m = cam:FindFirstChild("Model") if m and m:FindFirstChildOfClass("Humanoid") then return m end end
    local wp = workspace:FindFirstChild("Players")
    if wp then local m = wp:FindFirstChild(lp.Name) if m and m:FindFirstChildOfClass("Humanoid") then return m end end
    return nil
end

local function applyFullbright(on)
    if on then
        if not origLighting.Ambient then origLighting.Ambient = Lighting.Ambient origLighting.OutdoorAmbient = Lighting.OutdoorAmbient origLighting.Brightness = Lighting.Brightness origLighting.ClockTime = Lighting.ClockTime end
        Lighting.Ambient = Color3.fromRGB(255,255,255) Lighting.OutdoorAmbient = Color3.fromRGB(255,255,255) Lighting.Brightness = 2 Lighting.ClockTime = 12
    elseif origLighting.Ambient then
        Lighting.Ambient = origLighting.Ambient Lighting.OutdoorAmbient = origLighting.OutdoorAmbient Lighting.Brightness = origLighting.Brightness Lighting.ClockTime = origLighting.ClockTime origLighting = {}
    end
end

local hub = Instance.new("ScreenGui")
hub.Name = "VortexHub"; hub.ResetOnSpawn = false; hub.IgnoreGuiInset = true; hub.DisplayOrder = 100000; hub.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; hub.Parent = pg

local espGui = Instance.new("ScreenGui")
espGui.Name = "VortexESP"; espGui.ResetOnSpawn = false; espGui.IgnoreGuiInset = true; espGui.DisplayOrder = 999999; espGui.Parent = pg

local chamsFolder = Instance.new("Folder", espGui); chamsFolder.Name = "Chams"

-- CROSSHAIR GUI
local chGui = Instance.new("Frame", hub)
chGui.Size = UDim2.fromOffset(100, 100); chGui.Position = UDim2.fromScale(0.5, 0.5); chGui.AnchorPoint = Vector2.new(0.5, 0.5); chGui.BackgroundTransparency = 1; chGui.Visible = false; chGui.ZIndex = 9999

local chTop = Instance.new("Frame", chGui); chTop.BackgroundColor3 = chColor; chTop.BorderSizePixel = 0; chTop.AnchorPoint = Vector2.new(0.5, 1)
local chBot = Instance.new("Frame", chGui); chBot.BackgroundColor3 = chColor; chBot.BorderSizePixel = 0; chBot.AnchorPoint = Vector2.new(0.5, 0)
local chLeft = Instance.new("Frame", chGui); chLeft.BackgroundColor3 = chColor; chLeft.BorderSizePixel = 0; chLeft.AnchorPoint = Vector2.new(1, 0.5)
local chRight = Instance.new("Frame", chGui); chRight.BackgroundColor3 = chColor; chRight.BorderSizePixel = 0; chRight.AnchorPoint = Vector2.new(0, 0.5)
local chDot = Instance.new("Frame", chGui); chDot.BackgroundColor3 = chColor; chDot.BorderSizePixel = 0; chDot.AnchorPoint = Vector2.new(0.5, 0.5); chDot.Position = UDim2.fromScale(0.5, 0.5)

local function updateCrosshair()
    chGui.Visible = crosshairEnabled
    local L, G, T, D = chLength, chGap, chThickness, chDotSize
    chTop.Size = UDim2.fromOffset(T, L); chTop.Position = UDim2.new(0.5, 0, 0.5, -G)
    chBot.Size = UDim2.fromOffset(T, L); chBot.Position = UDim2.new(0.5, 0, 0.5, G)
    chLeft.Size = UDim2.fromOffset(L, T); chLeft.Position = UDim2.new(0.5, -G, 0.5, 0)
    chRight.Size = UDim2.fromOffset(L, T); chRight.Position = UDim2.new(0.5, G, 0.5, 0)
    chDot.Size = UDim2.fromOffset(D, D)
    chTop.BackgroundColor3 = chColor; chBot.BackgroundColor3 = chColor; chLeft.BackgroundColor3 = chColor; chRight.BackgroundColor3 = chColor; chDot.BackgroundColor3 = chColor
end

-- Target HUD
local targetHud = Instance.new("Frame", hub)
targetHud.Size = UDim2.fromOffset(220, 75); targetHud.Position = UDim2.new(0.5, -110, 0.5, 100); targetHud.BackgroundColor3 = C.bg; targetHud.BorderSizePixel = 0; targetHud.Visible = false; targetHud.Active = true
Instance.new("UICorner", targetHud).CornerRadius = UDim.new(0, 6); Instance.new("UIStroke", targetHud).Color = C.stroke

local thName = Instance.new("TextLabel", targetHud); thName.Size = UDim2.new(1, -20, 0, 20); thName.Position = UDim2.fromOffset(10, 8); thName.BackgroundTransparency = 1; thName.Text = "Player"; thName.TextColor3 = C.text; thName.Font = Enum.Font.GothamBold; thName.TextSize = 14; thName.TextXAlignment = Enum.TextXAlignment.Left
local thWeapon = Instance.new("TextLabel", targetHud); thWeapon.Size = UDim2.new(1, -20, 0, 14); thWeapon.Position = UDim2.fromOffset(10, 26); thWeapon.BackgroundTransparency = 1; thWeapon.Text = "Weapon: None"; thWeapon.TextColor3 = C.dim; thWeapon.Font = Enum.Font.GothamMedium; thWeapon.TextSize = 11; thWeapon.TextXAlignment = Enum.TextXAlignment.Left

local thHpBg = Instance.new("Frame", targetHud); thHpBg.Size = UDim2.new(1, -20, 0, 12); thHpBg.Position = UDim2.fromOffset(10, 45); thHpBg.BackgroundColor3 = Color3.fromRGB(40,40,40); thHpBg.BorderSizePixel = 0
Instance.new("UICorner", thHpBg).CornerRadius = UDim.new(0, 4)
local thHpFill = Instance.new("Frame", thHpBg); thHpFill.Size = UDim2.fromScale(1, 1); thHpFill.BackgroundColor3 = C.vis; thHpFill.BorderSizePixel = 0
Instance.new("UICorner", thHpFill).CornerRadius = UDim.new(0, 4)
local thHpText = Instance.new("TextLabel", thHpFill); thHpText.Size = UDim2.fromScale(1, 1); thHpText.BackgroundTransparency = 1; thHpText.Text = "100"; thHpText.TextColor3 = Color3.new(0,0,0); thHpText.Font = Enum.Font.GothamBold; thHpText.TextSize = 10

local thDrag, thS, thP = false, nil, nil
targetHud.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then thDrag = true; thS = i.Position; thP = targetHud.Position end end)
UIS.InputChanged:Connect(function(i) if thDrag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then local d = i.Position - thS; targetHud.Position = UDim2.new(thP.X.Scale, thP.X.Offset + d.X, thP.Y.Scale, thP.Y.Offset + d.Y) end end)
UIS.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then thDrag = false end end)

-- UI, Pages, Tabs Setup (Опущено для краткости, идентично предыдущим версиям)
local loading = Instance.new("Frame", hub); loading.Size = UDim2.fromOffset(340, 130); loading.Position = UDim2.fromScale(0.5, 0.5); loading.AnchorPoint = Vector2.new(0.5, 0.5); loading.BackgroundColor3 = C.bg; loading.BorderSizePixel = 0; loading.ZIndex = 100
Instance.new("UICorner", loading).CornerRadius = UDim.new(0, 8); local ls = Instance.new("UIStroke", loading); ls.Color = C.stroke
local lTitle = Instance.new("TextLabel", loading); lTitle.Size = UDim2.new(1, 0, 0, 40); lTitle.Position = UDim2.fromOffset(0, 25); lTitle.BackgroundTransparency = 1; lTitle.Text = "Vortex Hub"; lTitle.TextColor3 = C.text; lTitle.Font = Enum.Font.GothamBold; lTitle.TextSize = 26; lTitle.ZIndex = 101
local lSub = Instance.new("TextLabel", loading); lSub.Size = UDim2.new(1, 0, 0, 16); lSub.Position = UDim2.fromOffset(0, 66); lSub.BackgroundTransparency = 1; lSub.Text = "loading " .. VERSION .. "..."; lSub.TextColor3 = C.dim; lSub.Font = Enum.Font.GothamMedium; lSub.TextSize = 12; lSub.ZIndex = 101
local lBarBg = Instance.new("Frame", loading); lBarBg.Size = UDim2.new(1, -40, 0, 3); lBarBg.Position = UDim2.new(0, 20, 1, -22); lBarBg.BackgroundColor3 = C.card; lBarBg.BorderSizePixel = 0; lBarBg.ZIndex = 101; Instance.new("UICorner", lBarBg).CornerRadius = UDim.new(1, 0)
local lBar = Instance.new("Frame", lBarBg); lBar.Size = UDim2.new(0, 0, 1, 0); lBar.BackgroundColor3 = C.text; lBar.BorderSizePixel = 0; lBar.ZIndex = 102; Instance.new("UICorner", lBar).CornerRadius = UDim.new(1, 0); TweenService:Create(lBar, TweenInfo.new(1.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.fromScale(1, 1)}):Play()

local fovCircle = Instance.new("Frame", hub); fovCircle.Size = UDim2.fromOffset(aimFov*2, aimFov*2); fovCircle.AnchorPoint = Vector2.new(0.5, 0.5); fovCircle.Position = UDim2.fromScale(0.5, 0.5); fovCircle.BackgroundTransparency = 1; fovCircle.BorderSizePixel = 0; fovCircle.Visible = false; fovCircle.ZIndex = 5
Instance.new("UICorner", fovCircle).CornerRadius = UDim.new(1, 0); local fovStroke = Instance.new("UIStroke", fovCircle); fovStroke.Color = C.text; fovStroke.Thickness = 1.5; fovStroke.Transparency = 0.5

local MENU_W, MENU_H = 580, 420
local main = Instance.new("Frame", hub); main.Size = UDim2.fromOffset(MENU_W, MENU_H); main.Position = UDim2.fromScale(0.5, 0.5); main.AnchorPoint = Vector2.new(0.5, 0.5); main.BackgroundColor3 = C.bg; main.BorderSizePixel = 0; main.Visible = false
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 6); Instance.new("UIStroke", main).Color = C.stroke
local hubGrad = Instance.new("UIGradient", main); hubGrad.Color = ColorSequence.new(Color3.fromHSV(hubColor1H, 0.5, 0.2), Color3.fromHSV(hubColor2H, 0.5, 0.2))

local header = Instance.new("Frame", main); header.Size = UDim2.new(1, 0, 0, 30); header.BackgroundTransparency = 1; header.Active = true
local headerTitle = Instance.new("TextLabel", header); headerTitle.Size = UDim2.new(1, -20, 1, 0); headerTitle.Position = UDim2.fromOffset(15, 0); headerTitle.BackgroundTransparency = 1; headerTitle.Text = "Vortex Hub"; headerTitle.TextColor3 = C.dim; headerTitle.Font = Enum.Font.GothamBold; headerTitle.TextSize = 12; headerTitle.TextXAlignment = Enum.TextXAlignment.Left
local sidebar = Instance.new("Frame", main); sidebar.Size = UDim2.new(0, 140, 1, -30); sidebar.Position = UDim2.fromOffset(0, 30); sidebar.BackgroundColor3 = Color3.fromRGB(14,14,14); sidebar.BorderSizePixel = 0; Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 6)
local profile = Instance.new("Frame", sidebar); profile.Size = UDim2.new(1, 0, 0, 80); profile.Position = UDim2.new(0, 0, 1, -80); profile.BackgroundTransparency = 1
local av = Instance.new("ImageLabel", profile); av.Size = UDim2.fromOffset(32, 32); av.Position = UDim2.fromOffset(15, 10); av.BackgroundColor3 = C.card; av.BorderSizePixel = 0; av.Image = "rbxthumb://type=AvatarHeadShot&id="..lp.UserId.."&w=48&h=48"; Instance.new("UICorner", av).CornerRadius = UDim.new(1, 0)
local dn = Instance.new("TextLabel", profile); dn.Size = UDim2.new(1, -60, 0, 16); dn.Position = UDim2.fromOffset(55, 8); dn.BackgroundTransparency = 1; dn.Text = lp.DisplayName; dn.TextColor3 = C.text; dn.Font = Enum.Font.GothamBold; dn.TextSize = 13; dn.TextXAlignment = Enum.TextXAlignment.Left
local un = Instance.new("TextLabel", profile); un.Size = UDim2.new(1, -60, 0, 14); un.Position = UDim2.fromOffset(55, 24); un.BackgroundTransparency = 1; un.Text = "@" .. lp.Name; un.TextColor3 = C.dim; un.Font = Enum.Font.GothamMedium; un.TextSize = 11; un.TextXAlignment = Enum.TextXAlignment.Left
local ver = Instance.new("TextLabel", profile); ver.Size = UDim2.new(1, -30, 0, 14); ver.Position = UDim2.fromOffset(15, 46); ver.BackgroundTransparency = 1; ver.Text = "Version: " .. VERSION; ver.TextColor3 = C.vis; ver.Font = Enum.Font.GothamMedium; ver.TextSize = 10; ver.TextXAlignment = Enum.TextXAlignment.Left
local auth = Instance.new("TextLabel", profile); auth.Size = UDim2.new(1, -30, 0, 14); auth.Position = UDim2.fromOffset(15, 60); auth.BackgroundTransparency = 1; auth.Text = "Author: Fatal"; auth.TextColor3 = C.dim; auth.Font = Enum.Font.GothamMedium; auth.TextSize = 10; auth.TextXAlignment = Enum.TextXAlignment.Left
local pages = Instance.new("Frame", main); pages.Size = UDim2.new(1, -150, 1, -40); pages.Position = UDim2.fromOffset(140, 35); pages.BackgroundTransparency = 1
local function makePage() local sf = Instance.new("ScrollingFrame", pages); sf.Size = UDim2.fromScale(1, 1); sf.BackgroundTransparency = 1; sf.BorderSizePixel = 0; sf.ScrollBarThickness = 2; sf.ScrollBarImageColor3 = C.stroke; sf.CanvasSize = UDim2.new(0,0,0,0); sf.ScrollingDirection = Enum.ScrollingDirection.Y; sf.Visible = false; local lay = Instance.new("UIListLayout", sf); lay.Padding = UDim.new(0, 8); lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() sf.CanvasSize = UDim2.new(0,0,0, lay.AbsoluteContentSize.Y + 10) end); return sf end
local espPage, combatPage, mainPage = makePage(), makePage(), makePage()
local tabs = {}
local function makeTab(name, label, page, y) local btn = Instance.new("TextButton", sidebar); btn.Size = UDim2.new(1, -20, 0, 36); btn.Position = UDim2.fromOffset(10, y); btn.BackgroundColor3 = C.card; btn.BackgroundTransparency = 1; btn.Text = label; btn.TextColor3 = C.dim; btn.Font = Enum.Font.GothamMedium; btn.TextSize = 13; btn.AutoButtonColor = false; Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4); btn.MouseButton1Click:Connect(function() for _, t in pairs(tabs) do t.btn.BackgroundTransparency = 1; t.btn.TextColor3 = C.dim; t.page.Visible = false end btn.BackgroundTransparency = 0; btn.TextColor3 = C.text; page.Visible = true; headerTitle.Text = "Vortex Hub / " .. label end); tabs[name] = {btn=btn, page=page} end
makeTab("visuals", "Visuals", espPage, 10) makeTab("combat", "Combat", combatPage, 52) makeTab("main", "Main", mainPage, 94)
tabs["visuals"].btn.BackgroundTransparency = 0; tabs["visuals"].btn.TextColor3 = C.text; espPage.Visible = true

local function makeSection(parent, title) local f = Instance.new("Frame", parent); f.Size = UDim2.new(1, -10, 0, 24); f.BackgroundTransparency = 1; local l = Instance.new("TextLabel", f); l.Size = UDim2.fromScale(1, 1); l.BackgroundTransparency = 1; l.Text = title; l.TextColor3 = C.dim; l.Font = Enum.Font.GothamBold; l.TextSize = 11; l.TextXAlignment = Enum.TextXAlignment.Left end

local function makeToggle(parent, text, default, cb, id) local row = Instance.new("Frame", parent); row.Size = UDim2.new(1, -10, 0, 36); row.BackgroundColor3 = C.card; row.BorderSizePixel = 0; row.Active = true; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4); local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(1, -50, 1, 0); lbl.Position = UDim2.fromOffset(12, 0); lbl.BackgroundTransparency = 1; lbl.Text = text; lbl.TextColor3 = C.dim; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 13; lbl.TextXAlignment = Enum.TextXAlignment.Left; local box = Instance.new("Frame", row); box.Size = UDim2.fromOffset(18, 18); box.Position = UDim2.new(1, -30, 0.5, -9); box.BackgroundColor3 = C.bg; box.BorderSizePixel = 0; Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3); local bs = Instance.new("UIStroke", box); bs.Color = C.stroke; local check = Instance.new("Frame", box); check.Size = UDim2.new(1, -6, 1, -6); check.Position = UDim2.fromOffset(3, 3); check.BackgroundColor3 = C.text; check.BorderSizePixel = 0; Instance.new("UICorner", check).CornerRadius = UDim.new(0, 2); local state = default; local function set(v) state = v; check.Visible = v; lbl.TextColor3 = v and C.text or C.dim; bs.Color = v and C.text or C.stroke; if cb then cb(v) end end if id then _G.VortexUI.toggles[id] = set end check.Visible = default row.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then set(not state) end end) end

local function makeSlider(parent, text, min, max, default, cb, fmt, id) local row = Instance.new("Frame", parent); row.Size = UDim2.new(1, -10, 0, 36); row.BackgroundColor3 = C.card; row.BorderSizePixel = 0; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4); local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(1, -150, 1, 0); lbl.Position = UDim2.fromOffset(12, 0); lbl.BackgroundTransparency = 1; lbl.Text = text; lbl.TextColor3 = C.text; lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 13; lbl.TextXAlignment = Enum.TextXAlignment.Left; local track = Instance.new("Frame", row); track.Size = UDim2.new(0.25, 0, 0, 4); track.Position = UDim2.new(0.55, -10, 0.5, -2); track.BackgroundColor3 = C.bg; track.BorderSizePixel = 0; local fill = Instance.new("Frame", track); fill.Size = UDim2.new(math.clamp((default-min)/(max-min), 0, 1), 0, 1, 0); fill.BackgroundColor3 = C.text; fill.BorderSizePixel = 0; local val = Instance.new("TextLabel", row); val.Size = UDim2.fromOffset(55, 36); val.Position = UDim2.new(1, -60, 0, 0); val.BackgroundTransparency = 1; val.Text = fmt and fmt(default) or tostring(default); val.TextColor3 = C.dim; val.Font = Enum.Font.GothamBold; val.TextSize = 12; val.TextXAlignment = Enum.TextXAlignment.Right; local hit = Instance.new("Frame", row); hit.Size = UDim2.new(0.3, 0, 1, 0); hit.Position = UDim2.new(0.5, 0, 0, 0); hit.BackgroundTransparency = 1; hit.Active = true; local function set(v) local rel = math.clamp((v - min) / (max - min), 0, 1); fill.Size = UDim2.new(rel, 0, 1, 0); val.Text = fmt and fmt(v) or tostring(v); if cb then cb(v) end end if id then _G.VortexUI.sliders[id] = set end local drag = false local function setX(x) local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1); set(math.floor(min + rel * (max - min) + 0.5)) end hit.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = true; setX(i.Position.X) end end) UIS.InputChanged:Connect(function(i) if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then setX(i.Position.X) end end) UIS.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end end) return row end
-- Vortex Hub | v1 (Part 2/4)

task.spawn(function()
    while running do
        task.wait(0.3)
        if not running then break end
        pcall(function()
            local cam = workspace.CurrentCamera
            local myChar = getLocalChar()
            if not cam then return end
            local newT = {}

            local function processModel(model)
                if not model or not model:IsA("Model") then return end
                local hum = model:FindFirstChildOfClass("Humanoid")
                local head = model:FindFirstChild("Head") or model:FindFirstChild("head") or model:FindFirstChild("HumanoidRootPart")
                
                if hum and head and head:IsA("BasePart") and hum.Health > 0 then
                    if model == myChar or model.Parent == cam then return end
                    if model.Name == lp.Name or model.Name == lp.DisplayName then return end
                    
                    local friend = isFriend(model)
                    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso") or head
                    local visible = true
                    local origin = cam.CFrame.Position
                    rayParams.FilterDescendantsInstances = {model, myChar}
                    if workspace:Raycast(origin, head.Position - origin, rayParams) then visible = false end

                    local bones = {}
                    for i = 1, SKELETON_COUNT do
                        local pair = SKELETON_PAIRS[i]
                        bones[i] = {model:FindFirstChild(pair[1]), model:FindFirstChild(pair[2])}
                    end

                    if not friend then
                        if bigHeadScale > 1 then
                            if not origHeadSizes[head] then origHeadSizes[head] = head.Size end
                            head.Size = origHeadSizes[head] * bigHeadScale
                        elseif origHeadSizes[head] then
                            head.Size = origHeadSizes[head]; origHeadSizes[head] = nil
                        end
                    elseif origHeadSizes[head] then
                        head.Size = origHeadSizes[head]; origHeadSizes[head] = nil
                    end

                    newT[model] = {char=model, head=head, root=root, name=model.Name, hum=hum, visible=visible, bones=bones, isFriend=friend}
                end
            end

            local wp = workspace:FindFirstChild("Players")
            if wp then for _, c in ipairs(wp:GetChildren()) do processModel(c) end end
            for _, c in ipairs(workspace:GetChildren()) do 
                if c:IsA("Model") and c.Name ~= "Players" then processModel(c) end 
            end
            for _, folder in ipairs(workspace:GetChildren()) do
                if folder:IsA("Folder") and folder.Name ~= "Players" then
                    for _, c in ipairs(folder:GetChildren()) do if c:IsA("Model") then processModel(c) end end
                end
            end

            cachedTargets = newT
            for char, b in pairs(espBoxes) do if not newT[char] then pcall(function() b.box:Destroy() end); espBoxes[char] = nil end end
            for char, d in pairs(tracerDrawings) do if not newT[char] then pcall(function() d:Remove() end); tracerDrawings[char] = nil end end
            for char, entry in pairs(skeletonDrawings) do if not newT[char] then for _, l in pairs(entry.lines) do pcall(function() l:Remove() end) end; skeletonDrawings[char] = nil end end
            for char, a in pairs(arrowDrawings) do if not newT[char] then pcall(function() a.line:Remove() end); pcall(function() a.dot:Remove() end); arrowDrawings[char] = nil end end
            for head in pairs(origHeadSizes) do if not head.Parent then origHeadSizes[head] = nil end end
        end)
    end
end)

local function getBox(char, name)
    if espBoxes[char] then return espBoxes[char] end
    local box = Instance.new("Frame", espGui)
    box.BackgroundTransparency = 1; box.BorderSizePixel = 0; box.Visible = false
    local s = Instance.new("UIStroke", box); s.Color = C.vis; s.Thickness = 1.5
    local grad = Instance.new("UIGradient", s)
    local lbl = Instance.new("TextLabel", box)
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, 60, 0, 14)
    lbl.Position = UDim2.new(0, -30, -16, 0); lbl.TextColor3 = C.vis
    lbl.Font = Enum.Font.Code; lbl.TextSize = 12; lbl.TextStrokeTransparency = 0.3
    lbl.Text = name
    espBoxes[char] = {box=box, stroke=s, grad=grad, name=lbl}
    return espBoxes[char]
end

local renderThrottle = 0
RunService.Heartbeat:Connect(function()
    if not running then return end
    local now = tick()
    if now - renderThrottle < 0.03 then return end
    renderThrottle = now

    pcall(function()
        local cam = workspace.CurrentCamera
        if not cam then return end
        local vp = cam.ViewportSize
        if vp.X == 0 then return end
        local bx, by = vp.X/2, vp.Y
        local cx, cy = vp.X/2, vp.Y/2

        local espC1 = Color3.fromHSV(espColor1H, 1, 1)
        local espC2 = Color3.fromHSV(espColor2H, 1, 1)
        local espSeq = ColorSequence.new(espC1, espC2)

        for char, t in pairs(cachedTargets) do
            local col = t.isFriend and C.friend or (t.visible and C.vis or C.occ)
            
            if chamsEnabled and char.Parent then
                local hl = chamsHighlights[char]
                if not hl then
                    hl = Instance.new("Highlight"); hl.Adornee = char; hl.FillTransparency = 0.5
                    hl.OutlineTransparency = 0; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.Parent = chamsFolder; chamsHighlights[char] = hl
                end
                hl.FillColor = col; hl.OutlineColor = col
            elseif chamsHighlights[char] and not chamsEnabled then
                pcall(function() chamsHighlights[char]:Destroy() end); chamsHighlights[char] = nil
            end

            if char.Parent and t.head and t.head.Parent then
                local sp = cam:WorldToViewportPoint(t.head.Position)
                local onScreen = sp.Z > 0 and sp.X >= 0 and sp.X <= vp.X and sp.Y >= 0 and sp.Y <= vp.Y

                if sp.Z > 0 then
                    if espEnabled and t.root and t.root.Parent then
                        local sp2 = cam:WorldToViewportPoint(t.root.Position - Vector3.new(0, 2, 0))
                        local h = math.abs(sp2.Y - sp.Y)
                        if h > 5 then
                            local w = h * 0.5
                            local b = getBox(char, t.name)
                            
                            -- DISTANCE ESP LOGIC
                            local finalName = t.name
                            if distEspEnabled then
                                local dist = math.floor((cam.CFrame.Position - t.head.Position).Magnitude)
                                finalName = t.name .. " [" .. dist .. "m]"
                            end
                            
                            b.box.Size = UDim2.fromOffset(w, h); b.box.Position = UDim2.fromOffset(sp.X - w/2, sp.Y); b.box.Visible = true
                            b.stroke.Color = col; b.grad.Color = espSeq
                            b.name.TextColor3 = col
                            if b.name.Text ~= finalName then b.name.Text = finalName end
                        else
                            local b = espBoxes[char]; if b then b.box.Visible = false end
                        end
                    elseif not espEnabled then
                        local b = espBoxes[char]; if b then b.box.Visible = false end
                    end
                    
                    if tracerEnabled and hasDrawing then
                        local d = tracerDrawings[char]
                        if not d then local ok, nd = pcall(function() return Drawing.new("Line") end); if ok and nd then nd.Thickness = 1.5; tracerDrawings[char] = nd; d = nd end end
                        if d then d.From = Vector2.new(bx, by); d.To = Vector2.new(sp.X, sp.Y); d.Color = col; d.Visible = true end
                    elseif not tracerEnabled then local d = tracerDrawings[char]; if d then d.Visible = false end end
                    
                    if skeletonEnabled and hasDrawing then
                        local entry = skeletonDrawings[char] or {lines={}}
                        skeletonDrawings[char] = entry
                        for i = 1, SKELETON_COUNT do
                            local bones = t.bones[i]; local line = entry.lines[i]
                            if not line then local ok, nl = pcall(function() return Drawing.new("Line") end); if ok and nl then nl.Thickness = 1; entry.lines[i] = nl; line = nl end end
                            if line and bones and bones[1] and bones[2] and bones[1].Parent and bones[2].Parent then
                                local v1 = cam:WorldToViewportPoint(bones[1].Position); local v2 = cam:WorldToViewportPoint(bones[2].Position)
                                if v1.Z > 0 and v2.Z > 0 then line.From = Vector2.new(v1.X, v1.Y); line.To = Vector2.new(v2.X, v2.Y); line.Color = col; line.Visible = true else line.Visible = false end
                            elseif line then line.Visible = false end
                        end
                    elseif not skeletonEnabled and skeletonDrawings[char] then for _, line in pairs(skeletonDrawings[char].lines) do line.Visible = false end end
                else
                    local b = espBoxes[char]; if b then b.box.Visible = false end
                    local d = tracerDrawings[char]; if d then d.Visible = false end
                    if skeletonDrawings[char] then for _, l in pairs(skeletonDrawings[char].lines) do l.Visible = false end end
                end
                
                if arrowsEnabled and hasDrawing and hasCircles then
                    local a = arrowDrawings[char]
                    if not a then local ok, nl = pcall(function() return {line = Drawing.new("Line"), dot = Drawing.new("Circle")} end); if ok and nl then nl.line.Thickness = 3; nl.dot.Radius = 5; nl.dot.Filled = true; arrowDrawings[char] = nl; a = nl end end
                    if a and not onScreen and sp.Z ~= 0 then
                        local dx, dy = sp.X - cx, sp.Y - cy; if sp.Z < 0 then dx = -dx; dy = -dy end
                        local angle = math.atan2(dy, dx); local radius = math.min(vp.X, vp.Y) * 0.15
                        local edgeX = cx + math.cos(angle) * radius; local edgeY = cy + math.sin(angle) * radius
                        a.line.From = Vector2.new(cx, cy); a.line.To = Vector2.new(edgeX, edgeY); a.line.Color = col; a.line.Visible = true
                        a.dot.Position = Vector2.new(edgeX, edgeY); a.dot.Color = col; a.dot.Visible = true
                    elseif a then a.line.Visible = false; a.dot.Visible = false end
                elseif not arrowsEnabled and arrowDrawings[char] then arrowDrawings[char].line.Visible = false; arrowDrawings[char].dot.Visible = false end
            end
        end
    end)
end)
-- Vortex Hub | v1 (Part 3/4)

local function getWeaponName(char)
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then return tool.Name end
    local rh = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
    if rh then
        for _, child in ipairs(rh:GetChildren()) do
            if child:IsA("BasePart") or child:IsA("Model") then 
                if child.Name ~= "RightHand" and child.Name ~= "Right Arm" and child.Name ~= "Handle" then return child.Name end 
            end
        end
    end
    return "None"
end

UIS.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbHeld = true end end)
UIS.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbHeld = false end end)

local savedCamType, savedOffset, myRootCached, rootRefreshCounter = nil, nil, nil, 0
local function releaseAim() if savedCamType then local cam = workspace.CurrentCamera; if cam then cam.CameraType = savedCamType end; savedCamType = nil end end

local cachedAimTarget = nil
local cachedAimChar = nil
task.spawn(function()
    while running do
        task.wait(0.05)
        if not running then break end
        pcall(function()
            if not aimEnabled or main.Visible or not rmbHeld then cachedAimTarget = nil; cachedAimChar = nil; return end
            local cam = workspace.CurrentCamera
            if not cam then return end
            local vp = cam.ViewportSize; local cx, cy = vp.X/2, vp.Y/2
            local bestDist, best, bestChar = aimFov * aimFov, nil, nil
            for char, t in pairs(cachedTargets) do
                if t.head and t.head.Parent and not t.isFriend then
                    local sp = cam:WorldToViewportPoint(t.head.Position)
                    if sp.Z > 0 then
                        local dx, dy = sp.X - cx, sp.Y - cy; local d2 = dx*dx + dy*dy
                        if d2 < bestDist then bestDist = d2; best = t.head; bestChar = char end
                    end
                end
            end
            cachedAimTarget = best
            cachedAimChar = bestChar
        end)
    end
end)

local function aimUpdate()
    if not running then return end
    pcall(function()
        if not aimEnabled or main.Visible then releaseAim(); currentAimTargetChar = nil; return end
        currentAimTargetChar = cachedAimChar
        if not rmbHeld then releaseAim(); return end
        if not cachedAimTarget then releaseAim(); return end
        
        local char = getLocalChar(); if not char then releaseAim(); return end
        local myRoot = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head") or char:FindFirstChild("Torso")
        if not myRoot then releaseAim(); return end
        if not savedCamType then
            savedCamType = workspace.CurrentCamera.CameraType; savedOffset = myRoot.CFrame:PointToObjectSpace(workspace.CurrentCamera.CFrame.Position); myRootCached = myRoot; workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
        end
        rootRefreshCounter = rootRefreshCounter + 1
        if rootRefreshCounter >= 20 then rootRefreshCounter = 0; myRootCached = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head") or char:FindFirstChild("Torso") end
        if not myRootCached or not myRootCached.Parent then releaseAim(); return end
        workspace.CurrentCamera.CFrame = CFrame.lookAt(myRootCached.CFrame:PointToWorldSpace(savedOffset), cachedAimTarget.Position)
    end)
end
pcall(function() RunService:UnbindFromRenderStep("VortexAim") end)
RunService:BindToRenderStep("VortexAim", Enum.RenderPriority.Camera.Value + 1, aimUpdate)

task.spawn(function()
    while running do
        task.wait(0.05); if not running then break end
        pcall(function()
            if not targetHudEnabled or not currentAimTargetChar or not currentAimTargetChar.Parent then targetHud.Visible = false; return end
            local hum = currentAimTargetChar:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                targetHud.Visible = true; thName.Text = currentAimTargetChar.Name
                
                -- WEAPON HUD UPDATE
                thWeapon.Text = "Weapon: " .. getWeaponName(currentAimTargetChar)
                
                local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1); thHpFill.Size = UDim2.fromScale(pct, 1); thHpText.Text = math.floor(hum.Health) .. " / " .. math.floor(hum.MaxHealth)
                if pct > 0.5 then thHpFill.BackgroundColor3 = C.vis elseif pct > 0.25 then thHpFill.BackgroundColor3 = Color3.fromRGB(255, 255, 50) else thHpFill.BackgroundColor3 = C.occ end
            else targetHud.Visible = false end
        end)
    end
end)

makeSection(espPage, "ESP")
makeToggle(espPage, "Player & Bot Boxes", false, function(on) espEnabled = on end, "esp")
makeToggle(espPage, "Distance ESP", false, function(on) distEspEnabled = on end, "distesp")
makeToggle(espPage, "Tracers", false, function(on) tracerEnabled = on end, "tracer")
makeToggle(espPage, "Skeleton", false, function(on) skeletonEnabled = on; if not on then for _, entry in pairs(skeletonDrawings) do for _, l in pairs(entry.lines) do l.Visible = false end end end end, "skeleton")
makeToggle(espPage, "Arrows", false, function(on) arrowsEnabled = on end, "arrows")
makeSection(espPage, "CHAMS")
makeToggle(espPage, "Enable Chams", false, function(on) chamsEnabled = on; if not on then for char, hl in pairs(chamsHighlights) do pcall(function() hl:Destroy() end) end; chamsHighlights = {} end end, "chams")
makeSection(espPage, "WORLD")
makeToggle(espPage, "Fullbright", false, function(on) fullbrightEnabled = on; applyFullbright(on) end, "fullbright")

-- CROSSHAIR UI
makeSection(mainPage, "CUSTOM CROSSHAIR")
makeToggle(mainPage, "Enable Crosshair", false, function(on) crosshairEnabled = on; updateCrosshair() end, "chenabled")
makeSlider(mainPage, "Crosshair Length", 1, 30, chLength, function(v) chLength = v; updateCrosshair() end, nil, "chlen")
makeSlider(mainPage, "Crosshair Gap", 0, 20, chGap, function(v) chGap = v; updateCrosshair() end, nil, "chgap")
makeSlider(mainPage, "Crosshair Thickness", 1, 10, chThickness, function(v) chThickness = v; updateCrosshair() end, nil, "chthick")
makeSlider(mainPage, "Crosshair Dot Size", 0, 10, chDotSize, function(v) chDotSize = v; updateCrosshair() end, nil, "chdot")
makeSlider(mainPage, "CH Color (Hue)", 0, 360, 0, function(v) chColor = Color3.fromHSV(v/360, 1, 1); updateCrosshair() end, nil, "chcolor")

makeSection(combatPage, "AIMBOT")
makeToggle(combatPage, "Aimbot (Hold RMB)", false, function(on) aimEnabled = on; fovCircle.Visible = on; if not on then releaseAim() end end, "aimbot")
makeSlider(combatPage, "Aim FOV", 30, 800, aimFov, function(v) aimFov = v; fovCircle.Size = UDim2.fromOffset(aimFov*2, aimFov*2) end, nil, "fov")
makeSection(combatPage, "HITBOX")
makeSlider(combatPage, "Big Head", 1, 5, 1, function(v) bigHeadScale = v end, function(v) return v.."x" end, "bighead")
makeSection(combatPage, "TARGET HUD")
makeToggle(combatPage, "Enable Target HUD", false, function(on) targetHudEnabled = on; if not on then targetHud.Visible = false end end, "hud")

makeSection(mainPage, "CAMERA & FOV")
makeToggle(mainPage, "Third Person", false, function(on) thirdPersonEnabled = on; if on then lp.CameraMode = Enum.CameraMode.Classic else lp.CameraMode = Enum.CameraMode.LockFirstPerson end end, "thirdperson")
makeSlider(mainPage, "Third Person Dist", 5, 20, 12, function(v) thirdPersonDist = v; lp.CameraMaxZoomDistance = v; lp.CameraMinZoomDistance = v end, function(v) return v.."m" end, "tpdist")
makeSlider(mainPage, "Camera FOV", 70, 100, 70, function(v) camFov = v; local cam = workspace.CurrentCamera; if cam and not isZooming then cam.FieldOfView = v end end, nil, "camfov")

makeSection(mainPage, "UI GRADIENTS")
makeSlider(mainPage, "Hub Color 1", 0, 360, hubColor1H * 360, function(v) hubColor1H = v / 360; hubGrad.Color = ColorSequence.new(Color3.fromHSV(hubColor1H, 0.5, 0.2), Color3.fromHSV(hubColor2H, 0.5, 0.2)) end, nil, "hubc1")
makeSlider(mainPage, "Hub Color 2", 0, 360, hubColor2H * 360, function(v) hubColor2H = v / 360; hubGrad.Color = ColorSequence.new(Color3.fromHSV(hubColor1H, 0.5, 0.2), Color3.fromHSV(hubColor2H, 0.5, 0.2)) end, nil, "hubc2")
makeSlider(mainPage, "ESP Color 1", 0, 360, espColor1H * 360, function(v) espColor1H = v / 360 end, nil, "espc1")
makeSlider(mainPage, "ESP Color 2", 0, 360, espColor2H * 360, function(v) espColor2H = v / 360 end, nil, "espc2")
-- Vortex Hub | v1 (Part 4/4)

makeSection(mainPage, "FRIENDS")
local friendInputRow = Instance.new("Frame", mainPage); friendInputRow.Size = UDim2.new(1, -10, 0, 36); friendInputRow.BackgroundColor3 = C.card; friendInputRow.BorderSizePixel = 0
Instance.new("UICorner", friendInputRow).CornerRadius = UDim.new(0, 4)
local friendBox = Instance.new("TextBox", friendInputRow); friendBox.Size = UDim2.new(0.6, -10, 0, 26); friendBox.Position = UDim2.new(0, 10, 0.5, -13); friendBox.BackgroundColor3 = C.bg; friendBox.BorderSizePixel = 0
Instance.new("UICorner", friendBox).CornerRadius = UDim.new(0, 4); friendBox.PlaceholderText = "Player name..."; friendBox.Text = ""; friendBox.TextColor3 = C.text; friendBox.Font = Enum.Font.GothamMedium; friendBox.TextSize = 12
local friendAddBtn = Instance.new("TextButton", friendInputRow); friendAddBtn.Size = UDim2.fromOffset(60, 26); friendAddBtn.Position = UDim2.new(0.6, 5, 0.5, -13); friendAddBtn.BackgroundColor3 = C.vis; friendAddBtn.BackgroundTransparency = 0.5; friendAddBtn.BorderSizePixel = 0
Instance.new("UICorner", friendAddBtn).CornerRadius = UDim.new(0, 4); friendAddBtn.Text = "Add"; friendAddBtn.TextColor3 = C.text; friendAddBtn.Font = Enum.Font.GothamBold; friendAddBtn.TextSize = 12; friendAddBtn.AutoButtonColor = false

local friendList = Instance.new("ScrollingFrame", mainPage); friendList.Size = UDim2.new(1, -10, 0, 100); friendList.BackgroundColor3 = C.card; friendList.BorderSizePixel = 0
Instance.new("UICorner", friendList).CornerRadius = UDim.new(0, 4); friendList.ScrollBarThickness = 2; friendList.ScrollBarImageColor3 = C.stroke; friendList.CanvasSize = UDim2.new(0, 0, 0, 0)
local fLayout = Instance.new("UIListLayout", friendList); fLayout.SortOrder = Enum.SortOrder.LayoutOrder; fLayout.Padding = UDim.new(0, 4)
fLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() friendList.CanvasSize = UDim2.new(0, 0, 0, fLayout.AbsoluteContentSize.Y) end)

local function refreshFriendList()
    for _, c in ipairs(friendList:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local hasAny = false
    for name, _ in pairs(friends) do
        hasAny = true
        local row = Instance.new("Frame", friendList); row.Name = name; row.Size = UDim2.new(1, -6, 0, 26); row.BackgroundColor3 = C.bg; row.BorderSizePixel = 0
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)
        local nameLbl = Instance.new("TextLabel", row); nameLbl.Size = UDim2.new(1, -80, 1, 0); nameLbl.Position = UDim2.fromOffset(8, 0); nameLbl.BackgroundTransparency = 1; nameLbl.Text = name; nameLbl.TextColor3 = C.friend; nameLbl.Font = Enum.Font.GothamMedium; nameLbl.TextSize = 12; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        local removeBtn = Instance.new("TextButton", row); removeBtn.Size = UDim2.fromOffset(70, 20); removeBtn.Position = UDim2.new(1, -75, 0.5, -10); removeBtn.BackgroundColor3 = C.occ; removeBtn.BackgroundTransparency = 0.5; removeBtn.BorderSizePixel = 0
        Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 3); removeBtn.Text = "Remove"; removeBtn.TextColor3 = C.text; removeBtn.Font = Enum.Font.GothamBold; removeBtn.TextSize = 11; removeBtn.AutoButtonColor = false
        removeBtn.MouseButton1Click:Connect(function() removeFriend(name); refreshFriendList() end)
    end
    if not hasAny then
        local emptyLbl = Instance.new("TextLabel", friendList); emptyLbl.Name = "Empty"; emptyLbl.Size = UDim2.new(1, -6, 0, 26); emptyLbl.BackgroundTransparency = 1; emptyLbl.Text = "No friends added"; emptyLbl.TextColor3 = C.dim; emptyLbl.Font = Enum.Font.GothamMedium; emptyLbl.TextSize = 11; emptyLbl.TextXAlignment = Enum.TextXAlignment.Left
    end
end
refreshFriendList()
friendAddBtn.MouseButton1Click:Connect(function() local n = friendBox.Text; if n and n ~= "" then addFriend(n); friendBox.Text = ""; refreshFriendList() end end)

local configFolder = "VortexHub_Configs"
local autoLoadFile = "VortexHub_AutoLoad.json"
pcall(function() if makefolder and not isfolder(configFolder) then makefolder(configFolder) end end)

local function getConfigs() local list = {}; if listfiles then local ok, files = pcall(listfiles, configFolder); if ok and files then for _, file in ipairs(files) do local name = file:match("([^/\\]+)%.json$"); if name then table.insert(list, name) end end end end; return list end
local function saveConfigToFile(name)
    if not writefile then return end
    local data = {
        esp = espEnabled, distesp = distEspEnabled, tracer = tracerEnabled, skeleton = skeletonEnabled, arrows = arrowsEnabled, chams = chamsEnabled,
        aim = aimEnabled, fov = aimFov, bighead = bigHeadScale, hud = targetHudEnabled,
        fullbright = fullbrightEnabled, thirdperson = thirdPersonEnabled, tpdist = thirdPersonDist, camfov = camFov,
        hubc1 = hubColor1H * 360, hubc2 = hubColor2H * 360, espc1 = espColor1H * 360, espc2 = espColor2H * 360,
        chenabled = crosshairEnabled, chlen = chLength, chgap = chGap, chthick = chThickness, chdot = chDotSize, chcolor = chColor:ToHSV() * 360
    }
    pcall(writefile, configFolder .. "/" .. name .. ".json", HttpService:JSONEncode(data))
end
local function loadConfigFromFile(name)
    if not readfile then return end
    local ok, data = pcall(readfile, configFolder .. "/" .. name .. ".json"); if not ok or not data then return end
    local decOk, decoded = pcall(function() return HttpService:JSONDecode(data) end); if not decOk or not decoded then return end
    local UI = _G.VortexUI
    if decoded.esp ~= nil and UI.toggles.esp then UI.toggles.esp(decoded.esp) end
    if decoded.distesp ~= nil and UI.toggles.distesp then UI.toggles.distesp(decoded.distesp) end
    if decoded.tracer ~= nil and UI.toggles.tracer then UI.toggles.tracer(decoded.tracer) end
    if decoded.skeleton ~= nil and UI.toggles.skeleton then UI.toggles.skeleton(decoded.skeleton) end
    if decoded.arrows ~= nil and UI.toggles.arrows then UI.toggles.arrows(decoded.arrows) end
    if decoded.chams ~= nil and UI.toggles.chams then UI.toggles.chams(decoded.chams) end
    if decoded.aim ~= nil and UI.toggles.aimbot then UI.toggles.aimbot(decoded.aim) end
    if decoded.hud ~= nil and UI.toggles.hud then UI.toggles.hud(decoded.hud) end
    if decoded.fullbright ~= nil and UI.toggles.fullbright then UI.toggles.fullbright(decoded.fullbright) end
    if decoded.thirdperson ~= nil and UI.toggles.thirdperson then UI.toggles.thirdperson(decoded.thirdperson) end
    if decoded.chenabled ~= nil and UI.toggles.chenabled then UI.toggles.chenabled(decoded.chenabled) end
    
    if decoded.fov ~= nil and UI.sliders.fov then UI.sliders.fov(decoded.fov) end
    if decoded.bighead ~= nil and UI.sliders.bighead then UI.sliders.bighead(decoded.bighead) end
    if decoded.tpdist ~= nil and UI.sliders.tpdist then UI.sliders.tpdist(decoded.tpdist) end
    if decoded.camfov ~= nil and UI.sliders.camfov then UI.sliders.camfov(decoded.camfov) end
    if decoded.hubc1 ~= nil and UI.sliders.hubc1 then UI.sliders.hubc1(decoded.hubc1) end
    if decoded.hubc2 ~= nil and UI.sliders.hubc2 then UI.sliders.hubc2(decoded.hubc2) end
    if decoded.espc1 ~= nil and UI.sliders.espc1 then UI.sliders.espc1(decoded.espc1) end
    if decoded.espc2 ~= nil and UI.sliders.espc2 then UI.sliders.espc2(decoded.espc2) end
    if decoded.chlen ~= nil and UI.sliders.chlen then UI.sliders.chlen(decoded.chlen) end
    if decoded.chgap ~= nil and UI.sliders.chgap then UI.sliders.chgap(decoded.chgap) end
    if decoded.chthick ~= nil and UI.sliders.chthick then UI.sliders.chthick(decoded.chthick) end
    if decoded.chdot ~= nil and UI.sliders.chdot then UI.sliders.chdot(decoded.chdot) end
    if decoded.chcolor ~= nil and UI.sliders.chcolor then UI.sliders.chcolor(decoded.chcolor) end
end
local function deleteConfigFile(name) 
    if delfile then pcall(delfile, configFolder .. "/" .. name .. ".json") elseif os and os.remove then pcall(os.remove, configFolder .. "/" .. name .. ".json") end 
    local ok, auto = pcall(readfile, autoLoadFile)
    if ok and auto then local dec, aName = pcall(function() return HttpService:JSONDecode(auto) end); if dec and aName == name then pcall(delfile, autoLoadFile) end end
end

makeSection(mainPage, "CONFIGS")
local configList = Instance.new("ScrollingFrame", mainPage); configList.Size = UDim2.new(1, -10, 0, 140); configList.BackgroundColor3 = C.card; configList.BorderSizePixel = 0
Instance.new("UICorner", configList).CornerRadius = UDim.new(0, 4); configList.ScrollBarThickness = 2; configList.ScrollBarImageColor3 = C.stroke; configList.CanvasSize = UDim2.new(0,0,0,0)
local cLayout = Instance.new("UIListLayout", configList); cLayout.SortOrder = Enum.SortOrder.LayoutOrder; cLayout.Padding = UDim.new(0,4)
cLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() configList.CanvasSize = UDim2.new(0,0,0,cLayout.AbsoluteContentSize.Y) end)

local function refreshConfigList()
    for _, c in ipairs(configList:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local configs = getConfigs()
    local okAuto, autoData = pcall(readfile, autoLoadFile)
    local autoName = nil
    if okAuto and autoData then local dOk, dn = pcall(function() return HttpService:JSONDecode(autoData) end); if dOk then autoName = dn end end
    
    if #configs == 0 then
        local emptyLbl = Instance.new("TextLabel", configList); emptyLbl.Name = "Empty"; emptyLbl.Size = UDim2.new(1, -6, 0, 26); emptyLbl.BackgroundTransparency = 1; emptyLbl.Text = "No configs saved"; emptyLbl.TextColor3 = C.dim; emptyLbl.Font = Enum.Font.GothamMedium; emptyLbl.TextSize = 11; emptyLbl.TextXAlignment = Enum.TextXAlignment.Left; return
    end
    for _, name in ipairs(configs) do
        local row = Instance.new("Frame", configList); row.Name = name; row.Size = UDim2.new(1, -6, 0, 28); row.BackgroundColor3 = C.bg; row.BorderSizePixel = 0; Instance.new("UICorner", row).CornerRadius = UDim.new(0,4)
        
        local nameLbl = Instance.new("TextLabel", row); nameLbl.Size = UDim2.new(1, -155, 1, 0); nameLbl.Position = UDim2.fromOffset(8, 0); nameLbl.BackgroundTransparency = 1; nameLbl.Text = name; nameLbl.TextColor3 = (name == autoName) and C.vis or C.text; nameLbl.Font = Enum.Font.GothamMedium; nameLbl.TextSize = 12; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        
        local autoBtn = Instance.new("TextButton", row); autoBtn.Size = UDim2.fromOffset(45, 20); autoBtn.Position = UDim2.new(1, -150, 0.5, -10); autoBtn.BackgroundColor3 = C.card; autoBtn.BorderSizePixel = 0
        Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0,3); autoBtn.Text = (name == autoName) and "Auto" or "Set Auto"; autoBtn.TextColor3 = (name == autoName) and C.vis or C.dim; autoBtn.Font = Enum.Font.GothamBold; autoBtn.TextSize = 10; autoBtn.AutoButtonColor = false
        autoBtn.MouseButton1Click:Connect(function() 
            if name == autoName then pcall(delfile, autoLoadFile) else pcall(writefile, autoLoadFile, HttpService:JSONEncode(name)) end
            refreshConfigList() 
        end)

        local loadBtn = Instance.new("TextButton", row); loadBtn.Size = UDim2.fromOffset(45, 20); loadBtn.Position = UDim2.new(1, -100, 0.5, -10); loadBtn.BackgroundColor3 = C.vis; loadBtn.BackgroundTransparency = 0.6; loadBtn.BorderSizePixel = 0
        Instance.new("UICorner", loadBtn).CornerRadius = UDim.new(0,3); loadBtn.Text = "Load"; loadBtn.TextColor3 = C.text; loadBtn.Font = Enum.Font.GothamBold; loadBtn.TextSize = 11; loadBtn.AutoButtonColor = false
        loadBtn.MouseButton1Click:Connect(function() loadConfigFromFile(name); refreshConfigList() end)
        
        local delBtn = Instance.new("TextButton", row); delBtn.Size = UDim2.fromOffset(45, 20); delBtn.Position = UDim2.new(1, -50, 0.5, -10); delBtn.BackgroundColor3 = C.occ; delBtn.BackgroundTransparency = 0.5; delBtn.BorderSizePixel = 0
        Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0,3); delBtn.Text = "Delete"; delBtn.TextColor3 = C.text; delBtn.Font = Enum.Font.GothamBold; delBtn.TextSize = 11; delBtn.AutoButtonColor = false
        delBtn.MouseButton1Click:Connect(function() deleteConfigFile(name); refreshConfigList() end)
    end
end
refreshConfigList()

local saveRow = Instance.new("Frame", mainPage); saveRow.Size = UDim2.new(1, -10, 0, 36); saveRow.BackgroundColor3 = C.card; saveRow.BorderSizePixel = 0; Instance.new("UICorner", saveRow).CornerRadius = UDim.new(0,4)
local cfgBox = Instance.new("TextBox", saveRow); cfgBox.Size = UDim2.new(0.6, -10, 0, 26); cfgBox.Position = UDim2.new(0, 10, 0.5, -13); cfgBox.BackgroundColor3 = C.bg; cfgBox.BorderSizePixel = 0; Instance.new("UICorner", cfgBox).CornerRadius = UDim.new(0,4)
cfgBox.PlaceholderText = "Config Name..."; cfgBox.Text = ""; cfgBox.TextColor3 = C.text; cfgBox.Font = Enum.Font.GothamMedium; cfgBox.TextSize = 12

local promptFrame = Instance.new("Frame", hub); promptFrame.Size = UDim2.fromOffset(280, 100); promptFrame.Position = UDim2.fromScale(0.5, 0.5); promptFrame.AnchorPoint = Vector2.new(0.5, 0.5); promptFrame.BackgroundColor3 = C.bg; promptFrame.BorderSizePixel = 0; promptFrame.Visible = false; promptFrame.ZIndex = 200
Instance.new("UICorner", promptFrame).CornerRadius = UDim.new(0,6); Instance.new("UIStroke", promptFrame).Color = C.stroke
local pTxt = Instance.new("TextLabel", promptFrame); pTxt.Size = UDim2.new(1, -20, 0, 40); pTxt.Position = UDim2.fromOffset(10, 10); pTxt.BackgroundTransparency = 1; pTxt.Text = "Name already exists. Overwrite?"; pTxt.TextColor3 = C.text; pTxt.Font = Enum.Font.GothamMedium; pTxt.TextSize = 14
local pYes = Instance.new("TextButton", promptFrame); pYes.Size = UDim2.fromOffset(100, 26); pYes.Position = UDim2.new(0, 40, 1, -36); pYes.BackgroundColor3 = C.vis; pYes.BorderSizePixel = 0; Instance.new("UICorner", pYes).CornerRadius = UDim.new(0,4); pYes.Text = "Yes"; pYes.TextColor3 = C.bg; pYes.Font = Enum.Font.GothamBold; pYes.TextSize = 12
local pNo = Instance.new("TextButton", promptFrame); pNo.Size = UDim2.fromOffset(100, 26); pNo.Position = UDim2.new(1, -140, 1, -36); pNo.BackgroundColor3 = C.occ; pNo.BorderSizePixel = 0; Instance.new("UICorner", pNo).CornerRadius = UDim.new(0,4); pNo.Text = "No"; pNo.TextColor3 = C.text; pNo.Font = Enum.Font.GothamBold; pNo.TextSize = 12
local saveBtn = Instance.new("TextButton", saveRow); saveBtn.Size = UDim2.fromOffset(60, 26); saveBtn.Position = UDim2.new(0.6, 5, 0.5, -13); saveBtn.BackgroundColor3 = C.bg; saveBtn.BorderSizePixel = 0; Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0,4); saveBtn.Text = "Save"; saveBtn.TextColor3 = C.text; saveBtn.Font = Enum.Font.GothamBold; saveBtn.TextSize = 12; saveBtn.AutoButtonColor = false
saveBtn.MouseButton1Click:Connect(function() local name = cfgBox.Text; if name == "" then return end; if isfile and isfile(configFolder .. "/" .. name .. ".json") then promptFrame.Visible = true; pYes.MouseButton1Click:Connect(function() saveConfigToFile(name); refreshConfigList(); promptFrame.Visible = false end) else saveConfigToFile(name); refreshConfigList() end end)
pNo.MouseButton1Click:Connect(function() promptFrame.Visible = false end)

local closeRow = Instance.new("Frame", mainPage); closeRow.Size = UDim2.new(1, -10, 0, 36); closeRow.BackgroundColor3 = Color3.fromRGB(40, 10, 10); closeRow.BorderSizePixel = 0; Instance.new("UICorner", closeRow).CornerRadius = UDim.new(0,4)
local closeBtn = Instance.new("TextButton", closeRow); closeBtn.Size = UDim2.fromScale(1, 1); closeBtn.BackgroundTransparency = 1; closeBtn.Text = "Close Hub (Unload)"; closeBtn.TextColor3 = C.occ; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 13; closeBtn.AutoButtonColor = false
closeBtn.MouseButton1Click:Connect(function()
    running = false; pcall(function() RunService:UnbindFromRenderStep("VortexAim") end)
    for char, hl in pairs(chamsHighlights) do pcall(function() hl:Destroy() end) end
    for head, size in pairs(origHeadSizes) do pcall(function() head.Size = size end) end
    for _, d in pairs(tracerDrawings) do pcall(function() d:Remove() end) end
    for _, entry in pairs(skeletonDrawings) do for _, l in pairs(entry.lines) do pcall(function() l:Remove() end) end end
    for _, a in pairs(arrowDrawings) do pcall(function() a.line:Remove() end); pcall(function() a.dot:Remove() end) end
    pcall(function() blur:Destroy() end); pcall(function() hub:Destroy() end); pcall(function() espGui:Destroy() end)
end)

local drag, dS, dP = false, nil, nil
header.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = true; dS = i.Position; dP = main.Position end end)
UIS.InputChanged:Connect(function(i) if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then local d = i.Position - dS; main.Position = UDim2.new(dP.X.Scale, dP.X.Offset + d.X, dP.Y.Scale, dP.Y.Offset + d.Y) end end)
UIS.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end end)

local function toggleMenu(show)
    if not main then return end
    main.Visible = true
    if show then
        if blur and blur.Parent then pcall(function() blur.Enabled = true; TweenService:Create(blur, TweenInfo.new(0.4), {Size = 15}):Play() end) end
        main.BackgroundTransparency = 0; main.Size = UDim2.fromOffset(MENU_W, MENU_H)
        pcall(function() main.Size = UDim2.fromOffset(MENU_W - 100, MENU_H - 70); local t = TweenService:Create(main, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(MENU_W, MENU_H), BackgroundTransparency = 0}); t:Play() end)
    else
        if blur and blur.Parent then pcall(function() TweenService:Create(blur, TweenInfo.new(0.4), {Size = 0}):Play(); task.delay(0.4, function() if blur and blur.Parent and blur.Size <= 1 then blur.Enabled = false end end) end) end
        local t = TweenService:Create(main, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.fromOffset(MENU_W - 100, MENU_H - 70), BackgroundTransparency = 1})
        t.Completed:Connect(function() main.Visible = false end); t:Play()
    end
end

UIS.InputBegan:Connect(function(i, gpe)
    if gpe or not running then return end
    if i.KeyCode == Enum.KeyCode.RightShift then toggleMenu(not main.Visible) end
    if i.KeyCode == Enum.KeyCode.C and zoomEnabled and not main.Visible then
        local cam = workspace.CurrentCamera; if cam and not isZooming then defaultFov = cam.FieldOfView; TweenService:Create(cam, TweenInfo.new(0.2), {FieldOfView = defaultFov / zoomLevel}):Play(); isZooming = true end
    end
end)

UIS.InputEnded:Connect(function(i)
    if not running then return end
    if i.KeyCode == Enum.KeyCode.C and isZooming then local cam = workspace.CurrentCamera; if cam then TweenService:Create(cam, TweenInfo.new(0.2), {FieldOfView = defaultFov}):Play() end; isZooming = false end
end)

task.wait(1.9)
if loading then loading.Visible = false; pcall(function() loading:Destroy() end) end
if main then main.Visible = true; main.BackgroundTransparency = 0; main.Size = UDim2.fromOffset(MENU_W, MENU_H) end
if blur and blur.Parent then pcall(function() blur.Enabled = true; blur.Size = 15 end) end

task.spawn(function()
    task.wait(0.5)
    local ok, data = pcall(readfile, autoLoadFile)
    if ok and data then
        local dec, aName = pcall(function() return HttpService:JSONDecode(data) end)
        if dec and aName then
            loadConfigFromFile(aName)
            print("[Vortex] Auto-loaded config: " .. tostring(aName))
        end
    end
end)

print("[Vortex] Version " .. VERSION .. " loaded successfully with Weapon HUD, Distance ESP, and Custom Crosshair.")
