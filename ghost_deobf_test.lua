-- ╔══════════════════════════════════════════════════════════════╗
-- ║              Ghost v3  —  Rayfield Edition  v2               ║
-- ║  Target-lock system. Keybinds per feature. No timers.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Executor Detector + Bad Executor Notification
-- Small Luau snippet for Roblox exploits
-- === UN-SPOOFABLE EXECUTOR DETECTOR (Luau) ===
-- Resistant to most getgenv() spoofing, identifyexecutor hooks, etc.

local function isBadExecutor()
    local name = "Unknown"

    -- Method 1: Direct call (harder to hook properly)
    local success, result = pcall(function()
        return identifyexecutor and identifyexecutor() or nil
    end)
    if success and result then
        name = result
    end

    -- Method 2: Check raw globals (many spoofers miss these)
    local rawget = getgenv().rawget or rawget
    if rawget(getgenv(), "Solara") or rawget(_G, "Solara") then name = "Solara" end
    if rawget(getgenv(), "Xeno") or rawget(_G, "Xeno") then name = "Xeno" end
    if rawget(getgenv(), "Delta") or rawget(_G, "Delta") then name = "Delta" end

    -- Method 3: Unique function signatures / behavior checks
    if getgc then
        for _, v in ipairs(getgc()) do
            if typeof(v) == "function" then
                local info = debug.getinfo(v)
                if info and info.source and info.source:find("solara") then
                    name = "Solara"
                    break
                end
            end
        end
    end

    -- Method 4: Check for common spoof patterns
    local lowerName = name:lower()
    if lowerName:find("solara") or lowerName:find("xeno") or lowerName:find("delta") then
        return true, name
    end

    -- Extra common bad ones
    local badList = {"solara", "xeno", "delta", "fluxus", "krnl", "codex"}
    for _, bad in ipairs(badList) do
        if lowerName:find(bad) then
            return true, name
        end
    end

    return false, name
end

-- ============== USAGE ==============
local isBad, executorName = isBadExecutor()

if isBad then
    notify({
        Title = "Executor Detected",
        Text = executorName .. " is buns.\nSome functions will not work properly.",
        Duration = 10,
        Icon = "rbxassetid://7072720872" -- warning icon
    })
    
    warn("Bad executor detected:", executorName)
    
    -- Optional: Stop the script
    -- return
end
-- Example usage later in your script:
-- if isBad then return end -- or skip certain functions

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService  = game:GetService("TeleportService")
local HttpService      = game:GetService("HttpService")
local Lighting         = game:GetService("Lighting")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

local LP     = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local function log(msg)  print("[Ghost] "..tostring(msg)) end
local function warn_(msg) warn("[Ghost] "..tostring(msg)) end
log("Starting Ghost v3 v2...")

-- ── Load Rayfield ─────────────────────────────────────────────────
local Rayfield
do
    local ok,err=pcall(function()
        Rayfield=loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    end)
    if not ok then error("Rayfield failed: "..tostring(err),0) end
    log("Rayfield loaded ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  FEATURE FLAGS                                               ║
-- ╚══════════════════════════════════════════════════════════════╝
local F = {
    -- Target system
    targetLocked=false, targetTeamCheck=false, targetLOSCheck=false,
    targetAliveCheck=true, targetForceCheck=false,
    -- Aimbot modes
    camAimlock=false, mouseAimlock=false,
    mouseRMBHold=false, mouseWallCheck=false, mouseTeamCheck=false, mouseJitter=false,
    prediction=false, bulletPred=false, silentAim=false,
    -- Combat
    triggerbot=false, antiAim=false, killAura=false, rapidFire=false,
    -- ESP
    espHighlights=false, espTracers=false, espNametags=false,
    espHealthBars=false, espBoxes=false, espSkeleton=false,
    -- Movement
    speedHack=false, infJump=false, noclip=false, bhop=false,
    lowGrav=false, swimSpeed=false, autoCollect=false,
    -- Misc
    fullbright=false, fakeLag=false, antiAfk=false,
    clickTp=false, infZoom=false, watermark=false, autoRejoin=false, radar=false,
    csync=false,
}

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  STATE                                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
local BASE_SPEED   = 16
local PROFILE_FOLDER="GhostV3/Profiles/"

-- Target system
local lockedTarget    = nil   -- the Part (e.g. Head) of the locked target
local lockedPlayer    = nil   -- the Player instance of the locked target
local targetSelectMode= "Closest to Mouse"  -- or "Closest to Player"
local aimlockFOV      = 120
local aimlockSmooth   = 0.12
local predScale       = 0.08
local camSmooth       = 0.08

-- Mouse aimlock
local mouseAimlockConn= nil
local mouseAimPart    = "Head"
local mouseSmooth     = 0.25
local mouseDeadzone   = 2
local mouseJitterAmt  = 3

-- ESP
local espActive       = false
local espHighlightObjs= {}
local espTracerLines  = {}
local nametagTexts    = {}
local hpBGLines       = {}
local hpFillLines     = {}
local boxLineGroups   = {}
local skelLineGroups  = {}
local espLineColor    = Color3.fromRGB(255,50,50)
local espLineThick    = 1.5

local SKEL_R15={
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"LowerTorso","LeftUpperLeg"},{"LowerTorso","RightUpperLeg"},
    {"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    {"UpperTorso","LeftUpperArm"},{"UpperTorso","RightUpperArm"},
    {"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
}
local SKEL_R6={{"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},
    {"Torso","Left Leg"},{"Torso","Right Leg"}}

-- Fly
local flyActive=false; local flyBV,flyBG,flyConn=nil,nil,nil
local flySpeed=50; local flyMode="Velocity"  -- "Velocity" or "CFrame"

-- Connections
local speedConn=nil; local infJumpConn=nil; local noclipConn=nil
local bhopConn=nil; local fakeLagConn=nil; local antiAfkConn=nil
local clickTpConn=nil; local zoomConn=nil; local autoRejoinConn=nil
local antiAimConn=nil; local antiAimAngle=0; local antiAimMode="Spin"; local antiAimSpeed=20
local tbConn=nil; local tbCooldown=false; local triggerDelay=0.08
local killAuraConn=nil; local killAuraRange=20; local killAuraDmg=10; local killAuraRate=0.1
local gravConn=nil; local gravScale=30; local swimConn=nil; local swimMult=3
local autoCollectConn=nil; local collectInterval=1
local fakeLagMS=200; local speedMult=2

-- Rapid fire
local rapidFireConn=nil; local rapidFireDelay=0.01; local isFiring=false

-- CSync — fixed version: saves origin, tps back on disable
local csyncConn=nil; local csyncRadius=1000000; local csyncSpeed=10; local csyncAngle=0
local csyncOrigin=nil  -- saved CFrame before csync moves HRP

-- Ragebot
local ragebotActive=false; local ragebotOrigin=nil
local ragebotFlyBV=nil; local ragebotFlyBG=nil; local ragebotConn=nil
local ragebotSmooth=0.20; local ragebotFireThresh=80; local ragebotTrigDelay=0.05
local ragebotRadius=8; local ragebotOrbitSpd=120
local _rbTarget=nil  -- Player instance

-- Radar
local RADAR_RADIUS=120; local RADAR_RANGE=150; local RADAR_X=20; local RADAR_Y=20
local radarBG,radarRing,radarBorder,radarSelf=nil,nil,nil,nil
local radarDots={}; local radarLabels={}

-- Misc
local origAmbient=Lighting.Ambient; local origOutdoorAmbient=Lighting.OutdoorAmbient
local origBrightness=Lighting.Brightness; local origClockTime=Lighting.ClockTime
local origGravity=workspace.Gravity; local origFOV=Camera.FieldOfView
local tpTarget=nil; local spectateSelected=nil; local spectateTarget=nil
local spectateConn=nil; local spectateOrigType=nil
local silentTarget=nil

-- Keybinds — each feature has its own
local KB = {
    lockTarget   = Enum.KeyCode.C,
    clearTarget  = Enum.KeyCode.X,
    camAimlock   = Enum.KeyCode.Unknown,  -- assign to enable cam aimlock hold
    mouseAimlock = Enum.KeyCode.Unknown,
    esp          = Enum.KeyCode.E,
    fly          = Enum.KeyCode.F,
    panic        = Enum.KeyCode.Delete,
    clickTp      = Enum.KeyCode.G,
    ragebot      = Enum.KeyCode.Unknown,
}

-- Cached
local _losParams=RaycastParams.new(); _losParams.FilterType=Enum.RaycastFilterType.Exclude
local _gtCenter=Vector2.new(0,0)
local _wmFPS=0; local _wmPing=0; local _wmTimer=0

local NOCLIP_PARTS={
    HumanoidRootPart=true,Head=true,Torso=true,UpperTorso=true,LowerTorso=true,
    ["Left Arm"]=true,["Right Arm"]=true,["Left Leg"]=true,["Right Leg"]=true,
    LeftUpperArm=true,LeftLowerArm=true,LeftHand=true,
    RightUpperArm=true,RightLowerArm=true,RightHand=true,
    LeftUpperLeg=true,LeftLowerLeg=true,LeftFoot=true,
    RightUpperLeg=true,RightLowerLeg=true,RightFoot=true,
}

-- Forward
local stopRagebot

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  RAYFIELD WINDOW + TABS                                       ║
-- ╚══════════════════════════════════════════════════════════════╝
local Window=Rayfield:CreateWindow({
    Name="Ghost v3",LoadingTitle="Ghost v3",LoadingSubtitle="Loading...",
    ConfigurationSaving={Enabled=true,FolderName="GhostV3",FileName="Config"},
    Discord={Enabled=false},KeySystem=false,
})

local TabAimbot   = Window:CreateTab("Aimbot",   "crosshair")
local TabCombat   = Window:CreateTab("Combat",   "swords")
local TabRagebot  = Window:CreateTab("Ragebot",  "zap")
local TabVisual   = Window:CreateTab("Visual",   "eye")
local TabMovement = Window:CreateTab("Movement", "wind")
local TabUtility  = Window:CreateTab("Utility",  "wrench")
log("Tabs created ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  DRAWING HELPERS                                              ║
-- ╚══════════════════════════════════════════════════════════════╝
local function newLine(col,thick)
    local l=Drawing.new("Line"); l.Visible=false
    l.Color=col or Color3.new(1,1,1); l.Thickness=thick or 1; l.Transparency=1; return l
end
local function newText(col,sz)
    local t=Drawing.new("Text"); t.Visible=false
    t.Color=col or Color3.new(1,1,1); t.Size=sz or 14; t.Font=2
    t.Center=true; t.Outline=true; t.OutlineColor=Color3.new(0,0,0); return t
end

local fovCircle=Drawing.new("Circle"); fovCircle.Visible=false
fovCircle.Color=Color3.fromRGB(255,255,255); fovCircle.Thickness=1.5
fovCircle.Transparency=1; fovCircle.Filled=false; fovCircle.NumSides=64; fovCircle.Radius=120

-- Target indicator dot (shows on screen where locked target is)
local targetDot=Drawing.new("Circle"); targetDot.Visible=false; targetDot.Filled=true
targetDot.Color=Color3.fromRGB(255,255,0); targetDot.Transparency=1
targetDot.NumSides=12; targetDot.Radius=6

radarBG=Drawing.new("Circle"); radarBG.Visible=false; radarBG.Filled=true
radarBG.Color=Color3.fromRGB(10,10,10); radarBG.Transparency=0.45; radarBG.NumSides=64; radarBG.Radius=RADAR_RADIUS
radarRing=Drawing.new("Circle"); radarRing.Visible=false; radarRing.Filled=false
radarRing.Color=Color3.fromRGB(80,80,80); radarRing.Thickness=1; radarRing.Transparency=1; radarRing.NumSides=64; radarRing.Radius=RADAR_RADIUS*0.5
radarBorder=Drawing.new("Circle"); radarBorder.Visible=false; radarBorder.Filled=false
radarBorder.Color=Color3.fromRGB(180,180,180); radarBorder.Thickness=1.5; radarBorder.Transparency=1; radarBorder.NumSides=64; radarBorder.Radius=RADAR_RADIUS
radarSelf=Drawing.new("Circle"); radarSelf.Visible=false; radarSelf.Filled=true
radarSelf.Color=Color3.fromRGB(0,255,120); radarSelf.Transparency=1; radarSelf.NumSides=8; radarSelf.Radius=4

local wmText=Drawing.new("Text"); wmText.Visible=false
wmText.Color=Color3.fromRGB(255,255,255); wmText.OutlineColor=Color3.new(0,0,0)
wmText.Outline=true; wmText.Size=15; wmText.Font=2; wmText.Center=false
wmText.Position=Vector2.new(8,8); wmText.Text="Ghost v3"

local predDot=Drawing.new("Circle"); predDot.Visible=false; predDot.Filled=true
predDot.NumSides=12; predDot.Radius=5; predDot.Color=Color3.fromRGB(255,60,0); predDot.Transparency=1

log("Drawing objects initialised ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TARGET LOCK SYSTEM                                           ║
-- ║  Press KB.lockTarget to select; KB.clearTarget to release.   ║
-- ║  Checks: team, LOS, alive, forcefield — all optional toggles  ║
-- ╚══════════════════════════════════════════════════════════════╝
local function hasLOS(from, to, targetChar)
    local dir=to-from
    _losParams.FilterDescendantsInstances={LP.Character or workspace, targetChar}
    return workspace:Raycast(from,dir.Unit*dir.Magnitude,_losParams)==nil
end

local function playerPassesChecks(player, char, part)
    if not player or not char or not part then return false end
    local hum=char:FindFirstChildOfClass("Humanoid")
    -- Alive check
    if F.targetAliveCheck and (not hum or hum.Health<=0) then return false end
    -- Team check
    if F.targetTeamCheck and player.Team and LP.Team and player.Team==LP.Team then return false end
    -- Forcefield check
    if F.targetForceCheck and char:FindFirstChildOfClass("ForceField") then return false end
    -- LOS check
    if F.targetLOSCheck then
        local myChar=LP.Character; local myRoot=myChar and myChar:FindFirstChild("HumanoidRootPart")
        if myRoot and not hasLOS(myRoot.Position,part.Position,char) then return false end
    end
    return true
end

local function selectTarget()
    local myChar=LP.Character; if not myChar then return end
    local myRoot=myChar:FindFirstChild("HumanoidRootPart"); if not myRoot then return end
    local best=nil; local bestPlayer=nil; local bestScore=math.huge
    local vp=Camera.ViewportSize
    local center=Vector2.new(vp.X*0.5,vp.Y*0.5)
    local mousePos=UserInputService:GetMouseLocation()

    for _,player in ipairs(Players:GetPlayers()) do
        if player==LP then continue end
        local char=player.Character; if not char then continue end
        local part=char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        if not part then continue end
        if not playerPassesChecks(player,char,part) then continue end

        local vp3=Camera:WorldToViewportPoint(part.Position)
        if vp3.Z<=0 then continue end

        local score
        if targetSelectMode=="Closest to Mouse" then
            -- Distance from cursor to target screen position
            score=(Vector2.new(vp3.X,vp3.Y)-mousePos).Magnitude
        else
            -- Distance from my HRP to target in 3D world
            score=(part.Position-myRoot.Position).Magnitude
        end

        if score<bestScore then bestScore=score; best=part; bestPlayer=player end
    end

    if best then
        lockedTarget=best; lockedPlayer=bestPlayer
        log("Target locked: "..bestPlayer.Name)
        Rayfield:Notify({Title="Target Locked",Content=bestPlayer.Name,Duration=2})
    else
        Rayfield:Notify({Title="Target",Content="No valid target found",Duration=2})
    end
end

local function clearTarget()
    lockedTarget=nil; lockedPlayer=nil
    targetDot.Visible=false
    log("Target cleared")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ESP HELPERS                                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
local function espColorFor(player)
    if player.Team and player.TeamColor then return player.TeamColor.Color end
    return espLineColor
end

local function ensureDrawings(player)
    if not espTracerLines[player] then espTracerLines[player]=newLine(espColorFor(player),espLineThick) end
    if not nametagTexts[player]   then nametagTexts[player]=newText(Color3.fromRGB(255,255,255),14) end
    if not hpBGLines[player]      then hpBGLines[player]=newLine(Color3.fromRGB(15,15,15),4); hpFillLines[player]=newLine(Color3.fromRGB(0,210,80),3) end
    if not boxLineGroups[player]  then boxLineGroups[player]={}; for i=1,4 do boxLineGroups[player][i]=newLine(espColorFor(player),1.5) end end
    if not skelLineGroups[player] then skelLineGroups[player]={}; for i=1,14 do skelLineGroups[player][i]=newLine(espColorFor(player),1) end end
end

local function hideDrawings(player)
    if espTracerLines[player] then espTracerLines[player].Visible=false end
    if nametagTexts[player]   then nametagTexts[player].Visible=false end
    if hpBGLines[player]      then hpBGLines[player].Visible=false end
    if hpFillLines[player]    then hpFillLines[player].Visible=false end
    if boxLineGroups[player]  then for _,l in ipairs(boxLineGroups[player])  do l.Visible=false end end
    if skelLineGroups[player] then for _,l in ipairs(skelLineGroups[player]) do l.Visible=false end end
end

local function destroyDrawings(player)
    local function rd(tbl,p)
        if not tbl[p] then return end
        if type(tbl[p])=="table" then for _,l in ipairs(tbl[p]) do pcall(function() l:Remove() end) end
        else pcall(function() tbl[p]:Remove() end) end; tbl[p]=nil
    end
    rd(espTracerLines,player); rd(nametagTexts,player)
    rd(hpBGLines,player);      rd(hpFillLines,player)
    rd(boxLineGroups,player);  rd(skelLineGroups,player)
end

local function clearAllESP()
    for _,hl in pairs(espHighlightObjs) do pcall(function() hl:Destroy() end) end
    espHighlightObjs={}
    local all={}
    for p in pairs(espTracerLines) do all[p]=true end
    for p in pairs(nametagTexts)   do all[p]=true end
    for p in pairs(hpBGLines)      do all[p]=true end
    for p in pairs(boxLineGroups)  do all[p]=true end
    for p in pairs(skelLineGroups) do all[p]=true end
    for p in pairs(all) do destroyDrawings(p) end
end

local function applyESPToPlayer(player)
    if player==LP then return end
    local char=player.Character; if not char then return end
    local oldHL=espHighlightObjs[player]
    if oldHL and oldHL.Parent then oldHL:Destroy(); espHighlightObjs[player]=nil end
    if F.espHighlights then
        local col=espColorFor(player)
        local hl=Instance.new("Highlight")
        hl.Adornee=char; hl.FillColor=col; hl.OutlineColor=col
        hl.FillTransparency=0.65; hl.OutlineTransparency=0
        hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent=char
        espHighlightObjs[player]=hl
    end
    ensureDrawings(player)
end

local function activateESP()
    clearAllESP()
    for _,p in ipairs(Players:GetPlayers()) do applyESPToPlayer(p) end
    espActive=true; log("ESP on ✓")
end

-- ESP per-element helpers (split to avoid 200-local limit)
local function _espTracer(player,origin,rootVP,col)
    local tl=espTracerLines[player]; if not tl then return end
    if F.espTracers and rootVP.Z>0 then
        tl.From=origin; tl.To=Vector2.new(rootVP.X,rootVP.Y)
        tl.Color=col; tl.Thickness=espLineThick; tl.Visible=true
    else tl.Visible=false end
end
local function _espNametag(player,root,head,rootVP)
    local nt=nametagTexts[player]; if not nt then return end
    if F.espNametags and head and rootVP.Z>0 then
        local tagVP=Camera:WorldToViewportPoint(head.Position+Vector3.new(0,2.4,0))
        if tagVP.Z>0 then
            local dist=math.floor((root.Position-Camera.CFrame.Position).Magnitude)
            nt.Position=Vector2.new(tagVP.X,tagVP.Y); nt.Color=Color3.fromRGB(255,255,255)
            nt.Text=player.Name.."  ["..dist.."m]"; nt.Visible=true
        else nt.Visible=false end
    else nt.Visible=false end
end
local function _espHealthBar(player,root,head,hum,rootVP)
    local bg=hpBGLines[player]; local fil=hpFillLines[player]
    if not bg or not fil then return end
    if F.espHealthBars and hum and rootVP.Z>0 then
        local headPos=head and head.Position or root.Position+Vector3.new(0,3,0)
        local hVP=Camera:WorldToViewportPoint(headPos)
        local fVP=Camera:WorldToViewportPoint(root.Position-Vector3.new(0,3,0))
        if hVP.Z>0 and fVP.Z>0 then
            local y1=math.min(hVP.Y,fVP.Y); local y2=math.max(hVP.Y,fVP.Y)
            local bx=rootVP.X-((y2-y1)*0.5+6)
            local pct=math.clamp(hum.Health/math.max(hum.MaxHealth,1),0,1)
            bg.From=Vector2.new(bx,y1); bg.To=Vector2.new(bx,y2); bg.Visible=true
            fil.From=Vector2.new(bx,y2); fil.To=Vector2.new(bx,y2-(y2-y1)*pct)
            fil.Color=Color3.fromRGB(math.floor(255*(1-pct)),math.floor(210*pct),30); fil.Visible=true
        else bg.Visible=false; fil.Visible=false end
    else bg.Visible=false; fil.Visible=false end
end
local function _espBox(player,root,head,col,rootVP)
    local box=boxLineGroups[player]; if not box then return end
    if F.espBoxes and head and rootVP.Z>0 then
        local topVP=Camera:WorldToViewportPoint(head.Position+Vector3.new(0,0.7,0))
        local botVP=Camera:WorldToViewportPoint(root.Position-Vector3.new(0,3,0))
        if topVP.Z>0 and botVP.Z>0 then
            local y1=math.min(topVP.Y,botVP.Y); local y2=math.max(topVP.Y,botVP.Y)
            local cx=(topVP.X+botVP.X)*0.5; local W=math.max((y2-y1)*0.45,8)
            local x1,x2=cx-W,cx+W
            box[1].From=Vector2.new(x1,y1);box[1].To=Vector2.new(x2,y1);box[1].Color=col;box[1].Visible=true
            box[2].From=Vector2.new(x1,y2);box[2].To=Vector2.new(x2,y2);box[2].Color=col;box[2].Visible=true
            box[3].From=Vector2.new(x1,y1);box[3].To=Vector2.new(x1,y2);box[3].Color=col;box[3].Visible=true
            box[4].From=Vector2.new(x2,y1);box[4].To=Vector2.new(x2,y2);box[4].Color=col;box[4].Visible=true
        else for _,l in ipairs(box) do l.Visible=false end end
    else for _,l in ipairs(box) do l.Visible=false end end
end
local function _espSkeleton(player,char,col,rootVP)
    local skel=skelLineGroups[player]; if not skel then return end
    if F.espSkeleton and char and rootVP.Z>0 then
        local joints=char:FindFirstChild("Torso") and SKEL_R6 or SKEL_R15
        for i,pair in ipairs(joints) do
            local line=skel[i]; local pA=char:FindFirstChild(pair[1]); local pB=char:FindFirstChild(pair[2])
            if pA and pB and line then
                local aVP=Camera:WorldToViewportPoint(pA.Position); local bVP=Camera:WorldToViewportPoint(pB.Position)
                if aVP.Z>0 and bVP.Z>0 then
                    line.From=Vector2.new(aVP.X,aVP.Y); line.To=Vector2.new(bVP.X,bVP.Y)
                    line.Color=col; line.Visible=true
                else line.Visible=false end
            elseif line then line.Visible=false end
        end
        for i=#(char:FindFirstChild("Torso") and SKEL_R6 or SKEL_R15)+1,#skel do
            if skel[i] then skel[i].Visible=false end
        end
    else for _,l in ipairs(skel) do l.Visible=false end end
end

local function updateESPDrawings()
    local vp=Camera.ViewportSize; local origin=Vector2.new(vp.X*0.5,vp.Y)
    for player in pairs(espTracerLines) do
        local char=player.Character; local root=char and char:FindFirstChild("HumanoidRootPart")
        if not root then hideDrawings(player) else
            local head=char:FindFirstChild("Head"); local hum=char:FindFirstChildOfClass("Humanoid")
            local col=espColorFor(player); local rootVP=Camera:WorldToViewportPoint(root.Position)
            _espTracer(player,origin,rootVP,col); _espNametag(player,root,head,rootVP)
            _espHealthBar(player,root,head,hum,rootVP); _espBox(player,root,head,col,rootVP)
            _espSkeleton(player,char,col,rootVP)
        end
    end
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  RADAR                                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
local function updateRadar()
    local vp=Camera.ViewportSize
    local cx=vp.X-RADAR_RADIUS-RADAR_X; local cy=vp.Y-RADAR_RADIUS-RADAR_Y
    radarBG.Position=Vector2.new(cx,cy); radarBG.Visible=true
    radarRing.Position=Vector2.new(cx,cy); radarRing.Visible=true
    radarBorder.Position=Vector2.new(cx,cy); radarBorder.Visible=true
    radarSelf.Position=Vector2.new(cx,cy); radarSelf.Visible=true
    local myChar=LP.Character; local myRoot=myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end
    local camYaw=math.atan2(-Camera.CFrame.LookVector.X,-Camera.CFrame.LookVector.Z)
    for _,player in ipairs(Players:GetPlayers()) do
        if player==LP then continue end
        if not radarDots[player] then
            local d=Drawing.new("Circle"); d.Filled=true; d.NumSides=8; d.Radius=4
            d.Transparency=1; d.Visible=false; radarDots[player]=d
        end
        if not radarLabels[player] then
            local l=Drawing.new("Text"); l.Size=11; l.Font=2; l.Center=true
            l.Outline=true; l.OutlineColor=Color3.new(0,0,0); l.Visible=false; radarLabels[player]=l
        end
        local dot=radarDots[player]; local lbl=radarLabels[player]
        local pRoot=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not pRoot then dot.Visible=false; lbl.Visible=false; continue end
        local delta=pRoot.Position-myRoot.Position
        local dx,dz=delta.X,delta.Z
        local rx=dx*math.cos(camYaw)+dz*math.sin(camYaw)
        local ry=-dx*math.sin(camYaw)+dz*math.cos(camYaw)
        local scale=RADAR_RADIUS/RADAR_RANGE
        local sx,sy=rx*scale,ry*scale
        local len=math.sqrt(sx*sx+sy*sy)
        if len>RADAR_RADIUS-5 then local f=(RADAR_RADIUS-5)/len; sx,sy=sx*f,sy*f end
        local dotPos=Vector2.new(cx+sx,cy+sy)
        local col=espColorFor(player)
        -- Highlight locked target in yellow
        if player==lockedPlayer then dot.Color=Color3.fromRGB(255,255,0); dot.Radius=6
        else dot.Color=col; dot.Radius=4 end
        dot.Position=dotPos; dot.Visible=true
        lbl.Position=Vector2.new(dotPos.X,dotPos.Y-12); lbl.Text=player.Name; lbl.Color=col; lbl.Visible=true
    end
    for player,dot in pairs(radarDots) do
        if not player.Parent then dot.Visible=false
            if radarLabels[player] then radarLabels[player].Visible=false end
        end
    end
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  RENDERSTEP                                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
RunService.RenderStepped:Connect(function(dt)
    if espActive then updateESPDrawings() end

    if F.radar then updateRadar()
    else
        radarBG.Visible=false; radarRing.Visible=false; radarBorder.Visible=false; radarSelf.Visible=false
        for _,d in pairs(radarDots) do d.Visible=false end
        for _,l in pairs(radarLabels) do l.Visible=false end
    end

    -- FOV circle
    if F.targetLocked and lockedTarget then
        fovCircle.Visible=false  -- replace with target dot when locked
    elseif lockedTarget==nil then
        if F.aimlockFOVShow then
            local vp=Camera.ViewportSize
            fovCircle.Position=Vector2.new(vp.X*0.5,vp.Y*0.5)
            fovCircle.Radius=aimlockFOV; fovCircle.Visible=true
        else fovCircle.Visible=false end
    end

    -- Target dot on screen
    if lockedTarget and lockedTarget.Parent then
        local vp3=Camera:WorldToViewportPoint(lockedTarget.Position)
        if vp3.Z>0 then
            targetDot.Position=Vector2.new(vp3.X,vp3.Y); targetDot.Visible=true
        else targetDot.Visible=false end
    else targetDot.Visible=false end

    -- Camera aimlock (runs when key held or always-on)
    if F.camAimlock and lockedTarget and lockedTarget.Parent then
        local tgtPos=lockedTarget.Position
        if F.prediction then
            local rb=lockedTarget.Parent:FindFirstChildOfClass("BasePart")
            if rb then tgtPos=tgtPos+rb.AssemblyLinearVelocity*predScale end
        end
        local cur=Camera.CFrame
        Camera.CFrame=cur:Lerp(CFrame.new(cur.Position,tgtPos),camSmooth)
    end

    -- Bullet prediction dot
    if F.bulletPred and lockedTarget and lockedTarget.Parent then
        local rb=lockedTarget.Parent:FindFirstChildOfClass("BasePart")
        local vel=rb and rb.AssemblyLinearVelocity or Vector3.zero
        local aimPos=lockedTarget.Position+vel*predScale
        local vp3=Camera:WorldToViewportPoint(aimPos)
        if vp3.Z>0 then predDot.Position=Vector2.new(vp3.X,vp3.Y); predDot.Visible=true
        else predDot.Visible=false end
    elseif predDot then predDot.Visible=false end

    -- Watermark
    if F.watermark then
        _wmTimer+=dt
        if _wmTimer>=0.5 then
            _wmTimer=0; _wmFPS=math.round(1/math.max(dt,0.001))
            pcall(function()
                _wmPing=tonumber(tostring(
                    game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValueString()
                ):match("%d+")) or 0
            end)
        end
        local tname=lockedPlayer and (" | TGT: "..lockedPlayer.Name) or ""
        wmText.Text=string.format("Ghost v3  |  %dfps  |  %dms  |  %s%s",_wmFPS,_wmPing,os.date("%H:%M:%S"),tname)
        wmText.Visible=true
    else wmText.Visible=false end

    -- Silent aim
    if F.silentAim then silentTarget=lockedTarget
    else silentTarget=nil end
end)

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  MOUSE AIMLOCK  (WorldToScreenPoint = correct coords)         ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setMouseAimlock(on)
    F.mouseAimlock=on
    if mouseAimlockConn then mouseAimlockConn:Disconnect(); mouseAimlockConn=nil end
    if not on then return end
    mouseAimlockConn=RunService.RenderStepped:Connect(function()
        if not F.mouseAimlock then return end
        if F.mouseRMBHold and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
        if not lockedTarget or not lockedTarget.Parent then return end
        local char=lockedTarget.Parent
        -- Team check
        if F.mouseTeamCheck then
            for _,p in ipairs(Players:GetPlayers()) do
                if p.Character and lockedTarget:IsDescendantOf(p.Character) then
                    if p.Team and LP.Team and p.Team==LP.Team then return end; break
                end
            end
        end
        -- Wall check
        if F.mouseWallCheck then
            local myChar=LP.Character; local myRoot=myChar and myChar:FindFirstChild("HumanoidRootPart")
            if myRoot and not hasLOS(myRoot.Position,lockedTarget.Position,char) then return end
        end
        local aimPart=char:FindFirstChild(mouseAimPart) or lockedTarget
        local aimPos=aimPart.Position
        if F.prediction then
            local rb=char:FindFirstChildOfClass("BasePart")
            if rb then aimPos=aimPos+rb.AssemblyLinearVelocity*predScale end
        end
        local sp=Camera:WorldToScreenPoint(aimPos)
        if sp.Z<=0 then return end
        local mouse=LP:GetMouse()
        local delta=Vector2.new(sp.X,sp.Y)-Vector2.new(mouse.X,mouse.Y)
        if F.mouseJitter then
            delta=delta+Vector2.new((math.random()-0.5)*2*mouseJitterAmt,(math.random()-0.5)*2*mouseJitterAmt)
        end
        if delta.Magnitude<mouseDeadzone then return end
        local smooth=math.clamp(mouseSmooth,0.01,1)
        pcall(function() mousemoverel(delta.X*smooth,delta.Y*smooth) end)
    end)
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  SILENT AIM                                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
local function hookGunHandler()
    local ok2,GunHandler=pcall(function() return require(ReplicatedStorage.Modules.GunHandler) end)
    if not ok2 or not GunHandler then return false end
    local OriginalGetAim=GunHandler.getAim
    GunHandler.getAim=function(origin,range)
        if not F.silentAim then return OriginalGetAim(origin,range) end
        -- Use locked target if available, otherwise find nearest to mouse
        local Target=silentTarget
        if not Target then
            local Distance=math.huge
            for _,Player in pairs(Players:GetPlayers()) do
                if Player==LP or not Player.Character or not Player.Character:FindFirstChild("Head") then continue end
                local Position=Camera:WorldToViewportPoint(Player.Character.Head.Position)
                local Magnitude=(Vector2.new(Position.X,Position.Y)-UserInputService:GetMouseLocation()).Magnitude
                if Magnitude<=Distance and Magnitude<=1000 then Distance=Magnitude; Target=Player.Character.Head end
            end
        end
        if Target then
            local dir=(Target.Position-origin)
            return dir.Unit,math.min(dir.Magnitude,range)
        end
        return OriginalGetAim(origin,range)
    end
    log("GunHandler hooked ✓"); return true
end

local function hookTools(char)
    for _,tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and not tool:GetAttribute("_SAHooked") then
            tool:SetAttribute("_SAHooked",true)
            tool.Activated:Connect(function()
                if not F.silentAim or not silentTarget or not silentTarget.Parent then return end
                local orig=Camera.CFrame
                Camera.CFrame=CFrame.new(orig.Position,silentTarget.Position)
                task.defer(function() Camera.CFrame=orig end)
            end)
        end
    end
end
task.spawn(function()
    if not hookGunHandler() then log("GunHandler not found — camera-flip fallback") end
end)
LP.CharacterAdded:Connect(function(char)
    task.wait(0.5); hookTools(char)
    char.ChildAdded:Connect(function(c) if c:IsA("Tool") then task.wait(0.1); hookTools(char) end end)
end)
if LP.Character then
    task.spawn(function() task.wait(0.3); hookTools(LP.Character) end)
    LP.Character.ChildAdded:Connect(function(c)
        if c:IsA("Tool") then task.wait(0.1); hookTools(LP.Character) end
    end)
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  FLY  (two modes: Velocity and CFrame)                       ║
-- ╚══════════════════════════════════════════════════════════════╝
local function stopFly()
    if flyBV then flyBV:Destroy(); flyBV=nil end
    if flyBG then flyBG:Destroy(); flyBG=nil end
    if flyConn then flyConn:Disconnect(); flyConn=nil end
    local char=LP.Character
    if char then local h=char:FindFirstChildOfClass("Humanoid"); if h then h.PlatformStand=false end end
end

local function startFly()
    local char=LP.Character; if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart"); local hum=char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    if flyMode=="Velocity" then
        -- BodyVelocity method: smooth physics-based flight
        hum.PlatformStand=true
        flyBV=Instance.new("BodyVelocity"); flyBV.Velocity=Vector3.zero
        flyBV.MaxForce=Vector3.new(1e5,1e5,1e5); flyBV.Parent=hrp
        flyBG=Instance.new("BodyGyro"); flyBG.MaxTorque=Vector3.new(1e5,1e5,1e5)
        flyBG.D=100; flyBG.Parent=hrp
        flyConn=RunService.Heartbeat:Connect(function()
            if not flyBV or not flyBV.Parent then return end
            local d=Vector3.zero; local cf=Camera.CFrame
            if UserInputService:IsKeyDown(Enum.KeyCode.W)         then d+=cf.LookVector      end
            if UserInputService:IsKeyDown(Enum.KeyCode.S)         then d-=cf.LookVector      end
            if UserInputService:IsKeyDown(Enum.KeyCode.A)         then d-=cf.RightVector     end
            if UserInputService:IsKeyDown(Enum.KeyCode.D)         then d+=cf.RightVector     end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then d+=Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then d-=Vector3.new(0,1,0) end
            flyBV.Velocity=(d.Magnitude>0 and d.Unit or Vector3.zero)*flySpeed
            flyBG.CFrame=cf
        end)
    else
        -- CFrame method: direct teleport each frame (no collision)
        hum.PlatformStand=true
        flyConn=RunService.RenderStepped:Connect(function(dt)
            if not hrp then return end
            local d=Vector3.zero; local cf=Camera.CFrame
            if UserInputService:IsKeyDown(Enum.KeyCode.W)         then d+=cf.LookVector      end
            if UserInputService:IsKeyDown(Enum.KeyCode.S)         then d-=cf.LookVector      end
            if UserInputService:IsKeyDown(Enum.KeyCode.A)         then d-=cf.RightVector     end
            if UserInputService:IsKeyDown(Enum.KeyCode.D)         then d+=cf.RightVector     end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then d+=Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then d-=Vector3.new(0,1,0) end
            if d.Magnitude>0 then
                hrp.CFrame=hrp.CFrame+d.Unit*flySpeed*dt
            end
        end)
    end
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  MOVEMENT                                                     ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setSpeedHack(on)
    F.speedHack=on
    if speedConn then speedConn:Disconnect(); speedConn=nil end
    if not on then
        local char=LP.Character
        if char then local hum=char:FindFirstChildOfClass("Humanoid"); if hum then hum.WalkSpeed=BASE_SPEED end end; return
    end
    speedConn=RunService.Stepped:Connect(function()
        if not F.speedHack then return end
        local char=LP.Character; if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        hum.WalkSpeed=BASE_SPEED*speedMult
    end)
end

local function setInfJump(on)
    F.infJump=on
    if infJumpConn then infJumpConn:Disconnect(); infJumpConn=nil end
    if not on then return end
    infJumpConn=UserInputService.JumpRequest:Connect(function()
        local char=LP.Character; if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
end

local function setNoclip(on)
    F.noclip=on
    if noclipConn then noclipConn:Disconnect(); noclipConn=nil end
    if not on then
        local char=LP.Character
        if char then for _,p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and NOCLIP_PARTS[p.Name] then p.CanCollide=true end
        end end; return
    end
    noclipConn=RunService.Stepped:Connect(function()
        local char=LP.Character; if not char then return end
        for _,p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and NOCLIP_PARTS[p.Name] then p.CanCollide=false end
        end
    end)
end

local function setBhop(on)
    F.bhop=on
    if bhopConn then bhopConn:Disconnect(); bhopConn=nil end
    if not on then return end
    local function hookChar(char)
        local hum=char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        if bhopConn then bhopConn:Disconnect() end
        bhopConn=hum.StateChanged:Connect(function(_,new)
            if new==Enum.HumanoidStateType.Landed and F.bhop then
                task.wait(); hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end
    if LP.Character then hookChar(LP.Character) end
    LP.CharacterAdded:Connect(function(c) task.wait(0.1); hookChar(c) end)
end

local function setLowGravity(on)
    F.lowGrav=on
    if gravConn then gravConn:Disconnect(); gravConn=nil end
    if not on then workspace.Gravity=origGravity; return end
    gravConn=RunService.Heartbeat:Connect(function() if F.lowGrav then workspace.Gravity=gravScale end end)
end

local function setSwimSpeed(on)
    F.swimSpeed=on
    if swimConn then swimConn:Disconnect(); swimConn=nil end
    if not on then
        local char=LP.Character
        if char then local hum=char:FindFirstChildOfClass("Humanoid"); if hum then hum.WalkSpeed=BASE_SPEED end end; return
    end
    swimConn=RunService.Stepped:Connect(function()
        if not F.swimSpeed then return end
        local char=LP.Character; if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        pcall(function() hum.WalkSpeed=BASE_SPEED*swimMult end)
    end)
end

local function setAutoCollect(on)
    F.autoCollect=on
    if autoCollectConn then autoCollectConn:Disconnect(); autoCollectConn=nil end
    if not on then return end
    local timer=0
    autoCollectConn=RunService.Heartbeat:Connect(function(dt)
        if not F.autoCollect then return end
        timer+=dt; if timer<collectInterval then return end; timer=0
        local char=LP.Character; if not char then return end
        for _,obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Tool") then pcall(function() obj.Parent=char end) end
        end
    end)
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  RAPID FIRE                                                   ║
-- ║  Activates tool on LMB hold, repeating at config.delay rate  ║
-- ╚══════════════════════════════════════════════════════════════╝
getgenv().ghostRapidConfig = {enable=false, delay=0.01}

local function getGun()
    local char=LP.Character; if not char then return nil end
    for _,tool in next,char:GetChildren() do
        if tool:IsA("Tool") and tool:FindFirstChild("Ammo") then return tool end
    end
    -- Fallback: any equipped tool
    for _,tool in next,char:GetChildren() do
        if tool:IsA("Tool") then return tool end
    end
    return nil
end

UserInputService.InputBegan:Connect(function(i,proc)
    if proc then return end
    if i.UserInputType==Enum.UserInputType.MouseButton1 then
        local gun=getGun()
        if getgenv().ghostRapidConfig.enable and gun and not isFiring then
            isFiring=true
            task.spawn(function()
                while isFiring and getgenv().ghostRapidConfig.enable do
                    pcall(function() gun:Activate() end)
                    task.wait(getgenv().ghostRapidConfig.delay)
                end
            end)
        end
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 then isFiring=false end
end)

local function setRapidFire(on)
    F.rapidFire=on
    getgenv().ghostRapidConfig.enable=on
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  COMBAT FEATURES                                              ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setTriggerbot(on)
    F.triggerbot=on
    if tbConn then tbConn:Disconnect(); tbConn=nil end
    if not on then return end
    tbConn=RunService.Heartbeat:Connect(function()
        if not F.triggerbot or tbCooldown then return end
        local mouse=LP:GetMouse(); local target=mouse.Target; if not target then return end
        for _,player in ipairs(Players:GetPlayers()) do
            if player==LP then continue end
            local char=player.Character
            if char and target:IsDescendantOf(char) then
                local hum=char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health>0 then
                    tbCooldown=true
                    pcall(function()
                        local vim=game:GetService("VirtualInputManager")
                        vim:SendMouseButtonEvent(0,0,0,true,game,1)
                        vim:SendMouseButtonEvent(0,0,0,false,game,1)
                    end)
                    task.delay(triggerDelay,function() tbCooldown=false end); break
                end
            end
        end
    end)
end

local function setAntiAim(on)
    F.antiAim=on
    if antiAimConn then antiAimConn:Disconnect(); antiAimConn=nil end
    if not on then antiAimAngle=0; return end
    antiAimConn=RunService.Heartbeat:Connect(function()
        if not F.antiAim then return end
        local char=LP.Character; if not char then return end
        local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        if antiAimMode=="Spin" then
            antiAimAngle=(antiAimAngle+antiAimSpeed)%360
            hrp.CFrame=CFrame.new(hrp.Position)*CFrame.Angles(0,math.rad(antiAimAngle),0)
        else
            local flip=(math.floor(tick()*30)%2==0) and 0 or math.pi
            hrp.CFrame=CFrame.new(hrp.Position)*CFrame.fromEulerAnglesYXZ(0,flip,0)
        end
    end)
end

local function setKillAura(on)
    F.killAura=on
    if killAuraConn then killAuraConn:Disconnect(); killAuraConn=nil end
    if not on then return end
    local kaClock=0
    killAuraConn=RunService.Heartbeat:Connect(function(dt)
        if not F.killAura then return end
        kaClock-=dt; if kaClock>0 then return end; kaClock=killAuraRate
        local myRoot=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"); if not myRoot then return end
        for _,player in ipairs(Players:GetPlayers()) do
            if player==LP then continue end
            if F.targetTeamCheck and player.Team==LP.Team then continue end
            local char=player.Character; if not char then continue end
            local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
            if (hrp.Position-myRoot.Position).Magnitude>killAuraRange then continue end
            local hum=char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health<=0 then continue end
            pcall(function() hum.Health=hum.Health-killAuraDmg end)
        end
    end)
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  CSYNC  (fixed: saves origin, tps back on disable)           ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setCSync(on)
    F.csync=on
    if csyncConn then csyncConn:Disconnect(); csyncConn=nil end
    if not on then
        -- Teleport back to where we were before csync
        local char=LP.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
        if hrp and csyncOrigin then hrp.CFrame=csyncOrigin; log("CSync: returned to origin") end
        csyncOrigin=nil; return
    end
    -- Save current position
    local char=LP.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    csyncOrigin=hrp.CFrame
    csyncAngle=0
    csyncConn=RunService.Heartbeat:Connect(function(dt)
        if not F.csync then return end
        local c=LP.Character; local h=c and c:FindFirstChild("HumanoidRootPart"); if not h then return end
        csyncAngle=(csyncAngle+csyncSpeed*dt*60)%(math.pi*2)
        h.CFrame=CFrame.new(math.cos(csyncAngle)*csyncRadius,0,math.sin(csyncAngle)*csyncRadius)
    end)
    log("CSync on ✓")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  RAGEBOT                                                      ║
-- ╚══════════════════════════════════════════════════════════════╝
stopRagebot=function()
    if ragebotConn then ragebotConn:Disconnect(); ragebotConn=nil end
    ragebotActive=false
    if ragebotFlyBV and ragebotFlyBV.Parent then ragebotFlyBV:Destroy() end
    if ragebotFlyBG and ragebotFlyBG.Parent then ragebotFlyBG:Destroy() end
    ragebotFlyBV=nil; ragebotFlyBG=nil
    local char=LP.Character; local hum=char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed=BASE_SPEED; hum.PlatformStand=false end
    local hrp=char and char:FindFirstChild("HumanoidRootPart")
    if hrp and ragebotOrigin then hrp.CFrame=ragebotOrigin; log("Ragebot: returned to origin") end
    ragebotOrigin=nil
    Rayfield:Notify({Title="Ragebot",Content="Stopped — returned to origin",Duration=2})
end

local function startRagebot(targetPlayer)
    if not targetPlayer then Rayfield:Notify({Title="Ragebot",Content="No target selected!",Duration=2}); return end
    local myChar=LP.Character; local myHRP=myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myHum=myChar and myChar:FindFirstChildOfClass("Humanoid")
    if not myHRP or not myHum then return end
    local tChar=targetPlayer.Character; local tHRP=tChar and tChar:FindFirstChild("HumanoidRootPart")
    if not tHRP then Rayfield:Notify({Title="Ragebot",Content="Target has no character!",Duration=2}); return end
    ragebotOrigin=myHRP.CFrame
    local startAngle=math.random()*math.pi*2
    myHRP.CFrame=CFrame.new(tHRP.Position.X+math.cos(startAngle)*ragebotRadius,tHRP.Position.Y,tHRP.Position.Z+math.sin(startAngle)*ragebotRadius)
    myHum.PlatformStand=true
    ragebotFlyBV=Instance.new("BodyVelocity"); ragebotFlyBV.Velocity=Vector3.zero
    ragebotFlyBV.MaxForce=Vector3.new(1e5,1e5,1e5); ragebotFlyBV.Parent=myHRP
    ragebotFlyBG=Instance.new("BodyGyro"); ragebotFlyBG.MaxTorque=Vector3.new(1e5,1e5,1e5)
    ragebotFlyBG.D=100; ragebotFlyBG.Parent=myHRP
    ragebotActive=true
    Rayfield:Notify({Title="Ragebot",Content="Started on "..targetPlayer.Name,Duration=2})
    local orbitAngle=startAngle; local orbitDir=(math.random(0,1)==0) and 1 or -1
    local dirClock=0; local tbClock=0
    ragebotConn=RunService.Heartbeat:Connect(function(dt)
        if not ragebotActive then stopRagebot(); return end
        local tC=targetPlayer.Character; local tH=tC and tC:FindFirstChild("HumanoidRootPart")
        local tHu=tC and tC:FindFirstChildOfClass("Humanoid")
        if not tH or not tHu or tHu.Health<=0 then return end
        local mC=LP.Character; local mH=mC and mC:FindFirstChild("HumanoidRootPart"); if not mH then return end
        local cur=Camera.CFrame
        Camera.CFrame=cur:Lerp(CFrame.new(cur.Position,tH.Position),ragebotSmooth)
        tbClock+=dt
        if tbClock>=ragebotTrigDelay then
            tbClock=0
            local vp3=Camera:WorldToViewportPoint(tH.Position)
            if vp3.Z>0 then
                local vp=Camera.ViewportSize
                if (Vector2.new(vp3.X,vp3.Y)-Vector2.new(vp.X*0.5,vp.Y*0.5)).Magnitude<ragebotFireThresh then
                    pcall(function()
                        local vim=game:GetService("VirtualInputManager")
                        vim:SendMouseButtonEvent(0,0,0,true,game,1); vim:SendMouseButtonEvent(0,0,0,false,game,1)
                    end)
                end
            end
        end
        dirClock+=dt
        if dirClock>=0.1+math.random()*0.3 then dirClock=0; orbitDir=(math.random(0,1)==0) and 1 or -1 end
        orbitAngle=orbitAngle+math.rad(ragebotOrbitSpd)*orbitDir*dt
        local tPos=tH.Position
        local desired=Vector3.new(tPos.X+math.cos(orbitAngle)*ragebotRadius,tPos.Y,tPos.Z+math.sin(orbitAngle)*ragebotRadius)
        if ragebotFlyBV and ragebotFlyBV.Parent then ragebotFlyBV.Velocity=(desired-mH.Position)*ragebotOrbitSpd*0.3 end
        if ragebotFlyBG and ragebotFlyBG.Parent then
            ragebotFlyBG.CFrame=CFrame.new(mH.Position,Vector3.new(tPos.X,mH.Position.Y,tPos.Z))
        end
    end)
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  MISC                                                         ║
-- ╚══════════════════════════════════════════════════════════════╝
local function setFullbright(on)
    F.fullbright=on
    if on then
        Lighting.Ambient=Color3.fromRGB(255,255,255); Lighting.OutdoorAmbient=Color3.fromRGB(255,255,255)
        Lighting.Brightness=2; Lighting.ClockTime=14
        for _,v in ipairs(Lighting:GetChildren()) do
            if v:IsA("Atmosphere") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") then v.Enabled=false end
        end
    else
        Lighting.Ambient=origAmbient; Lighting.OutdoorAmbient=origOutdoorAmbient
        Lighting.Brightness=origBrightness; Lighting.ClockTime=origClockTime
        for _,v in ipairs(Lighting:GetChildren()) do
            if v:IsA("Atmosphere") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") then v.Enabled=true end
        end
    end
end

local function setFakeLag(on)
    F.fakeLag=on
    if fakeLagConn then fakeLagConn:Disconnect(); fakeLagConn=nil end
    if not on then return end
    fakeLagConn=RunService.Heartbeat:Connect(function()
        if not F.fakeLag then return end
        local s=os.clock(); while os.clock()-s<fakeLagMS/1000 do end
    end)
end

local function setAntiAfk(on)
    F.antiAfk=on
    if antiAfkConn then antiAfkConn:Disconnect(); antiAfkConn=nil end
    if not on then return end
    local t=0
    antiAfkConn=RunService.Heartbeat:Connect(function(dt)
        t+=dt; if t<55 then return end; t=0
        pcall(function()
            local vim=game:GetService("VirtualInputManager")
            vim:SendKeyEvent(true,Enum.KeyCode.W,false,game); vim:SendKeyEvent(false,Enum.KeyCode.W,false,game)
        end)
    end)
end

local function setClickTp(on)
    F.clickTp=on
    if clickTpConn then clickTpConn:Disconnect(); clickTpConn=nil end
    if not on then return end
    clickTpConn=UserInputService.InputBegan:Connect(function(inp,proc)
        if proc then return end
        if inp.UserInputType==Enum.UserInputType.MouseButton1 and UserInputService:IsKeyDown(KB.clickTp) then
            local ray=Camera:ScreenPointToRay(inp.Position.X,inp.Position.Y)
            local res=workspace:Raycast(ray.Origin,ray.Direction*2000)
            if res then
                local hrp=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if hrp then hrp.CFrame=CFrame.new(res.Position+Vector3.new(0,4,0)) end
            end
        end
    end)
end

local function setInfZoom(on)
    F.infZoom=on
    if zoomConn then zoomConn:Disconnect(); zoomConn=nil end
    if not on then pcall(function() LP.CameraMaxZoomDistance=128; LP.CameraMinZoomDistance=0.5 end); return end
    local function az() pcall(function() LP.CameraMaxZoomDistance=math.huge; LP.CameraMinZoomDistance=0.5 end) end
    az(); zoomConn=RunService.Heartbeat:Connect(az)
end

local function setAutoRejoin(on)
    F.autoRejoin=on
    if autoRejoinConn then autoRejoinConn:Disconnect(); autoRejoinConn=nil end
    if not on then return end
    autoRejoinConn=LP.OnTeleport:Connect(function(state)
        if state==Enum.TeleportState.Failed then
            task.wait(2); pcall(function() TeleportService:Teleport(game.PlaceId,LP) end)
        end
    end)
end

local function stopSpectate()
    if spectateConn then spectateConn:Disconnect(); spectateConn=nil end
    if spectateOrigType then Camera.CameraType=spectateOrigType; spectateOrigType=nil end
    local char=LP.Character
    if char then Camera.CameraSubject=char:FindFirstChildOfClass("Humanoid") or char:FindFirstChild("HumanoidRootPart") end
    spectateTarget=nil
end

local function startSpectate(player)
    if spectateConn then stopSpectate() end
    if not player or not player.Parent then return end
    spectateTarget=player; spectateOrigType=Camera.CameraType; Camera.CameraType=Enum.CameraType.Follow
    spectateConn=RunService.RenderStepped:Connect(function()
        if not spectateTarget or not spectateTarget.Parent then stopSpectate(); return end
        local tChar=spectateTarget.Character; if not tChar then return end
        Camera.CameraSubject=tChar:FindFirstChildOfClass("Humanoid") or tChar:FindFirstChild("HumanoidRootPart")
    end)
    Rayfield:Notify({Title="Spectate",Content="Spectating "..player.Name,Duration=2})
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  PANIC                                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
local function doPanic()
    F.camAimlock=false; F.mouseAimlock=false; F.silentAim=false; F.triggerbot=false
    F.csync=false; setCSync(false); setAntiAim(false); setFakeLag(false); setSpeedHack(false)
    setRapidFire(false); setKillAura(false); stopRagebot()
    Camera.FieldOfView=origFOV; workspace.Gravity=origGravity
    espActive=false; clearAllESP(); stopFly(); flyActive=false; stopSpectate()
    setMouseAimlock(false); clearTarget()
    pcall(function()
        for _,gui in ipairs(game:GetService("CoreGui"):GetChildren()) do
            if gui.Name:find("Rayfield") then gui.Enabled=false end
        end
    end)
    log("PANIC — all off, UI hidden")
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  INPUT HANDLER                                                ║
-- ╚══════════════════════════════════════════════════════════════╝
local function resolveKC(v,fb)
    if type(v)=="string" and v~="" then return Enum.KeyCode[v] or fb
    elseif type(v)=="userdata" then return v end; return fb
end

UserInputService.InputBegan:Connect(function(inp,proc)
    if proc then return end
    local kc=inp.KeyCode

    if kc==KB.lockTarget  then selectTarget() end
    if kc==KB.clearTarget then clearTarget()  end
    if kc==KB.esp         then
        if not espActive then activateESP() else espActive=false; clearAllESP() end
    end
    if kc==KB.fly then
        if flyActive then flyActive=false; stopFly() else flyActive=true; startFly() end
    end
    if kc==KB.panic       then doPanic() end
    if kc==KB.ragebot     then
        if not ragebotActive then startRagebot(_rbTarget) else stopRagebot() end
    end
end)

-- Heartbeat: update cached values
RunService.Heartbeat:Connect(function(dt)
    local vp=Camera.ViewportSize
    _gtCenter=Vector2.new(vp.X*0.5,vp.Y*0.5)

    -- Validate locked target is still alive/valid
    if lockedTarget and lockedPlayer then
        if not lockedTarget.Parent or not lockedPlayer.Parent then
            clearTarget()
        elseif F.targetAliveCheck then
            local hum=lockedPlayer.Character and lockedPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health<=0 then clearTarget() end
        end
    end
end)

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  RESPAWN                                                      ║
-- ╚══════════════════════════════════════════════════════════════╝
Players.PlayerAdded:Connect(function(p) p.CharacterAdded:Connect(function() if espActive then task.defer(applyESPToPlayer,p) end end) end)
for _,p in ipairs(Players:GetPlayers()) do p.CharacterAdded:Connect(function() if espActive then task.defer(applyESPToPlayer,p) end end) end
LP.CharacterAdded:Connect(function()
    flyActive=false; flyBV=nil; flyBG=nil; flyConn=nil
    if ragebotActive then stopRagebot() end
    if F.csync then F.csync=false; csyncOrigin=nil end
    clearTarget()
    if espActive then task.defer(activateESP) end
    task.wait(0.1)
    if F.speedHack   then setSpeedHack(true)   end
    if F.infJump     then setInfJump(true)     end
    if F.noclip      then setNoclip(true)      end
    if F.bhop        then setBhop(true)        end
    if F.antiAfk     then setAntiAfk(true)     end
    if F.fullbright  then setFullbright(true)  end
    if F.antiAim     then setAntiAim(true)     end
    if F.lowGrav     then setLowGravity(true)  end
    if F.swimSpeed   then setSwimSpeed(true)   end
    if F.mouseAimlock then setMouseAimlock(true) end
end)

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  UI — AIMBOT TAB                                              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Helper
local function getOtherNames()
    local t={}; for _,p in ipairs(Players:GetPlayers()) do if p~=LP then table.insert(t,p.Name) end end
    if #t==0 then table.insert(t,"(no players)") end; return t
end

TabAimbot:CreateSection("Target Lock")
TabAimbot:CreateKeybind({Name="Lock Target Key",CurrentKeybind="C",HoldToInteract=false,Flag="KB_LockTarget",
    Callback=function(v) KB.lockTarget=resolveKC(v,KB.lockTarget) end})
TabAimbot:CreateKeybind({Name="Clear Target Key",CurrentKeybind="X",HoldToInteract=false,Flag="KB_ClearTarget",
    Callback=function(v) KB.clearTarget=resolveKC(v,KB.clearTarget) end})
TabAimbot:CreateDropdown({Name="Selection Mode",Options={"Closest to Mouse","Closest to Player"},
    CurrentOption="Closest to Mouse",Flag="TargetSelectMode",
    Callback=function(v) targetSelectMode=type(v)=="table" and v[1] or v end})
TabAimbot:CreateToggle({Name="Team Check",    CurrentValue=false,Flag="TgtTeam",   Callback=function(v) F.targetTeamCheck=v end})
TabAimbot:CreateToggle({Name="LOS / Wall Check",CurrentValue=false,Flag="TgtLOS",  Callback=function(v) F.targetLOSCheck=v end})
TabAimbot:CreateToggle({Name="Alive Check",   CurrentValue=true, Flag="TgtAlive",  Callback=function(v) F.targetAliveCheck=v end})
TabAimbot:CreateToggle({Name="Forcefield Check",CurrentValue=false,Flag="TgtFF",   Callback=function(v) F.targetForceCheck=v end})

TabAimbot:CreateSection("Camera Aimlock")
TabAimbot:CreateToggle({Name="Camera Aimlock (always-on)",CurrentValue=false,Flag="CamAimlock",
    Callback=function(v) F.camAimlock=v end})
TabAimbot:CreateSlider({Name="Camera Smooth %",Range={1,100},Increment=1,Suffix="%",CurrentValue=8,Flag="CamSmooth",
    Callback=function(v) camSmooth=v/100 end})
TabAimbot:CreateToggle({Name="Show FOV Circle",CurrentValue=false,Flag="FOVShow",
    Callback=function(v) F.aimlockFOVShow=v; if not v then fovCircle.Visible=false end end})
TabAimbot:CreateSlider({Name="FOV Radius",Range={20,400},Increment=5,Suffix="px",CurrentValue=120,Flag="AIMFOV",
    Callback=function(v) aimlockFOV=v; fovCircle.Radius=v end})

TabAimbot:CreateSection("Mouse Aimlock")
TabAimbot:CreateToggle({Name="Mouse Aimlock",CurrentValue=false,Flag="MouseAimlock",
    Callback=function(v) setMouseAimlock(v) end})
TabAimbot:CreateToggle({Name="RMB Hold",     CurrentValue=false,Flag="MouseRMB",    Callback=function(v) F.mouseRMBHold=v end})
TabAimbot:CreateToggle({Name="Wall Check",   CurrentValue=false,Flag="MouseWall",   Callback=function(v) F.mouseWallCheck=v end})
TabAimbot:CreateToggle({Name="Team Check",   CurrentValue=false,Flag="MouseTeam",   Callback=function(v) F.mouseTeamCheck=v end})
TabAimbot:CreateDropdown({Name="Aim At Part",
    Options={"Head","UpperTorso","Torso","HumanoidRootPart","LowerTorso"},
    CurrentOption="Head",Flag="MouseAimPart",
    Callback=function(v) mouseAimPart=type(v)=="table" and v[1] or v end})
TabAimbot:CreateSlider({Name="Smooth %",Range={1,100},Increment=1,Suffix="%",CurrentValue=25,Flag="MouseSmooth",
    Callback=function(v) mouseSmooth=v/100 end})
TabAimbot:CreateSlider({Name="Dead Zone (px)",Range={0,30},Increment=1,Suffix="px",CurrentValue=2,Flag="MouseDZ",
    Callback=function(v) mouseDeadzone=v end})
TabAimbot:CreateToggle({Name="Jitter",       CurrentValue=false,Flag="MouseJitter", Callback=function(v) F.mouseJitter=v end})
TabAimbot:CreateSlider({Name="Jitter Amount",Range={1,15},Increment=1,Suffix="px",CurrentValue=3,Flag="MouseJAmt",
    Callback=function(v) mouseJitterAmt=v end})

TabAimbot:CreateSection("Prediction")
TabAimbot:CreateToggle({Name="Bullet Prediction",   CurrentValue=false,Flag="Prediction",  Callback=function(v) F.prediction=v end})
TabAimbot:CreateToggle({Name="Show Prediction Dot", CurrentValue=false,Flag="BulletDot",   Callback=function(v) F.bulletPred=v; if not v then predDot.Visible=false end end})
TabAimbot:CreateSlider({Name="Lead Time x0.01s",    Range={1,30},Increment=1,CurrentValue=8,Flag="PredScale",
    Callback=function(v) predScale=v/100 end})

TabAimbot:CreateSection("Silent Aim")
TabAimbot:CreateToggle({Name="Silent Aim",CurrentValue=false,Flag="SilentAim",Callback=function(v) F.silentAim=v end})

log("Aimbot tab ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  UI — COMBAT TAB                                              ║
-- ╚══════════════════════════════════════════════════════════════╝
TabCombat:CreateSection("Triggerbot")
TabCombat:CreateToggle({Name="Triggerbot",CurrentValue=false,Flag="Triggerbot",Callback=function(v) setTriggerbot(v) end})
TabCombat:CreateSlider({Name="Delay",Range={0,500},Increment=10,Suffix="ms",CurrentValue=80,Flag="TrigDelay",
    Callback=function(v) triggerDelay=v/1000 end})

TabCombat:CreateSection("Rapid Fire")
TabCombat:CreateToggle({Name="Rapid Fire",CurrentValue=false,Flag="RapidFire",Callback=function(v) setRapidFire(v) end})
TabCombat:CreateSlider({Name="Fire Delay",Range={1,100},Increment=1,Suffix="x0.01s",CurrentValue=1,Flag="RapidDelay",
    Callback=function(v) rapidFireDelay=v/100; getgenv().ghostRapidConfig.delay=rapidFireDelay end})

TabCombat:CreateSection("Anti-Aim")
TabCombat:CreateToggle({Name="Anti-Aim",CurrentValue=false,Flag="AntiAim",Callback=function(v) setAntiAim(v) end})
TabCombat:CreateDropdown({Name="Mode",Options={"Spin","Jitter"},CurrentOption="Spin",Flag="AntiAimMode",
    Callback=function(v)
        antiAimMode=type(v)=="table" and v[1] or v
        if F.antiAim then setAntiAim(false); setAntiAim(true) end
    end})
TabCombat:CreateSlider({Name="Spin Speed",Range={5,60},Increment=1,Suffix=" d/f",CurrentValue=20,Flag="AntiAimSpd",
    Callback=function(v) antiAimSpeed=v end})

TabCombat:CreateSection("Kill Aura")
TabCombat:CreateToggle({Name="Kill Aura",CurrentValue=false,Flag="KillAura",Callback=function(v) setKillAura(v) end})
TabCombat:CreateSlider({Name="Range",Range={5,100},Increment=1,Suffix=" st",CurrentValue=20,Flag="KARange",
    Callback=function(v) killAuraRange=v end})
TabCombat:CreateSlider({Name="Damage/tick",Range={1,100},Increment=1,CurrentValue=10,Flag="KADmg",
    Callback=function(v) killAuraDmg=v end})
TabCombat:CreateSlider({Name="Rate x0.01s",Range={5,200},Increment=5,CurrentValue=10,Flag="KARate",
    Callback=function(v) killAuraRate=v/100 end})

TabCombat:CreateSection("CSync")
TabCombat:CreateToggle({Name="CSync (hitbox spinner)",CurrentValue=false,Flag="CSync",
    Callback=function(v) setCSync(v) end})
TabCombat:CreateSlider({Name="Orbit Radius",Range={1000,5000000},Increment=10000,CurrentValue=1000000,Flag="CSyncR",
    Callback=function(v) csyncRadius=v end})
TabCombat:CreateSlider({Name="Spin Speed",Range={1,50},Increment=1,CurrentValue=10,Flag="CSyncSpd",
    Callback=function(v) csyncSpeed=v end})

log("Combat tab ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  UI — RAGEBOT TAB                                             ║
-- ╚══════════════════════════════════════════════════════════════╝
TabRagebot:CreateSection("Target")
local _rbNames=getOtherNames()
local RbDrop=TabRagebot:CreateDropdown({Name="Target Player",Options=_rbNames,CurrentOption=_rbNames[1],Flag="RbTarget",
    Callback=function(v) local n=type(v)=="table" and v[1] or v; _rbTarget=Players:FindFirstChild(n) end})
Players.PlayerAdded:Connect(function() pcall(function() RbDrop:Set(getOtherNames()) end) end)
Players.PlayerRemoving:Connect(function(rem)
    if ragebotActive and _rbTarget==rem then stopRagebot() end
    pcall(function() RbDrop:Set(getOtherNames()) end)
end)
TabRagebot:CreateKeybind({Name="Ragebot Toggle Key",CurrentKeybind="Unknown",HoldToInteract=false,Flag="KB_Ragebot",
    Callback=function(v) KB.ragebot=resolveKC(v,KB.ragebot) end})
TabRagebot:CreateButton({Name="▶  Activate Ragebot",Callback=function()
    if ragebotActive then Rayfield:Notify({Title="Ragebot",Content="Already active!",Duration=2}); return end
    if not _rbTarget or not _rbTarget.Parent then
        Rayfield:Notify({Title="Ragebot",Content="Select a valid target first!",Duration=2}); return end
    startRagebot(_rbTarget)
end})
TabRagebot:CreateButton({Name="■  Stop Ragebot",Callback=stopRagebot})

TabRagebot:CreateSection("Config")
TabRagebot:CreateSlider({Name="Cam Smooth %",Range={1,50},Increment=1,Suffix="%",CurrentValue=20,Flag="RbSmooth",
    Callback=function(v) ragebotSmooth=v/100 end})
TabRagebot:CreateSlider({Name="Fire Threshold (px)",Range={10,300},Increment=5,Suffix="px",CurrentValue=80,Flag="RbFire",
    Callback=function(v) ragebotFireThresh=v end})
TabRagebot:CreateSlider({Name="Trigger Delay (ms)",Range={0,300},Increment=5,Suffix="ms",CurrentValue=50,Flag="RbTrig",
    Callback=function(v) ragebotTrigDelay=v/1000 end})
TabRagebot:CreateSlider({Name="Orbit Radius (studs)",Range={2,50},Increment=1,Suffix=" st",CurrentValue=8,Flag="RbRadius",
    Callback=function(v) ragebotRadius=v end})
TabRagebot:CreateSlider({Name="Orbit Speed (deg/s)",Range={30,720},Increment=10,Suffix=" d/s",CurrentValue=120,Flag="RbOrbitSpd",
    Callback=function(v) ragebotOrbitSpd=v end})

log("Ragebot tab ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  UI — VISUAL TAB                                              ║
-- ╚══════════════════════════════════════════════════════════════╝
TabVisual:CreateSection("ESP")
TabVisual:CreateKeybind({Name="ESP Toggle Key",CurrentKeybind="E",HoldToInteract=false,Flag="KB_ESP",
    Callback=function(v) KB.esp=resolveKC(v,KB.esp) end})
TabVisual:CreateButton({Name="Toggle ESP",Callback=function()
    if not espActive then activateESP() else espActive=false; clearAllESP() end
end})
TabVisual:CreateToggle({Name="Highlights",  CurrentValue=false,Flag="ESPHigh",  Callback=function(v) F.espHighlights=v; if espActive then activateESP() end end})
TabVisual:CreateToggle({Name="Tracers",     CurrentValue=false,Flag="ESPTrac",  Callback=function(v) F.espTracers=v end})
TabVisual:CreateToggle({Name="Nametags",    CurrentValue=false,Flag="ESPNames", Callback=function(v) F.espNametags=v end})
TabVisual:CreateToggle({Name="Health Bars", CurrentValue=false,Flag="ESPHP",    Callback=function(v) F.espHealthBars=v end})
TabVisual:CreateToggle({Name="Box ESP",     CurrentValue=false,Flag="ESPBox",   Callback=function(v) F.espBoxes=v end})
TabVisual:CreateToggle({Name="Skeleton",    CurrentValue=false,Flag="ESPSkel",  Callback=function(v) F.espSkeleton=v end})
TabVisual:CreateSlider({Name="Line Thickness",Range={1,6},Increment=0.5,CurrentValue=1.5,Flag="ESPThick",
    Callback=function(v)
        espLineThick=v
        for _,l in pairs(espTracerLines) do l.Thickness=v end
        for _,g in pairs(boxLineGroups) do for _,l in ipairs(g) do l.Thickness=v end end
    end})

TabVisual:CreateSection("Radar")
TabVisual:CreateToggle({Name="Show Radar",CurrentValue=false,Flag="Radar",Callback=function(v) F.radar=v end})
TabVisual:CreateSlider({Name="Range (wu)",Range={50,500},Increment=10,Suffix=" wu",CurrentValue=150,Flag="RadarRange",
    Callback=function(v) RADAR_RANGE=v end})
TabVisual:CreateSlider({Name="Size (px)",Range={60,200},Increment=5,Suffix="px",CurrentValue=120,Flag="RadarSize",
    Callback=function(v) RADAR_RADIUS=v; radarBG.Radius=v; radarRing.Radius=v*0.5; radarBorder.Radius=v end})

TabVisual:CreateSection("HUD")
TabVisual:CreateToggle({Name="Watermark (FPS + target)",CurrentValue=false,Flag="WM",Callback=function(v) F.watermark=v end})

log("Visual tab ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  UI — MOVEMENT TAB                                            ║
-- ╚══════════════════════════════════════════════════════════════╝
TabMovement:CreateSection("Fly")
TabMovement:CreateKeybind({Name="Fly Toggle Key",CurrentKeybind="F",HoldToInteract=false,Flag="KB_Fly",
    Callback=function(v) KB.fly=resolveKC(v,KB.fly) end})
TabMovement:CreateDropdown({Name="Fly Mode",Options={"Velocity","CFrame"},CurrentOption="Velocity",Flag="FlyMode",
    Callback=function(v)
        local m=type(v)=="table" and v[1] or v; flyMode=m
        if flyActive then stopFly(); startFly() end
    end})
TabMovement:CreateSlider({Name="Fly Speed",Range={10,250},Increment=5,Suffix=" st/s",CurrentValue=50,Flag="FlySpeed",
    Callback=function(v) flySpeed=v end})
TabMovement:CreateButton({Name="Toggle Fly",Callback=function()
    if flyActive then flyActive=false; stopFly() else flyActive=true; startFly() end
end})

TabMovement:CreateSection("Speed")
TabMovement:CreateToggle({Name="Speed Hack",CurrentValue=false,Flag="SpeedHack",Callback=function(v) setSpeedHack(v) end})
TabMovement:CreateSlider({Name="Speed Multiplier",Range={1,10},Increment=0.5,Suffix="x",CurrentValue=2,Flag="SpeedMult",
    Callback=function(v) speedMult=v end})
TabMovement:CreateToggle({Name="Swim Speed",CurrentValue=false,Flag="SwimSpeed",Callback=function(v) setSwimSpeed(v) end})
TabMovement:CreateSlider({Name="Swim Multiplier",Range={1,10},Increment=0.5,Suffix="x",CurrentValue=3,Flag="SwimMult",
    Callback=function(v) swimMult=v end})

TabMovement:CreateSection("Jump / Physics")
TabMovement:CreateToggle({Name="Infinite Jump",CurrentValue=false,Flag="InfJump",  Callback=function(v) setInfJump(v) end})
TabMovement:CreateToggle({Name="No-Clip",       CurrentValue=false,Flag="Noclip",  Callback=function(v) setNoclip(v) end})
TabMovement:CreateToggle({Name="Bunny Hop",     CurrentValue=false,Flag="Bhop",    Callback=function(v) setBhop(v) end})
TabMovement:CreateToggle({Name="Low Gravity",   CurrentValue=false,Flag="LowGrav", Callback=function(v) setLowGravity(v) end})
TabMovement:CreateSlider({Name="Gravity Value", Range={5,196},Increment=1,CurrentValue=30,Flag="GravVal",
    Callback=function(v) gravScale=v end})

TabMovement:CreateSection("Auto-Collect")
TabMovement:CreateToggle({Name="Auto-Collect",CurrentValue=false,Flag="AutoCollect",Callback=function(v) setAutoCollect(v) end})
TabMovement:CreateSlider({Name="Interval x0.01s",Range={10,500},Increment=10,CurrentValue=100,Flag="CollectInt",
    Callback=function(v) collectInterval=v/100 end})

log("Movement tab ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  UI — UTILITY TAB                                             ║
-- ╚══════════════════════════════════════════════════════════════╝
TabUtility:CreateSection("Teleport to Player")
local TpDrop=TabUtility:CreateDropdown({Name="Target",Options=getOtherNames(),
    CurrentOption=getOtherNames()[1],Flag="TpTarget",
    Callback=function(v) local n=type(v)=="table" and v[1] or v; tpTarget=Players:FindFirstChild(n) end})
Players.PlayerAdded:Connect(function() pcall(function() TpDrop:Set(getOtherNames()) end) end)
Players.PlayerRemoving:Connect(function(p)
    if tpTarget==p then tpTarget=nil end; pcall(function() TpDrop:Set(getOtherNames()) end)
end)
TabUtility:CreateButton({Name="Teleport to Player",Callback=function()
    if not tpTarget or not tpTarget.Parent then
        Rayfield:Notify({Title="TP",Content="Select a target!",Duration=2}); return end
    local tRoot=tpTarget.Character and tpTarget.Character:FindFirstChild("HumanoidRootPart")
    local myRoot=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not tRoot or not myRoot then return end
    myRoot.CFrame=tRoot.CFrame*CFrame.new(0,2,-3)
    Rayfield:Notify({Title="TP",Content="Warped to "..tpTarget.Name,Duration=2})
end})

TabUtility:CreateSection("Teleport to Coords")
local coordX,coordY,coordZ=0,0,0
TabUtility:CreateSlider({Name="X",Range={-10000,10000},Increment=1,CurrentValue=0,Flag="CoordX",Callback=function(v) coordX=v end})
TabUtility:CreateSlider({Name="Y",Range={-500,5000},  Increment=1,CurrentValue=0,Flag="CoordY",Callback=function(v) coordY=v end})
TabUtility:CreateSlider({Name="Z",Range={-10000,10000},Increment=1,CurrentValue=0,Flag="CoordZ",Callback=function(v) coordZ=v end})
TabUtility:CreateButton({Name="Warp to Coords",Callback=function()
    local hrp=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CFrame=CFrame.new(coordX,coordY,coordZ) end
end})
TabUtility:CreateButton({Name="Copy My Position",Callback=function()
    local hrp=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local p=hrp.Position
    Rayfield:Notify({Title="Position",Content=string.format("%.0f, %.0f, %.0f",p.X,p.Y,p.Z),Duration=5})
end})

TabUtility:CreateSection("Spectate")
local SpecDrop=TabUtility:CreateDropdown({Name="Player",Options=getOtherNames(),
    CurrentOption=getOtherNames()[1],Flag="SpecTarget",
    Callback=function(v) local n=type(v)=="table" and v[1] or v; spectateSelected=Players:FindFirstChild(n) end})
Players.PlayerAdded:Connect(function() pcall(function() SpecDrop:Set(getOtherNames()) end) end)
Players.PlayerRemoving:Connect(function(p)
    if spectateSelected==p then spectateSelected=nil end
    if spectateTarget==p then stopSpectate() end
    pcall(function() SpecDrop:Set(getOtherNames()) end)
end)
TabUtility:CreateButton({Name="Start Spectate",Callback=function()
    if not spectateSelected or not spectateSelected.Parent then
        Rayfield:Notify({Title="Spectate",Content="Select a player!",Duration=2}); return end
    startSpectate(spectateSelected)
end})
TabUtility:CreateButton({Name="Stop Spectate",Callback=stopSpectate})

TabUtility:CreateSection("Tool Picker")
local function scanForTools()
    local found={}; local seen={}
    local function scan(c) pcall(function() for _,obj in ipairs(c:GetDescendants()) do
        if obj:IsA("Tool") and not seen[obj.Name] then seen[obj.Name]=true; table.insert(found,obj) end
    end) end end
    scan(workspace); scan(game:GetService("ReplicatedStorage"))
    pcall(function() scan(game:GetService("ServerStorage")) end); return found
end
local _cachedTools=scanForTools(); local _toolSel=_cachedTools[1]
local function toolNames(t) local n={}; for _,v in ipairs(t) do table.insert(n,v.Name) end; if #n==0 then table.insert(n,"(none)") end; return n end
local ToolDrop=TabUtility:CreateDropdown({Name="Tool",Options=toolNames(_cachedTools),
    CurrentOption=toolNames(_cachedTools)[1],Flag="ToolSel",
    Callback=function(v) local n=type(v)=="table" and v[1] or v; for _,t in ipairs(_cachedTools) do if t.Name==n then _toolSel=t; break end end end})
TabUtility:CreateButton({Name="Refresh",Callback=function()
    _cachedTools=scanForTools(); pcall(function() ToolDrop:Set(toolNames(_cachedTools)) end)
    Rayfield:Notify({Title="Tools",Content=#_cachedTools.." found",Duration=2})
end})
TabUtility:CreateButton({Name="Give Selected Tool",Callback=function()
    if not _toolSel or not _toolSel.Parent then
        Rayfield:Notify({Title="Tools",Content="Refresh first!",Duration=2}); return end
    local char=LP.Character; if not char then return end
    local clone=_toolSel:Clone(); clone.Parent=char
    Rayfield:Notify({Title="Tools",Content="Gave: ".._toolSel.Name,Duration=2})
end})

TabUtility:CreateSection("Misc")
TabUtility:CreateToggle({Name="Infinite Zoom",       CurrentValue=false,Flag="InfZoom",    Callback=function(v) setInfZoom(v) end})
TabUtility:CreateToggle({Name="Auto-Rejoin on Kick", CurrentValue=false,Flag="AutoRejoin", Callback=function(v) setAutoRejoin(v) end})
TabUtility:CreateToggle({Name="Fullbright",          CurrentValue=false,Flag="Fullbright", Callback=function(v) setFullbright(v) end})
TabUtility:CreateToggle({Name="Fake Lag",            CurrentValue=false,Flag="FakeLag",    Callback=function(v) setFakeLag(v) end})
TabUtility:CreateSlider({Name="Fake Lag (ms)",Range={50,1000},Increment=25,Suffix="ms",CurrentValue=200,Flag="FakeLagMS",
    Callback=function(v) fakeLagMS=v end})
TabUtility:CreateToggle({Name="Anti-AFK",            CurrentValue=false,Flag="AntiAfk",   Callback=function(v) setAntiAfk(v) end})
TabUtility:CreateToggle({Name="Click Teleport (hold key + LMB)",CurrentValue=false,Flag="ClickTp",
    Callback=function(v) setClickTp(v) end})
TabUtility:CreateKeybind({Name="Click TP Key",CurrentKeybind="G",HoldToInteract=false,Flag="KB_ClickTp",
    Callback=function(v) KB.clickTp=resolveKC(v,KB.clickTp); if F.clickTp then setClickTp(false); setClickTp(true) end end})
TabUtility:CreateButton({Name="Rejoin",Callback=function()
    task.delay(1,function() TeleportService:Teleport(game.PlaceId,LP) end)
    Rayfield:Notify({Title="Rejoin",Content="Rejoining...",Duration=2})
end})
TabUtility:CreateButton({Name="Server Hop",Callback=function()
    task.spawn(function()
        local ok2,data=pcall(function()
            return HttpService:JSONDecode(game:HttpGet(
                "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=10"))
        end)
        if ok2 and data and data.data then
            for _,s in ipairs(data.data) do
                if s.id~=game.JobId and s.playing<s.maxPlayers then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId,s.id,LP); return
                end
            end
        end
        TeleportService:Teleport(game.PlaceId,LP)
    end)
end})
TabUtility:CreateSection("Danger Zone")
TabUtility:CreateKeybind({Name="Panic Key",CurrentKeybind="Delete",HoldToInteract=false,Flag="KB_Panic",
    Callback=function(v) KB.panic=resolveKC(v,KB.panic) end})
TabUtility:CreateButton({Name="PANIC (disable all + hide UI)",Callback=doPanic})

log("Utility tab ✓")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  DONE                                                         ║
-- ╚══════════════════════════════════════════════════════════════╝
log("════════════════════════════════════════════")
log("Ghost v3 v2 (Rayfield) fully loaded ✓")
log("  Aimbot  : Target-lock (C), Camera, Mouse, Prediction, Silent Aim")
log("  Combat  : Triggerbot, Rapid Fire, Anti-Aim, Kill Aura, CSync")
log("  Ragebot : Orbit strafe, Auto-fire, Return-to-origin")
log("  Visual  : ESP x6 + target dot, Radar, Watermark")
log("  Movement: Fly (Vel/CF), Speed, Swim, Jump, No-Clip, Bhop, Grav, Collect")
log("  Utility : TP, Spectate, Coords, Tool Picker, Rejoin, Misc")
log("════════════════════════════════════════════")
Rayfield:Notify({Title="Ghost v3 v2",Content="All systems loaded!",Duration=4})
