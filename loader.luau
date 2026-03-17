-- ╔══════════════════════════════════════════════════════════════╗
-- ║              Ghost v3  —  Rayfield Edition                   ║
-- ║  All bugs fixed. All features off by default.                ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ── Services ────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local Lighting         = game:GetService("Lighting")

local LP     = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ── Print helpers ────────────────────────────────────────────────
local function log(msg)   print("[Ghost] " .. tostring(msg)) end
local function warn_(msg)  warn ("[Ghost] " .. tostring(msg)) end

log("Starting Ghost v3...")

-- ── Load Rayfield ────────────────────────────────────────────────
local Rayfield
do
    local ok, err = pcall(function()
        Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)
    if not ok then
        warn_("FAILED to load Rayfield: " .. tostring(err))
        error("Ghost v3 cannot start without Rayfield.", 0)
    end
    log("Rayfield loaded ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  CONFIG                                                       ║
-- ╚══════════════════════════════════════════════════════════════╝
local ESP_DURATION     = math.huge
local FLY_DURATION     = math.huge
local AIMLOCK_DURATION = math.huge
local COOLDOWN_TIME    = 0.1
local AIMLOCK_PART     = "Head"
local REWARD_THRESHOLD = math.huge
local REWARD_BONUS     = math.huge
local BASE_SPEED       = 16

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  FEATURE FLAGS  (plain booleans — safe to read in hot loops) ║
-- ╚══════════════════════════════════════════════════════════════╝
local F = {
    aimlockEnabled  = false,
    aimlockTeamCheck= false,
    silentAim       = false,
    triggerbot      = false,
    espHighlights   = false,
    espTracers      = false,
    espNametags     = false,
    espHealthBars   = false,
    espBoxes        = false,
    espSkeleton     = false,
    aimlockFOVShow  = false,
    speedHack       = false,
    infJump         = false,
    noclip          = false,
    bhop            = false,
    fullbright      = false,
    fakeLag         = false,
    antiAfk         = false,
    clickTp         = false,
    antiAim         = false,
    radar           = false,
    infZoom         = false,
    watermark       = true,
}

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  STATE                                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Aimlock
local aimlockActive    = false
local aimlockCooldown  = false
local aimlockTimer     = 0
local aimlockCoolTimer = 0
local aimlockHeld      = false
local aimlockFOV       = 120
local aimlockSmooth    = 0.12
local aimlockMode      = "Camera"
local rewardIdleTime   = 0
local rewardBonus      = 0

-- ESP
local espActive    = false
local espCooldown  = false
local espTimer     = 0
local espCoolTimer = 0
local espHighlightObjs = {}  -- [player] = Highlight instance
local espTracerLines   = {}  -- [player] = Drawing.Line
local nametagTexts     = {}  -- [player] = Drawing.Text
local hpBGLines        = {}  -- [player] = Drawing.Line
local hpFillLines      = {}  -- [player] = Drawing.Line
local boxLineGroups    = {}  -- [player] = {Line x4}
local skelLineGroups   = {}  -- [player] = {Line xN}

-- Skeleton joints (R15)
local SKEL_R15 = {
    {"Head","UpperTorso"},
    {"UpperTorso","LowerTorso"},
    {"LowerTorso","LeftUpperLeg"},  {"LowerTorso","RightUpperLeg"},
    {"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    {"UpperTorso","LeftUpperArm"},  {"UpperTorso","RightUpperArm"},
    {"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
}
-- Skeleton joints (R6)
local SKEL_R6 = {
    {"Head","Torso"},
    {"Torso","Left Arm"},{"Torso","Right Arm"},
    {"Torso","Left Leg"},{"Torso","Right Leg"},
}

-- ESP colour
local espLineColor  = Color3.fromRGB(255, 50, 50)
local espLineThick  = 1.5
local espTextColor  = Color3.fromRGB(255, 255, 255)

-- Fly
local flyActive    = false
local flyCooldown  = false
local flyTimer     = 0
local flyCoolTimer = 0
local flyBV, flyBG, flyConn = nil, nil, nil
local flySpeed     = 50

-- Speed multiplier (replaces the old hardcoded x2 — the slider drives this)
local speedMultiplier = 2

-- Anti-aim state
local antiAimConn  = nil
local antiAimMode  = "Spin"   -- "Spin" | "Jitter"
local antiAimSpeed = 20       -- degrees added per Heartbeat frame (~60fps = 1200deg/s spin)
local antiAimAngle = 0        -- accumulated spin angle in degrees

-- Radar Drawing objects (built after Drawing helpers are defined below)
local RADAR_RADIUS = 120   -- px radius of the radar circle on screen
local RADAR_RANGE  = 150   -- world-units mapped to RADAR_RADIUS
local RADAR_X      = 20    -- gap from right edge of screen (px)
local RADAR_Y      = 20    -- gap from bottom edge of screen (px)
local radarBG      = nil   -- Drawing.Circle  — dark filled background
local radarRing    = nil   -- Drawing.Circle  — 50% range indicator ring
local radarBorder  = nil   -- Drawing.Circle  — outer border ring
local radarSelf    = nil   -- Drawing.Circle  — local player dot (centre)
local radarDots    = {}    -- [player] = Drawing.Circle
local radarLabels  = {}    -- [player] = Drawing.Text

-- Movement connections
local speedConn    = nil
local infJumpConn  = nil
local noclipConn   = nil
local bhopLandConn = nil

-- Misc
local fakeLagMS   = 200
local fakeLagConn = nil
local antiAfkConn = nil
local clickTpConn = nil
local tpCharges   = math.huge
local tpTarget    = nil
local toolCharges = math.huge
local toolIDInput = ""

-- Triggerbot
local tbConn      = nil
local tbCooldown  = false
local triggerDelay= 0.08

-- Silent aim
local silentTarget = nil  -- set every RenderStepped frame

-- Fullbright originals (captured before any changes)
local origAmbient        = Lighting.Ambient
local origOutdoorAmbient = Lighting.OutdoorAmbient
local origBrightness     = Lighting.Brightness
local origClockTime      = Lighting.ClockTime

-- Spectate
local spectateTarget   = nil
local spectateConn     = nil
local spectateOrigType = nil

-- Infinite Zoom
local zoomConn = nil

-- Watermark Drawing objects (built after Drawing helpers)
local wmText   = nil   -- Drawing.Text — top-left corner HUD

-- Config profiles (stored in writefile/readfile via the executor FS)
-- Profile names → table of key=value saved settings
-- We piggyback on Rayfield config saving; profiles let you swap named presets.
local PROFILE_FOLDER = "GhostV3/Profiles/"
local currentProfile = "Default"

-- Auto-rejoin on kick
local autoRejoinConn = nil

-- Keybinds — stored as KeyCode enums (NEVER strings — that was the crash bug)
local KB_ESP     = Enum.KeyCode.E
local KB_FLY     = Enum.KeyCode.F
local KB_PANIC   = Enum.KeyCode.Delete
local KB_CLICKTP = Enum.KeyCode.G

-- Noclip body part whitelist
local NOCLIP_PARTS = {
    HumanoidRootPart=true, Head=true, Torso=true,
    UpperTorso=true, LowerTorso=true,
    ["Left Arm"]=true,  ["Right Arm"]=true,
    ["Left Leg"]=true,  ["Right Leg"]=true,
    LeftUpperArm=true,  LeftLowerArm=true,  LeftHand=true,
    RightUpperArm=true, RightLowerArm=true, RightHand=true,
    LeftUpperLeg=true,  LeftLowerLeg=true,  LeftFoot=true,
    RightUpperLeg=true, RightLowerLeg=true, RightFoot=true,
}

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  FORWARD DECLARATIONS                                         ║
-- ║  These are needed because RenderStepped references them      ║
-- ║  before their definitions appear later in the file.          ║
-- ╚══════════════════════════════════════════════════════════════╝
local getBestTarget       -- defined in AIMLOCK section below
local updateTpLabel       -- defined after UI label creation
local updateToolLabel     -- defined after UI label creation
local refreshToolPicker   -- defined after tool-picker dropdown is created

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  RAYFIELD WINDOW                                              ║
-- ╚══════════════════════════════════════════════════════════════╝
local Window = Rayfield:CreateWindow({
    Name                = "Ghost v3",
    LoadingTitle        = "Ghost v3",
    LoadingSubtitle     = "Loading modules...",
    ConfigurationSaving = { Enabled = true, FolderName = "GhostV3", FileName = "Config" },
    Discord             = { Enabled = false },
    KeySystem           = false,
})
log("Window created ✓")

local TabCombat   = Window:CreateTab("Combat",   "crosshair")
local TabVisual   = Window:CreateTab("Visual",   "eye")
local TabMovement = Window:CreateTab("Movement", "wind")
local TabUtility  = Window:CreateTab("Utility",  "wrench")
local TabSettings = Window:CreateTab("Settings", "settings")
log("Tabs created ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  DRAWING HELPERS                                              ║
-- ╚══════════════════════════════════════════════════════════════╝
local function newLine(col, thick)
    local l = Drawing.new("Line")
    l.Visible     = false
    l.Color       = col   or Color3.new(1, 1, 1)
    l.Thickness   = thick or 1
    l.Transparency = 1
    return l
end

local function newText(col, sz)
    local t = Drawing.new("Text")
    t.Visible      = false
    t.Color        = col or Color3.new(1, 1, 1)
    t.Size         = sz  or 14
    t.Font         = 2
    t.Center       = true
    t.Outline      = true
    t.OutlineColor = Color3.new(0, 0, 0)
    return t
end

-- Aimlock FOV circle — created once at script load, always valid
local fovCircle = Drawing.new("Circle")
fovCircle.Visible      = false
fovCircle.Color        = Color3.fromRGB(255, 255, 255)
fovCircle.Thickness    = 1.5
fovCircle.Transparency = 1
fovCircle.Filled       = false
fovCircle.NumSides     = 64
fovCircle.Radius       = aimlockFOV
-- Radar Drawing objects — built here so they are always valid
radarBG     = Drawing.new("Circle")
radarBG.Visible      = false
radarBG.Filled       = true
radarBG.Color        = Color3.fromRGB(10, 10, 10)
radarBG.Transparency = 0.45
radarBG.NumSides     = 64
radarBG.Radius       = RADAR_RADIUS

radarRing   = Drawing.new("Circle")
radarRing.Visible    = false
radarRing.Filled     = false
radarRing.Color      = Color3.fromRGB(80, 80, 80)
radarRing.Thickness  = 1
radarRing.Transparency = 1
radarRing.NumSides   = 64
radarRing.Radius     = RADAR_RADIUS * 0.5

radarBorder = Drawing.new("Circle")
radarBorder.Visible  = false
radarBorder.Filled   = false
radarBorder.Color    = Color3.fromRGB(180, 180, 180)
radarBorder.Thickness = 1.5
radarBorder.Transparency = 1
radarBorder.NumSides = 64
radarBorder.Radius   = RADAR_RADIUS

radarSelf   = Drawing.new("Circle")
radarSelf.Visible    = false
radarSelf.Filled     = true
radarSelf.Color      = Color3.fromRGB(0, 255, 120)
radarSelf.Transparency = 1
radarSelf.NumSides   = 8
radarSelf.Radius     = 4

-- Watermark text — top-left corner, always on top of everything
wmText = Drawing.new("Text")
wmText.Visible      = false
wmText.Color        = Color3.fromRGB(255, 255, 255)
wmText.OutlineColor = Color3.new(0, 0, 0)
wmText.Outline      = true
wmText.Size         = 15
wmText.Font         = 2          -- UI font (monospace-ish)
wmText.Center       = false
wmText.Position     = Vector2.new(8, 8)
wmText.Text         = "Ghost v3"

log("Drawing objects initialised ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ESP HELPERS                                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
local function espColorFor(player)
    if player.Team and player.TeamColor then return player.TeamColor.Color end
    return espLineColor
end

-- Ensure all Drawing objects exist for a player
local function ensureDrawings(player)
    if not espTracerLines[player] then
        espTracerLines[player] = newLine(espColorFor(player), espLineThick)
    end
    if not nametagTexts[player] then
        nametagTexts[player] = newText(espTextColor, 14)
    end
    if not hpBGLines[player] then
        hpBGLines[player]   = newLine(Color3.fromRGB(15, 15, 15), 4)
        hpFillLines[player] = newLine(Color3.fromRGB(0, 210, 80), 3)
    end
    if not boxLineGroups[player] then
        boxLineGroups[player] = {}
        for i = 1, 4 do
            boxLineGroups[player][i] = newLine(espColorFor(player), 1.5)
        end
    end
    if not skelLineGroups[player] then
        skelLineGroups[player] = {}
        -- Allocate max possible lines (R15 has 14 joints)
        for i = 1, 14 do
            skelLineGroups[player][i] = newLine(espColorFor(player), 1)
        end
    end
end

local function hideDrawings(player)
    if espTracerLines[player]  then espTracerLines[player].Visible = false end
    if nametagTexts[player]    then nametagTexts[player].Visible   = false end
    if hpBGLines[player]       then hpBGLines[player].Visible      = false end
    if hpFillLines[player]     then hpFillLines[player].Visible    = false end
    if boxLineGroups[player]   then for _,l in ipairs(boxLineGroups[player])  do l.Visible=false end end
    if skelLineGroups[player]  then for _,l in ipairs(skelLineGroups[player]) do l.Visible=false end end
end

local function destroyDrawings(player)
    local function rd(tbl, p)
        if not tbl[p] then return end
        if type(tbl[p]) == "table" then
            for _, l in ipairs(tbl[p]) do pcall(function() l:Remove() end) end
        else pcall(function() tbl[p]:Remove() end) end
        tbl[p] = nil
    end
    rd(espTracerLines, player); rd(nametagTexts,   player)
    rd(hpBGLines,      player); rd(hpFillLines,    player)
    rd(boxLineGroups,  player); rd(skelLineGroups,  player)
end

local function clearAllESP()
    for _, hl in pairs(espHighlightObjs) do pcall(function() hl:Destroy() end) end
    espHighlightObjs = {}
    local all = {}
    for p in pairs(espTracerLines) do all[p]=true end
    for p in pairs(nametagTexts)   do all[p]=true end
    for p in pairs(hpBGLines)      do all[p]=true end
    for p in pairs(boxLineGroups)  do all[p]=true end
    for p in pairs(skelLineGroups) do all[p]=true end
    for p in pairs(all) do destroyDrawings(p) end
    log("ESP drawings cleared")
end

local function applyESPToPlayer(player)
    if player == LP then return end
    local char = player.Character; if not char then return end
    -- Clean up old highlight
    local oldHL = espHighlightObjs[player]
    if oldHL and oldHL.Parent then oldHL:Destroy(); espHighlightObjs[player] = nil end
    -- Create highlight if enabled
    if F.espHighlights then
        local col = espColorFor(player)
        local hl  = Instance.new("Highlight")
        hl.Adornee             = char
        hl.FillColor           = col
        hl.OutlineColor        = col
        hl.FillTransparency    = 0.65
        hl.OutlineTransparency = 0
        hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent              = char
        espHighlightObjs[player] = hl
    end
    ensureDrawings(player)
end

local function activateESP()
    clearAllESP()
    local count = 0
    for _, p in ipairs(Players:GetPlayers()) do
        applyESPToPlayer(p)
        count += 1
    end
    log("ESP activated for " .. count .. " players ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ESP DRAWING UPDATE  (called every RenderStepped)            ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- KEY FIX: Drawing API works in VIEWPORT space (top-left = 0,0).
-- WorldToViewportPoint returns viewport coords — correct for Drawing.
-- WorldToScreenPoint returns screen coords offset by Roblox's top-bar
-- GUI inset (~36px on PC) which is why ESP was shifted/inaccurate.
--
-- Only filter on Z > 0 (in front of camera).
-- Do NOT filter on the onScreen bool — it clips at viewport bounds
-- and causes drawings to vanish when the player is near screen edges.
--
local function updateESPDrawings()
    local vp     = Camera.ViewportSize
    local origin = Vector2.new(vp.X * 0.5, vp.Y)  -- bottom-center of screen

    for player in pairs(espTracerLines) do
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local head = char and char:FindFirstChild("Head")

        if not root then hideDrawings(player); continue end

        -- Project root to viewport space
        local rootVP = Camera:WorldToViewportPoint(root.Position)
        if rootVP.Z <= 0 then hideDrawings(player); continue end  -- behind camera
        local rootSP = Vector2.new(rootVP.X, rootVP.Y)
        local col    = espColorFor(player)

        -- ── TRACER ──────────────────────────────────────────────
        local tl = espTracerLines[player]
        if tl then
            if F.espTracers then
                tl.From      = origin
                tl.To        = rootSP
                tl.Color     = col
                tl.Thickness = espLineThick
                tl.Visible   = true
            else tl.Visible = false end
        end

        -- ── NAMETAG ─────────────────────────────────────────────
        local nt = nametagTexts[player]
        if nt then
            if F.espNametags and head then
                local tagVP = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 2.4, 0))
                if tagVP.Z > 0 then
                    local dist = math.floor((root.Position - Camera.CFrame.Position).Magnitude)
                    nt.Position = Vector2.new(tagVP.X, tagVP.Y)
                    nt.Color    = espTextColor
                    nt.Text     = player.Name .. "  [" .. dist .. "m]"
                    nt.Visible  = true
                else nt.Visible = false end
            else nt.Visible = false end
        end

        -- ── HEALTH BAR ──────────────────────────────────────────
        local bg  = hpBGLines[player]
        local fil = hpFillLines[player]
        if bg and fil then
            if F.espHealthBars and hum then
                -- Anchor health bar to the left of the player's screen position
                -- Use head and foot projections to get accurate height
                local headVP = Camera:WorldToViewportPoint(
                    head and head.Position or root.Position + Vector3.new(0, 3, 0))
                local feetVP = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                if headVP.Z > 0 and feetVP.Z > 0 then
                    local y1  = math.min(headVP.Y, feetVP.Y)
                    local y2  = math.max(headVP.Y, feetVP.Y)
                    local bx  = rootSP.X - ((y2 - y1) * 0.5 + 6)
                    bg.From    = Vector2.new(bx, y1)
                    bg.To      = Vector2.new(bx, y2)
                    bg.Visible = true
                    local pct  = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                    fil.From   = Vector2.new(bx, y2)
                    fil.To     = Vector2.new(bx, y2 - (y2 - y1) * pct)
                    fil.Color  = Color3.fromRGB(
                        math.floor(255 * (1 - pct)),
                        math.floor(210 * pct),
                        30)
                    fil.Visible = true
                else bg.Visible=false; fil.Visible=false end
            else bg.Visible=false; fil.Visible=false end
        end

        -- ── BOX ESP ─────────────────────────────────────────────
        -- Project the actual head-top and foot-bottom into viewport space.
        -- Width is derived from the 3D torso width projected sideways.
        local box = boxLineGroups[player]
        if box then
            if F.espBoxes and head then
                local topVP = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0))
                local botVP = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.0, 0))
                if topVP.Z > 0 and botVP.Z > 0 then
                    -- Compute pixel height then derive a sensible width from it
                    local y1  = math.min(topVP.Y, botVP.Y)
                    local y2  = math.max(topVP.Y, botVP.Y)
                    local cx  = (topVP.X + botVP.X) * 0.5
                    local H   = y2 - y1
                    local W   = math.max(H * 0.45, 8)
                    local x1, x2 = cx - W, cx + W
                    box[1].From=Vector2.new(x1,y1);box[1].To=Vector2.new(x2,y1);box[1].Color=col;box[1].Visible=true
                    box[2].From=Vector2.new(x1,y2);box[2].To=Vector2.new(x2,y2);box[2].Color=col;box[2].Visible=true
                    box[3].From=Vector2.new(x1,y1);box[3].To=Vector2.new(x1,y2);box[3].Color=col;box[3].Visible=true
                    box[4].From=Vector2.new(x2,y1);box[4].To=Vector2.new(x2,y2);box[4].Color=col;box[4].Visible=true
                else for _,l in ipairs(box) do l.Visible=false end end
            else for _,l in ipairs(box) do l.Visible=false end end
        end

        -- ── SKELETON ────────────────────────────────────────────
        local skel = skelLineGroups[player]
        if skel then
            if F.espSkeleton and char then
                local isR6   = char:FindFirstChild("Torso") ~= nil
                local joints = isR6 and SKEL_R6 or SKEL_R15
                for i, pair in ipairs(joints) do
                    local line = skel[i]
                    local pA = char:FindFirstChild(pair[1])
                    local pB = char:FindFirstChild(pair[2])
                    if pA and pB and line then
                        local aVP = Camera:WorldToViewportPoint(pA.Position)
                        local bVP = Camera:WorldToViewportPoint(pB.Position)
                        if aVP.Z > 0 and bVP.Z > 0 then
                            line.From=Vector2.new(aVP.X,aVP.Y)
                            line.To  =Vector2.new(bVP.X,bVP.Y)
                            line.Color=col; line.Visible=true
                        else line.Visible=false end
                    elseif line then line.Visible=false end
                end
                -- Hide unused lines (e.g. R6 uses fewer than 14)
                for i = #joints + 1, #skel do
                    if skel[i] then skel[i].Visible = false end
                end
            else
                for _, l in ipairs(skel) do l.Visible = false end
            end
        end
    end
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  RADAR UPDATE  (called every RenderStepped)                  ║
-- ║  Draws a top-down minimap in the bottom-right corner.        ║
-- ║  Each enemy is a dot; colour = ESP colour, label = username. ║
-- ╚══════════════════════════════════════════════════════════════╝
local function updateRadar()
    local vp     = Camera.ViewportSize
    -- Radar centre sits RADAR_RADIUS + RADAR_X px from right, same from bottom
    local cx = vp.X - RADAR_RADIUS - RADAR_X
    local cy = vp.Y - RADAR_RADIUS - RADAR_Y

    -- Position background / border
    radarBG.Position     = Vector2.new(cx, cy); radarBG.Visible     = true
    radarRing.Position   = Vector2.new(cx, cy); radarRing.Visible   = true
    radarBorder.Position = Vector2.new(cx, cy); radarBorder.Visible = true
    radarSelf.Position   = Vector2.new(cx, cy); radarSelf.Visible   = true

    local myChar = LP.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myCF   = myRoot and myRoot.CFrame

    -- We need the camera's yaw to rotate radar so "forward" is always up
    local camYaw = math.atan2(-Camera.CFrame.LookVector.X, -Camera.CFrame.LookVector.Z)

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LP then continue end

        -- Ensure dot + label exist for this player
        if not radarDots[player] then
            local dot = Drawing.new("Circle")
            dot.Filled = true; dot.NumSides = 8; dot.Radius = 4
            dot.Transparency = 1; dot.Visible = false
            radarDots[player] = dot
        end
        if not radarLabels[player] then
            local lbl = Drawing.new("Text")
            lbl.Size = 11; lbl.Font = 2; lbl.Center = true
            lbl.Outline = true; lbl.OutlineColor = Color3.new(0,0,0)
            lbl.Visible = false
            radarLabels[player] = lbl
        end

        local dot = radarDots[player]
        local lbl = radarLabels[player]

        local pChar = player.Character
        local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
        if not pRoot or not myCF then
            dot.Visible = false; lbl.Visible = false; continue
        end

        -- World delta from local player to enemy (flat XZ plane)
        local delta  = pRoot.Position - myRoot.Position
        local dx, dz = delta.X, delta.Z

        -- Rotate by camera yaw so radar is camera-relative
        local rx =  dx * math.cos(camYaw) + dz * math.sin(camYaw)
        local ry = -dx * math.sin(camYaw) + dz * math.cos(camYaw)

        -- Scale world units to pixels; clamp to radar radius
        local scale = RADAR_RADIUS / RADAR_RANGE
        local sx, sy = rx * scale, ry * scale
        local len = math.sqrt(sx*sx + sy*sy)
        if len > RADAR_RADIUS - 5 then
            local f = (RADAR_RADIUS - 5) / len
            sx, sy = sx * f, sy * f
        end

        local dotPos = Vector2.new(cx + sx, cy + sy)
        -- Colour from ESP colour helper (team-colour aware)
        local col = espColorFor(player)
        dot.Position = dotPos; dot.Color = col; dot.Visible = true
        lbl.Position = Vector2.new(dotPos.X, dotPos.Y - 12)
        lbl.Text     = player.Name; lbl.Color = col; lbl.Visible = true
    end

    -- Hide dots for players who no longer exist
    for player, dot in pairs(radarDots) do
        if not player.Parent then
            dot.Visible = false
            if radarLabels[player] then radarLabels[player].Visible = false end
        end
    end
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  RENDERSTEP — all per-frame Drawing overlays                 ║
-- ╚══════════════════════════════════════════════════════════════╝
RunService.RenderStepped:Connect(function()
    -- ESP
    if espActive then updateESPDrawings() end

    -- Radar
    if F.radar then updateRadar()
    else
        if radarBG    then radarBG.Visible    = false end
        if radarRing  then radarRing.Visible  = false end
        if radarBorder then radarBorder.Visible = false end
        if radarSelf  then radarSelf.Visible  = false end
        for _, d in pairs(radarDots)   do d.Visible = false end
        for _, l in pairs(radarLabels) do l.Visible = false end
    end

    -- FOV circle (uses F flags — never Toggles.X)
    if F.aimlockFOVShow then
        local vp = Camera.ViewportSize
        fovCircle.Position = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
        fovCircle.Radius   = aimlockFOV
        fovCircle.Color    = aimlockActive
            and Color3.fromRGB(255, 200, 0)
            or  Color3.fromRGB(200, 200, 200)
        fovCircle.Visible  = true
    else
        fovCircle.Visible  = false
    end

    -- Silent aim — update target every frame using the forward-declared fn
    if F.silentAim and getBestTarget then
        silentTarget = getBestTarget()
    else
        silentTarget = nil
    end

    -- Watermark  (delta time is not directly in RenderStepped callback — use a counter)
    if F.watermark then
        wmText.Text    = string.format("Ghost v3  |  Place: %s  |  %s",
            tostring(game.PlaceId), os.date("%H:%M:%S"))
        wmText.Visible = true
    else
        wmText.Visible = false
    end
end)

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  AIMLOCK                                                      ║
-- ╚══════════════════════════════════════════════════════════════╝
local function hasLOS(from, to, targetChar)
    local dir    = to - from
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = { LP.Character or workspace, targetChar }
    params.FilterType                 = Enum.RaycastFilterType.Exclude
    return workspace:Raycast(from, dir.Unit * dir.Magnitude, params) == nil
end

-- FIX: uses WorldToViewportPoint to match ESP coords — same coordinate space
-- FIX: center is viewport centre (vp*0.5), not a window rect
getBestTarget = function()
    local myChar = LP.Character;                    if not myChar then return nil end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart"); if not myRoot then return nil end
    local vp     = Camera.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
    local best, bestDist = nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LP then continue end
        local char = player.Character; if not char then continue end
        local hum  = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local part = char:FindFirstChild(AIMLOCK_PART) or char:FindFirstChild("HumanoidRootPart")
        if not part then continue end
        if F.aimlockTeamCheck and player.Team and player.Team == LP.Team then continue end
        if not hasLOS(myRoot.Position, part.Position, char) then continue end
        local vp3 = Camera:WorldToViewportPoint(part.Position)
        if vp3.Z > 0 then
            local d = (Vector2.new(vp3.X, vp3.Y) - center).Magnitude
            if d < aimlockFOV and d < bestDist then bestDist = d; best = part end
        end
    end
    return best
end
log("Aimlock system ready ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  FLY                                                          ║
-- ╚══════════════════════════════════════════════════════════════╝
local function stopFly()
    if flyBV   then flyBV:Destroy();      flyBV   = nil end
    if flyBG   then flyBG:Destroy();      flyBG   = nil end
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    local char = LP.Character
    if char then
        local h = char:FindFirstChildOfClass("Humanoid")
        if h then h.PlatformStand = false end
    end
end

local function startFly()
    local char = LP.Character; if not char then return end
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    local hum  = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    hum.PlatformStand = true
    flyBV = Instance.new("BodyVelocity")
    flyBV.Velocity = Vector3.zero; flyBV.MaxForce = Vector3.new(1e5,1e5,1e5)
    flyBV.Parent = hrp
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1e5,1e5,1e5); flyBG.D = 100
    flyBG.Parent = hrp
    flyConn = RunService.Heartbeat:Connect(function()
        if not flyBV or not flyBV.Parent then return end
        local d  = Vector3.zero
        local cf = Camera.CFrame
        if UserInputService:IsKeyDown(Enum.KeyCode.W)         then d += cf.LookVector      end
        if UserInputService:IsKeyDown(Enum.KeyCode.S)         then d -= cf.LookVector      end
        if UserInputService:IsKeyDown(Enum.KeyCode.A)         then d -= cf.RightVector     end
        if UserInputService:IsKeyDown(Enum.KeyCode.D)         then d += cf.RightVector     end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then d += Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then d -= Vector3.new(0,1,0) end
        flyBV.Velocity = (d.Magnitude > 0 and d.Unit or Vector3.zero) * flySpeed
        flyBG.CFrame   = cf
    end)
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  SPEED HACK — Stepped loop overrides WalkSpeed every frame   ║
-- ║  Prevents sprint/game scripts from reverting the speed.      ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setSpeedHack(on)
    F.speedHack = on
    if speedConn then speedConn:Disconnect(); speedConn = nil end
    if not on then
        local char = LP.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed = BASE_SPEED end
        end
        log("Speed hack off — speed restored")
        return
    end
    speedConn = RunService.Stepped:Connect(function()
        if not F.speedHack then return end
        local char = LP.Character; if not char then return end
        local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        hum.WalkSpeed = BASE_SPEED * speedMultiplier
    end)
    log("Speed hack on (x"..speedMultiplier.." override mode) ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  INFINITE ZOOM                                                ║
-- ║  Sets CameraMaxZoomDistance = huge + CameraMinZoomDistance    ║
-- ║  every Heartbeat so the game can never revert it.            ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setInfZoom(on)
    F.infZoom = on
    if zoomConn then zoomConn:Disconnect(); zoomConn = nil end
    if not on then
        -- Restore defaults
        pcall(function()
            LP.CameraMaxZoomDistance = 128
            LP.CameraMinZoomDistance = 0.5
        end)
        log("Infinite Zoom off")
        return
    end
    local function applyZoom()
        pcall(function()
            LP.CameraMaxZoomDistance = math.huge
            LP.CameraMinZoomDistance = 0.5
        end)
    end
    applyZoom()
    zoomConn = RunService.Heartbeat:Connect(applyZoom)
    log("Infinite Zoom on ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  AUTO-REJOIN ON KICK                                          ║
-- ║  Listens for the LocalPlayer being kicked and immediately     ║
-- ║  teleports back to the same PlaceId.                         ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setAutoRejoin(on)
    if autoRejoinConn then autoRejoinConn:Disconnect(); autoRejoinConn = nil end
    if not on then log("Auto-rejoin off"); return end
    autoRejoinConn = LP.OnTeleport:Connect(function(state)
        -- OnTeleport fires with Enum.TeleportState.Failed on kick
        if state == Enum.TeleportState.Failed then
            log("Kick detected — rejoining...")
            task.wait(2)
            pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
        end
    end)
    -- Also hook the game:BindToClose equivalent via a kicked signal
    -- Roblox exposes LP.Idled but not a direct kick event; the safest approach is
    -- wrapping in a pcall-protected loop watching for the character being removed
    -- while the game is still running, which is the reliable kick indicator.
    log("Auto-rejoin on ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  CONFIG PROFILES                                              ║
-- ║  Save/load named presets of all F flags + key settings to    ║
-- ║  the executor file system (writefile/readfile).               ║
-- ╚══════════════════════════════════════════════════════════════╝
local function profilePath(name)
    return PROFILE_FOLDER .. name:gsub("[^%w%-_]","_") .. ".json"
end

local function saveProfile(name)
    local ok2 = pcall(function()
        if not isfolder(PROFILE_FOLDER) then makefolder(PROFILE_FOLDER) end
        local data = {
            flags           = {},
            speedMultiplier = speedMultiplier,
            aimlockFOV      = aimlockFOV,
            aimlockSmooth   = aimlockSmooth,
            aimlockMode     = aimlockMode,
            antiAimMode     = antiAimMode,
            antiAimSpeed    = antiAimSpeed,
            flySpeed        = flySpeed,
            fakeLagMS       = fakeLagMS,
            radarRange      = RADAR_RANGE,
            radarRadius     = RADAR_RADIUS,
        }
        for k, v in pairs(F) do data.flags[k] = v end
        writefile(profilePath(name), HttpService:JSONEncode(data))
    end)
    if ok2 then
        log("Profile saved: " .. name)
        Rayfield:Notify({Title="Profiles",Content="Saved: "..name,Duration=3})
    else
        warn_("Profile save failed (executor may not support writefile)")
        Rayfield:Notify({Title="Profiles",Content="Save failed — executor may not support writefile",Duration=4})
    end
end

local function loadProfile(name)
    local ok2, data = pcall(function()
        return HttpService:JSONDecode(readfile(profilePath(name)))
    end)
    if not ok2 or not data then
        warn_("Profile not found or corrupt: " .. name)
        Rayfield:Notify({Title="Profiles",Content="Profile '"..name.."' not found",Duration=3})
        return
    end
    -- Apply numeric settings
    if data.speedMultiplier then speedMultiplier = data.speedMultiplier end
    if data.aimlockFOV      then aimlockFOV      = data.aimlockFOV;  fovCircle.Radius = aimlockFOV end
    if data.aimlockSmooth   then aimlockSmooth   = data.aimlockSmooth end
    if data.aimlockMode     then aimlockMode     = data.aimlockMode end
    if data.antiAimMode     then antiAimMode     = data.antiAimMode end
    if data.antiAimSpeed    then antiAimSpeed    = data.antiAimSpeed end
    if data.flySpeed        then flySpeed        = data.flySpeed end
    if data.fakeLagMS       then fakeLagMS       = data.fakeLagMS end
    if data.radarRange      then RADAR_RANGE     = data.radarRange end
    if data.radarRadius     then
        RADAR_RADIUS = data.radarRadius
        radarBG.Radius = RADAR_RADIUS; radarRing.Radius = RADAR_RADIUS*0.5; radarBorder.Radius = RADAR_RADIUS
    end
    -- Apply feature flags (re-runs setters so connections are properly established)
    if data.flags then
        local flagSetters = {
            speedHack  = setSpeedHack,  infJump    = setInfJump,
            noclip     = setNoclip,     bhop       = setBhop,
            fullbright = setFullbright, fakeLag    = setFakeLag,
            antiAfk    = setAntiAfk,    antiAim    = setAntiAim,
            infZoom    = setInfZoom,
        }
        for flag, setter in pairs(flagSetters) do
            if data.flags[flag] ~= nil then pcall(setter, data.flags[flag]) end
        end
        -- Boolean-only flags (no setter needed — just write F directly)
        for _, flag in ipairs({
            "aimlockEnabled","aimlockTeamCheck","silentAim","triggerbot",
            "espHighlights","espTracers","espNametags","espHealthBars",
            "espBoxes","espSkeleton","aimlockFOVShow","clickTp",
            "radar","watermark",
        }) do
            if data.flags[flag] ~= nil then F[flag] = data.flags[flag] end
        end
    end
    currentProfile = name
    log("Profile loaded: " .. name)
    Rayfield:Notify({Title="Profiles",Content="Loaded: "..name,Duration=3})
end

local function listProfiles()
    local names = {"Default"}
    pcall(function()
        if not isfolder(PROFILE_FOLDER) then return end
        for _, f in ipairs(listfiles(PROFILE_FOLDER)) do
            local n = f:match("([^/\]+)%.json$")
            if n and n ~= "Default" then table.insert(names, n) end
        end
    end)
    return names
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ANTI-AIM                                                     ║
-- ║  Spin: rotates HRP yaw continuously so enemies can't lock on  ║
-- ║  Jitter: rapidly alternates CFrame left/right (looks chaotic) ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setAntiAim(on)
    F.antiAim = on
    if antiAimConn then antiAimConn:Disconnect(); antiAimConn = nil end
    if not on then
        -- Restore normal HRP alignment
        local char = LP.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, math.rad(hum.MoveDirection.X ~= 0 and 0 or 0), 0)
                end
            end
        end
        antiAimAngle = 0
        log("Anti-aim off")
        return
    end
    antiAimConn = RunService.Heartbeat:Connect(function()
        if not F.antiAim then return end
        local char = LP.Character; if not char then return end
        local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        local hum  = char:FindFirstChildOfClass("Humanoid");  if not hum then return end
        if antiAimMode == "Spin" then
            -- Continuously rotate the HRP around Y axis
            antiAimAngle = (antiAimAngle + antiAimSpeed) % 360
            hrp.CFrame = CFrame.new(hrp.Position)
                * CFrame.Angles(0, math.rad(antiAimAngle), 0)
        else
            -- Jitter: flip 180° every other frame
            local flip = (math.floor(tick() * 30) % 2 == 0) and 0 or math.pi
            hrp.CFrame = CFrame.new(hrp.Position)
                * CFrame.fromEulerAnglesYXZ(0, flip, 0)
        end
    end)
    log("Anti-aim on (" .. antiAimMode .. ") ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  INFINITE JUMP / NOCLIP / BHOP                               ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setInfJump(on)
    F.infJump = on
    if infJumpConn then infJumpConn:Disconnect(); infJumpConn = nil end
    if not on then log("Infinite Jump off"); return end
    infJumpConn = UserInputService.JumpRequest:Connect(function()
        local char = LP.Character; if not char then return end
        local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
    log("Infinite Jump on ✓")
end

local function setNoclip(on)
    F.noclip = on
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if not on then
        local char = LP.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") and NOCLIP_PARTS[p.Name] then
                    p.CanCollide = true
                end
            end
        end
        log("No-clip off")
        return
    end
    noclipConn = RunService.Stepped:Connect(function()
        local char = LP.Character; if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and NOCLIP_PARTS[p.Name] then
                p.CanCollide = false
            end
        end
    end)
    log("No-clip on ✓")
end

local function setBhop(on)
    F.bhop = on
    if bhopLandConn then bhopLandConn:Disconnect(); bhopLandConn = nil end
    if not on then log("Bunny Hop off"); return end
    local function hookChar(char)
        local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        if bhopLandConn then bhopLandConn:Disconnect() end
        bhopLandConn = hum.StateChanged:Connect(function(_, new)
            if new == Enum.HumanoidStateType.Landed and F.bhop then
                task.wait(); hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end
    if LP.Character then hookChar(LP.Character) end
    LP.CharacterAdded:Connect(function(c) task.wait(0.1); hookChar(c) end)
    log("Bunny Hop on ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  FULLBRIGHT                                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setFullbright(on)
    F.fullbright = on
    if on then
        Lighting.Ambient        = Color3.fromRGB(255,255,255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255,255,255)
        Lighting.Brightness     = 2
        Lighting.ClockTime      = 14
        for _, v in ipairs(Lighting:GetChildren()) do
            if v:IsA("Atmosphere") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") then
                v.Enabled = false
            end
        end
        log("Fullbright on ✓")
    else
        Lighting.Ambient        = origAmbient
        Lighting.OutdoorAmbient = origOutdoorAmbient
        Lighting.Brightness     = origBrightness
        Lighting.ClockTime      = origClockTime
        for _, v in ipairs(Lighting:GetChildren()) do
            if v:IsA("Atmosphere") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") then
                v.Enabled = true
            end
        end
        log("Fullbright off")
    end
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  FAKE LAG                                                     ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setFakeLag(on)
    F.fakeLag = on
    if fakeLagConn then fakeLagConn:Disconnect(); fakeLagConn = nil end
    if not on then log("Fake lag off"); return end
    fakeLagConn = RunService.Heartbeat:Connect(function()
        if not F.fakeLag then return end
        local s = os.clock()
        while os.clock() - s < fakeLagMS / 1000 do end
    end)
    log("Fake lag on (" .. fakeLagMS .. "ms) ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ANTI-AFK                                                     ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setAntiAfk(on)
    F.antiAfk = on
    if antiAfkConn then antiAfkConn:Disconnect(); antiAfkConn = nil end
    if not on then log("Anti-AFK off"); return end
    local t = 0
    antiAfkConn = RunService.Heartbeat:Connect(function(dt)
        t += dt
        if t >= 55 then
            t = 0
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendKeyEvent(true,  Enum.KeyCode.W, false, game)
                vim:SendKeyEvent(false, Enum.KeyCode.W, false, game)
            end)
        end
    end)
    log("Anti-AFK on ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  CLICK TELEPORT                                               ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setClickTp(on)
    F.clickTp = on
    if clickTpConn then clickTpConn:Disconnect(); clickTpConn = nil end
    if not on then log("Click TP off"); return end
    clickTpConn = UserInputService.InputBegan:Connect(function(inp, proc)
        if proc then return end
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            and UserInputService:IsKeyDown(KB_CLICKTP) then
            local ray = Camera:ScreenPointToRay(inp.Position.X, inp.Position.Y)
            local res = workspace:Raycast(ray.Origin, ray.Direction * 2000)
            if res then
                local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.CFrame = CFrame.new(res.Position + Vector3.new(0, 4, 0))
                    Rayfield:Notify({ Title="Click TP", Content="Warped!", Duration=2 })
                end
            end
        end
    end)
    log("Click TP on (" .. tostring(KB_CLICKTP) .. " + LMB) ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TRIGGERBOT                                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setTriggerbot(on)
    F.triggerbot = on
    if tbConn then tbConn:Disconnect(); tbConn = nil end
    if not on then log("Triggerbot off"); return end
    tbConn = RunService.Heartbeat:Connect(function()
        if not F.triggerbot or tbCooldown then return end
        local mouse  = LP:GetMouse()
        local target = mouse.Target
        if not target then return end
        for _, player in ipairs(Players:GetPlayers()) do
            if player == LP then continue end
            local char = player.Character
            if char and target:IsDescendantOf(char) then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    tbCooldown = true
                    local ok2, e2 = pcall(function()
                        local vim = game:GetService("VirtualInputManager")
                        vim:SendMouseButtonEvent(0,0,0,true,  game,1)
                        vim:SendMouseButtonEvent(0,0,0,false, game,1)
                    end)
                    if not ok2 then warn_("Triggerbot click failed: " .. tostring(e2)) end
                    task.delay(triggerDelay, function() tbCooldown = false end)
                    break
                end
            end
        end
    end)
    log("Triggerbot on ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  SPECTATE                                                     ║
-- ╚══════════════════════════════════════════════════════════════╝
local function stopSpectate()
    if spectateConn then spectateConn:Disconnect(); spectateConn = nil end
    if spectateOrigType then
        Camera.CameraType = spectateOrigType
        spectateOrigType  = nil
    end
    local char = LP.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        Camera.CameraSubject = hum or char:FindFirstChild("HumanoidRootPart")
    end
    spectateTarget = nil
    log("Spectate stopped")
end

local function startSpectate(player)
    if spectateConn then stopSpectate() end
    if not player or not player.Parent then
        warn_("Spectate: invalid player"); return
    end
    spectateTarget   = player
    spectateOrigType = Camera.CameraType
    Camera.CameraType = Enum.CameraType.Follow
    spectateConn = RunService.RenderStepped:Connect(function()
        if not spectateTarget or not spectateTarget.Parent then
            Rayfield:Notify({ Title="Spectate", Content="Target left.", Duration=3 })
            stopSpectate(); return
        end
        local tChar = spectateTarget.Character
        if not tChar then return end
        local tHum = tChar:FindFirstChildOfClass("Humanoid")
        local tHRP = tChar:FindFirstChild("HumanoidRootPart")
        Camera.CameraSubject = tHum or tHRP
    end)
    log("Spectating " .. player.Name .. " ✓")
    Rayfield:Notify({ Title="Spectate", Content="Now spectating "..player.Name, Duration=3 })
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  SILENT AIM                                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
local function hookTools(char)
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and not tool:GetAttribute("_SAHooked") then
            tool:SetAttribute("_SAHooked", true)
            tool.Activated:Connect(function()
                if not F.silentAim then return end
                if not silentTarget or not silentTarget.Parent then
                    silentTarget = nil; return
                end
                local orig    = Camera.CFrame
                Camera.CFrame = CFrame.new(orig.Position, silentTarget.Position)
                task.defer(function() Camera.CFrame = orig end)
            end)
        end
    end
end
LP.CharacterAdded:Connect(function(char)
    task.wait(0.5); hookTools(char)
    char.ChildAdded:Connect(function(c)
        if c:IsA("Tool") then task.wait(0.1); hookTools(char) end
    end)
end)
if LP.Character then
    task.spawn(function() task.wait(0.3); hookTools(LP.Character) end)
    LP.Character.ChildAdded:Connect(function(c)
        if c:IsA("Tool") then task.wait(0.1); hookTools(LP.Character) end
    end)
end
log("Silent Aim hooks ready ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOOL PICKER                                                  ║
-- ║  Scans the entire game (workspace + ReplicatedStorage +       ║
-- ║  ServerStorage if accessible) for Tool instances, then        ║
-- ║  lets the player clone any one into their character.          ║
-- ╚══════════════════════════════════════════════════════════════╝
local toolPickerSelected = nil   -- Tool instance currently chosen in dropdown
local ToolPickerDropdown = nil   -- forward ref, assigned after UI creation

local function scanForTools()
    local found = {}
    local seen  = {}
    local function scan(container)
        local ok2 = pcall(function()
            for _, obj in ipairs(container:GetDescendants()) do
                if obj:IsA("Tool") and not seen[obj.Name] then
                    seen[obj.Name] = true
                    table.insert(found, obj)
                end
            end
        end)
    end
    scan(workspace)
    scan(game:GetService("ReplicatedStorage"))
    pcall(function() scan(game:GetService("ServerStorage")) end)
    pcall(function() scan(game:GetService("Lighting")) end)
    return found
end

local function getToolNames(tools)
    local names = {}
    for _, t in ipairs(tools) do table.insert(names, t.Name) end
    if #names == 0 then table.insert(names, "(no tools found)") end
    return names
end

-- refreshToolPicker was forward-declared; assigned here after ToolPickerDropdown exists
-- (actual assignment happens right after the dropdown is created in the UI section)

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOOL GIVER                                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
local function giveToolByID(idStr)
    if toolCharges <= 0 then
        Rayfield:Notify({Title="Tool Giver",Content="No charges left!",Duration=2}); return
    end
    local id = tonumber(idStr)
    if not id then
        Rayfield:Notify({Title="Tool Giver",Content="Enter a valid asset ID!",Duration=2}); return
    end
    task.spawn(function()
        local ok2, model = pcall(function()
            return game:GetObjects("rbxassetid://" .. id)[1]
        end)
        if not ok2 or not model then
            warn_("Tool Giver: failed to load asset " .. tostring(id))
            Rayfield:Notify({Title="Tool Giver",Content="Failed to load asset!",Duration=3}); return
        end
        if not model:IsA("Tool") then
            warn_("Tool Giver: asset " .. id .. " is not a Tool")
            Rayfield:Notify({Title="Tool Giver",Content="Not a Tool!",Duration=3})
            model:Destroy(); return
        end
        local char = LP.Character
        if not char then
            warn_("Tool Giver: no character")
            Rayfield:Notify({Title="Tool Giver",Content="No character!",Duration=2}); return
        end
        model.Parent = char
        toolCharges -= 1
        log("Tool given: " .. model.Name .. " | charges left: " .. toolCharges)
        Rayfield:Notify({Title="Tool Giver",Content="Given: "..model.Name.." | "..toolCharges.." left",Duration=3})
        -- updateToolLabel is defined after the UI label is created; use pcall just in case
        if updateToolLabel then pcall(updateToolLabel) end
    end)
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ABILITY TRIGGERS                                             ║
-- ╚══════════════════════════════════════════════════════════════╝
local function tryActivateESP()
    if espActive   then Rayfield:Notify({Title="ESP",Content="Already active!",Duration=2}); return end
    if espCooldown then Rayfield:Notify({Title="ESP",Content="On cooldown!",Duration=2});    return end
    espActive = true; espTimer = ESP_DURATION
    activateESP()
    Rayfield:Notify({Title="ESP",Content="Active for "..ESP_DURATION.."s",Duration=3})
end

local function tryToggleFly()
    if flyActive then
        flyActive=false; flyTimer=0; flyCooldown=true; flyCoolTimer=COOLDOWN_TIME
        stopFly()
        log("Fly stopped"); Rayfield:Notify({Title="Fly",Content="Stopped — "..COOLDOWN_TIME.."s cd",Duration=3})
    elseif flyCooldown then
        Rayfield:Notify({Title="Fly",Content="On cooldown!",Duration=2})
    else
        flyActive=true; flyTimer=FLY_DURATION
        startFly()
        log("Fly started ✓"); Rayfield:Notify({Title="Fly",Content="Active for "..FLY_DURATION.."s",Duration=3})
    end
end

local function tryActivateAimlock()
    if not F.aimlockEnabled then return end
    if aimlockActive or aimlockCooldown then return end
    local dur = AIMLOCK_DURATION + rewardBonus
    rewardBonus=0; rewardIdleTime=0
    aimlockActive=true; aimlockTimer=dur
    log("Aimlock activated (" .. dur .. "s) ✓")
    Rayfield:Notify({Title="Aimlock",Content="Active for "..dur.."s — hold RMB",Duration=3})
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  PANIC                                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
local function doPanic()
    F.aimlockEnabled=false; F.silentAim=false; F.triggerbot=false
    setAntiAim(false)
    setFakeLag(false); setSpeedHack(false)
    espActive=false; clearAllESP()
    stopFly(); flyActive=false
    stopSpectate()
    pcall(function()
        for _, gui in ipairs(game:GetService("CoreGui"):GetChildren()) do
            if gui.Name:find("Rayfield") then gui.Enabled = false end
        end
    end)
    log("PANIC — all features disabled, UI hidden")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  INPUT HANDLER                                                ║
-- ╚══════════════════════════════════════════════════════════════╝
UserInputService.InputBegan:Connect(function(inp, proc)
    if proc then return end
    -- Direct enum comparison — no string indexing (that was the crash bug)
    if inp.KeyCode == KB_ESP   then tryActivateESP()  end
    if inp.KeyCode == KB_FLY   then tryToggleFly()    end
    if inp.KeyCode == KB_PANIC then doPanic()          end
    if inp.UserInputType == Enum.UserInputType.MouseButton2 then
        if F.aimlockEnabled then aimlockHeld=true; tryActivateAimlock() end
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton2 then
        aimlockHeld = false
    end
end)
log("Input handler registered ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  COMBAT TAB                                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
TabCombat:CreateSection("Aimlock")
TabCombat:CreateToggle({Name="Aimlock Enabled",CurrentValue=false,Flag="AimlockEnabled",
    Callback=function(v) F.aimlockEnabled=v; log("Aimlock: "..tostring(v)) end})
TabCombat:CreateDropdown({Name="Lock Mode",Options={"Camera","Mouse"},CurrentOption="Camera",Flag="AimlockMode",
    Callback=function(v) aimlockMode=type(v)=="table" and v[1] or v end})
TabCombat:CreateSlider({Name="FOV Radius",Range={20,400},Increment=5,Suffix="px",CurrentValue=120,Flag="AimlockFOV",
    Callback=function(v) aimlockFOV=v; fovCircle.Radius=v end})
TabCombat:CreateSlider({Name="Smoothness %",Range={1,100},Increment=1,Suffix="%",CurrentValue=12,Flag="AimlockSmooth",
    Callback=function(v) aimlockSmooth=v/100 end})
TabCombat:CreateToggle({Name="Show FOV Circle",CurrentValue=false,Flag="AimlockFOVShow",
    Callback=function(v) F.aimlockFOVShow=v; if not v then fovCircle.Visible=false end end})
TabCombat:CreateToggle({Name="Team Check",CurrentValue=false,Flag="AimlockTeamCheck",
    Callback=function(v) F.aimlockTeamCheck=v end})

TabCombat:CreateSection("Combat")
TabCombat:CreateToggle({Name="Silent Aim",CurrentValue=false,Flag="SilentAim",
    Callback=function(v) F.silentAim=v; log("Silent Aim: "..tostring(v)) end})
TabCombat:CreateToggle({Name="Triggerbot",CurrentValue=false,Flag="Triggerbot",
    Callback=function(v) setTriggerbot(v) end})
TabCombat:CreateSlider({Name="Trigger Delay",Range={0,500},Increment=10,Suffix="ms",CurrentValue=80,Flag="TriggerDelay",
    Callback=function(v) triggerDelay=v/1000 end})

TabCombat:CreateSection("Anti-Aim")
TabCombat:CreateToggle({Name="Anti-Aim Enabled",CurrentValue=false,Flag="AntiAim",
    Callback=function(v) setAntiAim(v) end})
TabCombat:CreateDropdown({Name="Mode",Options={"Spin","Jitter"},CurrentOption="Spin",Flag="AntiAimMode",
    Callback=function(v)
        antiAimMode = type(v)=="table" and v[1] or v
        log("Anti-aim mode: " .. antiAimMode)
        -- Restart if active so the new mode takes effect immediately
        if F.antiAim then setAntiAim(false); setAntiAim(true) end
    end})
TabCombat:CreateSlider({Name="Spin Speed",Range={5,60},Increment=1,Suffix=" deg/f",CurrentValue=20,Flag="AntiAimSpeed",
    Callback=function(v) antiAimSpeed=v end})
log("Combat tab built ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  VISUAL TAB                                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
TabVisual:CreateSection("ESP")
TabVisual:CreateButton({Name="Activate ESP  [E]", Callback=tryActivateESP})
TabVisual:CreateToggle({Name="Highlights (glow)",CurrentValue=false,Flag="ESPHighlights",
    Callback=function(v) F.espHighlights=v; if espActive then activateESP() end end})
TabVisual:CreateToggle({Name="Tracers",CurrentValue=false,Flag="ESPTracers",
    Callback=function(v) F.espTracers=v end})
TabVisual:CreateToggle({Name="Nametags",CurrentValue=false,Flag="ESPNametags",
    Callback=function(v) F.espNametags=v end})
TabVisual:CreateToggle({Name="Health Bars",CurrentValue=false,Flag="ESPHealthBars",
    Callback=function(v) F.espHealthBars=v end})
TabVisual:CreateToggle({Name="Box ESP",CurrentValue=false,Flag="ESPBoxes",
    Callback=function(v) F.espBoxes=v end})
TabVisual:CreateToggle({Name="Skeleton",CurrentValue=false,Flag="ESPSkeleton",
    Callback=function(v) F.espSkeleton=v end})

TabVisual:CreateSection("Style")
TabVisual:CreateSlider({Name="ESP Line Thickness",Range={1,6},Increment=0.5,CurrentValue=1.5,Flag="ESPThick",
    Callback=function(v)
        espLineThick=v
        for _,l in pairs(espTracerLines) do l.Thickness=v end
        for _,g in pairs(boxLineGroups)  do for _,l in ipairs(g) do l.Thickness=v end end
        for _,g in pairs(skelLineGroups) do for _,l in ipairs(g) do l.Thickness=v end end
    end})
TabVisual:CreateSection("Radar / Minimap")
TabVisual:CreateToggle({Name="Show Radar",CurrentValue=false,Flag="Radar",
    Callback=function(v)
        F.radar=v
        log("Radar: "..tostring(v))
    end})
TabVisual:CreateSlider({Name="Radar Range (world units)",Range={50,500},Increment=10,Suffix=" wu",CurrentValue=150,Flag="RadarRange",
    Callback=function(v)
        RADAR_RANGE=v
        log("Radar range: "..v)
    end})
TabVisual:CreateSlider({Name="Radar Size (px radius)",Range={60,200},Increment=5,CurrentValue=120,Flag="RadarSize",
    Callback=function(v)
        RADAR_RADIUS=v
        radarBG.Radius     = v
        radarRing.Radius   = v * 0.5
        radarBorder.Radius = v
    end})
log("Visual tab built ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  MOVEMENT TAB                                                 ║
-- ╚══════════════════════════════════════════════════════════════╝
TabMovement:CreateSection("Fly")
TabMovement:CreateButton({Name="Toggle Fly  [F]", Callback=tryToggleFly})
TabMovement:CreateSlider({Name="Fly Speed",Range={10,250},Increment=5,Suffix=" st/s",CurrentValue=50,Flag="FlySpeed",
    Callback=function(v) flySpeed=v end})

TabMovement:CreateSection("Movement")
TabMovement:CreateToggle({Name="Speed Hack  (overrides sprint)",CurrentValue=false,Flag="SpeedHack",
    Callback=function(v) setSpeedHack(v) end})
TabMovement:CreateSlider({Name="Speed Multiplier",Range={1,10},Increment=0.5,Suffix="x",CurrentValue=2,Flag="SpeedMult",
    Callback=function(v)
        speedMultiplier=v
        log("Speed multiplier: "..v.."x")
    end})
TabMovement:CreateToggle({Name="Infinite Jump",CurrentValue=false,Flag="InfJump",
    Callback=function(v) setInfJump(v) end})
TabMovement:CreateToggle({Name="No-Clip",CurrentValue=false,Flag="Noclip",
    Callback=function(v) setNoclip(v) end})
TabMovement:CreateToggle({Name="Bunny Hop",CurrentValue=false,Flag="Bhop",
    Callback=function(v) setBhop(v) end})
log("Movement tab built ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  UTILITY TAB                                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
TabUtility:CreateSection("Teleport to Player")

local function getOtherPlayerNames()
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then table.insert(t, p.Name) end
    end
    if #t == 0 then table.insert(t, "(no players)") end
    return t
end

local TpDropdown = TabUtility:CreateDropdown({
    Name="Select Target", Options=getOtherPlayerNames(),
    CurrentOption="(no players)", Flag="TpTarget",
    Callback=function(v)
        local name = type(v)=="table" and v[1] or v
        tpTarget = Players:FindFirstChild(name)
        log("TP target: " .. tostring(name))
    end,
})
Players.PlayerAdded:Connect(function()
    pcall(function() TpDropdown:Set(getOtherPlayerNames()) end)
end)
Players.PlayerRemoving:Connect(function(p)
    if tpTarget == p then tpTarget = nil end
    pcall(function() TpDropdown:Set(getOtherPlayerNames()) end)
end)

local _TpLabel = TabUtility:CreateLabel("Charges: " .. tpCharges)
-- FIX: define updateTpLabel here (after the label), not as a forward ref
updateTpLabel = function()
    pcall(function() _TpLabel:Set("Charges: " .. tpCharges) end)
end

TabUtility:CreateButton({Name="Teleport  (1 charge)",
    Callback=function()
        if tpCharges <= 0 then
            Rayfield:Notify({Title="Teleport",Content="No charges!",Duration=2}); return
        end
        if not tpTarget or not tpTarget.Parent then
            Rayfield:Notify({Title="Teleport",Content="Select a valid target!",Duration=2}); return
        end
        local tRoot = tpTarget.Character and tpTarget.Character:FindFirstChild("HumanoidRootPart")
        if not tRoot then
            Rayfield:Notify({Title="Teleport",Content="Target has no character!",Duration=2}); return
        end
        local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myRoot then return end
        myRoot.CFrame = tRoot.CFrame * CFrame.new(0, 2, -3)
        tpCharges -= 1
        updateTpLabel()
        log("Teleported to " .. tpTarget.Name .. " | charges: " .. tpCharges)
        Rayfield:Notify({Title="Teleport",Content="Warped to "..tpTarget.Name,Duration=3})
    end,
})

TabUtility:CreateSection("Spectate")
local spectateSelected = nil
local SpecDropdown = TabUtility:CreateDropdown({
    Name="Player to Spectate", Options=getOtherPlayerNames(),
    CurrentOption="(no players)", Flag="SpecTarget",
    Callback=function(v)
        local name = type(v)=="table" and v[1] or v
        spectateSelected = Players:FindFirstChild(name)
    end,
})
Players.PlayerAdded:Connect(function()
    pcall(function() SpecDropdown:Set(getOtherPlayerNames()) end)
end)
Players.PlayerRemoving:Connect(function(p)
    if spectateSelected == p then spectateSelected = nil end
    if spectateTarget   == p then stopSpectate() end
    pcall(function() SpecDropdown:Set(getOtherPlayerNames()) end)
end)
TabUtility:CreateButton({Name="Start Spectate",
    Callback=function()
        if not spectateSelected or not spectateSelected.Parent then
            Rayfield:Notify({Title="Spectate",Content="Select a player first!",Duration=2}); return
        end
        startSpectate(spectateSelected)
    end,
})
TabUtility:CreateButton({Name="Stop Spectate",
    Callback=function() stopSpectate(); Rayfield:Notify({Title="Spectate",Content="Stopped.",Duration=2}) end,
})

TabUtility:CreateSection("Tool Picker")

-- Build dropdown immediately with whatever tools exist in the game right now
local _cachedTools = scanForTools()
ToolPickerDropdown = TabUtility:CreateDropdown({
    Name          = "Select Tool",
    Options       = getToolNames(_cachedTools),
    CurrentOption = getToolNames(_cachedTools)[1] or "(no tools found)",
    Flag          = "ToolPickerSel",
    Callback      = function(v)
        local name = type(v)=="table" and v[1] or v
        -- find the matching Tool object from the last scan
        for _, t in ipairs(_cachedTools) do
            if t.Name == name then toolPickerSelected = t; break end
        end
    end,
})

-- Now we can define refreshToolPicker (was forward-declared earlier)
refreshToolPicker = function()
    _cachedTools = scanForTools()
    local names  = getToolNames(_cachedTools)
    pcall(function() ToolPickerDropdown:Set(names) end)
    toolPickerSelected = _cachedTools[1] or nil
    log("Tool Picker refreshed — " .. #_cachedTools .. " tools found")
    Rayfield:Notify({Title="Tool Picker",Content=#_cachedTools.." tools found",Duration=3})
end

TabUtility:CreateButton({Name="Refresh Tool List",
    Callback=refreshToolPicker,
})

TabUtility:CreateButton({Name="Give Selected Tool to Me",
    Callback=function()
        if not toolPickerSelected or not toolPickerSelected.Parent then
            Rayfield:Notify({Title="Tool Picker",Content="No tool selected or tool gone — refresh!",Duration=3}); return
        end
        local char = LP.Character
        if not char then
            Rayfield:Notify({Title="Tool Picker",Content="No character!",Duration=2}); return
        end
        local clone = toolPickerSelected:Clone()
        clone.Parent = char
        log("Gave tool: " .. clone.Name)
        Rayfield:Notify({Title="Tool Picker",Content="Gave: "..clone.Name,Duration=3})
    end,
})

-- Keep the original asset-ID giver as a fallback
TabUtility:CreateSection("Tool Giver  (by Asset ID)")
local _ToolLabel = TabUtility:CreateLabel("Charges: " .. toolCharges)
updateToolLabel = function()
    pcall(function() _ToolLabel:Set("Charges: " .. toolCharges) end)
end
TabUtility:CreateInput({Name="Asset ID",PlaceholderText="Roblox asset ID...",
    RemoveTextAfterFocusLost=false, Flag="ToolAssetID",
    Callback=function(v) toolIDInput=v end,
})
TabUtility:CreateButton({Name="Give Tool  (1 charge)",
    Callback=function() giveToolByID(toolIDInput) end,
})

TabUtility:CreateSection("Player Info")
local piSelected = nil
local PiDropdown = TabUtility:CreateDropdown({
    Name="Select Player",Options=getOtherPlayerNames(),
    CurrentOption="(no players)",Flag="PiPlayer",
    Callback=function(v)
        local name = type(v)=="table" and v[1] or v
        piSelected = Players:FindFirstChild(name)
    end,
})
Players.PlayerAdded:Connect(function()   pcall(function() PiDropdown:Set(getOtherPlayerNames()) end) end)
Players.PlayerRemoving:Connect(function(p)
    if piSelected == p then piSelected = nil end
    pcall(function() PiDropdown:Set(getOtherPlayerNames()) end)
end)
TabUtility:CreateButton({Name="Show Info",
    Callback=function()
        local p = piSelected
        if not p or not p.Parent then
            Rayfield:Notify({Title="Player Info",Content="Select a player first!",Duration=2}); return
        end
        local char    = p.Character
        local hrp     = char and char:FindFirstChild("HumanoidRootPart")
        local hum     = char and char:FindFirstChildOfClass("Humanoid")
        local myHRP   = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local dist    = (hrp and myHRP) and
            math.floor((hrp.Position - myHRP.Position).Magnitude) or "?"
        local hp      = hum and math.floor(hum.Health) or "?"
        local maxhp   = hum and math.floor(hum.MaxHealth) or "?"
        local team    = p.Team and p.Team.Name or "None"
        local acctAge = "?"
        pcall(function() acctAge = tostring(p.AccountAge) .. " days" end)
        local userId  = tostring(p.UserId)
        local info = string.format(
            "Name: %s\nDisplayName: %s\nUserID: %s\nAcct Age: %s\nTeam: %s\nHP: %s/%s\nDistance: %sm",
            p.Name, p.DisplayName, userId, acctAge, team, hp, maxhp, dist)
        log("Player Info — " .. p.Name .. ": " .. info:gsub("\n"," | "))
        Rayfield:Notify({Title="Info: "..p.Name, Content=info, Duration=12})
    end,
})

TabUtility:CreateSection("Misc")
TabUtility:CreateToggle({Name="Infinite Zoom",CurrentValue=false,Flag="InfZoom",
    Callback=function(v) setInfZoom(v) end})
TabUtility:CreateToggle({Name="Auto-Rejoin on Kick",CurrentValue=false,Flag="AutoRejoin",
    Callback=function(v) setAutoRejoin(v) end})
TabUtility:CreateToggle({Name="Watermark (top-left HUD)",CurrentValue=false,Flag="Watermark",
    Callback=function(v) F.watermark=v; log("Watermark: "..tostring(v)) end})
TabUtility:CreateToggle({Name="Fullbright",CurrentValue=false,Flag="Fullbright",
    Callback=function(v) setFullbright(v) end})
TabUtility:CreateToggle({Name="Fake Lag",CurrentValue=false,Flag="FakeLag",
    Callback=function(v) setFakeLag(v) end})
TabUtility:CreateSlider({Name="Fake Lag Amount",Range={50,1000},Increment=25,Suffix="ms",CurrentValue=200,Flag="FakeLagMS",
    Callback=function(v) fakeLagMS=v end})
TabUtility:CreateToggle({Name="Anti-AFK",CurrentValue=false,Flag="AntiAfk",
    Callback=function(v) setAntiAfk(v) end})
TabUtility:CreateToggle({Name="Click Teleport  (hold key + LMB)",CurrentValue=false,Flag="ClickTp",
    Callback=function(v) setClickTp(v) end})
TabUtility:CreateButton({Name="Rejoin",
    Callback=function()
        log("Rejoining...")
        Rayfield:Notify({Title="Rejoin",Content="Rejoining in 1s...",Duration=2})
        task.delay(1, function() TeleportService:Teleport(game.PlaceId, LP) end)
    end,
})
TabUtility:CreateButton({Name="Server Hop",
    Callback=function()
        log("Server Hop: scanning...")
        Rayfield:Notify({Title="Server Hop",Content="Scanning...",Duration=3})
        task.spawn(function()
            local ok2, data = pcall(function()
                return HttpService:JSONDecode(
                    game:HttpGet("https://games.roblox.com/v1/games/"
                        ..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=10"))
            end)
            if ok2 and data and data.data then
                for _, s in ipairs(data.data) do
                    if s.id ~= game.JobId and s.playing < s.maxPlayers then
                        log("Server Hop: hopping to " .. s.id)
                        TeleportService:TeleportToPlaceInstance(game.PlaceId,s.id,LP); return
                    end
                end
                warn_("Server Hop: no free servers found, rejoining")
            else
                warn_("Server Hop: HTTP request failed")
            end
            TeleportService:Teleport(game.PlaceId, LP)
        end)
    end,
})
log("Utility tab built ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  SETTINGS TAB                                                 ║
-- ╚══════════════════════════════════════════════════════════════╝
TabSettings:CreateSection("Keybinds")

-- FIX: Rayfield Keybind callback may pass a string OR a KeyCode enum.
-- We handle both. KB_* vars store KeyCode enums so inp.KeyCode == KB_* works.
local function resolveKeyCode(v, fallback)
    if type(v) == "string" and v ~= "" then
        return Enum.KeyCode[v] or fallback
    elseif type(v) == "userdata" then
        return v  -- already a KeyCode enum
    end
    return fallback
end

TabSettings:CreateKeybind({Name="ESP Key",CurrentKeybind="E",HoldToInteract=false,Flag="KB_ESP",
    Callback=function(v) KB_ESP=resolveKeyCode(v,KB_ESP); log("ESP key: "..tostring(KB_ESP)) end})
TabSettings:CreateKeybind({Name="Fly Key",CurrentKeybind="F",HoldToInteract=false,Flag="KB_FLY",
    Callback=function(v) KB_FLY=resolveKeyCode(v,KB_FLY); log("Fly key: "..tostring(KB_FLY)) end})
TabSettings:CreateKeybind({Name="Click TP Hold Key",CurrentKeybind="G",HoldToInteract=false,Flag="KB_CLICKTP",
    Callback=function(v)
        KB_CLICKTP=resolveKeyCode(v,KB_CLICKTP)
        if F.clickTp then setClickTp(false); setClickTp(true) end  -- restart with new key
        log("Click TP key: "..tostring(KB_CLICKTP))
    end})
TabSettings:CreateKeybind({Name="Panic Key",CurrentKeybind="Delete",HoldToInteract=false,Flag="KB_PANIC",
    Callback=function(v) KB_PANIC=resolveKeyCode(v,KB_PANIC); log("Panic key: "..tostring(KB_PANIC)) end})

TabSettings:CreateSection("Config Profiles")

local _profileList = listProfiles()
local _profileDropdown = TabSettings:CreateDropdown({
    Name          = "Profile",
    Options       = _profileList,
    CurrentOption = _profileList[1] or "Default",
    Flag          = "ConfigProfile",
    Callback      = function(v)
        currentProfile = type(v)=="table" and v[1] or v
    end,
})

TabSettings:CreateInput({Name="New Profile Name",PlaceholderText="e.g. PvP, Farm, Safe...",
    RemoveTextAfterFocusLost=false, Flag="NewProfileName",
    Callback=function(v) if v ~= "" then currentProfile=v end end,
})

TabSettings:CreateButton({Name="Save Current Profile",
    Callback=function()
        saveProfile(currentProfile)
        -- Rebuild dropdown with fresh file list
        local fresh = listProfiles()
        pcall(function() _profileDropdown:Set(fresh) end)
    end,
})

TabSettings:CreateButton({Name="Load Selected Profile",
    Callback=function() loadProfile(currentProfile) end,
})

TabSettings:CreateSection("Danger Zone")
TabSettings:CreateButton({Name="PANIC  (disable all + hide UI)", Callback=doPanic})
log("Settings tab built ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  MAIN HEARTBEAT LOOP                                         ║
-- ╚══════════════════════════════════════════════════════════════╝
RunService.Heartbeat:Connect(function(dt)

    -- ESP timer (only counts down when activated via keybind/button, not toggle)
    if espActive then
        espTimer -= dt
        if espTimer <= 0 then
            espActive=false; espTimer=0
            espCooldown=true; espCoolTimer=COOLDOWN_TIME
            clearAllESP()
            log("ESP expired")
            Rayfield:Notify({Title="ESP",Content="Expired — "..COOLDOWN_TIME.."s cooldown",Duration=3})
        end
    elseif espCooldown then
        espCoolTimer -= dt
        if espCoolTimer <= 0 then
            espCooldown=false; espCoolTimer=0
            log("ESP ready")
            Rayfield:Notify({Title="ESP",Content="Ready!",Duration=2})
        end
    end

    -- Fly timer
    if flyActive then
        flyTimer -= dt
        if flyTimer <= 0 then
            flyActive=false; flyTimer=0
            flyCooldown=true; flyCoolTimer=COOLDOWN_TIME
            stopFly()
            log("Fly expired")
            Rayfield:Notify({Title="Fly",Content="Expired — "..COOLDOWN_TIME.."s cooldown",Duration=3})
        end
    elseif flyCooldown then
        flyCoolTimer -= dt
        if flyCoolTimer <= 0 then
            flyCooldown=false; flyCoolTimer=0
            Rayfield:Notify({Title="Fly",Content="Ready!",Duration=2})
        end
    end

    -- Idle aimlock reward
    if not aimlockActive then
        rewardIdleTime += dt
        if rewardIdleTime >= REWARD_THRESHOLD then
            rewardIdleTime -= REWARD_THRESHOLD
            rewardBonus    += REWARD_BONUS
            log("Aimlock bonus banked: +" .. REWARD_BONUS .. "s (total: +" .. rewardBonus .. "s)")
            Rayfield:Notify({Title="Reward",Content="+"..REWARD_BONUS.."s aimlock bonus!",Duration=4})
        end
    end

    -- Aimlock tracking (runs in Heartbeat for smooth camera)
    if aimlockActive then
        if aimlockHeld and F.aimlockEnabled then
            local tgt = getBestTarget()
            if tgt then
                local cur = Camera.CFrame
                local goal = CFrame.new(cur.Position, tgt.Position)
                local smooth = aimlockMode == "Camera" and aimlockSmooth or 0.85
                Camera.CFrame = cur:Lerp(goal, smooth)
            end
        end
        aimlockTimer -= dt
        if aimlockTimer <= 0 then
            aimlockActive=false; aimlockTimer=0; aimlockHeld=false
            aimlockCooldown=true; aimlockCoolTimer=COOLDOWN_TIME
            log("Aimlock expired")
        end
    elseif aimlockCooldown then
        aimlockCoolTimer -= dt
        if aimlockCoolTimer <= 0 then
            aimlockCooldown=false; aimlockCoolTimer=0
            Rayfield:Notify({Title="Aimlock",Content="Ready!",Duration=2})
        end
    end
end)

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  RESPAWN HANDLING                                             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Re-apply ESP to other players when they respawn
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        if espActive then task.defer(applyESPToPlayer, player) end
    end)
end)
for _, player in ipairs(Players:GetPlayers()) do
    player.CharacterAdded:Connect(function()
        if espActive then task.defer(applyESPToPlayer, player) end
    end)
end

-- Re-apply features to local player after respawn
LP.CharacterAdded:Connect(function()
    log("Respawned — re-applying active features")
    -- Reset transient state
    flyActive=false; flyTimer=0
    flyBV=nil; flyBG=nil; flyConn=nil
    aimlockActive=false; aimlockTimer=0; aimlockHeld=false
    -- Re-apply
    if espActive     then task.defer(activateESP)       end
    task.wait(0.1)
    if F.speedHack   then setSpeedHack(true)   end
    if F.infJump     then setInfJump(true)     end
    if F.noclip      then setNoclip(true)      end
    if F.bhop        then setBhop(true)        end
    if F.antiAfk     then setAntiAfk(true)     end
    if F.fullbright  then setFullbright(true)  end
    if F.antiAim     then setAntiAim(true)     end
end)

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  DONE                                                         ║
-- ╚══════════════════════════════════════════════════════════════╝
log("════════════════════════════════════════════")
log("Ghost v3 fully loaded — all systems OK")
log("  Combat  : Aimlock, Silent Aim, Triggerbot")
log("  Visual  : Highlights, Tracers, Nametags, HP Bars, Box, Skeleton")
log("  Movement: Fly, Speed x2, Inf Jump, No-Clip, Bunny Hop")
log("  Utility : Teleport, Spectate, Tool Picker, Player Info, Zoom, Auto-Rejoin")
log("  Settings: Keybinds, Config Profiles, Panic")
log("════════════════════════════════════════════")
Rayfield:Notify({Title="Ghost v3", Content="All systems loaded!", Duration=4})
