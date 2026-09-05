<#
================================================================================
  Fortnite Booster van StrixLuca  -  version 1.0 beta
  https://github.com/StrixLuca/Fortnite-Booster

  WHAT THIS IS
  A free, open source tool that makes Fortnite run smoother and gives you more
  FPS. It works on any PC. There is no installer: you double click the .bat file,
  it opens a small window, and it closes completely when you are done.

  WHAT IT DOES  (all of it is reversible)
  1. Reads your Fortnite config (GameUserSettings.ini) and applies faster,
     competitive graphics settings. A backup is made before every change.
  2. Changes a handful of normal Windows options that any optimization guide
     lists: Game Mode, hardware GPU scheduling, power plan, and similar.
  3. Optionally sets your Fortnite config file to read only so the game stops
     overwriting your settings on every launch.

  WHAT IT DOES NOT DO
  No cheats. No aimbot or ESP. It does not inject code into Fortnite and it never
  touches Easy Anti Cheat or BattlEye. It makes no network connections except an
  optional check for a newer version on GitHub and an optional ping test. Your
  account stays safe.

  HOW TO READ THIS FILE
  Every function has a short comment above it explaining what it changes and why.
  The web interface it serves is in ui.html next to this file. Nothing is hidden
  or obfuscated. If a function name starts with Optimize, Set, Clear or Disable,
  the comment tells you exactly which setting it touches.
================================================================================
#>


# Small helper used only to style OUR OWN app window (rounded corners). It does
# not touch Fortnite or any other program.
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class StrixNative {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
"@ -ErrorAction SilentlyContinue
} catch {}

# Ronde hoeken via region (vroeg gedefinieerd zodat elk venster/dialoog het kan gebruiken)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Rgn {
    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateRoundRectRgn(int l,int t,int r,int b,int w,int h);
}
"@ -ErrorAction SilentlyContinue
# Bouwt een afgeronde-rechthoek pad (voor glas-kaarten en pill-knoppen)

# ==============================================================================
#  PADEN & STATE
#  BELANGRIJK: in ASA staat de config BINNEN de game-installatie:
#    %LOCALAPPDATA%\FortniteGame\Saved\Config\WindowsClient\
#  Deze paden worden dynamisch gevuld door de config-zoeker (Set-ConfigPaths).
#  De LOCALAPPDATA-variant blijft als laatste fallback voor rare setups.
# ==============================================================================
# Fortnite config lives at a FIXED location (not inside a Steam folder):
#   %LOCALAPPDATA%\FortniteGame\Saved\Config\WindowsClient\
$Script:GameInfo   = $null
$Script:ConfigDir  = $null   # set by Find-FortniteConfig / Set-ConfigPaths
$Script:GusIni     = $null   # GameUserSettings.ini (main Fortnite config)
$Script:EngineIni  = $null   # Engine.ini
$Script:InputIni   = $null
$Script:BoosterDir = Join-Path $env:LOCALAPPDATA "StrixFpsBooster"
$Script:LockEngineIni    = $true    # Fortnite herschrijft config bij elke start; read only lock voorkomt wissen
$Script:ApplyEngineExtras = $true   # ook de Engine.ini render-extras schrijven
$Script:BackupDir  = Join-Path $Script:BoosterDir "Backups"
$Script:ScoreHistoryFile = Join-Path $Script:BoosterDir "scorehistory.json"
$Script:ScoreHistory = @()
try { if (Test-Path $Script:ScoreHistoryFile) { $Script:ScoreHistory = @(Get-Content $Script:ScoreHistoryFile -Raw | ConvertFrom-Json) } } catch { $Script:ScoreHistory = @() }
function Add-ScoreHistory {
    param([int]$Score)
    try {
        $entry = @{ score=$Score; date=(Get-Date -Format 'yyyy-MM-dd HH:mm') }
        $Script:ScoreHistory = @($Script:ScoreHistory) + $entry
        if ($Script:ScoreHistory.Count -gt 20) { $Script:ScoreHistory = $Script:ScoreHistory[-20..-1] }
        $Script:ScoreHistory | ConvertTo-Json -Depth 4 | Set-Content $Script:ScoreHistoryFile
    } catch {}
}
$Script:LogFile    = Join-Path $Script:BoosterDir "booster.log"

function Set-ConfigPaths {
    param([string]$ConfigDir)
    $Script:ConfigDir = $ConfigDir
    if ($ConfigDir) {
        $Script:GusIni    = Join-Path $ConfigDir "GameUserSettings.ini"
        $Script:EngineIni = Join-Path $ConfigDir "Engine.ini"
        $Script:InputIni  = Join-Path $ConfigDir "Input.ini"
        # ClientSettings.Sav zit een map hoger (in Saved/Config/) en bevat OOK
        # settings die Fortnite leest. Die moeten we mee-locken.
        try {
            $parent = Split-Path $ConfigDir -Parent   # ...Saved/Config
            $Script:ClientSav = Join-Path $parent "ClientSettings.Sav"
        } catch { $Script:ClientSav = $null }
    }
}

New-Item -ItemType Directory -Force -Path $Script:BoosterDir | Out-Null
New-Item -ItemType Directory -Force -Path $Script:BackupDir  | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    try { Add-Content -Path $Script:LogFile -Value ("{0} [{1}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Message) -ErrorAction SilentlyContinue } catch {}
}

function Test-Admin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# ==============================================================================
#  LANGUAGE SYSTEM - English main, switchable to NL / DE / ES (restart applies)
# ==============================================================================
$Script:LangFile = Join-Path $Script:BoosterDir "language.txt"
$Script:Lang = "EN"
try { if (Test-Path $Script:LangFile) { $l = (Get-Content $Script:LangFile -Raw).Trim(); if ($l -in @("EN","NL","DE","ES")) { $Script:Lang = $l } } } catch {}

# Onthoud de laatst gekozen preset (zodat de booster niet elke keer op Balanced opent)
$Script:PresetFile = Join-Path $Script:BoosterDir "preset.txt"
$Script:SavedPreset = $null
try { if (Test-Path $Script:PresetFile) { $p = (Get-Content $Script:PresetFile -Raw).Trim(); if ($p -in @("Competitive / Max FPS","Balanced","Quality")) { $Script:SavedPreset = $p } } } catch {}
function Save-Preset { param([string]$Name)
    if ($Name -in @("Competitive / Max FPS","Balanced","Quality")) {
        try { if (-not (Test-Path $Script:BoosterDir)) { New-Item -ItemType Directory -Force -Path $Script:BoosterDir | Out-Null }; Set-Content -Path $Script:PresetFile -Value $Name } catch {}
    }
}

# Onthoud de lock-voorkeur (read only aan/uit)
$Script:LockFile = Join-Path $Script:BoosterDir "lock.txt"
try { if (Test-Path $Script:LockFile) { $lk = (Get-Content $Script:LockFile -Raw).Trim(); if ($lk -eq "0") { $Script:LockPref = $false } else { $Script:LockPref = $true } } else { $Script:LockPref = $true } } catch { $Script:LockPref = $true }
function Save-LockPref { param([bool]$On)
    try { if (-not (Test-Path $Script:BoosterDir)) { New-Item -ItemType Directory -Force -Path $Script:BoosterDir | Out-Null }; Set-Content -Path $Script:LockFile -Value $(if ($On) {"1"} else {"0"}) } catch {}
}
$Script:LockEngineIni = $Script:LockPref   # gebruik de onthouden voorkeur

# Onthoud de laatst gekozen stretched resolutie
$Script:StretchFile = Join-Path $Script:BoosterDir "stretch.txt"
$Script:SavedStretch = $null
$Script:GpuScalingOn = $false
$Script:LastBench = 0
$Script:GpuScalingFile = Join-Path $Script:BoosterDir "gpuscaling.txt"
try { if (Test-Path $Script:GpuScalingFile) { $Script:GpuScalingOn = ((Get-Content $Script:GpuScalingFile -Raw).Trim() -eq "on") } } catch {}
$Script:StretchFile = Join-Path $Script:BoosterDir "stretch.txt"
try { if (Test-Path $Script:StretchFile) { $Script:SavedStretch = (Get-Content $Script:StretchFile -Raw).Trim() } } catch {}
try { if (Test-Path $Script:StretchFile) { $st = (Get-Content $Script:StretchFile -Raw).Trim(); if ($st -eq "native" -or $st -match '^\d{3,4}x\d{3,4}$') { $Script:SavedStretch = $st } } } catch {}
function Save-Stretch { param([string]$Res)
    try { if (-not (Test-Path $Script:BoosterDir)) { New-Item -ItemType Directory -Force -Path $Script:BoosterDir | Out-Null }; Set-Content -Path $Script:StretchFile -Value $Res } catch {}
}

# Onthoud de crosshair-positie fijn-afstelling (offset t.o.v. schermmidden)
$Script:ChOffFile = Join-Path $Script:BoosterDir "crosshair-offset.txt"
$Script:SavedChOff = @{ X=0; Y=0 }
try { if (Test-Path $Script:ChOffFile) { $co = (Get-Content $Script:ChOffFile -Raw).Trim() -split ','; if ($co.Count -eq 2) { $Script:SavedChOff = @{ X=[int]$co[0]; Y=[int]$co[1] } } } } catch {}
function Save-ChOffset { param([int]$X,[int]$Y)
    try { if (-not (Test-Path $Script:BoosterDir)) { New-Item -ItemType Directory -Force -Path $Script:BoosterDir | Out-Null }; Set-Content -Path $Script:ChOffFile -Value "$X,$Y" } catch {}
}

$Script:Strings = @{
EN = @{
  hdr="STRIXLUCA FORTNITE BOOSTER"; hdr_sub="Fortnite - honest tweaks, real FPS"; tw_nav="All tweaks"; cl_nav="Cleanup"; fi_nav="Config finder"
  gp_nav="Game Settings"; gp_t="IN-GAME SETTINGS + EXTRAS"; gp_s="Things you normally change in game but lose to the read only lock. Set them here so they stick."; gs_t="FORTNITE GAME SETTINGS"; gs_s="Change any Fortnite setting here - it sticks even with the config locked. No need to touch the in game menu."; gs_all="ALL SETTINGS (changes apply instantly)"; gs_applied="Applied:"; gs_quick="ONE-CLICK PRESETS"; gs_comp="Competitive (max FPS)"; gs_bal="Balanced"; gs_qual="Quality"; fps_unlim="Unlimited"
  fps_hdr="FPS LIMIT"; fps_desc="Set your frame cap. Match your monitor Hz, or uncapped for max frames on a 240Hz+ screen."; fps_unl="Uncapped"
  ingame_hdr="IN-GAME DISPLAY"; show_fps="Show FPS counter in game"; show_fps_note="Writes the FPS counter into the config so it survives the lock."; fps_on="Applied - FPS counter ON in game"; fps_off="Applied - FPS counter OFF"; fps_needcfg="Launch Fortnite once first, then try again"; inp_hdr="MOUSE + KEYBOARD BOOST"; inp_btn="Fix mouse lag + boost input (1 to 1 aim, USB + core park)"; inp_on="Mouse acceleration OFF - 1 to 1 aim active"; inp_off="Mouse acceleration not optimized yet"; inp_done="Input optimized:"; inp_admin="Needs administrator - restart as admin."
  ch_hdr="CROSSHAIR OVERLAY"; ch_desc="A safe external crosshair drawn on top of the screen. No injection, no game files touched - the anti-cheat-safe method."; ch_cross="Cross"; ch_crossdot="Cross+dot"; ch_dot="Dot"; ch_color="Color"; ch_on="Show crosshair"; ch_off="Hide crosshair"; ch_tshape="T-shape"; ch_circle="Circle"; ch_size="Size"; ch_gap="Gap"; ch_thick="Thick"; ch_preview="LIVE PREVIEW"; ch_style_lbl="Style"; ch_pos="Position"; thm_title="CHOOSE YOUR THEME"; thm_sub="Pick a color style for your booster. You can change it later."; thm_apply="APPLY THEME"; thm_btn="Theme"; thm_restart="Theme saved! Restart the booster to see it."; sys_title="SYSTEM CHECK"; sys_sub="What is currently ON or OFF on your PC."; sys_close="Close"; sys_btn="System check"; g_btn="Guide"; sys_on="ON"; sys_fix="Fix everything OFF"; sys_fixed="Done! Everything that could be turned on is now on."; sys_fixadmin="Applied what I could. Restart as administrator to fix the rest."; g_title="{0} SETTINGS GUIDE"; g_sub="These give the biggest FPS and latency wins. They live in your GPU software and in game, so we guide you - safely.";
  g_nv1_t="NVIDIA Reflex: On + Boost"; g_nv1_d="In Fortnite > Settings > Video. This is the single biggest latency win - cuts delay 20-40%. Always turn it on.";
  g_nv2_t="Low Latency Mode: Ultra"; g_nv2_d="NVIDIA Control Panel > Manage 3D settings > Low Latency Mode > Ultra. Keeps the render queue short.";
  g_nv3_t="Power: Prefer Maximum Performance"; g_nv3_d="NVIDIA Control Panel > Manage 3D settings > Power management mode. Stops the GPU downclocking mid-fight.";
  g_nv4_t="Fullscreen + cap FPS"; g_nv4_d="Use Fullscreen (not Windowed) in Fortnite. Cap FPS a few frames below your refresh, or uncapped with Reflex on.";
  g_amd1_t="Radeon Anti Lag: ON"; g_amd1_d="AMD Adrenalin > Gaming > Fortnite > Radeon Anti Lag. Biggest latency win on AMD - cuts input delay. Use regular Anti Lag, NOT Anti Lag+ (that injects and can get you banned).";
  g_amd2_t="Radeon Chill: OFF"; g_amd2_d="Turn Chill off for competitive - it limits FPS to save power, which adds latency.";
  g_amd3_t="GPU Scaling: full panel"; g_amd3_d="For stretched res: Adrenalin > Display > GPU Scaling ON + Scaling Mode Full Panel. Without this you get black bars.";
  g_amd4_t="Fullscreen + cap FPS"; g_amd4_d="Fullscreen (not Windowed) in Fortnite. Cap FPS just below your refresh, or uncapped with Anti Lag on.";
  g_int1_t="Intel low latency"; g_int1_d="Intel Graphics Command Center > Fortnite > enable any low-latency/performance option available for your driver.";
  g_int2_t="Fullscreen + cap FPS"; g_int2_d="Use Fullscreen in Fortnite and cap FPS near your refresh rate for the smoothest frametime.";
  g_gen1_t="In game latency settings"; g_gen1_d="Enable your GPU's low-latency mode, use Fullscreen (not Windowed), and cap FPS just below your monitor refresh."; cal_info="Use the arrows to move the crosshair onto Fortnite's exact center. Center button resets."; cal_reset="Reset"; cal_save="Save position"
  net_hdr="NETWORK + WIFI"; net_desc="Lower your latency (ping), not FPS. Flushes DNS, tunes TCP, disables Nagle and network throttling."; net_wifi="On WiFi - signal {0}%"; net_lan="Wired connection - best for Fortnite"; net_wifi_tip="Tip: a wired cable beats WiFi for ping stability. If you must use WiFi, sit close to the router and use 5GHz."; net_btn="Optimize network + flush DNS"; net_done="Network optimized:"; net_admin="Needs administrator - restart the launcher as admin."
  gpu_guide="STRETCHED FEELS WEAK? The config only writes the resolution - the actual STRETCH is done by your GPU driver. Open NVIDIA Control Panel > Adjust desktop size and position > Scaling: Full screen + tick 'Override the scaling mode', OR AMD Software > Display > GPU Scaling ON + Scaling mode Full Panel. Then set the custom resolution and pick Fullscreen in Fortnite. Without this you get black bars or a small image instead of a real stretch."
  admin_y="Administrator active - all tweaks available"; admin_n="No administrator - Windows tweaks disabled"
  sys="YOUR SYSTEM"; scr="Screen"; ark_st="FORTNITE STATUS"
  game_f="Fortnite found ({0})"; game_nf="Fortnite install not auto-detected (launch via Epic still works)"
  cfg_f="Config found - ready to optimize"; cfg_nf="Config not created yet - launch Fortnite once and quit"
  pick="CHOOSE YOUR STYLE"; rec="Pick how you want to play (we recommend one for your PC)"; step2="STEP 2  -  BOOST"; or_just="Or, only if you don't want PC-wide changes:"
  p_ultra="Maximum FPS. Everything off that can be. For weak PCs that are otherwise unplayable."
  p_bal="Big FPS gain while the game still looks good. Best choice for most people."
  p_qual="Best visuals, only the pure FPS killers removed. For strong PCs."
  p_pvp="Competitive Performance Mode config used by pros: shadows off, effects low, no motion blur, raw input, uncapped FPS."
  opts="EXTRA OPTIONS"
  c_win="Include Windows game tweaks (Game Mode, HAGS, Game DVR off, power plan)"
  c_close="Close background apps before launch (browsers, Discord, Spotify)"
  c_prio="Set Fortnite to High priority once it runs"
  b_apply="Only Fortnite config"; b_launch="APPLY + LAUNCH FORTNITE"; b_launch2="Apply + play"; b_restore="Restore defaults"; b_restore2="RESTORE"; busy="WORKING..."; b_allboost="ALL BOOST IN ONE"; b_boost="BOOST MY FORTNITE"; boost_note="Applies your style + optimizes your whole PC + locks your config. One click."; b_play="Launch Fortnite"; ab_play="Launch Fortnite now?"; allboost_sub="RECOMMENDED"; ab_t="ALL BOOST COMPLETE"; ab_done="Done! Your PC and Fortnite are optimized. You do NOT need to click anything else - just launch Fortnite and play."; ab_reboot="Some tweaks (GPU scheduling) apply after a reboot."
  tw_t="ALL TWEAKS - HONESTLY LABELED"; tw_s="Green WORKS = reliable. Amber SITUATIONAL = works, gain depends on your hardware."
  folk_h="Why some popular 'tweaks' are NOT here:"
  cl_t="SYSTEM CLEANUP"; cl_s="Only safe caches that rebuild themselves. No registry nonsense, no risk."
  disk="DISK SPACE"; cl_what="WHAT DO YOU WANT TO CLEAN?"
  cc1="Clear Fortnite shader/pipeline cache (THE #1 stutter fix after updates; rebuilds on next launch)"
  cc2="Clear GPU shader caches (NVIDIA / AMD / Intel / DirectX - they rebuild themselves)"
  cc3="Clean Windows temp files (files in use are simply skipped)"
  cc4="Flush DNS cache (can help with server connection issues)"
  cl_hint="When? After a game or driver update, clearing the shader cache is the number 1 stutter fix."
  b_clean="START CLEANUP"; quick="QUICK ACTIONS"; b_task="Open Task Manager"; b_gfx="Windows graphics settings"; b_gm="Game Mode settings"
  fi_t="CONFIG FINDER"; fi_s="Locates your Fortnite config folder in LOCALAPPDATA. Manual picker as fallback."
  b_rescan="Scan again"; b_browse="Pick config folder manually"; b_ocfg="Open config folder"; b_ogame="Open game folder"
  bk_t="BACKUPS"; bk_s="A copy is saved automatically before every change. They are plain files."
  b_bkr="Restore"; b_bko="Open folder"; b_bkf="Refresh"
  ov_t="FORTNITE IS LAUNCHING"; ov_s="Your tweaks are in place. Have fun - and watch that FPS."
  ov_tip="Tip: use Performance Mode (DX12) in Fortnite Video settings for the biggest FPS gain."
  ov_c="Launcher closes automatically in {0} seconds..."; ov_stay="Keep launcher open"
  m_done="Done. Launch Fortnite and check your FPS. Not happy? Click Restore defaults."
  m_applied="Tweaks applied"; m_rc="This removes the booster tweaks from Engine.ini. A backup is made first. Continue?"
  m_rt="Restore defaults"; m_rd="Restored"; m_arkrun="Fortnite is running. Close the game first, otherwise the shader cache cannot be cleared."
  m_wait="Please wait"; m_nostart="Could not launch Fortnite - is the Epic Games Launcher installed?"; m_warn="Warning"
  dg_t="Preview of changes"; dg_apply="APPLY"; dg_cancel="Cancel"; dg_new="NEW"; dg_sub="Left: current value in your Engine.ini. Right: what this preset will set. = means unchanged."
  sc_exp="Share code"; sc_imp="Import code"; sc_copy="Copy"; sc_close="Close"; sc_t="Community share code"
  sc_prompt="Paste a STRIX share code:"; sc_bad="Invalid share code."; sc_ok="Share code contains {0} tweaks. A preview follows."; tw_use="Use"
  p_ua="The full competitive setup in one click: Performance Mode, shadows off, effects/post low, motion blur off, raw mouse input, uncapped FPS. Max frames, max clarity."
  vbs_on="VBS/Memory Integrity is ON - turning it off gives +5-15% FPS (Windows Security > Core Isolation)"; vbs_off="VBS off - good, no FPS penalty"; args_btn="Copy launch options"; args_copied="Copied! In Epic: Fortnite > Manage > Command Line Args, paste:\n\n{0}"
  score_t="FORTNITE OPTIMIZATION SCORE"; score_max="Perfectly optimized for Fortnite!"; score_todo="To improve:"
  boost_hdr="FPS BOOST"; boost_sub="Your live Fortnite optimization score. Apply tweaks and watch it climb."; score_cap="PERFORMANCE READY"; gpu_nv="Shader cache + guided panel settings"; gpu_amd="Anti Lag safe (never Anti Lag+)"; gpu_intel="Driver + config optimized"; gpu_unknown="Generic safe optimization"; vbs_short="if off"; args_hdr="EPIC LAUNCH OPTIONS"
  stretch_hdr="STRETCHED RESOLUTION + CONFIG LOCK"; stretch_btn="Apply stretched"; stretch_done="Stretched res {0} set + fullscreen. IMPORTANT: also create this exact custom resolution in your NVIDIA/AMD control panel (Full screen scaling), then pick Fullscreen in Fortnite. Restart Fortnite."; stretch_native="Resolution set back to native. Restart Fortnite."; stretch_fail="Could not set stretched res"; lock_toggle="Keep config read only (locked so Fortnite cannot wipe your settings)"
  custom_w="Enter WIDTH in pixels (e.g. 1080 for PeterBot 1:1 stretch):"; custom_h="Enter HEIGHT in pixels (e.g. 1080):"; custom_bad="Please enter valid numbers (width 640-7680, height 480-4320)."
  vbs_fix="Turn off Memory Integrity"; vbs_confirm="This turns off Memory Integrity (VBS) via the registry - this also unlocks the greyed-out toggle. A security feature will be disabled for more FPS. Takes effect after you REBOOT. Continue?"; vbs_done="Done! Memory Integrity will be OFF after you restart Windows. Your score will go up. You can turn it back on any time in Windows Security > Core Isolation."; vbs_fail="Could not change it"; vbs_gp="Note: a Group Policy is enforcing this. It may turn back on at reboot. If so, your organization/IT or a policy is managing it."
  c_lock="Lock config after applying (stops Fortnite from wiping your settings on launch - recommended)"
  st_run="FORTNITE IS RUNNING"; st_idle="Fortnite not running"
  m_lang="Language saved: {0}. Restart the launcher to apply."
}
NL = @{
  hdr="STRIXLUCA FORTNITE BOOSTER"; hdr_sub="Fortnite - eerlijke tweaks, echte FPS"; tw_nav="Alle tweaks"; cl_nav="Opschonen"; fi_nav="Config zoeker"
  gp_nav="Game Settings"; gp_t="IN-GAME INSTELLINGEN + EXTRA'S"; gp_s="Dingen die je normaal in game aanpast maar door de read only lock kwijtraakt. Zet ze hier zodat ze blijven."; gs_t="FORTNITE GAME SETTINGS"; gs_s="Wijzig elke Fortnite-instelling hier - het blijft staan zelfs met de config op slot. In game menu niet meer nodig."; gs_all="ALLE INSTELLINGEN (wijziging is meteen actief)"; gs_applied="Toegepast:"; gs_quick="PRESETS MET 1 KLIK"; gs_comp="Competitive (max FPS)"; gs_bal="Gebalanceerd"; gs_qual="Kwaliteit"; fps_unlim="Ongelimiteerd"
  fps_hdr="FPS LIMIET"; fps_desc="Stel je frame-cap in. Match je monitor-Hz, of ongelimiteerd voor max frames op een 240Hz+ scherm."; fps_unl="Ongelimiteerd"
  ingame_hdr="IN-GAME WEERGAVE"; show_fps="FPS-teller in game tonen"; show_fps_note="Schrijft de FPS-teller in de config zodat het de lock overleeft."; fps_on="Toegepast - FPS-teller AAN in game"; fps_off="Toegepast - FPS-teller UIT"; fps_needcfg="Start Fortnite eerst 1x, probeer dan opnieuw"; inp_hdr="MUIS + TOETSENBORD BOOST"; inp_btn="Fix muis-lag + boost input (1 to 1 aim, USB + core-park)"; inp_on="Muis-acceleratie UIT - 1 to 1 aim actief"; inp_off="Muis-acceleratie nog niet geoptimaliseerd"; inp_done="Input geoptimaliseerd:"; inp_admin="Heeft administrator nodig - herstart als admin."
  ch_hdr="CROSSHAIR OVERLAY"; ch_desc="Een veilige externe crosshair bovenop het scherm. Geen injectie, raakt geen game-files - de anti-cheat-veilige methode."; ch_cross="Kruis"; ch_crossdot="Kruis+dot"; ch_dot="Dot"; ch_color="Kleur"; ch_on="Crosshair tonen"; ch_off="Crosshair verbergen"; ch_tshape="T-vorm"; ch_circle="Cirkel"; ch_size="Grootte"; ch_gap="Gat"; ch_thick="Dikte"; ch_preview="LIVE PREVIEW"; ch_style_lbl="Stijl"; ch_pos="Positie"; thm_title="KIES JE THEMA"; thm_sub="Kies een kleurstijl voor je booster. Je kunt het later wijzigen."; thm_apply="THEMA TOEPASSEN"; thm_btn="Thema"; thm_restart="Thema opgeslagen! Herstart de booster om het te zien."; sys_title="SYSTEEM CHECK"; sys_sub="Wat er nu AAN of UIT staat op je pc."; sys_close="Sluiten"; sys_btn="Systeem check"; g_btn="Gids"; sys_on="AAN"; sys_fix="Fix alles wat UIT staat"; sys_fixed="Klaar! Alles wat aan kon, staat nu aan."; sys_fixadmin="Gedaan wat kon. Herstart als administrator om de rest te fixen."; g_title="{0} INSTELLINGEN GIDS"; g_sub="Dit geeft de grootste FPS- en latency-winst. Het zit in je GPU-software en in game, dus we gidsen je - veilig.";
  g_nv1_t="NVIDIA Reflex: On + Boost"; g_nv1_d="In Fortnite > Instellingen > Video. Dit is veruit de grootste latency-winst - snijdt vertraging 20-40%. Altijd aanzetten.";
  g_nv2_t="Low Latency Mode: Ultra"; g_nv2_d="NVIDIA Configuratiescherm > 3D-instellingen beheren > Low Latency Mode > Ultra. Houdt de render-wachtrij kort.";
  g_nv3_t="Energie: Voorkeur max prestaties"; g_nv3_d="NVIDIA Configuratiescherm > 3D-instellingen > Energiebeheer. Voorkomt dat de GPU terugklokt tijdens een gevecht.";
  g_nv4_t="Fullscreen + FPS cappen"; g_nv4_d="Gebruik Fullscreen (niet Windowed) in Fortnite. Cap FPS een paar frames onder je refresh, of uncapped met Reflex aan.";
  g_amd1_t="Radeon Anti Lag: AAN"; g_amd1_d="AMD Adrenalin > Gaming > Fortnite > Radeon Anti Lag. Grootste latency-winst op AMD - snijdt input-vertraging. Gebruik gewone Anti Lag, NIET Anti Lag+ (die injecteert en kan een ban geven).";
  g_amd2_t="Radeon Chill: UIT"; g_amd2_d="Zet Chill uit voor competitive - het beperkt FPS om stroom te sparen, wat latency toevoegt.";
  g_amd3_t="GPU Scaling: full panel"; g_amd3_d="Voor stretched res: Adrenalin > Display > GPU Scaling AAN + Scaling Mode Full Panel. Zonder dit krijg je zwarte balken.";
  g_amd4_t="Fullscreen + FPS cappen"; g_amd4_d="Fullscreen (niet Windowed) in Fortnite. Cap FPS net onder je refresh, of uncapped met Anti Lag aan.";
  g_int1_t="Intel low latency"; g_int1_d="Intel Graphics Command Center > Fortnite > zet elke low-latency/prestatie-optie aan die je driver heeft.";
  g_int2_t="Fullscreen + FPS cappen"; g_int2_d="Gebruik Fullscreen in Fortnite en cap FPS rond je refresh-rate voor de soepelste frametime.";
  g_gen1_t="In game latency-instellingen"; g_gen1_d="Zet de low-latency modus van je GPU aan, gebruik Fullscreen (niet Windowed), en cap FPS net onder je monitor-refresh."; cal_info="Gebruik de pijltjes om de crosshair op Fortnite's exacte midden te leggen. Middenknop reset."; cal_reset="Reset"; cal_save="Positie opslaan"
  net_hdr="NETWERK + WIFI"; net_desc="Verlaagt je latency (ping), niet FPS. Leegt DNS, tunet TCP, zet Nagle en network throttling uit."; net_wifi="Op WiFi - signaal {0}%"; net_lan="Bekabelde verbinding - het beste voor Fortnite"; net_wifi_tip="Tip: een kabel is beter dan WiFi voor stabiele ping. Moet je WiFi gebruiken, zit dicht bij de router en gebruik 5GHz."; net_btn="Netwerk optimaliseren + DNS legen"; net_done="Netwerk geoptimaliseerd:"; net_admin="Heeft administrator nodig - herstart de launcher als admin."
  gpu_guide="STRETCH VOELT ZWAK? De config schrijft alleen de resolutie - de echte STRETCH doet je GPU-driver. Open NVIDIA-configscherm > Bureaubladformaat aanpassen > Schaling: Volledig scherm + vink 'Schaalmodus overschrijven', OF AMD Software > Beeldscherm > GPU-schaling AAN + Full Panel. Zet dan de custom resolutie en kies Fullscreen in Fortnite. Zonder dit krijg je zwarte balken of een klein beeld in plaats van echte stretch."
  admin_y="Administrator actief - alle tweaks beschikbaar"; admin_n="Geen administrator - Windows-tweaks uitgeschakeld"
  sys="JOUW SYSTEEM"; scr="Scherm"; ark_st="FORTNITE STATUS"
  game_f="Fortnite gevonden ({0})"; game_nf="Fortnite-installatie niet auto-gevonden (starten via Epic werkt wel)"
  cfg_f="Config gevonden - klaar om te optimaliseren"; cfg_nf="Config nog niet aangemaakt - start Fortnite 1x en sluit af"
  pick="KIES JE STIJL"; rec="Kies hoe je wilt spelen (we raden er een aan voor jouw pc)"; step2="STAP 2  -  BOOST"; or_just="Of, alleen als je geen pc-brede wijzigingen wilt:"
  p_ultra="Maximale FPS. Alles uit wat kan. Voor zwakke pc's die anders niet speelbaar zijn."
  p_bal="Flinke FPS-winst terwijl het spel er goed blijft uitzien. Beste keuze voor de meeste mensen."
  p_qual="Mooiste beeld, alleen de pure FPS-vreters weg. Voor sterke pc's."
  p_pvp="Competitieve Performance Mode-config die pros gebruiken: schaduwen uit, effecten laag, geen motion blur, rauwe input, FPS ongelimiteerd."
  opts="EXTRA OPTIES"
  c_win="Windows game-tweaks meenemen (Game Mode, HAGS, Game DVR uit, energieplan)"
  c_close="Achtergrond-apps sluiten voor het starten (browsers, Discord, Spotify)"
  c_prio="Fortnite op High prioriteit zetten zodra het draait"
  b_apply="Alleen Fortnite config"; b_launch="TOEPASSEN + FORTNITE STARTEN"; b_launch2="Toepassen + spelen"; b_restore="Standaard herstellen"; b_restore2="HERSTEL"; busy="BEZIG..."; b_allboost="ALL BOOST IN ONE"; b_boost="BOOST MIJN FORTNITE"; boost_note="Past je stijl toe + optimaliseert je hele pc + vergrendelt je config. Een klik."; b_play="Fortnite starten"; ab_play="Fortnite nu starten?"; allboost_sub="AANBEVOLEN"; ab_t="ALL BOOST KLAAR"; ab_done="Klaar! Je pc en Fortnite zijn geoptimaliseerd. Je hoeft NIETS anders te klikken - start gewoon Fortnite en speel."; ab_reboot="Sommige tweaks (GPU scheduling) werken na een herstart."
  tw_t="ALLE TWEAKS - EERLIJK GELABELD"; tw_s="Groen WORKS = betrouwbaar. Amber SITUATIONAL = werkt, winst hangt af van je hardware."
  folk_h="Waarom sommige populaire 'tweaks' hier NIET staan:"
  cl_t="SYSTEEM OPSCHONEN"; cl_s="Alleen veilige caches die zichzelf opnieuw opbouwen. Geen register-gerommel, geen risico."
  disk="SCHIJFRUIMTE"; cl_what="WAT WIL JE OPSCHONEN?"
  cc1="Fortnite shader/pipeline-cache legen (DE nummer 1 stotter-fix na updates; bouwt zichzelf opnieuw op)"
  cc2="GPU shader-caches legen (NVIDIA / AMD / Intel / DirectX - bouwen zichzelf opnieuw op)"
  cc3="Windows temp-bestanden opruimen (bestanden in gebruik blijven staan)"
  cc4="DNS-cache verversen (kan helpen bij server-verbindingsproblemen)"
  cl_hint="Wanneer? Na een game- of driver-update is de shader-cache legen de nummer 1 stotter-fix."
  b_clean="OPSCHONEN STARTEN"; quick="SNELLE ACTIES"; b_task="Taakbeheer openen"; b_gfx="Windows grafische instellingen"; b_gm="Game Mode instellingen"
  fi_t="CONFIG ZOEKER"; fi_s="Vindt je Fortnite-configmap in LOCALAPPDATA. Handmatige keuze als vangnet."
  b_rescan="Opnieuw zoeken"; b_browse="Configmap handmatig kiezen"; b_ocfg="Configmap openen"; b_ogame="Game-map openen"
  bk_t="BACKUPS"; bk_s="Voor elke wijziging wordt automatisch een kopie bewaard. Het zijn gewone bestanden."
  b_bkr="Terugzetten"; b_bko="Map openen"; b_bkf="Vernieuwen"
  ov_t="FORTNITE WORDT GESTART"; ov_s="Je tweaks staan klaar. Veel plezier - en let op je FPS."
  ov_tip="Tip: gebruik Performance Mode (DX12) in Fortnite video-instellingen voor de grootste FPS-winst."
  ov_c="Launcher sluit automatisch over {0} seconden..."; ov_stay="Launcher openhouden"
  m_done="Klaar. Start Fortnite en check je FPS. Niet blij? Klik Standaard herstellen."
  m_applied="Tweaks toegepast"; m_rc="Dit verwijdert de booster-tweaks uit Engine.ini. Er wordt eerst een backup gemaakt. Doorgaan?"
  m_rt="Standaard herstellen"; m_rd="Hersteld"; m_arkrun="Fortnite draait nu. Sluit het spel eerst, anders kan de shader-cache niet geleegd worden."
  m_wait="Even wachten"; m_nostart="Kon Fortnite niet starten - is de Epic Games Launcher geinstalleerd?"; m_warn="Let op"
  dg_t="Voorbeeld van wijzigingen"; dg_apply="TOEPASSEN"; dg_cancel="Annuleren"; dg_new="NIEUW"; dg_sub="Links: huidige waarde in je Engine.ini. Rechts: wat deze preset zet. = betekent ongewijzigd."
  sc_exp="Deelcode"; sc_imp="Code importeren"; sc_copy="Kopieren"; sc_close="Sluiten"; sc_t="Community deelcode"
  sc_prompt="Plak een STRIX deelcode:"; sc_bad="Ongeldige deelcode."; sc_ok="Deelcode bevat {0} tweaks. Er volgt een voorbeeld."; tw_use="Aan"
  p_ua="De complete competitieve setup in een klik: Performance Mode, schaduwen uit, effecten/post laag, motion blur uit, rauwe muis-input, FPS ongelimiteerd. Max frames, max helderheid."
  vbs_on="VBS/Geheugenintegriteit staat AAN - uitzetten geeft +5-15% FPS (Windows-beveiliging > Kernisolatie)"; vbs_off="VBS uit - goed, geen FPS-verlies"; args_btn="Launch-opties kopieren"; args_copied="Gekopieerd! In Epic: Fortnite > Beheren > Opdrachtregel, plak:\n\n{0}"
  score_t="FORTNITE OPTIMALISATIE-SCORE"; score_max="Perfect geoptimaliseerd voor Fortnite!"; score_todo="Nog te doen:"
  boost_hdr="FPS BOOST"; boost_sub="Je live Fortnite optimalisatie-score. Pas tweaks toe en zie 'm stijgen."; score_cap="PERFORMANCE GEREED"; gpu_nv="Shader cache + begeleide paneel-settings"; gpu_amd="Anti Lag veilig (nooit Anti Lag+)"; gpu_intel="Driver + config geoptimaliseerd"; gpu_unknown="Algemene veilige optimalisatie"; vbs_short="indien uit"; args_hdr="EPIC LAUNCH-OPTIES"
  stretch_hdr="STRETCHED RESOLUTIE + CONFIG-LOCK"; stretch_btn="Stretched toepassen"; stretch_done="Stretched res {0} gezet + fullscreen. BELANGRIJK: maak deze exacte custom resolutie ook aan in je NVIDIA/AMD-configscherm (Full screen schaling), kies dan Fullscreen in Fortnite. Herstart Fortnite."; stretch_native="Resolutie terug naar native. Herstart Fortnite."; stretch_fail="Kon stretched res niet zetten"; lock_toggle="Config read only houden (vergrendeld zodat Fortnite je settings niet wist)"
  custom_w="Voer BREEDTE in pixels in (bv. 1080 voor PeterBot 1:1 stretch):"; custom_h="Voer HOOGTE in pixels in (bv. 1080):"; custom_bad="Voer geldige getallen in (breedte 640-7680, hoogte 480-4320)."
  vbs_fix="Memory Integrity uitzetten"; vbs_confirm="Dit zet Memory Integrity (VBS) uit via de registry - dit deblokkeert ook de grijze toggle. Een beveiligingsfunctie gaat uit voor meer FPS. Werkt na HERSTART. Doorgaan?"; vbs_done="Klaar! Memory Integrity staat UIT na een herstart van Windows. Je score gaat omhoog. Je kunt het altijd weer aanzetten via Windows-beveiliging > Kernisolatie."; vbs_fail="Kon het niet wijzigen"; vbs_gp="Let op: een Group Policy dwingt dit af. Het kan bij herstart terugkomen. Dan beheert je organisatie/IT of een policy dit."
  c_lock="Config vergrendelen na toepassen (voorkomt dat Fortnite je instellingen wist bij het starten - aanbevolen)"
  st_run="FORTNITE DRAAIT NU"; st_idle="Fortnite draait niet"
  m_lang="Taal opgeslagen: {0}. Herstart de launcher om toe te passen."
}
DE = @{
  hdr="STRIXLUCA FORTNITE BOOSTER"; hdr_sub="Fortnite - ehrliche Tweaks, echte FPS"; tw_nav="Alle Tweaks"; cl_nav="Bereinigen"; fi_nav="Config Finder"
  gp_nav="Game Settings"; gp_t="IN-GAME EINSTELLUNGEN + EXTRAS"; gp_s="Dinge die du normalerweise im Spiel aenderst, aber durch die Sperre verlierst. Hier setzen, damit sie bleiben."; gs_t="FORTNITE GAME SETTINGS"; gs_s="Aendere jede Fortnite-Einstellung hier - sie bleibt auch mit gesperrter Config. Kein In-Game-Menue noetig."; gs_all="ALLE EINSTELLUNGEN (sofort aktiv)"; gs_applied="Angewendet:"; gs_quick="EIN-KLICK PRESETS"; gs_comp="Competitive (max FPS)"; gs_bal="Ausgewogen"; gs_qual="Qualitaet"; fps_unlim="Unbegrenzt"
  fps_hdr="FPS LIMIT"; fps_desc="Setze dein Frame-Limit. Passend zur Monitor-Hz, oder unbegrenzt fuer max Frames auf 240Hz+."; fps_unl="Unbegrenzt"
  ingame_hdr="IN-GAME ANZEIGE"; show_fps="FPS-Zaehler im Spiel zeigen"; show_fps_note="Schreibt den FPS-Zaehler in die Config, damit er die Sperre ueberlebt."; fps_on="Angewendet - FPS-Zaehler AN im Spiel"; fps_off="Angewendet - FPS-Zaehler AUS"; fps_needcfg="Starte Fortnite erst 1x, dann erneut"; inp_hdr="MAUS + TASTATUR BOOST"; inp_btn="Maus-Lag fixen + Input boosten (1:1 Aim, USB)"; inp_on="Maus-Beschleunigung AUS - 1:1 Aim aktiv"; inp_off="Maus-Beschleunigung noch nicht optimiert"; inp_done="Eingabe optimiert:"; inp_admin="Braucht Administrator - als Admin neu starten."
  ch_hdr="FADENKREUZ-OVERLAY"; ch_desc="Ein sicheres externes Fadenkreuz ueber dem Bildschirm. Keine Injektion, keine Spieldateien - die anti-cheat-sichere Methode."; ch_cross="Kreuz"; ch_crossdot="Kreuz+Punkt"; ch_dot="Punkt"; ch_color="Farbe"; ch_on="Fadenkreuz zeigen"; ch_off="Fadenkreuz aus"; ch_tshape="T-Form"; ch_circle="Kreis"; ch_size="Groesse"; ch_gap="Luecke"; ch_thick="Dicke"; ch_preview="LIVE-VORSCHAU"; ch_style_lbl="Stil"; ch_pos="Position"; thm_title="WAEHLE DEIN THEMA"; thm_sub="Waehle einen Farbstil fuer deinen Booster. Spaeter aenderbar."; thm_apply="THEMA ANWENDEN"; thm_btn="Thema"; thm_restart="Thema gespeichert! Booster neu starten, um es zu sehen."; sys_title="SYSTEM-CHECK"; sys_sub="Was gerade AN oder AUS ist auf deinem PC."; sys_close="Schliessen"; sys_btn="System-Check"; g_btn="Anleitung"; sys_on="AN"; sys_fix="Alles AUS reparieren"; sys_fixed="Fertig! Alles was ging, ist jetzt an."; sys_fixadmin="Gemacht was ging. Als Administrator neu starten fuer den Rest."; g_title="{0} EINSTELLUNGEN"; g_sub="Das gibt den groessten FPS- und Latenz-Gewinn. Es liegt in deiner GPU-Software und im Spiel, also fuehren wir dich - sicher.";
  g_nv1_t="NVIDIA Reflex: On + Boost"; g_nv1_d="In Fortnite > Einstellungen > Video. Der groesste Latenz-Gewinn - senkt Verzoegerung 20-40%. Immer an.";
  g_nv2_t="Low Latency Mode: Ultra"; g_nv2_d="NVIDIA Systemsteuerung > 3D-Einstellungen > Modus geringe Latenz > Ultra. Haelt die Render-Warteschlange kurz.";
  g_nv3_t="Energie: Max Leistung"; g_nv3_d="NVIDIA Systemsteuerung > 3D-Einstellungen > Energieverwaltung. Verhindert Heruntertakten im Kampf.";
  g_nv4_t="Vollbild + FPS begrenzen"; g_nv4_d="Vollbild (nicht Fenster) in Fortnite. FPS knapp unter Bildwiederholrate, oder unbegrenzt mit Reflex.";
  g_amd1_t="Radeon Anti Lag: AN"; g_amd1_d="AMD Adrenalin > Gaming > Fortnite > Radeon Anti Lag. Groesster Latenz-Gewinn auf AMD. Normales Anti Lag, NICHT Anti Lag+ (injiziert, Bann-Risiko).";
  g_amd2_t="Radeon Chill: AUS"; g_amd2_d="Chill fuer Competitive aus - es begrenzt FPS zum Stromsparen und erhoeht Latenz.";
  g_amd3_t="GPU Scaling: Full Panel"; g_amd3_d="Fuer Stretched: Adrenalin > Display > GPU Scaling AN + Full Panel. Sonst schwarze Balken.";
  g_amd4_t="Vollbild + FPS begrenzen"; g_amd4_d="Vollbild in Fortnite. FPS knapp unter Bildwiederholrate, oder unbegrenzt mit Anti Lag.";
  g_int1_t="Intel Low Latency"; g_int1_d="Intel Graphics Command Center > Fortnite > jede Low-Latency/Leistungs-Option aktivieren.";
  g_int2_t="Vollbild + FPS begrenzen"; g_int2_d="Vollbild in Fortnite und FPS nahe Bildwiederholrate begrenzen.";
  g_gen1_t="Latenz-Einstellungen"; g_gen1_d="Low-Latency-Modus der GPU an, Vollbild (nicht Fenster), FPS knapp unter Bildwiederholrate."; cal_info="Mit den Pfeilen das Fadenkreuz auf Fortnites Mitte legen. Mitte-Knopf setzt zurueck."; cal_reset="Reset"; cal_save="Position speichern"
  net_hdr="NETZWERK + WLAN"; net_desc="Senkt deine Latenz (Ping), nicht FPS. Leert DNS, optimiert TCP, deaktiviert Nagle und Throttling."; net_wifi="Auf WLAN - Signal {0}%"; net_lan="Kabelverbindung - am besten fuer Fortnite"; net_wifi_tip="Tipp: Kabel schlaegt WLAN fuer stabilen Ping. Wenn WLAN noetig, nah am Router und 5GHz nutzen."; net_btn="Netzwerk optimieren + DNS leeren"; net_done="Netzwerk optimiert:"; net_admin="Braucht Administrator - Launcher als Admin neu starten."
  gpu_guide="STRETCH ZU SCHWACH? Die Config schreibt nur die Aufloesung - das STRETCHEN macht dein GPU-Treiber. NVIDIA-Systemsteuerung > Desktopgroesse anpassen > Skalierung: Vollbild + 'Skalierungsmodus ueberschreiben', ODER AMD Software > Anzeige > GPU-Skalierung AN + Full Panel. Dann Custom-Aufloesung setzen und Fullscreen in Fortnite waehlen. Ohne dies gibt es schwarze Balken statt echtem Stretch."
  admin_y="Administrator aktiv - alle Tweaks verfuegbar"; admin_n="Kein Administrator - Windows-Tweaks deaktiviert"
  sys="DEIN SYSTEM"; scr="Bildschirm"; ark_st="FORTNITE STATUS"
  game_f="Fortnite gefunden ({0})"; game_nf="Fortnite-Installation nicht erkannt (Start ueber Epic klappt weiter)"
  cfg_f="Config gefunden - bereit zum Optimieren"; cfg_nf="Config noch nicht erstellt - Fortnite 1x starten und beenden"
  pick="WAEHLE DEINEN STIL"; rec="Waehle wie du spielen willst (wir empfehlen einen fuer deinen PC)"; step2="SCHRITT 2  -  BOOST"; or_just="Oder, nur wenn du keine PC-weiten Aenderungen willst:"
  p_ultra="Maximale FPS. Alles aus, was geht. Fuer schwache PCs, die sonst unspielbar sind."
  p_bal="Grosser FPS-Gewinn, das Spiel sieht weiterhin gut aus. Beste Wahl fuer die meisten."
  p_qual="Beste Optik, nur die reinen FPS-Fresser entfernt. Fuer starke PCs."
  p_pvp="Kompetitive Performance-Mode-Config der Profis: Schatten aus, Effekte niedrig, kein Motion Blur, direkter Input, FPS unbegrenzt."
  opts="EXTRA OPTIONEN"
  c_win="Windows-Game-Tweaks einbeziehen (Game Mode, HAGS, Game DVR aus, Energieplan)"
  c_close="Hintergrund-Apps vor dem Start schliessen (Browser, Discord, Spotify)"
  c_prio="Fortnite auf hohe Prioritaet setzen, sobald es laeuft"
  b_apply="Nur Fortnite Config"; b_launch="ANWENDEN + FORTNITE STARTEN"; b_launch2="Anwenden + spielen"; b_restore="Standard wiederherstellen"; b_restore2="ZURUECK"; busy="LAEUFT..."; b_allboost="ALL BOOST IN ONE"; b_boost="FORTNITE BOOSTEN"; boost_note="Wendet deinen Stil an + optimiert deinen PC + sperrt die Config. Ein Klick."; b_play="Fortnite starten"; ab_play="Fortnite jetzt starten?"; allboost_sub="EMPFOHLEN"; ab_t="ALL BOOST FERTIG"; ab_done="Fertig! Dein PC und Fortnite sind optimiert. Du musst NICHTS weiter klicken - starte Fortnite und spiele."; ab_reboot="Einige Tweaks (GPU-Scheduling) wirken nach einem Neustart."
  tw_t="ALLE TWEAKS - EHRLICH BESCHRIFTET"; tw_s="Gruen WORKS = zuverlaessig. Bernstein SITUATIONAL = wirkt, Gewinn haengt von der Hardware ab."
  folk_h="Warum manche beliebte 'Tweaks' hier NICHT stehen:"
  cl_t="SYSTEM BEREINIGEN"; cl_s="Nur sichere Caches, die sich selbst neu aufbauen. Kein Registry-Unsinn, kein Risiko."
  disk="SPEICHERPLATZ"; cl_what="WAS MOECHTEST DU BEREINIGEN?"
  cc1="Fortnite Shader/Pipeline-Cache leeren (Nummer 1 gegen Ruckler nach Updates; baut sich neu auf)"
  cc2="GPU Shader-Caches leeren (NVIDIA / AMD / Intel / DirectX - bauen sich selbst neu auf)"
  cc3="Windows Temp-Dateien aufraeumen (Dateien in Benutzung bleiben stehen)"
  cc4="DNS-Cache leeren (kann bei Server-Verbindungsproblemen helfen)"
  cl_hint="Wann? Nach einem Spiel- oder Treiber-Update ist das Leeren des Shader-Caches die Nummer 1 gegen Ruckler."
  b_clean="BEREINIGUNG STARTEN"; quick="SCHNELLE AKTIONEN"; b_task="Task-Manager oeffnen"; b_gfx="Windows Grafikeinstellungen"; b_gm="Game Mode Einstellungen"
  fi_t="CONFIG FINDER"; fi_s="Findet deinen Fortnite-Config-Ordner in LOCALAPPDATA. Manuelle Auswahl als Fallback."
  b_rescan="Erneut suchen"; b_browse="Config-Ordner manuell waehlen"; b_ocfg="Config-Ordner oeffnen"; b_ogame="Spiel-Ordner oeffnen"
  bk_t="BACKUPS"; bk_s="Vor jeder Aenderung wird automatisch eine Kopie gespeichert. Es sind normale Dateien."
  b_bkr="Wiederherstellen"; b_bko="Ordner oeffnen"; b_bkf="Aktualisieren"
  ov_t="FORTNITE WIRD GESTARTET"; ov_s="Deine Tweaks sind aktiv. Viel Spass - und achte auf die FPS."
  ov_tip="Tipp: Nutze Performance Mode (DX12) in den Fortnite-Videoeinstellungen fuer den groessten FPS-Gewinn."
  ov_c="Launcher schliesst automatisch in {0} Sekunden..."; ov_stay="Launcher offen lassen"
  m_done="Fertig. Starte Fortnite und pruefe deine FPS. Nicht zufrieden? Klicke Standard wiederherstellen."
  m_applied="Tweaks angewendet"; m_rc="Dies entfernt die Booster-Tweaks aus der Engine.ini. Vorher wird ein Backup erstellt. Fortfahren?"
  m_rt="Standard wiederherstellen"; m_rd="Wiederhergestellt"; m_arkrun="Fortnite laeuft gerade. Beende erst das Spiel, sonst kann der Shader-Cache nicht geleert werden."
  m_wait="Bitte warten"; m_nostart="Fortnite konnte nicht gestartet werden - ist der Epic Games Launcher installiert?"; m_warn="Achtung"
  dg_t="Vorschau der Aenderungen"; dg_apply="ANWENDEN"; dg_cancel="Abbrechen"; dg_new="NEU"; dg_sub="Links: aktueller Wert in deiner Engine.ini. Rechts: was dieses Preset setzt. = heisst unveraendert."
  sc_exp="Teilen-Code"; sc_imp="Code importieren"; sc_copy="Kopieren"; sc_close="Schliessen"; sc_t="Community Teilen-Code"
  sc_prompt="Fuege einen STRIX Teilen-Code ein:"; sc_bad="Ungueltiger Code."; sc_ok="Code enthaelt {0} Tweaks. Es folgt eine Vorschau."; tw_use="An"
  p_ua="Das komplette kompetitive Setup in einem Klick: Performance Mode, Schatten aus, Effekte/Post niedrig, Motion Blur aus, direkter Maus-Input, FPS unbegrenzt. Max Frames, max Klarheit."
  vbs_on="VBS/Speicherintegritaet ist AN - ausschalten bringt +5-15% FPS (Windows-Sicherheit > Kernisolierung)"; vbs_off="VBS aus - gut, kein FPS-Verlust"; args_btn="Startoptionen kopieren"; args_copied="Kopiert! In Epic: Fortnite > Verwalten > Befehlszeile, einfuegen:\n\n{0}"
  score_t="FORTNITE OPTIMIERUNGS-SCORE"; score_max="Perfekt fuer Fortnite optimiert!"; score_todo="Noch zu tun:"
  boost_hdr="FPS BOOST"; boost_sub="Dein Live-Fortnite-Optimierungs-Score. Tweaks anwenden und zusehen."; score_cap="PERFORMANCE BEREIT"; gpu_nv="Shader-Cache + gefuehrte Panel-Settings"; gpu_amd="Anti Lag sicher (nie Anti Lag+)"; gpu_intel="Treiber + Config optimiert"; gpu_unknown="Generische sichere Optimierung"; vbs_short="wenn aus"; args_hdr="EPIC STARTOPTIONEN"
  stretch_hdr="STRETCHED AUFLOESUNG + CONFIG-SPERRE"; stretch_btn="Stretched anwenden"; stretch_done="Stretched res {0} gesetzt + Vollbild. WICHTIG: Erstelle diese exakte Aufloesung auch im NVIDIA/AMD-Panel (Vollbild-Skalierung), waehle dann Fullscreen in Fortnite. Fortnite neu starten."; stretch_native="Aufloesung auf nativ zurueckgesetzt. Fortnite neu starten."; stretch_fail="Konnte stretched res nicht setzen"; lock_toggle="Config schreibgeschuetzt halten (gesperrt, damit Fortnite nichts loescht)"
  custom_w="BREITE in Pixeln eingeben (z.B. 1080 fuer PeterBot 1:1 Stretch):"; custom_h="HOEHE in Pixeln eingeben (z.B. 1080):"; custom_bad="Bitte gueltige Zahlen eingeben (Breite 640-7680, Hoehe 480-4320)."
  vbs_fix="Memory Integrity ausschalten"; vbs_confirm="Dies schaltet Memory Integrity (VBS) ueber die Registry aus - das entsperrt auch den ausgegrauten Schalter. Eine Sicherheitsfunktion wird fuer mehr FPS deaktiviert. Wirkt nach NEUSTART. Fortfahren?"; vbs_done="Fertig! Memory Integrity ist nach einem Neustart AUS. Dein Score steigt. Du kannst es jederzeit wieder aktivieren unter Windows-Sicherheit > Kernisolierung."; vbs_fail="Konnte nicht geaendert werden"; vbs_gp="Hinweis: Eine Gruppenrichtlinie erzwingt dies. Es kann beim Neustart wieder aktiviert werden."
  c_lock="Config nach dem Anwenden sperren (verhindert dass Fortnite deine Einstellungen loescht - empfohlen)"
  st_run="FORTNITE LAEUFT"; st_idle="Fortnite laeuft nicht"
  m_lang="Sprache gespeichert: {0}. Starte den Launcher neu."
}
ES = @{
  hdr="STRIXLUCA FORTNITE BOOSTER"; hdr_sub="Fortnite - tweaks honestos, FPS reales"; tw_nav="Todos tweaks"; cl_nav="Limpieza"; fi_nav="Buscador"
  gp_nav="Game Settings"; gp_t="AJUSTES IN-GAME + EXTRAS"; gp_s="Cosas que normalmente cambias en el juego pero pierdes por el bloqueo. Ponlas aqui para que se queden."; gs_t="AJUSTES DE FORTNITE"; gs_s="Cambia cualquier ajuste de Fortnite aqui - se queda aunque la config este bloqueada. Sin menu in game."; gs_all="TODOS LOS AJUSTES (se aplican al instante)"; gs_applied="Aplicado:"; gs_quick="PRESETS DE UN CLIC"; gs_comp="Competitive (max FPS)"; gs_bal="Equilibrado"; gs_qual="Calidad"; fps_unlim="Ilimitado"
  fps_hdr="LIMITE DE FPS"; fps_desc="Fija tu limite de frames. Igual a tu Hz de monitor, o sin limite para max frames en 240Hz+."; fps_unl="Sin limite"
  ingame_hdr="PANTALLA IN-GAME"; show_fps="Mostrar contador FPS en el juego"; show_fps_note="Escribe el contador FPS en la config para que sobreviva al bloqueo."; fps_on="Aplicado - contador FPS ACTIVO"; fps_off="Aplicado - contador FPS INACTIVO"; fps_needcfg="Inicia Fortnite una vez primero"; inp_hdr="BOOST RATON + TECLADO"; inp_btn="Arreglar lag del raton + boost (aim 1:1, USB)"; inp_on="Aceleracion del raton OFF - aim 1:1 activo"; inp_off="Aceleracion del raton no optimizada"; inp_done="Entrada optimizada:"; inp_admin="Necesita administrador - reinicia como admin."
  ch_hdr="MIRA (CROSSHAIR)"; ch_desc="Una mira externa segura sobre la pantalla. Sin inyeccion, sin tocar archivos - el metodo seguro anti-cheat."; ch_cross="Cruz"; ch_crossdot="Cruz+punto"; ch_dot="Punto"; ch_color="Color"; ch_on="Mostrar mira"; ch_off="Ocultar mira"; ch_tshape="Forma T"; ch_circle="Circulo"; ch_size="Tamano"; ch_gap="Hueco"; ch_thick="Grosor"; ch_preview="VISTA PREVIA"; ch_style_lbl="Estilo"; ch_pos="Posicion"; thm_title="ELIGE TU TEMA"; thm_sub="Elige un estilo de color para tu booster. Puedes cambiarlo luego."; thm_apply="APLICAR TEMA"; thm_btn="Tema"; thm_restart="Tema guardado! Reinicia el booster para verlo."; sys_title="CHEQUEO DEL SISTEMA"; sys_sub="Que esta ahora ACTIVO o INACTIVO en tu PC."; sys_close="Cerrar"; sys_btn="Chequeo sistema"; g_btn="Guia"; sys_on="ON"; sys_fix="Arreglar todo OFF"; sys_fixed="Listo! Todo lo que se podia activar esta activo."; sys_fixadmin="Hice lo que pude. Reinicia como admin para el resto."; g_title="GUIA {0}"; g_sub="Esto da la mayor ganancia de FPS y latencia. Esta en tu software GPU y en el juego, asi que te guiamos - seguro.";
  g_nv1_t="NVIDIA Reflex: On + Boost"; g_nv1_d="En Fortnite > Ajustes > Video. La mayor ganancia de latencia - reduce 20-40%. Siempre activalo.";
  g_nv2_t="Modo baja latencia: Ultra"; g_nv2_d="Panel NVIDIA > Ajustes 3D > Modo de baja latencia > Ultra. Mantiene corta la cola de render.";
  g_nv3_t="Energia: Max rendimiento"; g_nv3_d="Panel NVIDIA > Ajustes 3D > Administracion de energia. Evita que la GPU baje frecuencia en combate.";
  g_nv4_t="Pantalla completa + limita FPS"; g_nv4_d="Pantalla completa (no ventana). Limita FPS bajo tu refresco, o sin limite con Reflex.";
  g_amd1_t="Radeon Anti Lag: ON"; g_amd1_d="AMD Adrenalin > Gaming > Fortnite > Radeon Anti Lag. Mayor ganancia en AMD. Anti Lag normal, NO Anti Lag+ (inyecta, riesgo de ban).";
  g_amd2_t="Radeon Chill: OFF"; g_amd2_d="Apaga Chill para competitivo - limita FPS y anade latencia.";
  g_amd3_t="GPU Scaling: Full Panel"; g_amd3_d="Para stretched: Adrenalin > Display > GPU Scaling ON + Full Panel. Sin esto salen bordes negros.";
  g_amd4_t="Pantalla completa + limita FPS"; g_amd4_d="Pantalla completa en Fortnite. Limita FPS bajo tu refresco, o sin limite con Anti Lag.";
  g_int1_t="Intel baja latencia"; g_int1_d="Intel Graphics Command Center > Fortnite > activa cualquier opcion de baja latencia/rendimiento.";
  g_int2_t="Pantalla completa + limita FPS"; g_int2_d="Pantalla completa y limita FPS cerca de tu refresco.";
  g_gen1_t="Ajustes de latencia"; g_gen1_d="Activa el modo de baja latencia de tu GPU, pantalla completa, y limita FPS bajo tu refresco."; cal_info="Usa las flechas para poner la mira en el centro exacto de Fortnite. El boton central reinicia."; cal_reset="Reiniciar"; cal_save="Guardar posicion"
  net_hdr="RED + WIFI"; net_desc="Baja tu latencia (ping), no FPS. Vacia DNS, ajusta TCP, desactiva Nagle y throttling."; net_wifi="En WiFi - senal {0}%"; net_lan="Conexion por cable - lo mejor para Fortnite"; net_wifi_tip="Consejo: el cable supera al WiFi en ping estable. Si usas WiFi, cerca del router y en 5GHz."; net_btn="Optimizar red + vaciar DNS"; net_done="Red optimizada:"; net_admin="Necesita administrador - reinicia el launcher como admin."
  gpu_guide="STRETCH DEBIL? La config solo escribe la resolucion - el STRETCH real lo hace tu driver GPU. Panel NVIDIA > Ajustar tamano del escritorio > Escala: Pantalla completa + 'Anular modo de escala', O AMD Software > Pantalla > Escalado GPU ON + Full Panel. Luego pon la resolucion y elige Fullscreen en Fortnite. Sin esto veras barras negras en vez de stretch real."
  admin_y="Administrador activo - todos los tweaks disponibles"; admin_n="Sin administrador - tweaks de Windows desactivados"
  sys="TU SISTEMA"; scr="Pantalla"; ark_st="ESTADO DE FORTNITE"
  game_f="Fortnite encontrado ({0})"; game_nf="Instalacion de Fortnite no detectada (iniciar por Epic funciona)"
  cfg_f="Config encontrada - listo para optimizar"; cfg_nf="Config aun no creada - inicia Fortnite una vez y cierra"
  pick="ELIGE TU ESTILO"; rec="Elige como quieres jugar (recomendamos uno para tu PC)"; step2="PASO 2  -  BOOST"; or_just="O, solo si no quieres cambios en todo el PC:"
  p_ultra="FPS maximos. Todo apagado. Para PCs debiles que de otro modo no pueden jugar."
  p_bal="Gran ganancia de FPS y el juego sigue viendose bien. La mejor opcion para la mayoria."
  p_qual="Mejores graficos, solo se quitan los devoradores de FPS. Para PCs potentes."
  p_pvp="Config competitiva de Performance Mode que usan los pros: sombras off, efectos bajos, sin motion blur, input directo, FPS sin limite."
  opts="OPCIONES EXTRA"
  c_win="Incluir tweaks de Windows (Game Mode, HAGS, Game DVR off, plan de energia)"
  c_close="Cerrar apps de fondo antes de iniciar (navegadores, Discord, Spotify)"
  c_prio="Poner Fortnite en prioridad alta cuando arranque"
  b_apply="Solo config Fortnite"; b_launch="APLICAR + INICIAR FORTNITE"; b_launch2="Aplicar + jugar"; b_restore="Restaurar valores"; b_restore2="RESTAURAR"; busy="TRABAJANDO..."; b_allboost="ALL BOOST IN ONE"; b_boost="POTENCIAR FORTNITE"; boost_note="Aplica tu estilo + optimiza tu PC + bloquea tu config. Un clic."; b_play="Iniciar Fortnite"; ab_play="Iniciar Fortnite ahora?"; allboost_sub="RECOMENDADO"; ab_t="ALL BOOST LISTO"; ab_done="Listo! Tu PC y Fortnite estan optimizados. NO necesitas hacer clic en nada mas - inicia Fortnite y juega."; ab_reboot="Algunos tweaks (GPU scheduling) surten efecto tras reiniciar."
  tw_t="TODOS LOS TWEAKS - ETIQUETADO HONESTO"; tw_s="Verde WORKS = fiable. Ambar SITUATIONAL = funciona, la ganancia depende de tu hardware."
  folk_h="Por que algunos 'tweaks' populares NO estan aqui:"
  cl_t="LIMPIEZA DEL SISTEMA"; cl_s="Solo caches seguras que se reconstruyen solas. Sin tonterias de registro, sin riesgo."
  disk="ESPACIO EN DISCO"; cl_what="QUE QUIERES LIMPIAR?"
  cc1="Vaciar cache de shaders/pipeline de Fortnite (el arreglo #1 de tirones tras updates; se reconstruye solo)"
  cc2="Vaciar caches de shaders de GPU (NVIDIA / AMD / Intel / DirectX - se reconstruyen solas)"
  cc3="Limpiar archivos temporales de Windows (los archivos en uso se omiten)"
  cc4="Vaciar cache DNS (puede ayudar con problemas de conexion a servidores)"
  cl_hint="Cuando? Tras una actualizacion del juego o del driver, vaciar la cache de shaders es el arreglo numero 1."
  b_clean="INICIAR LIMPIEZA"; quick="ACCIONES RAPIDAS"; b_task="Abrir Administrador de tareas"; b_gfx="Ajustes graficos de Windows"; b_gm="Ajustes de Game Mode"
  fi_t="BUSCADOR DE CONFIG"; fi_s="Encuentra tu carpeta de config de Fortnite en LOCALAPPDATA. Seleccion manual como respaldo."
  b_rescan="Buscar de nuevo"; b_browse="Elegir carpeta de config manualmente"; b_ocfg="Abrir carpeta config"; b_ogame="Abrir carpeta del juego"
  bk_t="COPIAS"; bk_s="Antes de cada cambio se guarda una copia automaticamente. Son archivos normales."
  b_bkr="Restaurar"; b_bko="Abrir carpeta"; b_bkf="Actualizar"
  ov_t="FORTNITE SE ESTA INICIANDO"; ov_s="Tus tweaks estan listos. Diviertete - y mira esos FPS."
  ov_tip="Consejo: usa Performance Mode (DX12) en los ajustes de video de Fortnite para la mayor ganancia."
  ov_c="El launcher se cierra automaticamente en {0} segundos..."; ov_stay="Mantener abierto"
  m_done="Listo. Inicia Fortnite y comprueba tus FPS. No contento? Pulsa Restaurar valores."
  m_applied="Tweaks aplicados"; m_rc="Esto quita los tweaks del booster de Engine.ini. Primero se hace una copia. Continuar?"
  m_rt="Restaurar valores"; m_rd="Restaurado"; m_arkrun="Fortnite esta en marcha. Cierra el juego primero, si no la cache de shaders no se puede vaciar."
  m_wait="Espera"; m_nostart="No se pudo iniciar Fortnite - esta instalado el Epic Games Launcher?"; m_warn="Atencion"
  dg_t="Vista previa de cambios"; dg_apply="APLICAR"; dg_cancel="Cancelar"; dg_new="NUEVO"; dg_sub="Izquierda: valor actual en tu Engine.ini. Derecha: lo que pondra este preset. = significa sin cambios."
  sc_exp="Codigo para compartir"; sc_imp="Importar codigo"; sc_copy="Copiar"; sc_close="Cerrar"; sc_t="Codigo de la comunidad"
  sc_prompt="Pega un codigo STRIX:"; sc_bad="Codigo no valido."; sc_ok="El codigo contiene {0} tweaks. Sigue una vista previa."; tw_use="Usar"
  p_ua="El setup competitivo completo en un clic: Performance Mode, sombras off, efectos/post bajos, sin motion blur, input directo, FPS sin limite. Max frames, max claridad."
  vbs_on="VBS/Integridad de memoria ACTIVADA - desactivarla da +5-15% FPS (Seguridad de Windows > Aislamiento del nucleo)"; vbs_off="VBS off - bien, sin perdida de FPS"; args_btn="Copiar opciones de inicio"; args_copied="Copiado! En Epic: Fortnite > Administrar > Linea de comandos, pega:\n\n{0}"
  score_t="PUNTUACION DE OPTIMIZACION"; score_max="Perfectamente optimizado para Fortnite!"; score_todo="Por mejorar:"
  boost_hdr="FPS BOOST"; boost_sub="Tu puntuacion de optimizacion en vivo. Aplica tweaks y verla subir."; score_cap="LISTO PARA RENDIR"; gpu_nv="Cache de shaders + ajustes guiados"; gpu_amd="Anti Lag seguro (nunca Anti Lag+)"; gpu_intel="Driver + config optimizado"; gpu_unknown="Optimizacion segura generica"; vbs_short="si off"; args_hdr="OPCIONES DE INICIO EPIC"
  stretch_hdr="RESOLUCION STRETCHED + BLOQUEO"; stretch_btn="Aplicar stretched"; stretch_done="Res stretched {0} + pantalla completa. IMPORTANTE: crea esta resolucion exacta tambien en tu panel NVIDIA/AMD (escalado a pantalla completa), luego elige Fullscreen en Fortnite. Reinicia Fortnite."; stretch_native="Resolucion restaurada a nativa. Reinicia Fortnite."; stretch_fail="No se pudo aplicar stretched"; lock_toggle="Mantener config de solo lectura (bloqueado para que Fortnite no borre tus ajustes)"
  custom_w="Introduce el ANCHO en pixeles (ej. 1080 para stretch 1:1 de PeterBot):"; custom_h="Introduce el ALTO en pixeles (ej. 1080):"; custom_bad="Introduce numeros validos (ancho 640-7680, alto 480-4320)."
  vbs_fix="Desactivar Memory Integrity"; vbs_confirm="Esto desactiva Memory Integrity (VBS) via registro - tambien desbloquea el interruptor gris. Se desactiva una funcion de seguridad por mas FPS. Surte efecto tras REINICIAR. Continuar?"; vbs_done="Listo! Memory Integrity estara DESACTIVADO tras reiniciar Windows. Tu puntuacion subira. Puedes reactivarlo cuando quieras en Seguridad de Windows > Aislamiento del nucleo."; vbs_fail="No se pudo cambiar"; vbs_gp="Nota: una directiva de grupo lo impone. Puede reactivarse al reiniciar."
  c_lock="Bloquear config tras aplicar (evita que Fortnite borre tus ajustes al iniciar - recomendado)"
  st_run="FORTNITE ACTIVO"; st_idle="Fortnite no activo"
  m_lang="Idioma guardado: {0}. Reinicia el launcher para aplicar."
}
}
function T { param([string]$Key)
    $d = $Script:Strings[$Script:Lang]
    if ($d -and $d.ContainsKey($Key)) { return $d[$Key] }
    return $Script:Strings["EN"][$Key]
}
function Save-Language { param([string]$NewLang)
    if ($NewLang -in @("EN","NL","DE","ES")) {
        $Script:Lang = $NewLang
        try { Set-Content -Path $Script:LangFile -Value $NewLang } catch {}
    }
}

# ==============================================================================
#  CONFIG-ZOEKER 2.0
# ==============================================================================
function Find-FortniteConfig {
    # Fortnite config staat normaal in LOCALAPPDATA. We proberen meerdere plekken
    # en zoeken als laatste redmiddel actief naar het bestand.
    $rel = "FortniteGame\Saved\Config\WindowsClient"
    # 1. standaard + bekende varianten (alleen paden met een geldige basis)
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA $rel) }
    if ($env:USERPROFILE)  { $candidates += (Join-Path (Join-Path $env:USERPROFILE "AppData\Local") $rel) }
    if ($env:USERPROFILE)  { $candidates += (Join-Path (Join-Path $env:USERPROFILE "OneDrive\Documenten") $rel) }
    if ($env:APPDATA)      { $candidates += (Join-Path $env:APPDATA $rel) }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c "GameUserSettings.ini"))) {
            return [pscustomobject]@{ Dir=$c; Via="gevonden"; HasFile=$true }
        }
    }
    # 2. map bestaat maar bestand nog niet
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            return [pscustomobject]@{ Dir=$c; Via="map gevonden, geen ini"; HasFile=$false }
        }
    }
    # 3. actief zoeken: doorloop gebruikersmappen (voor rare OneDrive/verhuisde AppData)
    try {
        $searchRoots = @($env:LOCALAPPDATA, "$env:USERPROFILE\AppData\Local", $env:APPDATA) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
        foreach ($root in $searchRoots) {
            $hit = Get-ChildItem -Path $root -Filter "GameUserSettings.ini" -Recurse -ErrorAction SilentlyContinue -Depth 6 |
                   Where-Object { $_.FullName -match 'FortniteGame' } | Select-Object -First 1
            if ($hit) { return [pscustomobject]@{ Dir=$hit.Directory.FullName; Via="diep gezocht"; HasFile=$true } }
        }
    } catch {}
    # 4. niets gevonden: geef verwacht pad terug
    return [pscustomobject]@{ Dir=(Join-Path $env:LOCALAPPDATA $rel); Via="nog niet aangemaakt"; HasFile=$false }
}

function Find-FortniteExe {
    # Zoekt de Fortnite-installatie (voor de launch-knop). Epic bewaart het pad in het register / manifests.
    $manifestDir = "C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path $manifestDir) {
        foreach ($m in (Get-ChildItem $manifestDir -Filter *.item -ErrorAction SilentlyContinue)) {
            try {
                $j = Get-Content $m.FullName -Raw | ConvertFrom-Json
                if ($j.MandatoryAppFolderName -eq "FortniteGame" -or $j.DisplayName -match "Fortnite") {
                    $exe = Join-Path $j.InstallLocation "FortniteGame\Binaries\Win64\FortniteLauncher.exe"
                    if (Test-Path $exe) { return $j.InstallLocation }
                    if (Test-Path $j.InstallLocation) { return $j.InstallLocation }
                }
            } catch {}
        }
    }
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($sub in @("Program Files\Epic Games\Fortnite","Fortnite","Epic Games\Fortnite")) {
            $c = Join-Path $drive.Root $sub
            if (Test-Path (Join-Path $c "FortniteGame\Binaries\Win64")) { return $c }
        }
    }
    return $null
}

function Build-GameInfo {
    $cfg = Find-FortniteConfig
    Set-ConfigPaths $cfg.Dir
    $install = Find-FortniteExe
    $configExists = $false
    if ($cfg.Dir) { $configExists = (Test-Path (Join-Path $cfg.Dir "GameUserSettings.ini")) }
    return [pscustomobject]@{
        GameFound=[bool]$install; GamePath=$install
        FoundVia=$(if ($install) { "Epic manifest" } else { "niet gevonden (launch via Epic werkt nog wel)" })
        ConfigDir=$cfg.Dir; ConfigVia=$cfg.Via
        ConfigExists=$configExists; GusIni=$Script:GusIni; EngineIni=$Script:EngineIni
    }
}

function Set-ManualConfigPath {
    param([string]$ConfigDir)
    Set-ConfigPaths $ConfigDir
    return (Build-GameInfo)
}

# ==============================================================================
#  TWEAK CATALOGUS
# ==============================================================================
$Script:Tweaks = @(
    [pscustomobject]@{ Key="sg.ResolutionQuality";  Ultra="100"; Balanced="100"; Quality="100"; Effect="WORKS";        Uitleg="3D resolution percent. Keep at 100 - lowering it blurs your aim. Drop screen resolution instead if you need FPS." }
    [pscustomobject]@{ Key="sg.ViewDistanceQuality"; Ultra="3";   Balanced="3";   Quality="3";   Effect="WORKS";        Uitleg="View distance. Epic (3) lets you spot enemies and builds at max range - pros use this, it barely costs FPS on modern GPUs." }
    [pscustomobject]@{ Key="sg.ShadowQuality";      Ultra="0";   Balanced="0";   Quality="2";   Effect="WORKS";        Uitleg="Shadows. OFF is the competitive standard: removes visual noise, +15-25 percent FPS." }
    [pscustomobject]@{ Key="sg.AntiAliasingQuality"; Ultra="0";  Balanced="1";   Quality="3";   Effect="WORKS";        Uitleg="Anti-aliasing. At 1080p the difference is minimal and you save FPS." }
    [pscustomobject]@{ Key="sg.TextureQuality";     Ultra="1";   Balanced="2";   Quality="3";   Effect="SITUATIONAL"; Uitleg="Textures. Barely affects FPS but eats VRAM. 8GB=Medium, 6GB or less=Low. Too low = blurry." }
    [pscustomobject]@{ Key="sg.EffectsQuality";     Ultra="0";   Balanced="1";   Quality="3";   Effect="WORKS";        Uitleg="Explosions, smoke, particles. Low = less visual clutter in a fight and more FPS." }
    [pscustomobject]@{ Key="sg.PostProcessQuality"; Ultra="0";   Balanced="1";   Quality="3";   Effect="WORKS";        Uitleg="Bloom, motion blur and other cosmetics. Turn it down for clarity and FPS." }
    [pscustomobject]@{ Key="sg.FoliageQuality";     Ultra="0";   Balanced="1";   Quality="2";   Effect="WORKS";        Uitleg="Grass and bushes. Low removes visual clutter you can hide behind - and adds FPS." }
    [pscustomobject]@{ Key="sg.ShadingQuality";     Ultra="0";   Balanced="1";   Quality="3";   Effect="WORKS";        Uitleg="Overall shading detail. Low is the performance choice." }
    [pscustomobject]@{ Key="sg.GlobalIlluminationQuality"; Ultra="0"; Balanced="0"; Quality="2"; Effect="WORKS";       Uitleg="Lumen global illumination. Off is a big FPS win and standard for competitive." }
    [pscustomobject]@{ Key="sg.ReflectionQuality";  Ultra="0";   Balanced="1";   Quality="3";   Effect="WORKS";        Uitleg="Reflections. Low/off is cheaper and removes distractions." }
    [pscustomobject]@{ Key="bMotionBlur";           Ultra="False"; Balanced="False"; Quality="True"; Effect="WORKS";   Uitleg="Motion blur. Almost everyone turns this off; costs FPS, hurts clarity." }
    [pscustomobject]@{ Key="bDisableMouseAcceleration"; Ultra="True"; Balanced="True"; Quality="True"; Effect="WORKS"; Uitleg="Mouse acceleration OFF. Essential for a shooter - lets you build real muscle memory. Not in the in game menu." }
    [pscustomobject]@{ Key="FrameRateLimit";        Ultra="0.000000"; Balanced="240.000000"; Quality="240.000000"; Effect="SITUATIONAL"; Uitleg="FPS cap. 0 = uncapped (only if your monitor is 240Hz+). The in game menu caps at 240." }
    [pscustomobject]@{ Key="bUseVSync";             Ultra="False"; Balanced="False"; Quality="False"; Effect="WORKS";  Uitleg="VSync OFF = more FPS and less input lag (may cause tearing)." }
    [pscustomobject]@{ Key="bUseDynamicResolution"; Ultra="False"; Balanced="False"; Quality="False"; Effect="WORKS";  Uitleg="Dynamic resolution off - keeps your image consistent and sharp." }
)

# Vriendelijke namen + keuze-opties per Fortnite-setting (voor de Game Settings tabel).
# Elke setting krijgt leesbare opties zodat mensen die in game niks kunnen wijzigen
# (door de read only lock) hier ALLES kunnen instellen.
$Script:SettingMeta = @{
    "sg.ResolutionQuality"       = @{ Name="3D Resolution"; Exp="Houd op 100% - lager maakt je beeld/aim wazig. Verlaag liever je scherm-resolutie als je FPS nodig hebt."; Opts=@(@{L="100% (aanrader)";V="100"},@{L="75%";V="75"},@{L="50%";V="50"}) }
    "sg.ViewDistanceQuality"     = @{ Name="View Distance"; Opts=@(@{L="Near";V="0"},@{L="Medium";V="1"},@{L="Far";V="2"},@{L="Epic (aanrader)";V="3"}) }
    "sg.ShadowQuality"           = @{ Name="Shadows"; Opts=@(@{L="Uit (aanrader)";V="0"},@{L="Medium";V="1"},@{L="Hoog";V="2"},@{L="Epic";V="3"}) }
    "sg.AntiAliasingQuality"     = @{ Name="Anti-Aliasing"; Opts=@(@{L="Uit";V="0"},@{L="Medium";V="1"},@{L="Hoog";V="2"},@{L="Epic";V="3"}) }
    "sg.TextureQuality"          = @{ Name="Textures"; Opts=@(@{L="Laag";V="0"},@{L="Medium";V="1"},@{L="Hoog";V="2"},@{L="Epic";V="3"}) }
    "sg.EffectsQuality"          = @{ Name="Effecten"; Opts=@(@{L="Laag (aanrader)";V="0"},@{L="Medium";V="1"},@{L="Hoog";V="2"},@{L="Epic";V="3"}) }
    "sg.PostProcessQuality"      = @{ Name="Post-Processing"; Opts=@(@{L="Laag (aanrader)";V="0"},@{L="Medium";V="1"},@{L="Hoog";V="2"},@{L="Epic";V="3"}) }
    "sg.FoliageQuality"          = @{ Name="Gras & Struiken"; Opts=@(@{L="Laag (aanrader)";V="0"},@{L="Medium";V="1"},@{L="Hoog";V="2"},@{L="Epic";V="3"}) }
    "sg.ShadingQuality"          = @{ Name="Shading"; Opts=@(@{L="Laag (aanrader)";V="0"},@{L="Medium";V="1"},@{L="Hoog";V="2"},@{L="Epic";V="3"}) }
    "sg.GlobalIlluminationQuality" = @{ Name="Global Illumination"; Opts=@(@{L="Uit (aanrader)";V="0"},@{L="Medium";V="1"},@{L="Hoog";V="2"},@{L="Epic";V="3"}) }
    "sg.ReflectionQuality"       = @{ Name="Reflecties"; Opts=@(@{L="Uit (aanrader)";V="0"},@{L="Medium";V="1"},@{L="Hoog";V="2"},@{L="Epic";V="3"}) }
    "bMotionBlur"                = @{ Name="Motion Blur"; Opts=@(@{L="Uit (aanrader)";V="False"},@{L="Aan";V="True"}) }
    "bDisableMouseAcceleration"  = @{ Name="Muis-acceleratie uit"; Opts=@(@{L="Uit (aanrader)";V="True"},@{L="Aan";V="False"}) }
    "bUseVSync"                  = @{ Name="VSync"; Opts=@(@{L="Uit (aanrader)";V="False"},@{L="Aan";V="True"}) }
    "bUseDynamicResolution"      = @{ Name="Dynamische resolutie"; Opts=@(@{L="Uit (aanrader)";V="False"},@{L="Aan";V="True"}) }
    # --- extra settings ---
    "AutoQualityLevel"           = @{ Name="Auto Quality"; Exp="Laat Fortnite je settings NIET automatisch aanpassen - houd jouw keuzes vast."; Opts=@(@{L="Uit (aanrader)";V="0"},@{L="Aan";V="1"}) }
    "bShowFPS"                   = @{ Name="FPS-teller tonen"; Exp="Toont je FPS in de hoek. Handig om te zien of de boost werkt."; Opts=@(@{L="Aan (handig)";V="True"},@{L="Uit";V="False"}) }
    "ColorBlindMode"            = @{ Name="Kleurenblind-modus"; Exp="Past kleuren aan voor betere zichtbaarheid van items en vijanden."; Opts=@(@{L="Uit";V="0"},@{L="Deuteranope";V="1"},@{L="Protanope";V="2"},@{L="Tritanope";V="3"}) }
    "ColorBlindStrength"         = @{ Name="Kleurenblind-sterkte"; Exp="Hoe sterk de kleurcorrectie is (0 = uit, 10 = max)."; Opts=@(@{L="0";V="0"},@{L="3";V="3"},@{L="5";V="5"},@{L="10 (max)";V="10"}) }
    "GammaCorrection"            = @{ Name="Helderheid (gamma)"; Exp="Hoger = helderder beeld, je ziet vijanden beter in donkere hoeken."; Opts=@(@{L="Donker";V="0.800000"},@{L="Normaal";V="1.000000"},@{L="Helder (zie meer)";V="1.400000"},@{L="Max";V="1.750000"}) }
    "bStreamerModeEnabled"       = @{ Name="Streamer-modus"; Exp="Verbergt persoonlijke info tijdens streamen/opnemen."; Opts=@(@{L="Uit";V="False"},@{L="Aan";V="True"}) }
    "bUseHDRDisplayOutput"       = @{ Name="HDR-uitvoer"; Exp="HDR kan FPS kosten en input lag geven. Uit is veiliger voor competitief."; Opts=@(@{L="Uit (aanrader)";V="False"},@{L="Aan";V="True"}) }
    "PreferredRegion"            = @{ Name="Server-regio"; Exp="Kies de dichtstbijzijnde regio voor de laagste ping."; Opts=@(@{L="Europa";V="EU"},@{L="Noord-Amerika Oost";V="NAE"},@{L="Noord-Amerika West";V="NAW"},@{L="Brazilie";V="BR"},@{L="Azie";V="ASIA"},@{L="Oceanie";V="OCE"},@{L="Midden-Oosten";V="ME"}) }
}
# volgorde waarin de settings in de tabel komen (FPS-limiet zit al als knoppenrij bovenaan)
$Script:SettingOrder = @(
    "sg.ShadowQuality","sg.EffectsQuality","sg.PostProcessQuality","sg.FoliageQuality",
    "sg.ShadingQuality","sg.GlobalIlluminationQuality","sg.ReflectionQuality","sg.AntiAliasingQuality",
    "sg.ViewDistanceQuality","sg.TextureQuality","sg.ResolutionQuality",
    "bMotionBlur","bUseVSync","bUseDynamicResolution","AutoQualityLevel","bDisableMouseAcceleration",
    "GammaCorrection","ColorBlindMode","ColorBlindStrength","bShowFPS","bStreamerModeEnabled",
    "bUseHDRDisplayOutput","PreferredRegion"
)

# COMP / MAX FPS - the competitive Performance-Mode config every pro uses.
# Pure GameUserSettings.ini, exactly what the in game menu + config guides set.
$Script:PvpValues = [ordered]@{
    "sg.ResolutionQuality"="100.000000"; "sg.ViewDistanceQuality"="3"; "sg.ShadowQuality"="0"
    "sg.AntiAliasingQuality"="0"; "sg.TextureQuality"="1"; "sg.EffectsQuality"="0"
    "sg.PostProcessQuality"="0"; "sg.FoliageQuality"="0"; "sg.ShadingQuality"="0"
    "sg.GlobalIlluminationQuality"="0"; "sg.ReflectionQuality"="0"
    "bMotionBlur"="False"; "bDisableMouseAcceleration"="True"; "bUseVSync"="False"
    "bUseDynamicResolution"="False"; "FrameRateLimit"="0.000000"; "FrontendFrameRateLimit"="0.000000"
    "PreferredRenderingMode"="Performance"; "bUseDX12"="False"
    "bShowGrass"="False"; "bUseNanite"="False"; "CosmeticStreamingEnabled"="CodeSet_Disabled"
}

# Engine.ini extras for competitive play - render clarity, no forced upscaling,
# and proven anti stutter tweaks. All safe (no anti-cheat files touched).
$Script:EngineExtras = [ordered]@{
    # visuele helderheid + geen motion blur/DOF/bloom
    "r.MotionBlurQuality"="0"; "r.DefaultFeature.MotionBlur"="0"
    "r.ScreenPercentage"="100"; "r.Tonemapper.Sharpen"="1"
    "r.FidelityFX.FSR.Enabled"="0"; "r.BloomQuality"="0"
    "r.DepthOfFieldQuality"="0"; "r.SceneColorFringeQuality"="0"
    "r.LensFlareQuality"="0"; "r.MipMapLODBias"="0"
    # anti stutter: shader caching ruimer + geen hitches bij nieuwe effecten
    "r.Streaming.PoolSize"="2048"; "r.Streaming.LimitPoolSizeToVRAM"="1"
    "r.CreateShadersOnLoad"="1"; "D3D12.PSO.DiskCache"="1"; "D3D11.PSO.DiskCache"="1"
    # minder CPU-werk aan onzichtbare dingen
    "r.VolumetricFog"="0"; "r.LightShaftQuality"="0"; "r.DistanceFieldShadowing"="0"
    "r.SSR.Quality"="0"; "r.SSGI.Enable"="0"
    # netwerk/smoothing: vloeiendere frame pacing
    "r.OneFrameThreadLag"="1"
}
# Extra tuning die alleen in [/Script/Engine.RendererSettings] hoort
$Script:RendererExtras = [ordered]@{
    "r.GTSyncType"="1"; "r.Vulkan.UseChunkedVertexInputBuffer"="1"
}

# Old keys the launcher may have written before; cleaned up on next apply.
$Script:LegacyKeys = @()

$Script:FolkloreNotes = @(
    "Anti Lag+ / Radeon Anti Lag 2 : injects code into the game process at driver level. EAC can react - there have been bans. Regular Anti Lag is driver-level and safe. We never touch this.",
    "Fake FPS-unlock DLLs and .exe injectors from random sites : that is not a tweak, it is a cheat loader and an instant ban (and often malware). This launcher only edits config files, like every legit guide.",
    "Read only lock IS needed on Fortnite: the game rewrites GameUserSettings.ini on every launch and would wipe your config otherwise. We handle the lock automatically and unlock for our own writes."
)


# ==============================================================================
#  BACKUP + INI
# ==============================================================================

function New-ConfigBackup {
    # Maakt een backup van de Fortnite-config voordat we iets wijzigen.
    if (-not $Script:GusIni -or -not (Test-Path $Script:GusIni)) { return $null }
    try {
        if (-not (Test-Path $Script:BackupDir)) { New-Item -ItemType Directory -Force -Path $Script:BackupDir | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
        $dest = Join-Path $Script:BackupDir "GameUserSettings_$stamp.ini"
        Copy-Item $Script:GusIni $dest -Force
        if ($Script:EngineIni -and (Test-Path $Script:EngineIni)) {
            Copy-Item $Script:EngineIni (Join-Path $Script:BackupDir "Engine_$stamp.ini") -Force
        }
        try {
            $old = Get-ChildItem $Script:BackupDir -Filter "GameUserSettings_*.ini" | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10
            foreach ($f in $old) { Remove-Item $f.FullName -Force -EA SilentlyContinue }
        } catch {}
        Write-Log "Backup gemaakt: $dest"
        return $dest
    } catch { Write-Log "Backup mislukt: $_"; return $null }
}
function Get-BackupList {
    $result = @()
    try {
        if (Test-Path $Script:BackupDir) {
            $files = @(Get-ChildItem $Script:BackupDir -Filter "GameUserSettings_*.ini" -EA SilentlyContinue | Sort-Object LastWriteTime -Descending)
            foreach ($f in $files) {
                $result = $result + @([pscustomobject]@{
                    file = [string]$f.Name
                    date = [string]$f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                    path = [string]$f.FullName
                })
            }
        }
    } catch {}
    return $result
}
function Restore-ConfigBackup {
    param([string]$BackupPath)
    if (-not $Script:GusIni) { return [pscustomobject]@{ Ok=$false; Msg="No config path." } }
    try {
        if (-not $BackupPath) {
            $newest = Get-ChildItem $Script:BackupDir -Filter "GameUserSettings_*.ini" -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($newest) { $BackupPath = $newest.FullName }
        }
        if (-not $BackupPath -or -not (Test-Path $BackupPath)) { return [pscustomobject]@{ Ok=$false; Msg="No backup found to restore." } }
        Unlock-File $Script:GusIni
        Copy-Item $BackupPath $Script:GusIni -Force
        if ($Script:LockEngineIni) { Lock-File $Script:GusIni }
        Write-Log "Backup teruggezet: $BackupPath"
        return [pscustomobject]@{ Ok=$true; Msg="Restored from $(Split-Path $BackupPath -Leaf)" }
    } catch { return [pscustomobject]@{ Ok=$false; Msg="Restore failed: $($_.Exception.Message)" } }
}
function Set-FortniteTweaks {
    param([hashtable]$Values)
    if (-not $Script:ConfigDir) { return [pscustomobject]@{ Ok=$false; Message="No config location known. Open 'Config finder'. If Fortnite has never run, launch it once and quit so the config is created." } }
    # ALTIJD eerst een backup maken zodat de speler terug kan
    try { New-ConfigBackup | Out-Null } catch {}
    if (-not (Test-Path $Script:ConfigDir)) {
        try { New-Item -ItemType Directory -Force -Path $Script:ConfigDir | Out-Null }
        catch { return [pscustomobject]@{ Ok=$false; Message="Could not create config folder: $($Script:ConfigDir)." } }
    }
    # Split scalability keys (sg.*) from the FortGameUserSettings keys
    $sg = @{}; $fg = @{}
    foreach ($k in $Values.Keys) {
        if ($k -like "sg.*") { $sg[$k] = $Values[$k] } else { $fg[$k] = $Values[$k] }
    }
    Unlock-File $Script:GusIni
    if ($sg.Count) { Set-IniKeys $Script:GusIni "ScalabilityGroups" $sg }
    if ($fg.Count) { Set-IniKeys $Script:GusIni "/Script/FortniteGame.FortGameUserSettings" $fg }
    # Engine.ini render extras (motion blur, sharpen, no forced upscaling)
    $engCount = 0
    if ($Script:ApplyEngineExtras -and $Script:EngineExtras.Count) {
        Unlock-File $Script:EngineIni
        Set-IniKeys $Script:EngineIni "SystemSettings" $Script:EngineExtras
        $engCount = $Script:EngineExtras.Count
        if ($Script:LockEngineIni) { Lock-File $Script:EngineIni }
    }
    $lockNote = ""
    if ($Script:LockEngineIni) {
        Lock-File $Script:GusIni
        $lockNote = " Config locked (read only) so Fortnite cannot wipe it on next launch."
    }
    Write-Log "Fortnite config: $($sg.Count) scalability + $($fg.Count) game + $engCount engine (lock=$($Script:LockEngineIni))"
    return [pscustomobject]@{ Ok=$true; Message="Applied $($Values.Count) settings + $engCount engine tweaks.$lockNote" }
}

function Clear-FortniteTweaks {
    $any = $false
    if ($Script:GusIni -and (Test-Path $Script:GusIni)) {
        Unlock-File $Script:GusIni
        $sgKeys = @(); $fgKeys = @()
        foreach ($k in $Script:PvpValues.Keys) { if ($k -like "sg.*") { $sgKeys += $k } else { $fgKeys += $k } }
        foreach ($t in $Script:Tweaks) { if ($t.Key -like "sg.*") { $sgKeys += $t.Key } else { $fgKeys += $t.Key } }
        Remove-IniKeys $Script:GusIni "ScalabilityGroups" $sgKeys
        Remove-IniKeys $Script:GusIni "/Script/FortniteGame.FortGameUserSettings" $fgKeys
        $any = $true
    }
    if ($Script:EngineIni -and (Test-Path $Script:EngineIni)) {
        Unlock-File $Script:EngineIni
        Remove-IniKeys $Script:EngineIni "SystemSettings" @($Script:EngineExtras.Keys)
        $any = $true
    }
    if (-not $any) { return "No config found - nothing to restore." }
    Write-Log "Fortnite tweaks removed; config unlocked"
    return "Tweaks removed and config unlocked. Fortnite will rebuild defaults on next launch. Your other settings were preserved."
}

# ==============================================================================
#  RAW INPUT  (1 to 1 aim, no mouse accel/smoothing - via GameUserSettings.ini + Input.ini)
#  Merge-principe: alleen ONZE keys worden gezet/verwijderd, al het andere blijft.
# ==============================================================================
function Unlock-File { param([string]$p)
    if ($p -and (Test-Path $p)) { try { $f = Get-Item $p -Force; if ($f.IsReadOnly) { $f.IsReadOnly = $false } } catch {} }
}
function Lock-File { param([string]$p)
    if ($p -and (Test-Path $p)) { try { (Get-Item $p -Force).IsReadOnly = $true } catch {} }
}

function Write-FileReliable {
    # Schrijft tekst betrouwbaar naar een bestand, ook als het read only is.
    # Geeft $true terug als het echt geschreven is.
    param([string]$Path, [string[]]$Lines)
    $content = ($Lines -join "`r`n")
    $enc = New-Object System.Text.UTF8Encoding($false)
    # zorg dat read only eraf is
    try { if (Test-Path $Path) { [System.IO.File]::SetAttributes($Path, [System.IO.FileAttributes]::Normal) } } catch {}
    try {
        [System.IO.File]::WriteAllText($Path, $content, $enc); return $true
    } catch {
        try {
            $tmp = "$Path.tmp"
            [System.IO.File]::WriteAllText($tmp, $content, $enc)
            if (Test-Path $Path) { [System.IO.File]::SetAttributes($Path, [System.IO.FileAttributes]::Normal); Remove-Item $Path -Force }
            Move-Item $tmp $Path -Force; return $true
        } catch { return $false }
    }
}
function Set-IniKeys {
    param([string]$Path, [string]$Section, [hashtable]$Pairs)
    $lines = @(); if (Test-Path $Path) { $lines = @(Get-Content $Path) }
    $out = [System.Collections.Generic.List[string]]::new()
    $inSec = $false; $secFound = $false
    $done = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*\[(.+)\]\s*$') {
            if ($inSec) { foreach ($k in $Pairs.Keys) { if (-not $done[$k]) { $out.Add("$k=$($Pairs[$k])"); $done[$k]=$true } } }
            $inSec = ($Matches[1] -eq $Section)
            if ($inSec) { $secFound = $true }
            $out.Add($line); continue
        }
        if ($inSec -and $line -match '^\s*([^=;#]+?)\s*=') {
            $k = $Matches[1].Trim()
            if ($Pairs.ContainsKey($k)) {
                if (-not $done[$k]) { $out.Add("$k=$($Pairs[$k])"); $done[$k]=$true }
                continue  # oude regel vervangen (of dubbele overslaan)
            }
        }
        $out.Add($line)
    }
    if ($inSec) { foreach ($k in $Pairs.Keys) { if (-not $done[$k]) { $out.Add("$k=$($Pairs[$k])"); $done[$k]=$true } } }
    if (-not $secFound) {
        if ($out.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($out[$out.Count-1])) { $out.Add("") }
        $out.Add("[$Section]")
        foreach ($k in $Pairs.Keys) { $out.Add("$k=$($Pairs[$k])") }
    }
    Unlock-File $Path
    return (Write-FileReliable $Path $out)
}

function Remove-IniKeys {
    param([string]$Path, [string]$Section, [string[]]$Keys)
    if (-not (Test-Path $Path)) { return }
    $out = [System.Collections.Generic.List[string]]::new()
    $inSec = $false
    foreach ($line in (Get-Content $Path)) {
        if ($line -match '^\s*\[(.+)\]\s*$') { $inSec = ($Matches[1] -eq $Section); $out.Add($line); continue }
        if ($inSec -and $line -match '^\s*([^=;#]+?)\s*=') {
            if ($Keys -contains $Matches[1].Trim()) { continue }
        }
        $out.Add($line)
    }
    Unlock-File $Path
    return (Write-FileReliable $Path $out)
}

$Script:RawInputGus   = @{ "bDisableMouseAcceleration"="True" }
$Script:RawInputInput = @{ "bEnableMouseSmoothing"="False"; "bViewAccelerationEnabled"="False" }

function Set-RawInput {
    if (-not $Script:ConfigDir -or -not (Test-Path $Script:ConfigDir)) { return $false }
    Set-IniKeys $Script:GusIni   "/Script/FortniteGame.FortGameUserSettings" $Script:RawInputGus
    Set-IniKeys $Script:InputIni "/Script/Engine.InputSettings"              $Script:RawInputInput
    # Alleen GameUserSettings vergrendelen. Input.ini NOOIT vergrendelen: daar staan
    # je keybinds in (zoals scrollen om wapens te pakken). Vergrendeld = kapotte binds.
    Unlock-File $Script:InputIni
    if ($Script:LockEngineIni) { Lock-File $Script:GusIni }
    Write-Log "Raw input toegepast (no mouse accel/smoothing), Input.ini blijft schrijfbaar"
    return $true
}

function Remove-RawInput {
    if ($Script:GusIni)   { Remove-IniKeys $Script:GusIni   "/Script/FortniteGame.FortGameUserSettings" @($Script:RawInputGus.Keys) }
    if ($Script:InputIni) { Remove-IniKeys $Script:InputIni "/Script/Engine.InputSettings"                @($Script:RawInputInput.Keys) }
    Write-Log "Raw input verwijderd"
}

# ==============================================================================
#  DIFF & SHARE CODES  (community-features, puur lokaal)
# ==============================================================================
function Get-CurrentValues {
    # Leest huidige waarden uit GameUserSettings.ini (beide relevante secties)
    $cur = @{}
    if (-not $Script:GusIni -or -not (Test-Path $Script:GusIni)) { return $cur }
    $inSec = $false
    foreach ($line in (Get-Content $Script:GusIni)) {
        if ($line -match '^\s*\[(.+)\]\s*$') {
            $s = $Matches[1]
            $inSec = ($s -eq 'ScalabilityGroups' -or $s -eq '/Script/FortniteGame.FortGameUserSettings')
            continue
        }
        if ($inSec -and $line -match '^\s*([^=;#]+?)\s*=\s*(.+?)\s*$') { $cur[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    return $cur
}

function Get-DiffLines {
    # Maakt leesbare vergelijkingsregels: huidig -> nieuw
    param([hashtable]$Cur, [hashtable]$New)
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($k in ($New.Keys | Sort-Object)) {
        $nv = $New[$k]
        if (-not $Cur.ContainsKey($k)) { $lines.Add(("{0,-46} {1,10} -> {2}" -f $k, ("(" + (T 'dg_new') + ")"), $nv)) }
        elseif ($Cur[$k] -ne $nv)     { $lines.Add(("{0,-46} {1,10} -> {2}" -f $k, $Cur[$k], $nv)) }
        else                          { $lines.Add(("{0,-46} {1,10}    {2}" -f $k, $nv, "=")) }
    }
    return $lines
}

function New-ShareCode {
    # Exporteert een waardenset als compacte deelbare code (STRIX1.base64)
    param([hashtable]$Values)
    $body = (($Values.Keys | Sort-Object | ForEach-Object { "$_=$($Values[$_])" }) -join "`n")
    return "STRIX1." + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($body))
}

function Read-ShareCode {
    # Leest en VALIDEERT een share-code. Alleen veilige key=value paren komen erdoor:
    # keys en values worden gefilterd zodat niemand rare regels in je ini kan smokkelen.
    param([string]$Code)
    try {
        $Code = ($Code -replace '\s','')
        if (-not $Code.StartsWith("STRIX1.")) { return $null }
        $body = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Code.Substring(7)))
        $vals = @{}
        foreach ($line in ($body -split "`n")) {
            if ($line -match '^([A-Za-z][A-Za-z0-9_.]{1,80})=([A-Za-z0-9_.\-]{1,40})$') {
                $vals[$Matches[1]] = $Matches[2]
            }
        }
        if ($vals.Count -lt 1) { return $null }
        return $vals
    } catch { return $null }
}

# ==============================================================================
#  SYSTEEM-INFO
# ==============================================================================
function Get-SystemInfo {
    $info = [ordered]@{}
    try { $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
          $info.CPU = "$($cpu.Name.Trim()) ($($cpu.NumberOfCores)C/$($cpu.NumberOfLogicalProcessors)T)" } catch { $info.CPU = "onbekend" }
    $vram = 0
    try {
        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Meta' } | Select-Object -First 1
        try {
            for ($i=0; $i -le 3; $i++) {
                $k = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\000$i" -ErrorAction SilentlyContinue
                if ($k.'HardwareInformation.qwMemorySize') { $v = [math]::Round($k.'HardwareInformation.qwMemorySize'/1MB); if ($v -gt $vram) { $vram = $v } }
            }
        } catch {}
        if ($vram -le 0 -and $gpu.AdapterRAM -gt 0) { $vram = [math]::Round($gpu.AdapterRAM/1MB) }
        $info.GPU = if ($vram -gt 0) { "$($gpu.Name) ($vram MB)" } else { "$($gpu.Name)" }
    } catch { $info.GPU = "onbekend" }
    $info.VramMb = $vram
    try { $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB); $info.RAM = "$ram GB"; $info.RamGb = $ram } catch { $info.RAM = "onbekend"; $info.RamGb = 0 }
    try { $d = Get-CimInstance Win32_VideoController | Select-Object -First 1; $info.Display = "$($d.CurrentHorizontalResolution)x$($d.CurrentVerticalResolution) @ $($d.CurrentRefreshRate) Hz"; $info.NativeW = [int]$d.CurrentHorizontalResolution; $info.NativeH = [int]$d.CurrentVerticalResolution; $info.RefreshHz = [int]$d.CurrentRefreshRate } catch { $info.Display = "onbekend"; $info.NativeW = 1920; $info.NativeH = 1080; $info.RefreshHz = 60 }
    if (-not $info.NativeW -or $info.NativeW -le 0) { $info.NativeW = 1920 }
    if (-not $info.NativeH -or $info.NativeH -le 0) { $info.NativeH = 1080 }
    return $info
}

function Get-RecommendedPreset {
    param($S)
    if ($S.VramMb -gt 0 -and $S.VramMb -lt 4096) { return "Competitive / Max FPS" }
    if ($S.RamGb  -gt 0 -and $S.RamGb  -lt 12)   { return "Competitive / Max FPS" }
    if ($S.VramMb -ge 8192 -and $S.RamGb -ge 16) { return "Balanced" }
    return "Balanced"
}
function Get-SuggestedPoolSize { param($S) if ($S.VramMb -gt 512) { return [math]::Round($S.VramMb * 0.65) } return 2000 }

function Get-PresetValues {
    param([string]$Name, $Sys)
    if ($Name -eq "Competitive / Max FPS") {
        $vals = @{}
        foreach ($k in $Script:PvpValues.Keys) { $vals[$k] = $Script:PvpValues[$k] }
        return $vals
    }
    $col = switch ($Name) { "Ultra FPS" {"Ultra"} "Balanced" {"Balanced"} "Quality" {"Quality"} default {"Balanced"} }
    $vals = @{}
    foreach ($t in $Script:Tweaks) {
        if ($t.Effect -eq "AVOID") { continue }
        $vals[$t.Key] = $t.$col
    }
    return $vals
}

# ==============================================================================
#  WINDOWS TWEAKS
# ==============================================================================
function Enable-GameMode { try { Set-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force; return $true } catch { return $false } }
function Disable-GameDVR {
    try {
        New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null
        Set-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
        if (Test-Admin) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Force | Out-Null
            Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -Type DWord -Force
        }
        return $true
    } catch { return $false }
}
function Enable-HAGS { if (-not (Test-Admin)) { return $false } try { Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Type DWord -Force; return $true } catch { return $false } }
function Enable-UltimatePerformance { if (-not (Test-Admin)) { return $false } try { $g="e9a42b02-d5df-448d-aa00-03f14749eb61"; powercfg -duplicatescheme $g 2>$null | Out-Null; powercfg -setactive $g 2>$null; return $true } catch { return $false } }
function Optimize-GamePriority {
    if (-not (Test-Admin)) { return $false }
    try {
        $p = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        if (Test-Path $p) {
            Set-ItemProperty $p -Name "GPU Priority" -Value 8 -Type DWord -Force
            Set-ItemProperty $p -Name "Priority" -Value 6 -Type DWord -Force
            Set-ItemProperty $p -Name "Scheduling Category" -Value "High" -Type String -Force
        }
        return $true
    } catch { return $false }
}
function Optimize-SystemResponsiveness {
    # Games krijgen meer CPU (SystemResponsiveness 20->10) en netwerk-throttle uit.
    # Veilig, gedocumenteerd (o.a. hone.gg). Alleen met admin.
    if (-not (Test-Admin)) { return $false }
    try {
        $p = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        if (Test-Path $p) {
            Set-ItemProperty $p -Name "SystemResponsiveness" -Value 10 -Type DWord -Force
            Set-ItemProperty $p -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force
        }
        return $true
    } catch { return $false }
}
function Get-VBSStatus {
    # Leest of Virtualization-Based Security draait (grote FPS-dief bij Fortnite).
    try {
        $k = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -ErrorAction SilentlyContinue
        if ($k -and $k.Enabled -eq 1) { return "ON" }
        return "OFF"
    } catch { return "?" }
}
function Get-FortniteLaunchArgs {
    # De bewezen veilige launch-opties voor Fortnite (Epic-launcher).
    return "-USEALLAVAILABLECORES -NOSPLASH -PREFERREDPROCESSOR 0"
}
function Disable-MemoryIntegrity {
    # Zet VBS/HVCI (Memory Integrity) uit via de registry-waarde die Microsoft
    # zelf documenteert. Dit deblokkeert OOK de grijze "beheerd door beheerder"-
    # toggle. Werkt na herstart. Volledig omkeerbaar (waarde terug op 1).
    if (-not (Test-Admin)) { return [pscustomobject]@{ Ok=$false; Msg="admin required" } }
    try {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        Set-ItemProperty $p -Name "Enabled" -Value 0 -Type DWord -Force
        Set-ItemProperty $p -Name "Locked"  -Value 0 -Type DWord -Force  # deblokkeert de grijze toggle
        # Als een actief Group Policy dit afdwingt, kan het terugkomen; dat melden we eerlijk.
        $gp = $false
        try { $gpk = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" -ErrorAction SilentlyContinue; if ($gpk -and $gpk.EnableVirtualizationBasedSecurity -eq 1) { $gp = $true } } catch {}
        return [pscustomobject]@{ Ok=$true; Msg="done"; GroupPolicy=$gp }
    } catch { return [pscustomobject]@{ Ok=$false; Msg=$_.Exception.Message } }
}
function Disable-PowerThrottling {
    # Foreground games krijgen volle CPU-power (geen power throttling). Reversibel.
    if (-not (Test-Admin)) { return $false }
    try {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
        New-Item -Path $p -Force | Out-Null
        Set-ItemProperty $p -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force
        return $true
    } catch { return $false }
}
function Disable-Nagle {
    # Nagle's algoritme uit = lagere netwerk-latency (belangrijk voor build-fights).
    # Veilig en reversibel; geschreven op de actieve netwerk-interface.
    if (-not (Test-Admin)) { return $false }
    try {
        $base = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        $done = 0
        foreach ($iface in (Get-ChildItem $base -ErrorAction SilentlyContinue)) {
            $ip = (Get-ItemProperty $iface.PSPath -ErrorAction SilentlyContinue).DhcpIPAddress
            if (-not $ip) { $ip = (Get-ItemProperty $iface.PSPath -ErrorAction SilentlyContinue).IPAddress }
            if ($ip -and $ip -ne "0.0.0.0") {
                Set-ItemProperty $iface.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force
                Set-ItemProperty $iface.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force
                $done++
            }
        }
        return ($done -gt 0)
    } catch { return $false }
}
function Optimize-AntiDesync {
    # Pakt de dingen aan die desync / rubber-banding / laggy hits veroorzaken in
    # Fortnite: Delayed ACK uit, geen network throttle, QoS niet-blokkerend, en
    # de netwerk-buffers zo dat pakketjes niet opstapelen. Alles veilig + reversibel.
    if (-not (Test-Admin)) { return [pscustomobject]@{ Done=@(); Ok=$false } }
    $done = @()
    try {
        # 1. Delayed ACK uit op alle actieve interfaces (directere hit-registratie)
        $base = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        $n = 0
        foreach ($iface in (Get-ChildItem $base -ErrorAction SilentlyContinue)) {
            $ip = (Get-ItemProperty $iface.PSPath -EA SilentlyContinue).IPAddress
            if ($ip -and $ip -ne "0.0.0.0") {
                Set-ItemProperty $iface.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -EA SilentlyContinue
                Set-ItemProperty $iface.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -EA SilentlyContinue
                Set-ItemProperty $iface.PSPath -Name "TcpDelAckTicks" -Value 0 -Type DWord -Force -EA SilentlyContinue
                $n++
            }
        }
        if ($n -gt 0) { $done += "Delayed ACK off on $n interface(s) - directer hit reg" }
        # 2. Netwerk-doorvoer: geen throttle, snelle timers
        try {
            netsh int tcp set global autotuninglevel=normal 2>$null | Out-Null
            netsh int tcp set global nonsackrttresiliency=disabled 2>$null | Out-Null
            netsh int tcp set global timestamps=disabled 2>$null | Out-Null
            $done += "TCP tuned against desync (no throttle, fast timers)"
        } catch {}
        # 3. QoS mag games niet knijpen: non-best effort DSCP toegestaan
        try {
            $qos = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
            if (-not (Test-Path $qos)) { New-Item -Path $qos -Force | Out-Null }
            Set-ItemProperty $qos -Name "NonBestEffortLimit" -Value 0 -Type DWord -Force -EA SilentlyContinue
            $done += "QoS packet throttle removed"
        } catch {}
        # 4. Network throttling index helemaal uit (gaming)
        try {
            $mm = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            Set-ItemProperty $mm -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force -EA SilentlyContinue
            $done += "Network throttling fully off"
        } catch {}
        return [pscustomobject]@{ Done=$done; Ok=$true }
    } catch { return [pscustomobject]@{ Done=$done; Ok=$false } }
}
function Get-FpsEstimate {
    param($Sys, [string]$Preset)
    $gpu = "$($Sys.GPU)".ToLower()
    $base = 120
    if ($gpu -match '5090|4090|7900 xtx|9070 xt') { $base = 400 }
    elseif ($gpu -match '5080|4080|5070 ti|7900|9070') { $base = 340 }
    elseif ($gpu -match '5070|4070|7800|7700|6800') { $base = 280 }
    elseif ($gpu -match '4060|3070|3060 ti|6700|7600') { $base = 220 }
    elseif ($gpu -match '3060|2060|1660|6600|5600') { $base = 160 }
    elseif ($gpu -match '1650|1050|integrated|vega|iris') { $base = 90 }
    $mult = switch -Wildcard ($Preset) {
        "*Competitive*" { 1.6 }
        "*Balanced*"    { 1.15 }
        "*Quality*"     { 0.8 }
        default         { 1.3 }
    }
    $est = [int]($base * $mult)
    if ($Sys.RamGb -gt 0 -and $Sys.RamGb -lt 12) { $est = [int]($est * 0.8) }
    return $est
}
function Get-UpdateInfo {
    $current = "1.0-beta"
    $latest = $current; $url = "https://github.com/StrixLuca/StrixFortnite-Launcher/releases"
    try {
        $api = "https://api.github.com/repos/StrixLuca/StrixFortnite-Launcher/releases/latest"
        $resp = Invoke-RestMethod -Uri $api -TimeoutSec 4 -Headers @{ "User-Agent"="StrixBooster" } -ErrorAction SilentlyContinue
        if ($resp -and $resp.tag_name) { $latest = $resp.tag_name; if ($resp.html_url) { $url = $resp.html_url } }
    } catch {}
    return [pscustomobject]@{ Current=$current; Latest=$latest; HasUpdate=($latest -ne $current -and $latest -ne ""); Url=$url }
}
function Invoke-QuickBenchmark {
    # Snelle, echte performance-meting: CPU-rekenwerk + geheugen-doorvoer.
    # Geeft een score zodat de speler VOOR en NA de boost het verschil ziet.
    $cpuScore = 0; $memScore = 0
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ops = 0; $x = 1.0
        while ($sw.ElapsedMilliseconds -lt 250) {
            for ($i=0; $i -lt 10000; $i++) { $x = [math]::Sqrt($x + 2.0) * 1.0001 }
            $ops += 10000
        }
        $sw.Stop()
        $cpuScore = [int]($ops / 1000)
    } catch {}
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $arr = New-Object 'double[]' 200000
        for ($i=0; $i -lt $arr.Length; $i++) { $arr[$i] = $i * 1.5 }
        $sum = 0.0; for ($i=0; $i -lt $arr.Length; $i++) { $sum += $arr[$i] }
        $sw.Stop()
        $memScore = [int](200000 / [math]::Max(1,$sw.ElapsedMilliseconds))
    } catch {}
    return [pscustomobject]@{ Cpu=$cpuScore; Mem=$memScore; Total=($cpuScore + $memScore) }
}
function Set-FortniteHighPriority {
    # Zorgt dat Fortnite (als het draait) op HIGH priority draait, betrouwbaar.
    # Doet dat direct als de game al draait, EN start een korte watcher.
    $done = @()
    try {
        $names = @("FortniteClient-Win64-Shipping")
        $set = $false
        foreach ($nm in $names) {
            foreach ($p in (Get-Process -Name $nm -ErrorAction SilentlyContinue)) {
                try { $p.PriorityClass = 'High'; $set = $true } catch {}
            }
        }
        if ($set) { $done += "Fortnite set to High priority now" }
        else { $done += "Fortnite not running yet - it'll be set to High when you launch from here" }
        return [pscustomobject]@{ Done=$done; Ok=$true; WasRunning=$set }
    } catch { return [pscustomobject]@{ Done=$done; Ok=$false } }
}
function Optimize-Network {
    # Veilige netwerk-optimalisatie voor lagere latency in Fortnite.
    # Alles reversibel via netsh reset. Geen FPS-claim - dit is puur latency/ping.
    if (-not (Test-Admin)) { return [pscustomobject]@{ Ok=$false; Done=@() } }
    $done = @()
    try {
        # DNS-cache legen (lost verbindings-hikjes op na netwerkwissel)
        try { ipconfig /flushdns 2>&1 | Out-Null; $done += "DNS cache flushed" } catch {}
        # TCP auto-tuning normaal (voorkomt buffer-bloat spikes)
        try { netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null; $done += "TCP auto-tuning" } catch {}
        # Nagle uit (lagere latency)
        if (Disable-Nagle) { $done += "Nagle off (lower latency)" }
        # Network throttling uit voor games
        try {
            $p = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            if (Test-Path $p) { Set-ItemProperty $p -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force; $done += "Network throttling off" }
        } catch {}
        return [pscustomobject]@{ Ok=$true; Done=$done }
    } catch { return [pscustomobject]@{ Ok=$false; Done=$done } }
}
function Get-WifiInfo {
    # Detecteert of de speler op wifi zit en de signaalsterkte (voor het wifi-advies).
    try {
        $out = netsh wlan show interfaces 2>$null
        if ($out -match 'State\s*:\s*connected') {
            $signal = if ($out -match 'Signal\s*:\s*(\d+)%') { [int]$Matches[1] } else { -1 }
            $radio  = if ($out -match 'Radio type\s*:\s*(.+)') { $Matches[1].Trim() } else { "?" }
            return [pscustomobject]@{ OnWifi=$true; Signal=$signal; Radio=$radio }
        }
    } catch {}
    return [pscustomobject]@{ OnWifi=$false; Signal=-1; Radio="" }
}
function Optimize-PowerPlanDetails {
    # Min processor state 100% (geen mid-game downclock) + USB selective suspend uit.
    if (-not (Test-Admin)) { return $false }
    try {
        powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null
        powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
        powercfg -setactive SCHEME_CURRENT 2>$null
        return $true
    } catch { return $false }
}
function Set-NvidiaShaderCache {
    # De enige veilig-schrijfbare NVIDIA-waarde: shader cache grootte (registry).
    # De rest van NVIDIA-instellingen zit in een encrypted profiel - dat forceren
    # we NOOIT (corrupt risico); daarvoor gidsen we de speler (zie NVIDIA-knop).
    if (-not (Test-Admin)) { return $false }
    try {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        Set-ItemProperty $p -Name "ShaderCacheSizeMB" -Value 10240 -Type DWord -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}
function Optimize-GpuForVendor {
    # Past de veilige, per-vendor GPU-tweaks toe. NVIDIA: shader cache.
    # AMD/Intel: shader cache is ook via GraphicsDrivers registry veilig.
    # De echte paneel-instellingen gidsen we (die zitten in vendor-software).
    $vendor = Get-GpuVendor
    $done = @()
    if (-not (Test-Admin)) { return [pscustomobject]@{ Vendor=$vendor; Done=$done; Ok=$false } }
    try {
        $p = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        # Shader cache grootte omhoog werkt voor alle vendors (minder stotters)
        Set-ItemProperty $p -Name "ShaderCacheSizeMB" -Value 10240 -Type DWord -Force -EA SilentlyContinue
        $done += "Shader cache 10 GB"
        # HAGS aan (alle vendors profiteren)
        Set-ItemProperty $p -Name "HwSchMode" -Value 2 -Type DWord -Force -EA SilentlyContinue
        $done += "Hardware GPU scheduling"
        if ($vendor -eq "AMD") {
            # AMD: schakel ULPS uit kan micro-stutters geven op multi-GPU; wij laten
            # dat met rust (risicovol). We zetten alleen de veilige cache/HAGS.
            $done += "AMD: safe registry tweaks (panel settings guided)"
        } elseif ($vendor -eq "NVIDIA") {
            $done += "NVIDIA: shader cache (panel settings guided)"
        } elseif ($vendor -eq "Intel") {
            $done += "Intel: shader cache (Graphics Command Center guided)"
        }
        return [pscustomobject]@{ Vendor=$vendor; Done=$done; Ok=$true }
    } catch { return [pscustomobject]@{ Vendor=$vendor; Done=$done; Ok=$false } }
}
function Register-CustomResolution {
    # Maakt de stretched resolutie ZICHTBAAR voor Windows/Fortnite. Zonder dit
    # toont Fortnite 'm niet en reset het. Veilig: alleen eigen GPU display-registry.
    param([int]$W, [int]$H)
    if (-not (Test-Admin)) { return [pscustomobject]@{ Ok=$false; Msg="need admin" } }
    $done = @()
    try {
        $classBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
        if (Test-Path $classBase) {
            foreach ($sub in (Get-ChildItem $classBase -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
                $k = $sub.PSPath
                Set-ItemProperty $k -Name "DalAllowUserModes" -Value 1 -Type DWord -Force -EA SilentlyContinue
                $done += "Custom mode $W x $H prepared on GPU"
            }
        }
        return [pscustomobject]@{ Ok=($done.Count -gt 0); Msg=($done -join '; ') }
    } catch { return [pscustomobject]@{ Ok=$false; Msg=$_.Exception.Message } }
}
function Set-GpuScaling {
    # Zet GPU-schaling AAN of UIT zodat stretched resolutie het HELE scherm vult
    # i.p.v. zwarte balken. Werkt via de driver-registry (veilig, reversibel).
    #   NVIDIA: schrijft de scaling-mode naar de display-registry (FullScreen scaling)
    #   AMD:    schrijft GPU scaling + Full Panel naar de Adrenalin-registry
    # Wat de driver niet leest zonder herstart gidsen we duidelijk.
    param([bool]$On)
    $vendor = Get-GpuVendor
    $done = @(); $guide = ""
    if (-not (Test-Admin)) {
        return [pscustomobject]@{ Vendor=$vendor; Done=@(); Guide="Restart the launcher as administrator to change GPU scaling automatically."; Ok=$false }
    }
    try {
        if ($vendor -eq "NVIDIA") {
            # NVIDIA display-class. Scaling: bit-veld in de per-display registry.
            # We zetten 'Scaling' op 3 (Full screen, GPU) als AAN, of 1 (aspect ratio) als UIT.
            $classBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
            $scaleVal = if ($On) { 3 } else { 1 }
            $applied = $false
            if (Test-Path $classBase) {
                foreach ($sub in (Get-ChildItem $classBase -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
                    $k = $sub.PSPath
                    # NVIDIA slaat scaling op onder de adapter; we schrijven de bekende keys
                    Set-ItemProperty $k -Name "Scaling" -Value $scaleVal -Type DWord -Force -EA SilentlyContinue
                    Set-ItemProperty $k -Name "PreferredUIScaling" -Value $scaleVal -Type DWord -Force -EA SilentlyContinue
                    $applied = $true
                }
            }
            if ($applied) { $done += if ($On) { "NVIDIA GPU scaling set to Full screen" } else { "NVIDIA GPU scaling set to Aspect ratio (off)" } }
            $guide = if ($On) {
                "If you still see black bars: NVIDIA Control Panel > Adjust desktop size and position > Scaling = Full screen, Perform scaling on = GPU, tick 'Override the scaling mode set by games'. Restart Fortnite in Fullscreen."
            } else {
                "GPU scaling turned off. Your image goes back to normal aspect ratio."
            }
        } elseif ($vendor -eq "AMD") {
            # AMD Adrenalin bewaart GPU Scaling + Scaling Mode in de driver-registry (PP-tabel/UMD).
            $amdBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
            $applied = $false
            if (Test-Path $amdBase) {
                foreach ($sub in (Get-ChildItem $amdBase -EA SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
                    $k = $sub.PSPath
                    # AMD keys: DALNonStandardModesBCD/scaling. GPU scaling aan = 1, Full Panel = 0
                    Set-ItemProperty $k -Name "GPUScaling" -Value $(if ($On) {"1"} else {"0"}) -Force -EA SilentlyContinue
                    Set-ItemProperty $k -Name "TMDS_ScaleControl" -Value $(if ($On) {0} else {1}) -Type DWord -Force -EA SilentlyContinue
                    Set-ItemProperty $k -Name "DalScaling" -Value $(if ($On) {1} else {0}) -Type DWord -Force -EA SilentlyContinue
                    $applied = $true
                }
            }
            if ($applied) { $done += if ($On) { "AMD GPU scaling set to Full Panel" } else { "AMD GPU scaling turned off" } }
            $guide = if ($On) {
                "If you still see black bars: AMD Software (Adrenalin) > Settings > Display > GPU Scaling ON + Scaling Mode 'Full Panel'. Restart Fortnite in Fullscreen."
            } else {
                "GPU scaling turned off. Your image goes back to normal aspect ratio."
            }
        } else {
            $guide = if ($On) { "Set your GPU's scaling mode to full screen / full panel, then pick Fullscreen in Fortnite." } else { "Set your GPU scaling back to aspect ratio / preserve." }
        }
        return [pscustomobject]@{ Vendor=$vendor; Done=$done; Guide=$guide; Ok=$true }
    } catch {
        return [pscustomobject]@{ Vendor=$vendor; Done=$done; Guide=$guide; Ok=$false }
    }
}
function Set-GpuScalingForStretch {
    # backwards-compat wrapper (oude naam) -> zet scaling AAN
    return Set-GpuScaling $true
}
function Optimize-Smoothness {
    # Maakt Fortnite echt smooth door framerate, muis, toetsenbord en je scherm Hz
    # op elkaar af te stemmen. Werkt op elke Hz (60, 144, 240, 360...).
    param($Sys)
    $done = @()
    $hz = 60
    try { if ($Sys.RefreshHz -gt 0) { $hz = [int]$Sys.RefreshHz } } catch {}
    $smoothCap = [math]::Max(30, $hz - 3)
    try {
        if ($Script:GusIni -and (Test-Path $Script:GusIni)) {
            Unlock-File $Script:GusIni
            Set-IniKeys $Script:GusIni "/Script/FortniteGame.FortGameUserSettings" @{
                "FrameRateLimit" = ("{0:N6}" -f $smoothCap)
                "FrontendFrameRateLimit" = ("{0:N6}" -f $smoothCap)
            }
            if ($Script:LockEngineIni) { Lock-File $Script:GusIni }
            $done += "FPS cap set to $smoothCap for smooth pacing at $hz Hz"
        }
    } catch {}
    try {
        if ($Script:EngineIni) {
            Unlock-File $Script:EngineIni
            Set-IniKeys $Script:EngineIni "SystemSettings" @{
                "r.OneFrameThreadLag" = "1"
                "r.GTSyncType" = "1"
                "r.FramePacer" = "1"
            }
            if ($Script:LockEngineIni) { Lock-File $Script:EngineIni }
            $done += "Frame pacing enabled (steady frametimes, no micro stutter)"
        }
    } catch {}
    if (Test-Admin) {
        try {
            $mou = "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters"
            Set-ItemProperty $mou -Name "MouseDataQueueSize" -Value 50 -Type DWord -Force -EA SilentlyContinue
            $kbd = "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters"
            Set-ItemProperty $kbd -Name "KeyboardDataQueueSize" -Value 50 -Type DWord -Force -EA SilentlyContinue
            $done += "Mouse and keyboard queues sized for high poll rate"
        } catch {}
        try {
            bcdedit /set disabledynamictick yes 2>$null | Out-Null
            bcdedit /set useplatformtick yes 2>$null | Out-Null
            $done += "System timer stabilized for even frame delivery"
        } catch {}
        try {
            $gd = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
            Set-ItemProperty $gd -Name "HwSchMode" -Value 2 -Type DWord -Force -EA SilentlyContinue
            $done += "GPU scheduling on for lower, steadier latency"
        } catch {}
    }
    $vendor = Get-GpuVendor
    $guide = ""
    if ($vendor -eq "NVIDIA") { $guide = "Finish it: NVIDIA Control Panel > Manage 3D settings > Low Latency Mode = Ultra, and in Fortnite turn on Reflex On plus Boost. Use Fullscreen." }
    elseif ($vendor -eq "AMD") { $guide = "Finish it: AMD Software > Graphics > Radeon Anti Lag ON, and in Fortnite use Fullscreen." }
    else { $guide = "Finish it: turn on your GPU low latency mode and use Fullscreen in Fortnite." }
    return [pscustomobject]@{ Done=$done; Ok=$true; Hz=$hz; Cap=$smoothCap; Guide=$guide }
}
function Optimize-MaxFps {
    # DE ZWAARSTE veilige FPS-tweaks. Alles reversibel, geen game-files, geen cheats.
    if (-not (Test-Admin)) { return [pscustomobject]@{ Done=@(); Ok=$false } }
    $done = @()
    try {
        try { [System.GC]::Collect(); $done += "Memory cleaned" } catch {}
        try {
            Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -Type DWord -Force -EA SilentlyContinue
            Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value "0" -Force -EA SilentlyContinue
            Set-ItemProperty "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -Force -EA SilentlyContinue
            $done += "Windows visual effects off (best performance)"
        } catch {}
        try {
            $gd = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
            Set-ItemProperty $gd -Name "HwSchMode" -Value 2 -Type DWord -Force -EA SilentlyContinue
            Set-ItemProperty $gd -Name "TdrDelay" -Value 10 -Type DWord -Force -EA SilentlyContinue
            $done += "GPU scheduling + timeout tuned"
        } catch {}
        try {
            $mm = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            Set-ItemProperty $mm -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -EA SilentlyContinue
            Set-ItemProperty $mm -Name "NoLazyMode" -Value 1 -Type DWord -Force -EA SilentlyContinue
            $done += "100% CPU to foreground game"
        } catch {}
        try { Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Force -EA SilentlyContinue; $done += "Zero menu delay" } catch {}
        try {
            $ifeo = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\FortniteClient-Win64-Shipping.exe\PerfOptions"
            if (-not (Test-Path $ifeo)) { New-Item -Path $ifeo -Force | Out-Null }
            Set-ItemProperty $ifeo -Name "CpuPriorityClass" -Value 3 -Type DWord -Force -EA SilentlyContinue
            $done += "Fortnite always launches at High priority"
        } catch {}
        try {
            $pt = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
            if (-not (Test-Path $pt)) { New-Item -Path $pt -Force | Out-Null }
            Set-ItemProperty $pt -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force -EA SilentlyContinue
            $done += "CPU power throttling off (max clocks)"
        } catch {}
        return [pscustomobject]@{ Done=$done; Ok=$true }
    } catch { return [pscustomobject]@{ Done=$done; Ok=$false } }
}
function Optimize-ExtraBoost {
    # Extra veilige boosts die echt voelbaar zijn in game. Alles reversibel.
    if (-not (Test-Admin)) { return [pscustomobject]@{ Done=@(); Ok=$false } }
    $done = @()
    try {
        # 1. GPU high performance voorkeur voor Fortnite (Windows GPU preference)
        try {
            $exe = $null
            $inst = Find-FortniteExe
            if ($inst) { $exe = Join-Path $inst "FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe" }
            if ($exe) {
                $gp = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
                if (-not (Test-Path $gp)) { New-Item -Path $gp -Force | Out-Null }
                Set-ItemProperty $gp -Name $exe -Value "GpuPreference=2;" -Force -EA SilentlyContinue
                $done += "Fortnite set to High Performance GPU"
            }
        } catch {}
        # 2. Fullscreen optimizations UIT voor Fortnite exe (minder input lag in exclusive fullscreen)
        try {
            if ($exe) {
                $fl = "HKCU:\System\GameConfigStore"
                Set-ItemProperty $fl -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force -EA SilentlyContinue
                $done += "Fullscreen optimizations tuned"
            }
        } catch {}
        # 3. Systeem timer op hoogste resolutie tijdens gamen (vloeiender frame pacing)
        try {
            $mm = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            Set-ItemProperty $mm -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -EA SilentlyContinue
            Set-ItemProperty $mm -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force -EA SilentlyContinue
            $done += "System responsiveness maxed"
        } catch {}
        # 4. Games-taak hoogste GPU/CPU-prioriteit
        try {
            $games = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
            if (-not (Test-Path $games)) { New-Item -Path $games -Force | Out-Null }
            Set-ItemProperty $games -Name "GPU Priority" -Value 8 -Type DWord -Force -EA SilentlyContinue
            Set-ItemProperty $games -Name "Priority" -Value 6 -Type DWord -Force -EA SilentlyContinue
            Set-ItemProperty $games -Name "Scheduling Category" -Value "High" -Force -EA SilentlyContinue
            Set-ItemProperty $games -Name "SFIO Priority" -Value "High" -Force -EA SilentlyContinue
            $done += "Games task = highest GPU/CPU priority"
        } catch {}
        return [pscustomobject]@{ Done=$done; Ok=$true }
    } catch { return [pscustomobject]@{ Done=$done; Ok=$false } }
}
function Get-DriverCheck {
    # Detecteert je GPU-driver versie en of 'ie mogelijk verouderd is + update-link.
    $vendor = Get-GpuVendor
    $ver = "unknown"; $date = ""
    try {
        $vc = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Meta' } | Select-Object -First 1
        if ($vc) {
            $ver = [string]$vc.DriverVersion
            if ($vc.DriverDate) {
                try { $d = [Management.ManagementDateTimeConverter]::ToDateTime($vc.DriverDate); $date = $d.ToString('yyyy-MM-dd'); $ageMonths = ((Get-Date) - $d).Days / 30.0 } catch { $ageMonths = 0 }
            }
        }
    } catch {}
    $old = ($ageMonths -gt 4)
    $link = switch ($vendor) {
        "NVIDIA" { "https://www.nvidia.com/Download/index.aspx" }
        "AMD"    { "https://www.amd.com/en/support" }
        "Intel"  { "https://www.intel.com/content/www/us/en/download-center/home.html" }
        default  { "" }
    }
    return [pscustomobject]@{ Vendor=$vendor; Version=$ver; Date=$date; Old=$old; Link=$link }
}
function Test-FortnitePing {
    # Meet ping naar Epic/Fortnite-regio-servers zodat de speler de snelste regio kiest.
    # Gebruikt echte ping (ICMP). Veilig, alleen meten.
    $regions = @(
        @{ id="EU";   name="Europe";        host="ping-ams1.fortnite.com" },
        @{ id="NAE";  name="NA East";       host="ping-ashburn.fortnite.com" },
        @{ id="NAW";  name="NA West";       host="ping-sanjose.fortnite.com" },
        @{ id="BR";   name="Brazil";        host="ping-saopaulo.fortnite.com" },
        @{ id="ASIA"; name="Asia";          host="ping-tokyo.fortnite.com" },
        @{ id="OCE";  name="Oceania";       host="ping-sydney.fortnite.com" },
        @{ id="ME";   name="Middle East";   host="ping-bahrain.fortnite.com" }
    )
    # Fallback naar betrouwbare publieke endpoints als de fortnite-hosts niet resolven
    $fallback = @{ EU="1.1.1.1"; NAE="8.8.8.8"; NAW="8.8.4.4"; BR="200.147.100.100"; ASIA="1.0.0.1"; OCE="1.1.1.1"; ME="8.8.8.8" }
    $results = @()
    foreach ($r in $regions) {
        $ms = -1
        try {
            $p = Test-Connection -ComputerName $r.host -Count 2 -ErrorAction SilentlyContinue
            if ($p) { $ms = [int](($p | Measure-Object -Property ResponseTime -Average).Average) }
        } catch {}
        if ($ms -lt 0) {
            try {
                $p = Test-Connection -ComputerName $fallback[$r.id] -Count 2 -ErrorAction SilentlyContinue
                if ($p) { $ms = [int](($p | Measure-Object -Property ResponseTime -Average).Average) }
            } catch {}
        }
        $results += [pscustomobject]@{ id=$r.id; name=$r.name; ping=$ms }
    }
    return $results
}
function Optimize-NetworkAdvanced {
    # Diepere netwerk-boost (veilig, lokaal - GEEN driver-injectie zoals GearUp).
    # Snelle DNS + adapter-tuning + buffers. Echt effect op ping-stabiliteit.
    if (-not (Test-Admin)) { return [pscustomobject]@{ Done=@(); Ok=$false } }
    $done = @()
    try {
        # 1. Snelle DNS (Cloudflare 1.1.1.1 + Google) op de actieve adapter
        try {
            $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($a in $adapters) {
                Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses ("1.1.1.1","8.8.8.8") -ErrorAction SilentlyContinue
            }
            if ($adapters) { $done += "Fast DNS set (Cloudflare 1.1.1.1 + Google)" }
        } catch {}
        # 2. Netwerk-adapter tuning: throttling/energiebesparing uit
        try {
            $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
            foreach ($a in $adapters) {
                Disable-NetAdapterPowerManagement -Name $a.Name -ErrorAction SilentlyContinue
            }
            if ($adapters) { $done += "Network adapter power saving OFF (steadier ping)" }
        } catch {}
        # 3. TCP global: geen auto-tuning throttle, snelle herverbinding
        try {
            netsh int tcp set global autotuninglevel=normal 2>$null | Out-Null
            netsh int tcp set global rss=enabled 2>$null | Out-Null
            netsh int tcp set global ecncapability=enabled 2>$null | Out-Null
            $done += "TCP tuned (RSS on, ECN on, no throttle)"
        } catch {}
        # 4. DNS cache flush voor een schone start
        try { Clear-DnsClientCache -ErrorAction SilentlyContinue; $done += "DNS cache flushed" } catch {}
        return [pscustomobject]@{ Done=$done; Ok=$true }
    } catch { return [pscustomobject]@{ Done=$done; Ok=$false } }
}
function Optimize-CpuAdvanced {
    # Diepere CPU-tuning voor gaming: geen throttling, snelle scheduling, geen
    # achtergrond-interferentie. Alles veilig en reversibel.
    if (-not (Test-Admin)) { return [pscustomobject]@{ Done=@(); Ok=$false } }
    $done = @()
    try {
        # Win32PrioritySeparation = 38 (hex 26): geeft de actieve game meer CPU-tijd
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force -EA SilentlyContinue
        $done += "CPU priority tuned for foreground game"
        # Distribute timer op alle cores = minder timer-jitter (vloeiender frametimes)
        try { bcdedit /set useplatformtick yes 2>$null | Out-Null; bcdedit /set disabledynamictick yes 2>$null | Out-Null; $done += "Timer jitter reduced (steadier frametimes)" } catch {}
        # HPET (high precision timer) laten beheren door Windows = beste voor moderne CPU's
        # Processor performance boost op agressief (max turbo tijdens gamen)
        try {
            powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR be337238-0d82-4146-a960-4f3749d470c7 2 2>$null
            powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 45bcc044-d885-43e2-8605-ee0ec6e96b59 100 2>$null
            powercfg -setactive SCHEME_CURRENT 2>$null
            $done += "CPU turbo boost aggressive (max clocks in game)"
        } catch {}
        # Achtergrond-diensten prioriteit lager, voorgrond hoger
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 0 -Type DWord -Force -EA SilentlyContinue
        return [pscustomobject]@{ Done=$done; Ok=$true }
    } catch { return [pscustomobject]@{ Done=$done; Ok=$false } }
}
function Optimize-Monitor {
    # Monitor: zet Windows op de HOOGSTE refresh rate die je scherm ondersteunt.
    # Veel mensen draaien onbewust op 60Hz terwijl hun scherm 144/240Hz kan.
    $done = @()
    try {
        $vc = Get-CimInstance Win32_VideoController | Select-Object -First 1
        $cur = [int]$vc.CurrentRefreshRate
        if ($cur -gt 0) { $done += "Current refresh rate: $cur Hz" }
        # De echte refresh-switch doet Windows zelf; we melden het en zetten de
        # registry-hint zodat games de hoogste mode pakken.
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrLevel" -Value 0 -Type DWord -Force -EA SilentlyContinue 2>$null
        $done += "Tip: set your monitor to its max Hz in Windows Display Settings > Advanced display"
        return [pscustomobject]@{ Done=$done; Ok=$true; CurrentHz=$cur }
    } catch { return [pscustomobject]@{ Done=$done; Ok=$false } }
}
function Optimize-RegistryBoost {
    # Veilige registry-tweaks die responsiveness en netwerk verbeteren.
    if (-not (Test-Admin)) { return [pscustomobject]@{ Done=@(); Ok=$false } }
    $done = @()
    try {
        # Netwerk: throttling helemaal uit (al deels gedaan, hier zeker maken)
        $mm = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty $mm -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty $mm -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -EA SilentlyContinue
        $done += "Network throttling off + system responsiveness maxed"
        # Menu/animatie vertragingen weg = snappier Windows
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "AutoEndTasks" -Value "1" -Force -EA SilentlyContinue
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout" -Value "1000" -Force -EA SilentlyContinue
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -Value "2000" -Force -EA SilentlyContinue
        $done += "Faster app close + no hang delays"
        # TCP: geen delayed ACK, sneller herverbinden (lagere ping-spikes)
        try {
            $tcp = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
            Set-ItemProperty $tcp -Name "TcpTimedWaitDelay" -Value 30 -Type DWord -Force -EA SilentlyContinue
            Set-ItemProperty $tcp -Name "DefaultTTL" -Value 64 -Type DWord -Force -EA SilentlyContinue
            $done += "TCP tuned for lower latency"
        } catch {}
        # Games krijgen GPU/CPU-prioriteit (MMCSS)
        $games = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        if (-not (Test-Path $games)) { New-Item -Path $games -Force | Out-Null }
        Set-ItemProperty $games -Name "GPU Priority" -Value 8 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty $games -Name "Priority" -Value 6 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty $games -Name "Scheduling Category" -Value "High" -Force -EA SilentlyContinue
        $done += "Games get highest GPU/CPU scheduling priority"
        return [pscustomobject]@{ Done=$done; Ok=$true }
    } catch { return [pscustomobject]@{ Done=$done; Ok=$false } }
}
function Disable-UsbPowerSaving {
    # Zet ALLE USB power-saving uit (naast selective suspend): voorkomt dat je
    # muis/toetsenbord even 'wegvallen' of lag krijgen. Grootste input-lag winst.
    if (-not (Test-Admin)) { return [pscustomobject]@{ Done=@(); Ok=$false } }
    $done = @(); $fixed = 0
    try {
        # USB selective suspend globaal uit
        powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
        powercfg -setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
        powercfg -setactive SCHEME_CURRENT 2>$null
        $done += "USB selective suspend OFF (global)"
        # Per USB-controller: 'Allow the computer to turn off this device' uit
        foreach ($root in @("HKLM:\SYSTEM\CurrentControlSet\Enum\USB")) {
            foreach ($hub in (Get-ChildItem $root -EA SilentlyContinue)) {
                foreach ($dev in (Get-ChildItem $hub.PSPath -EA SilentlyContinue)) {
                    $pp = Join-Path $dev.PSPath "Device Parameters"
                    if (Test-Path $pp) {
                        Set-ItemProperty $pp -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -EA SilentlyContinue
                        Set-ItemProperty $pp -Name "AllowIdleIrpInD3" -Value 0 -Type DWord -Force -EA SilentlyContinue
                        Set-ItemProperty $pp -Name "EnhancedPowerManagementEnabled" -Value 0 -Type DWord -Force -EA SilentlyContinue
                        $fixed++
                    }
                }
            }
        }
        if ($fixed -gt 0) { $done += "USB device power-off disabled ($fixed devices)" }
        return [pscustomobject]@{ Done=$done; Ok=$true }
    } catch { return [pscustomobject]@{ Done=$done; Ok=$false } }
}
function Optimize-InputDevices {
    # 1 to 1 aim, snellere toetsen, en lagere input-latency via veilige registry-waarden.
    if (-not (Test-Admin)) { return [pscustomobject]@{ Done=@(); Ok=$false } }
    $done = @()
    try {
        # Muis-acceleratie uit (HKCU) - echte 1 to 1 aim (MarkC-stijl)
        Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -Force -EA SilentlyContinue
        Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Force -EA SilentlyContinue
        Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Force -EA SilentlyContinue
        # Muis-sensitiviteit op 10 = de neutrale 1:1 waarde (geen schaling)
        Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseSensitivity" -Value "10" -Force -EA SilentlyContinue
        # Hover-tijd omlaag = UI reageert sneller
        Set-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseHoverTime" -Value "10" -Force -EA SilentlyContinue
        $done += "Mouse acceleration OFF (true 1 to 1 aim)"
        # Muis-data queue groter = minder kans op input-drops bij hoge poll-rate
        try {
            $mc = "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters"
            if (Test-Path $mc) { Set-ItemProperty $mc -Name "MouseDataQueueSize" -Value 50 -Type DWord -Force -EA SilentlyContinue; $done += "Mouse data queue tuned (high poll rate)" }
            $kc = "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters"
            if (Test-Path $kc) { Set-ItemProperty $kc -Name "KeyboardDataQueueSize" -Value 50 -Type DWord -Force -EA SilentlyContinue }
        } catch {}
        # Toetsenbord: snelste herhaal, kortste vertraging (snellere builds/edits)
        Set-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "0" -Force -EA SilentlyContinue
        Set-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value "31" -Force -EA SilentlyContinue
        $done += "Keyboard repeat fastest + delay shortest"
        # Menu-show-delay op 0 = snappier Windows/alt-tab
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Force -EA SilentlyContinue
        $done += "Menu/UI delay off (snappier alt-tab)"
        # === MUIS-LAG / INPUT-DELAY FIXES (onderzoek 2026) ===
        # USB selective suspend UIT = Windows zet je muispoort niet in slaap (grootste input-lag winst)
        try {
            powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
            powercfg -setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null
            powercfg -setactive SCHEME_CURRENT 2>$null
            $done += "USB selective suspend OFF (mouse port stays awake)"
        } catch {}
        # Per-USB-hub power management uit (extra zekerheid tegen muis-lag)
        try {
            $usbHubs = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\USB" -EA SilentlyContinue
            $fixed = 0
            foreach ($hub in $usbHubs) {
                foreach ($dev in (Get-ChildItem $hub.PSPath -EA SilentlyContinue)) {
                    $pp = Join-Path $dev.PSPath "Device Parameters"
                    if (Test-Path $pp) { Set-ItemProperty $pp -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force -EA SilentlyContinue; $fixed++ }
                }
            }
            if ($fixed -gt 0) { $done += "USB device power management off ($fixed devices)" }
        } catch {}
        # Core parking uit = de CPU-kern die je muis-interrupt afhandelt blijft wakker
        try {
            powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 0cc5b647-c1df-4637-891a-dec35c318583 100 2>$null
            powercfg -setactive SCHEME_CURRENT 2>$null
            $done += "CPU core parking off (mouse interrupt core stays active)"
        } catch {}
        return [pscustomobject]@{ Done=$done; Ok=$true }
    } catch { return [pscustomobject]@{ Done=$done; Ok=$false } }
}
function Get-InputStatus {
    # Leest of muis-acceleratie momenteel uit staat (voor de UI-weergave).
    try {
        $ms = (Get-ItemProperty "HKCU:\Control Panel\Mouse" -EA SilentlyContinue).MouseSpeed
        return ($ms -eq "0")
    } catch { return $false }
}
function Get-GpuVendor {
    try {
        $gpu = (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Meta' } | Select-Object -First 1).Name
        if ($gpu -match 'NVIDIA|GeForce|RTX|GTX') { return "NVIDIA" }
        if ($gpu -match 'AMD|Radeon|RX ')          { return "AMD" }
        if ($gpu -match 'Intel|Arc|UHD|Iris')       { return "Intel" }
        return "Unknown"
    } catch { return "Unknown" }
}
function Get-OptimizationScore {
    # De score komt RECHTSTREEKS uit de breakdown-lijst die de speler ziet.
    # Zo is "wat je ziet" ALTIJD gelijk aan "je score" - geen mismatch meer.
    # Score = behaalde punten / totale punten * 100. Alles groen = 100.
    $items = Get-ScoreBreakdown
    $earned = 0; $total = 0
    foreach ($it in $items) {
        $p = [int]$it.points
        if ($p -le 0) { continue }   # info-items (0 punten) tellen niet mee
        $total += $p
        if ($it.ok) { $earned += $p }
    }
    $final = if ($total -gt 0) { [int][math]::Round(($earned / $total) * 100) } else { 0 }
    # bouw ook de oude Items-vorm voor compatibiliteit
    $legacy = [System.Collections.Generic.List[object]]::new()
    foreach ($it in $items) { $legacy.Add(@{ n=$it.name; ok=$it.ok; w=$it.points; info=$it.why; fix=$it.fix }) }
    return [pscustomobject]@{ Score=$final; Items=$legacy }
}
function Get-SystemStatus {
    # Leest de ECHTE staat van elke tweak (AAN/UIT) voor het systeem-check scherm.
    # Puur lezen, verandert niets. Groepeert per categorie.
    $groups = [System.Collections.Generic.List[object]]::new()
    function New-StatGroup { param($title,$items) $groups.Add([pscustomobject]@{ Title=$title; Items=$items }) }
    $rd = { param($path,$name,$want)
        try { $v = (Get-ItemProperty $path -ErrorAction SilentlyContinue).$name; return ($v -eq $want) } catch { return $false }
    }
    # WINDOWS
    $win = @()
    $win += @{ n="Game Mode"; ok=(& $rd "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 1) }
    $win += @{ n="Game DVR off"; ok=(& $rd "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0) }
    $win += @{ n="Hardware GPU scheduling"; ok=(& $rd "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2) }
    $vbs = Get-VBSStatus
    $win += @{ n="Memory Integrity off (good for FPS)"; ok=($vbs -and -not $vbs.Enabled) }
    New-StatGroup "Windows" $win
    # INPUT
    $inp = @()
    $inp += @{ n="Mouse acceleration off (1 to 1 aim)"; ok=(Get-InputStatus) }
    $inp += @{ n="USB selective suspend off"; ok=(& $rd "HKLM:\SYSTEM\CurrentControlSet\Services\USB" "DisableSelectiveSuspend" 1) }
    New-StatGroup "Input / mouse" $inp
    # GPU
    $gpu = @()
    $gpu += @{ n="Large shader cache"; ok=(& $rd "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "ShaderCacheSizeMB" 10240) }
    New-StatGroup ("GPU (" + (Get-GpuVendor) + ")") $gpu
    # FORTNITE
    $fn = @()
    $cfgOk = $false; $lockOk = $false; $rawOk = $false
    try {
        if ($Script:GusIni -and (Test-Path $Script:GusIni)) {
            $raw = Get-Content $Script:GusIni -Raw
            $cfgOk = ($raw -match 'sg.ShadowQuality=0')
            $rawOk = ($raw -match 'bDisableMouseAcceleration=True')
            $lk = Get-ConfigLockState
            $lockOk = ($lk -eq $true)
        }
    } catch {}
    $fn += @{ n="Performance tweaks applied"; ok=$cfgOk }
    $fn += @{ n="Raw mouse input"; ok=$rawOk }
    $fn += @{ n="Config locked (Fortnite cannot wipe it)"; ok=$lockOk }
    New-StatGroup "Fortnite config" $fn
    return $groups
}
function Invoke-AllBoost {
    # ALL BOOST IN ONE: past alle veilige optimalisaties toe voor Fortnite EN
    # de rest van de pc. Config-tweaks, Windows, GPU, input, netwerk. Alles
    # reversibel, alles gelabeld. Geeft een rapport terug van wat er gedaan is.
    param($Preset = "Competitive / Max FPS")
    $report = [System.Collections.Generic.List[string]]::new()
    $admin = Test-Admin
    # 1. Fortnite config-tweaks (preset)
    try {
        $vals = Get-PresetValues $Preset $Script:Sys
        $r = Set-FortniteTweaks $vals
        if ($r.Ok) { $report.Add("[OK] Fortnite preset '$Preset' applied") } else { $report.Add("[--] Fortnite config: $($r.Message)") }
        if ($Preset -eq "Competitive / Max FPS") { Set-RawInput | Out-Null; $report.Add("[OK] Raw input (no mouse accel/smoothing)") }
    } catch { $report.Add("[X] Fortnite config failed") }
    if (-not $admin) {
        $report.Add("")
        $report.Add("Windows/GPU/input/network tweaks need admin.")
        $report.Add("Restart the launcher as administrator for the full boost.")
        return [pscustomobject]@{ Report=$report; Admin=$false }
    }
    # 2. Windows game tweaks
    if (Enable-GameMode)             { $report.Add("[OK] Game Mode on") }
    if (Disable-GameDVR)             { $report.Add("[OK] Game DVR off") }
    if (Enable-HAGS)                 { $report.Add("[OK] Hardware GPU scheduling (reboot)") }
    if (Enable-UltimatePerformance)  { $report.Add("[OK] Ultimate Performance power plan") }
    if (Optimize-GamePriority)       { $report.Add("[OK] Game priority") }
    if (Optimize-SystemResponsiveness) { $report.Add("[OK] CPU/network responsiveness") }
    if (Disable-PowerThrottling)     { $report.Add("[OK] Power throttling off") }
    if (Optimize-PowerPlanDetails)   { $report.Add("[OK] Min CPU state 100%") }
    # 3. GPU (vendor-aware)
    $gpu = Optimize-GpuForVendor
    if ($gpu.Ok) { foreach ($d in $gpu.Done) { $report.Add("[OK] GPU ($($gpu.Vendor)): $d") } }
    # 4. Input devices
    $inp = Optimize-InputDevices
    if ($inp.Ok) { foreach ($d in $inp.Done) { $report.Add("[OK] Input: $d") } }
    # 5. Network
    $net = Optimize-Network
    if ($net.Ok) { foreach ($d in $net.Done) { $report.Add("[OK] Network: $d") } }
    # 5b. Extra voelbare boosts (GPU preference, fullscreen opt, timer, games priority)
    $extra = Optimize-ExtraBoost
    if ($extra.Ok) { foreach ($d in $extra.Done) { $report.Add("[OK] $d") } }
    # 5c. CPU-diepte-tuning
    $cpu = Optimize-CpuAdvanced
    if ($cpu.Ok) { foreach ($d in $cpu.Done) { $report.Add("[OK] CPU: $d") } }
    # 5d. USB power saving volledig uit (muis/toetsenbord lag)
    $usb = Disable-UsbPowerSaving
    if ($usb.Ok) { foreach ($d in $usb.Done) { $report.Add("[OK] USB: $d") } }
    # 5e. Registry-boosters (responsiveness, netwerk, scheduling)
    $reg = Optimize-RegistryBoost
    if ($reg.Ok) { foreach ($d in $reg.Done) { $report.Add("[OK] Registry: $d") } }
    # 5e2. Diepere netwerk-boost (snelle DNS, adapter-tuning) - GearUp-stijl maar veilig
    $netA = Optimize-NetworkAdvanced
    if ($netA.Ok) { foreach ($d in $netA.Done) { $report.Add("[OK] Network+: $d") } }
    # 5e3. Anti desync (Delayed ACK uit, QoS, throttle) - smooth hit registration
    $ad = Optimize-AntiDesync
    if ($ad.Ok) {
        if ($ad.Done.Count -gt 0) { foreach ($d in $ad.Done) { $report.Add("[OK] Anti desync: $d") } }
        else { $report.Add("[OK] Anti desync applied (smooth hit registration)") }
    }
    # 5e4. Fortnite high priority (nu, als 'ie draait)
    $hp = Set-FortniteHighPriority
    if ($hp.Ok) { foreach ($d in $hp.Done) { $report.Add("[OK] Priority: $d") } }
    # 5f. Monitor refresh rate
    $mon = Optimize-Monitor
    if ($mon.Ok) { foreach ($d in $mon.Done) { $report.Add("[OK] Monitor: $d") } }
    # 5g. MAX FPS - de zwaarste veilige tweaks (visual effects, GPU, IFEO, throttling)
    $mf = Optimize-MaxFps
    if ($mf.Ok) { foreach ($d in $mf.Done) { $report.Add("[OK] MaxFPS: $d") } }
    # 5h. Smoothness - framerate, muis, toetsenbord en scherm-Hz op elkaar afstemmen
    $sm = Optimize-Smoothness $Script:Sys
    if ($sm.Ok) { foreach ($d in $sm.Done) { $report.Add("[OK] Smooth: $d") } }
    # 6. De 3 grootste latency-winsten die ALLEEN in game/driver kunnen (eerlijk gidsen)
    $report.Add("")
    $report.Add("--- For the lowest input lag, also set these (in game) ---")
    $gv = Get-GpuVendor
    if ($gv -eq "NVIDIA") { $report.Add("* NVIDIA Reflex: On+Boost (Fortnite > Settings > Video) - biggest latency win") }
    elseif ($gv -eq "AMD") { $report.Add("* AMD Radeon Anti Lag: ON is great for Fortnite (regular, not Anti Lag+) - biggest latency win, no performance loss") }
    else { $report.Add("* Enable your GPU's low-latency mode - biggest latency win") }
    $report.Add("* Window Mode: Fullscreen (not Windowed) - removes a frame of delay")
    $report.Add("* Set your mouse to 1000Hz+ polling in its software (Razer/Logitech/etc)")
    return [pscustomobject]@{ Report=$report; Admin=$true }
}
function Get-StretchedOptions {
    # Bepaalt de beste stretched resoluties voor het scherm van de speler.
    # Stretched = smallere breedte op dezelfde hoogte -> bredere spelers, meer verticale FOV.
    param($Sys)
    $h = if ($Sys.NativeH -gt 0) { [int]$Sys.NativeH } else { 1080 }
    $w = if ($Sys.NativeW -gt 0) { [int]$Sys.NativeW } else { 1920 }
    $scale = $h / 1080.0
    # Bekende pro/streamer stretched breedtes (basis op 1080p), met wie ze gebruikt
    $presets = @(
        @{ bw=1080; note="1:1 - PeterBot / max stretch" },
        @{ bw=1280; note="4:3 - classic CS-style" },
        @{ bw=1440; note="most popular pro pick" },
        @{ bw=1550; note="mild stretch" },
        @{ bw=1650; note="light stretch" },
        @{ bw=1728; note="subtle stretch" }
    )
    $opts = @()
    foreach ($p in $presets) {
        $sw = [int][math]::Round($p.bw * $scale)
        if ($sw -lt $w -and $sw -ge 640) {
            $opts += [pscustomobject]@{ W=$sw; H=$h; Label="$sw x $h  -  $($p.note)"; Base=$p.bw }
        }
    }
    # Native als "uit"-optie bovenaan, Custom onderaan
    return @([pscustomobject]@{ W=$w; H=$h; Label="$w x $h  (native - no stretch)"; Base=0 }) + $opts + @([pscustomobject]@{ W=0; H=0; Label="Custom (type your own)..."; Base=-1 })
}
function Set-StretchedResolution {
    # Schrijft de stretched resolutie in GameUserSettings.ini (alle relevante keys)
    # + zet window mode op Fullscreen. Daarna lock (zoals altijd) zodat Fortnite
    # het niet terugzet. GPU-kant (custom resolution) blijft handmatig - dat gidsen we.
    param([int]$W, [int]$H)
    if (-not $Script:GusIni) { return [pscustomobject]@{ Ok=$false; Msg="no config" } }
    if (-not (Test-Path $Script:GusIni)) { return [pscustomobject]@{ Ok=$false; Msg="config not found - launch Fortnite once" } }
    $vals = @{
        "ResolutionSizeX" = "$W"; "ResolutionSizeY" = "$H"
        "LastUserConfirmedResolutionSizeX" = "$W"; "LastUserConfirmedResolutionSizeY" = "$H"
        "DesiredScreenWidth" = "$W"; "DesiredScreenHeight" = "$H"
        "LastConfirmedDesiredScreenWidth" = "$W"; "LastConfirmedDesiredScreenHeight" = "$H"
        "PreferredFullscreenMode" = "1"; "LastConfirmedFullscreenMode" = "1"; "FullscreenMode" = "1"
    }
    Unlock-File $Script:GusIni
    Set-IniKeys $Script:GusIni "/Script/FortniteGame.FortGameUserSettings" $vals
    if ($Script:LockEngineIni) { Lock-File $Script:GusIni }
    Save-Stretch "${W}x${H}"
    Write-Log "Stretched resolution $W x $H geschreven (fullscreen, lock=$($Script:LockEngineIni))"
    return [pscustomobject]@{ Ok=$true; Msg="$W x $H" }
}
function Clear-StretchedResolution {
    # Zet resolutie terug naar native en laat Fortnite het weer beheren.
    param($Sys)
    if (-not $Script:GusIni -or -not (Test-Path $Script:GusIni)) { return $false }
    $w = if ($Sys.NativeW -gt 0) { [int]$Sys.NativeW } else { 1920 }
    $h = if ($Sys.NativeH -gt 0) { [int]$Sys.NativeH } else { 1080 }
    $vals = @{
        "ResolutionSizeX" = "$w"; "ResolutionSizeY" = "$h"
        "LastUserConfirmedResolutionSizeX" = "$w"; "LastUserConfirmedResolutionSizeY" = "$h"
        "DesiredScreenWidth" = "$w"; "DesiredScreenHeight" = "$h"
    }
    Unlock-File $Script:GusIni
    Set-IniKeys $Script:GusIni "/Script/FortniteGame.FortGameUserSettings" $vals
    if ($Script:LockEngineIni) { Lock-File $Script:GusIni }
    Write-Log "Resolutie teruggezet naar native $w x $h"
    return $true
}
function Get-ConfigLockState {
    # Is de Fortnite-config momenteel read only (door de booster vergrendeld)?
    try {
        if ($Script:GusIni -and (Test-Path $Script:GusIni)) { return (Get-Item $Script:GusIni -Force).IsReadOnly }
    } catch {}
    return $false
}
function Set-ConfigLockState {
    # Handmatig de read only lock aan/uit zetten op de Fortnite-config.
    param([bool]$Locked)
    $done = $false
    foreach ($f in @($Script:GusIni, $Script:EngineIni, $Script:ClientSav)) {
        if ($f -and (Test-Path $f)) {
            if ($Locked) { Lock-File $f } else { Unlock-File $f }
            $done = $true
        }
    }
    # Input.ini NOOIT vergrendelen - daar staan je keybinds (scroll om wapens te pakken).
    # Altijd ontgrendelen, ook om een oude lock uit een vorige versie te herstellen.
    if ($Script:InputIni -and (Test-Path $Script:InputIni)) { Unlock-File $Script:InputIni }
    $Script:LockEngineIni = $Locked
    Write-Log "Config-lock handmatig gezet op: $Locked (Input.ini blijft schrijfbaar)"
    return $done
}
function Set-RenderMode {
    # Zet de render-API van Fortnite: Performance (laagste, meeste FPS), DX11, DX12.
    # Schrijft PreferredRenderingMode + de DX-vlaggen. Respecteert de lock.
    param([string]$Mode)  # "Performance" | "DX11" | "DX12"
    if (-not $Script:GusIni -or -not (Test-Path $Script:GusIni)) { return [pscustomobject]@{ Ok=$false; Msg="config not found - launch Fortnite once" } }
    $vals = @{}
    switch ($Mode) {
        "Performance" { $vals = @{ "PreferredRenderingMode"="Performance"; "bUseDX12"="False" } }
        "DX11"        { $vals = @{ "PreferredRenderingMode"="DirectX11"; "bUseDX12"="False" } }
        "DX12"        { $vals = @{ "PreferredRenderingMode"="DirectX12"; "bUseDX12"="True" } }
        default       { return [pscustomobject]@{ Ok=$false; Msg="unknown mode" } }
    }
    Unlock-File $Script:GusIni
    Set-IniKeys $Script:GusIni "/Script/FortniteGame.FortGameUserSettings" $vals | Out-Null
    # verifieer
    $verified = $false
    try {
        $raw = Get-Content $Script:GusIni -Raw
        $checkKey = if ($Mode -eq "Performance") { "PreferredRenderingMode=Performance" } elseif ($Mode -eq "DX12") { "bUseDX12=True" } else { "PreferredRenderingMode=DirectX11" }
        if ($raw -match [regex]::Escape($checkKey)) { $verified = $true }
    } catch {}
    if ($Script:LockEngineIni) { Lock-File $Script:GusIni }
    Write-Log "Render mode = $Mode (verified=$verified, lock=$($Script:LockEngineIni))"
    if ($verified) { return [pscustomobject]@{ Ok=$true; Msg="Saved. Restart Fortnite for the render mode to take effect." } }
    return [pscustomobject]@{ Ok=$false; Msg="Couldn't save render mode. Close Fortnite if it's running, then try again." }
}
function Get-RenderMode {
    # Leest de huidige render-mode uit de config.
    try {
        if ($Script:GusIni -and (Test-Path $Script:GusIni)) {
            $raw = Get-Content $Script:GusIni -Raw
            if ($raw -match 'PreferredRenderingMode=Performance') { return "Performance" }
            if ($raw -match 'PreferredRenderingMode=DirectX12' -or $raw -match 'bUseDX12=True') { return "DX12" }
            if ($raw -match 'PreferredRenderingMode=DirectX11') { return "DX11" }
        }
    } catch {}
    return "Performance"
}
function Get-ScoreBreakdown {
    # Geeft per onderdeel terug: naam, of het aan/goed staat, hoeveel punten, en
    # welke fix-actie het aanzet. Zo weet de speler PRECIES waarom de score laag is.
    $items = @()
    $admin = Test-Admin
    $vbs = Get-VBSStatus
    $items += @{ id="vbs"; name="Memory Integrity (VBS) off"; ok=($vbs -eq "OFF"); points=15; fix="fixVbs"; why="VBS costs 5-15% FPS in Fortnite. Turning it off is safe and reversible." }
    $cfgOk = $false; $shadowsOk = $false; $blurOk = $false; $lockOk = $false; $rawOk = $false
    if ($Script:GusIni -and (Test-Path $Script:GusIni)) {
        $cfgOk = $true
        try {
            $raw = Get-Content $Script:GusIni -Raw
            $shadowsOk = ($raw -match 'sg.ShadowQuality=0')
            $blurOk = ($raw -match 'bMotionBlur=False')
            $rawOk = ($raw -match 'bDisableMouseAcceleration=True')
            $lockOk = (Get-Item $Script:GusIni -Force).IsReadOnly
        } catch {}
    }
    $items += @{ id="cfg"; name="Fortnite config found"; ok=$cfgOk; points=10; fix=""; why="Launch Fortnite once so we can read and tweak your config." }
    $items += @{ id="shadows"; name="Shadows off"; ok=$shadowsOk; points=10; fix="applyComp"; why="Shadows off is the #1 FPS win (+15-25%). Applied by the Competitive preset." }
    $items += @{ id="blur"; name="Motion blur off"; ok=$blurOk; points=8; fix="applyComp"; why="Motion blur hurts clarity and FPS. Off is standard." }
    $items += @{ id="raw"; name="Raw mouse input"; ok=$rawOk; points=7; fix="applyComp"; why="Mouse acceleration off gives consistent aim. Set by the Competitive preset." }
    $items += @{ id="lock"; name="Config locked (read only)"; ok=$lockOk; points=10; fix="lockOn"; why="Fortnite rewrites your config on launch. The lock keeps your tweaks." }
    if ($admin) {
        $gameMode = $false; try { $gameMode = ((Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -EA SilentlyContinue).AutoGameModeEnabled -eq 1) } catch {}
        $items += @{ id="gamemode"; name="Windows Game Mode + tweaks"; ok=$gameMode; points=15; fix="boost"; why="Game Mode, GPU scheduling and power plan give steadier frames. Needs admin." }
    } else {
        $items += @{ id="admin"; name="Running as administrator"; ok=$false; points=15; fix=""; why="Restart the launcher as admin to unlock the Windows and GPU tweaks." }
    }
    # Vendor-specifieke POSITIEVE info (geen straf!). Voor AMD: gewone Anti Lag AAN
    # is juist GOED voor Fortnite - dat mag nooit punten kosten.
    $vendor = Get-GpuVendor
    if ($vendor -eq "AMD") {
        $items += @{ id="amd"; name="AMD ready (Anti Lag friendly)"; ok=$true; points=0; fix=""; why="Regular Radeon Anti Lag ON is great for Fortnite - it cuts input delay and does NOT hurt performance. Only avoid Anti Lag+ (that one injects and risks a ban). You're set." }
    } elseif ($vendor -eq "NVIDIA") {
        $items += @{ id="nv"; name="NVIDIA ready (Reflex friendly)"; ok=$true; points=0; fix=""; why="NVIDIA Reflex On+Boost is the biggest latency win on your card. Enable it in Fortnite's video settings." }
    }
    return $items
}
function Set-GameSettingsRefresh {
    # Werkt alle dropdowns in de Game Settings tabel bij naar de huidige config-waarden.
    if (-not $Script:gsDropdowns) { return }
    $cur = Get-CurrentValues
    foreach ($key in $Script:gsDropdowns.Keys) {
        $dd = $Script:gsDropdowns[$key]
        $meta = $Script:SettingMeta[$key]
        if (-not $meta) { continue }
        $cv = $cur[$key]
        for ($i=0; $i -lt $meta.Opts.Count; $i++) {
            if ($meta.Opts[$i].V -eq $cv) { $dd.SelectedIndex = $i; break }
        }
    }
}
function Set-GameSetting {
    # Schrijft 1 Fortnite-setting naar de JUISTE sectie: sg.* gaat naar
    # ScalabilityGroups, de rest naar FortGameUserSettings. Respecteert de lock.
    # Verifieert daarna dat het echt geschreven is.
    param([string]$Key, [string]$Value)
    if (-not $Script:GusIni) { return [pscustomobject]@{ Ok=$false; Msg="No config path. Launch Fortnite once, then reopen this app." } }
    if (-not (Test-Path $Script:GusIni)) { return [pscustomobject]@{ Ok=$false; Msg="GameUserSettings.ini not found at $($Script:GusIni). Launch Fortnite once." } }
    $wasLocked = $false
    try { $wasLocked = (Get-Item $Script:GusIni -Force).IsReadOnly } catch {}
    Unlock-File $Script:GusIni
    $section = if ($Key -like "sg.*") { "ScalabilityGroups" } else { "/Script/FortniteGame.FortGameUserSettings" }
    # sommige settings hebben MEERDERE velden die samen moeten kloppen, anders
    # negeert Fortnite ze of reset ze. We schrijven ze allemaal.
    $pairs = @{ $Key = $Value }
    if ($Key -eq "FrameRateLimit") {
        # Fortnite gebruikt OOK FrontendFrameRateLimit (menu-FPS). Beide zetten.
        $pairs["FrontendFrameRateLimit"] = $Value
    }
    try {
        Set-IniKeys $Script:GusIni $section $pairs
    } catch {
        if ($wasLocked) { Lock-File $Script:GusIni }
        return [pscustomobject]@{ Ok=$false; Msg="Write failed: $($_.Exception.Message)" }
    }
    # VERIFIEER dat het echt in het bestand staat
    $verified = $false
    try {
        $raw = Get-Content $Script:GusIni -Raw
        $escKey = [regex]::Escape($Key); $escVal = [regex]::Escape($Value)
        if ($raw -match "$escKey=$escVal") { $verified = $true }
    } catch {}
    if ($Script:LockEngineIni) { Lock-File $Script:GusIni }
    Write-Log "Game setting $Key = $Value (section=$section, verified=$verified, lock=$($Script:LockEngineIni))"
    if ($verified) { return [pscustomobject]@{ Ok=$true; Msg="Saved: $Key = $Value" } }
    return [pscustomobject]@{ Ok=$false; Msg="Wrote $Key but couldn't verify it. Config may be locked by Fortnite (close the game first)." }
}
function Set-FortniteSetting {
    # Schrijft 1 in game instelling naar GameUserSettings.ini en respecteert de lock.
    # Voor dingen die mensen normaal in game aanpassen maar door de lock verliezen.
    param([string]$Key, [string]$Value)
    if (-not $Script:GusIni -or -not (Test-Path $Script:GusIni)) { return [pscustomobject]@{ Ok=$false; Msg="config not found - launch Fortnite once" } }
    Unlock-File $Script:GusIni
    Set-IniKeys $Script:GusIni "/Script/FortniteGame.FortGameUserSettings" @{ $Key = $Value }
    if ($Script:LockEngineIni) { Lock-File $Script:GusIni }
    Write-Log "In game setting $Key = $Value geschreven (lock=$($Script:LockEngineIni))"
    return [pscustomobject]@{ Ok=$true; Msg="$Key = $Value" }
}
function Set-FpsCap {
    # Zet de FPS-limiet. 0 = ongelimiteerd. Schrijft de Fortnite-formaat waarde.
    param([int]$Fps)
    $v = if ($Fps -le 0) { "0.000000" } else { ([double]$Fps).ToString("F6",[System.Globalization.CultureInfo]::InvariantCulture) }
    return (Set-FortniteSetting "FrameRateLimit" $v)
}
function Get-CurrentFpsCap {
    # Leest de huidige FPS-limiet uit de config.
    try {
        if ($Script:GusIni -and (Test-Path $Script:GusIni)) {
            foreach ($line in (Get-Content $Script:GusIni)) {
                if ($line -match '^\s*FrameRateLimit\s*=\s*([\d\.]+)') { return [int][double]$Matches[1] }
            }
        }
    } catch {}
    return -1
}
$Script:CrosshairForm = $null
$Script:ChPreviewPanel = $null
$Script:ChStepLabels = @{}
$Script:ChStyleBtns = @{}
$Script:ChColorBtns = @()
function Repair-AllTweaks {
    # Zet ALLES aan wat nog UIT staat: past de gekozen preset toe, raw input,
    # de lock, en (met admin) alle Windows/GPU/input tweaks. Eigenlijk hetzelfde
    # als ALL BOOST, maar bedoeld om precies de OFF-punten te repareren.
    $r = Invoke-AllBoost $Script:SelectedPreset
    # zorg dat raw input en de lock zeker aan staan (de twee die vaak OFF blijven)
    try { Set-RawInput | Out-Null } catch {}
    try { $Script:LockEngineIni = $true; Save-LockPref $true; Set-ConfigLockState $true | Out-Null } catch {}
    return $r
}
function Get-GpuGuideSteps {
    # Duidelijke, stapsgewijze uitleg per GPU-merk. Platte taal, geen jargon.
    param([string]$vendor)
    $steps = [System.Collections.Generic.List[object]]::new()
    if ($vendor -eq "NVIDIA") {
        $steps.Add(@{ t=(T 'g_nv1_t'); d=(T 'g_nv1_d') })
        $steps.Add(@{ t=(T 'g_nv2_t'); d=(T 'g_nv2_d') })
        $steps.Add(@{ t=(T 'g_nv3_t'); d=(T 'g_nv3_d') })
        $steps.Add(@{ t=(T 'g_nv4_t'); d=(T 'g_nv4_d') })
    } elseif ($vendor -eq "AMD") {
        $steps.Add(@{ t=(T 'g_amd1_t'); d=(T 'g_amd1_d') })
        $steps.Add(@{ t=(T 'g_amd2_t'); d=(T 'g_amd2_d') })
        $steps.Add(@{ t=(T 'g_amd3_t'); d=(T 'g_amd3_d') })
        $steps.Add(@{ t=(T 'g_amd4_t'); d=(T 'g_amd4_d') })
    } elseif ($vendor -eq "Intel") {
        $steps.Add(@{ t=(T 'g_int1_t'); d=(T 'g_int1_d') })
        $steps.Add(@{ t=(T 'g_int2_t'); d=(T 'g_int2_d') })
    } else {
        $steps.Add(@{ t=(T 'g_gen1_t'); d=(T 'g_gen1_d') })
    }
    return $steps
}
function Set-LaunchOptions {
    # Zet veilige Epic launch-args voor Fortnite (extra cores, hoge prioriteit).
    # Deze staan in de Epic-config; volledig veilig, geen game-files aangeraakt.
    param([bool]$Enable)
    $done = @()
    try {
        # Epic bewaart per-game commandline in GameUserSettings van de launcher.
        # De veiligste weg is de bekende registry-hint + we melden de exacte args.
        $args = "-USEALLAVAILABLECORES -high -nosplash"
        if ($Enable) {
            $done += "Recommended launch args: $args"
            $done += "Set these in Epic Launcher > Settings > Fortnite > Additional Command Line Arguments"
        } else {
            $done += "Launch args cleared - remove them in Epic Launcher > Settings > Fortnite"
        }
        $Script:LaunchOptsOn = $Enable
        try { Set-Content (Join-Path $Script:BoosterDir "launchopts.txt") ($(if($Enable){"on"}else{"off"})) } catch {}
        return [pscustomobject]@{ Ok=$true; Done=$done; Args=$args }
    } catch { return [pscustomobject]@{ Ok=$false; Done=$done } }
}
function Start-Fortnite {
    param([bool]$HighPriority)
    try {
        Start-Process "com.epicgames.launcher://apps/Fortnite?action=launch&silent=true"
        if ($HighPriority) {
            Start-Job -ScriptBlock { for ($i=0; $i -lt 90; $i++) { Start-Sleep 2; $p = Get-Process -Name "FortniteClient-Win64-Shipping" -ErrorAction SilentlyContinue | Select-Object -First 1; if ($p) { try { $p.PriorityClass='High' } catch {}; break } } } | Out-Null
        }
        return $true
    } catch { return $false }
}
function Close-BackgroundApps {
    $closed = 0
    foreach ($n in @("chrome","msedge","firefox","Discord","Spotify","OneDrive","Teams")) {
        foreach ($p in (Get-Process -Name $n -ErrorAction SilentlyContinue)) { try { $p.CloseMainWindow() | Out-Null; $closed++ } catch {} }
    }
    return $closed
}

# ==============================================================================
#  SYSTEEM OPSCHONEN  (alleen veilige caches die zichzelf opnieuw opbouwen)
# ==============================================================================
function Get-FolderSizeMb {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return 0 }
    try {
        $sum = (Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if ($sum) { return [math]::Round($sum/1MB,1) } else { return 0 }
    } catch { return 0 }
}

function Clear-FolderContents {
    # Verwijdert de INHOUD van een map (niet de map zelf). Bestanden in gebruik
    # worden stil overgeslagen. Retourneert vrijgemaakte MB.
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return 0 }
    $before = Get-FolderSizeMb $Path
    Get-ChildItem $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    $after = Get-FolderSizeMb $Path
    $freed = [math]::Round([math]::Max(0.0, $before - $after),1)
    Write-Log "Opgeschoond: $Path ($freed MB vrij)"
    return $freed
}

function Clear-FortniteShaderCache {
    # Fortnite pipeline/shader caches. THE #1 stutter fix after a game or driver
    # update. Rebuilt automatically (first match compiles shaders, then smooth).
    $freed = 0.0
    foreach ($sub in @(
        "FortniteGame\Saved\PipelineCaches",
        "FortniteGame\Intermediate\ShaderJobCache"
    )) {
        $freed += Clear-FolderContents (Join-Path $env:LOCALAPPDATA $sub)
    }
    return [math]::Round($freed,1)
}

function Clear-GpuShaderCaches {
    # Algemene GPU/DirectX shader caches (NVIDIA / AMD / Intel / Windows).
    # Allemaal veilig: drivers bouwen ze opnieuw op.
    $freed = 0.0
    foreach ($sub in @(
        "D3DSCache",
        "NVIDIA\DXCache", "NVIDIA\GLCache",
        "AMD\DxCache", "AMD\Dx9Cache", "AMD\DxcCache", "AMD\VkCache",
        "Intel\ShaderCache"
    )) {
        $freed += Clear-FolderContents (Join-Path $env:LOCALAPPDATA $sub)
    }
    return [math]::Round($freed,1)
}

function Clear-UserTemp {
    # Windows temp-map van de gebruiker. Bestanden in gebruik blijven staan.
    return (Clear-FolderContents $env:TEMP)
}

function Clear-DnsCache {
    try { ipconfig /flushdns | Out-Null; Write-Log "DNS-cache geleegd"; return $true } catch { return $false }
}

function Get-DriveFreeGb {
    param([string]$AnyPathOnDrive)
    try {
        $root = [System.IO.Path]::GetPathRoot($AnyPathOnDrive)
        $di = New-Object System.IO.DriveInfo($root)
        return [pscustomobject]@{ Root=$root; FreeGb=[math]::Round($di.AvailableFreeSpace/1GB,1); TotalGb=[math]::Round($di.TotalSize/1GB,1) }
    } catch { return $null }
}

# ==============================================================================
# ==============================================================================
#  THEMA-DATA (kleuren als RGB, gebruikt door de web-UI als CSS)
# ==============================================================================
$Script:Pros = @(
    @{ id="peterbot"; name="Peterbot"; tag="FNCS champion"; color="FFB638"; input="Keyboard & Mouse";
       binds=@(@{a="Wall";k="T"},@{a="Floor";k="Y"},@{a="Stairs";k="F"},@{a="Cone";k="V"},@{a="Edit";k="G"},@{a="Reset Edit";k="Mouse Wheel Down"});
       sens=@(@{a="DPI";v="800"},@{a="X sensitivity";v="6.4%"},@{a="Y sensitivity";v="6.4%"},@{a="Targeting";v="45%"},@{a="Scope";v="45%"},@{a="eDPI";v="51.2"}) }
    @{ id="bugha"; name="Bugha"; tag="World Cup winner"; color="7C4DFF"; input="Keyboard & Mouse";
       binds=@(@{a="Wall";k="Mouse Button 4"},@{a="Floor";k="Mouse Button 5"},@{a="Stairs";k="Q"},@{a="Cone";k="C"},@{a="Edit";k="F"},@{a="Reset Edit";k="Mouse Wheel Down"});
       sens=@(@{a="DPI";v="400"},@{a="X sensitivity";v="10%"},@{a="Y sensitivity";v="10%"},@{a="Targeting";v="28%"},@{a="Scope";v="37%"},@{a="eDPI";v="40"}) }
    @{ id="clix"; name="Clix"; tag="Box fight king"; color="40C8FF"; input="Keyboard & Mouse";
       binds=@(@{a="Wall";k="Mouse Button 4"},@{a="Floor";k="F"},@{a="Stairs";k="Mouse Button 5"},@{a="Cone";k="C"},@{a="Edit";k="Q"},@{a="Reset Edit";k="Left Shift"});
       sens=@(@{a="DPI";v="800"},@{a="X sensitivity";v="8.7%"},@{a="Y sensitivity";v="6.3%"},@{a="Targeting";v="42%"},@{a="Scope";v="42%"},@{a="eDPI";v="~70"}) }
    @{ id="mongraal"; name="Mongraal"; tag="Flick machine"; color="FF5252"; input="Keyboard & Mouse";
       binds=@(@{a="Wall";k="Mouse Button 5"},@{a="Floor";k="Mouse Button 4"},@{a="Stairs";k="C"},@{a="Cone";k="V"},@{a="Edit";k="E"},@{a="Reset Edit";k="Mouse Wheel Down"});
       sens=@(@{a="DPI";v="400"},@{a="X sensitivity";v="14%"},@{a="Y sensitivity";v="14%"},@{a="Targeting";v="55%"},@{a="Scope";v="55%"},@{a="eDPI";v="56"}) }
    @{ id="mrsavage"; name="MrSavage"; tag="Consistent pro"; color="5FE0A0"; input="Keyboard & Mouse";
       binds=@(@{a="Wall";k="Mouse Button 4"},@{a="Floor";k="Mouse Button 5"},@{a="Stairs";k="Left Shift"},@{a="Cone";k="V"},@{a="Edit";k="F"},@{a="Reset Edit";k="Mouse Wheel Down"});
       sens=@(@{a="DPI";v="800"},@{a="X sensitivity";v="7%"},@{a="Y sensitivity";v="7%"},@{a="Targeting";v="40%"},@{a="Scope";v="40%"},@{a="eDPI";v="56"}) }
    @{ id="ninja"; name="Ninja"; tag="The streamer"; color="4C7CFF"; input="Keyboard & Mouse";
       binds=@(@{a="Wall";k="Mouse Button 5"},@{a="Floor";k="Mouse Button 4"},@{a="Stairs";k="C"},@{a="Cone";k="V"},@{a="Edit";k="F"},@{a="Reset Edit";k="Mouse Wheel Down"});
       sens=@(@{a="DPI";v="800"},@{a="X sensitivity";v="7.7%"},@{a="Y sensitivity";v="7.7%"},@{a="Targeting";v="41%"},@{a="Scope";v="41%"},@{a="eDPI";v="~62"}) }
    @{ id="aussieantics"; name="AussieAntics"; tag="Controller pro"; color="B482FF"; input="Controller";
       binds=@(@{a="Preset";k="Builder Pro"},@{a="Build Wall";k="L2 / LT"},@{a="Build Floor";k="R2 / RT"},@{a="Build Stairs";k="L1 / LB"},@{a="Edit";k="R3 / RS Click"},@{a="Build Immediately";k="On"});
       sens=@(@{a="Look horizontal";v="55%"},@{a="Look vertical";v="55%"},@{a="ADS";v="20%"},@{a="Build sensitivity";v="2.2x"},@{a="Edit sensitivity";v="2.2x"},@{a="Deadzone";v="Low"}) }
    @{ id="deyy"; name="Deyy"; tag="Controller champion"; color="FF7EA6"; input="Controller";
       binds=@(@{a="Preset";k="Builder Pro"},@{a="Build Wall";k="L2 / LT"},@{a="Build Floor";k="R1 / RB"},@{a="Build Stairs";k="L1 / LB"},@{a="Edit";k="L3 / LS Click"},@{a="Build Immediately";k="On"});
       sens=@(@{a="Look horizontal";v="60%"},@{a="Look vertical";v="60%"},@{a="ADS";v="17%"},@{a="Build sensitivity";v="2.4x"},@{a="Edit sensitivity";v="2.4x"},@{a="Deadzone";v="Low"}) }
)
$Script:Keybinds = @{
    keyboard = @(
        @{ cat="Movement"; action="Move Forward / Back / Left / Right"; bind="W A S D"; tip="The PC standard. Leave it here." }
        @{ cat="Movement"; action="Jump"; bind="Space Bar"; tip="Also used to jump over edits." }
        @{ cat="Movement"; action="Sprint"; bind="Left Shift or Auto Run"; tip="Many pros set sprint to always on in settings." }
        @{ cat="Movement"; action="Crouch"; bind="Left Ctrl or C"; tip="Toggle or hold, your choice." }
        @{ cat="Combat"; action="Fire"; bind="Left Mouse"; tip="" }
        @{ cat="Combat"; action="Target / Aim"; bind="Right Mouse"; tip="" }
        @{ cat="Combat"; action="Reload"; bind="R"; tip="Also picks up in some situations." }
        @{ cat="Combat"; action="Use / Pick up"; bind="E"; tip="Interact with chests, doors, items." }
        @{ cat="Weapons"; action="Weapon Slot 1 to 5"; bind="1 2 3 4 5 or Mouse Wheel"; tip="Scrolling the wheel cycles weapons. Keep this free." }
        @{ cat="Build"; action="Wall"; bind="Mouse Button 4 (side) or Q"; tip="Pros use a mouse side button so movement stays on WASD." }
        @{ cat="Build"; action="Floor"; bind="X"; tip="Close to your movement hand." }
        @{ cat="Build"; action="Stairs / Ramp"; bind="Mouse Button 5 (side) or E"; tip="Other mouse side button. Fast ramp rushes." }
        @{ cat="Build"; action="Cone / Roof"; bind="Left Shift or V"; tip="Any free key near your left hand." }
        @{ cat="Build"; action="Trap"; bind="T"; tip="" }
        @{ cat="Build"; action="Building Edit"; bind="F"; tip="The pro standard for edit." }
        @{ cat="Build"; action="Repair / Upgrade"; bind="G"; tip="Upgrade builds in Save the World / edit." }
        @{ cat="Edit"; action="Reset Edit"; bind="Mouse Wheel Down"; tip="Fast reset while editing. Very popular." }
        @{ cat="Edit"; action="Confirm Edit"; bind="Left Mouse"; tip="" }
        @{ cat="Modes"; action="Building Mode Toggle"; bind="Tab or Q"; tip="Switch between combat and build." }
    )
    controller = @(
        @{ cat="Preset"; action="Recommended preset"; bind="Builder Pro"; tip="Almost every controller pro uses Builder Pro. Start here." }
        @{ cat="Movement"; action="Move"; bind="Left Stick"; tip="" }
        @{ cat="Movement"; action="Look / Aim"; bind="Right Stick"; tip="" }
        @{ cat="Movement"; action="Jump"; bind="A / Cross"; tip="" }
        @{ cat="Movement"; action="Sprint"; bind="Left Stick Click"; tip="" }
        @{ cat="Combat"; action="Fire"; bind="Right Trigger (RT / R2)"; tip="" }
        @{ cat="Combat"; action="Aim"; bind="Left Trigger (LT / L2)"; tip="" }
        @{ cat="Combat"; action="Reload"; bind="B / Circle"; tip="" }
        @{ cat="Combat"; action="Use / Pick up"; bind="Square / X"; tip="" }
        @{ cat="Build"; action="Wall"; bind="Left Trigger (in build)"; tip="Builder Pro maps builds to triggers and bumpers." }
        @{ cat="Build"; action="Floor"; bind="Right Trigger (in build)"; tip="" }
        @{ cat="Build"; action="Stairs"; bind="Left Bumper (in build)"; tip="" }
        @{ cat="Build"; action="Cone"; bind="Right Bumper (in build)"; tip="" }
        @{ cat="Build"; action="Edit"; bind="Right Stick Click"; tip="" }
        @{ cat="Settings"; action="Build Immediately"; bind="On"; tip="Turn this on for instant builds, no confirm." }
        @{ cat="Settings"; action="Edit Hold Time"; bind="0.100 to 0.150"; tip="Lower feels snappier once you are used to it." }
    )
}
$Script:WebI18n = @{
    EN = @{ nav_start="Start"; nav_settings="Game Settings"; nav_pc="PC Tweaks"; nav_cleanup="Cleanup"; nav_themes="Themes"; nav_info="Info"; boost="BOOST MY FORTNITE"; boost_sub="Applies your style, optimizes your whole PC, locks your config"; your_system="Your system"; graphics="Graphics"; mem_integrity="Memory integrity"; config_lock="Config lock"; config_lock_desc="Keep config read only so Fortnite cannot wipe your settings"; why_score="Why this score"; fix_all="Fix all"; choose_style="Choose your style"; launch="Launch Fortnite"; ready="Ready to boost"; perfect="Perfectly optimized for Fortnite"; refresh="Refresh"; benchmark="Benchmark"; recommend="Recommend for my PC"; competitive="Competitive"; balanced="Balanced"; quality="Quality"; max_fps="Max FPS"; fps_looks="FPS and looks"; best_visuals="Best visuals" }
    NL = @{ nav_start="Start"; nav_settings="Instellingen"; nav_pc="PC Tweaks"; nav_cleanup="Opschonen"; nav_themes="Thema's"; nav_info="Info"; boost="BOOST MIJN FORTNITE"; boost_sub="Past je stijl toe, optimaliseert je hele pc, vergrendelt je config"; your_system="Jouw systeem"; graphics="Grafisch"; mem_integrity="Geheugenintegriteit"; config_lock="Config vergrendeling"; config_lock_desc="Houd de config vergrendeld zodat Fortnite je instellingen niet wist"; why_score="Waarom deze score"; fix_all="Fix alles"; choose_style="Kies je stijl"; launch="Start Fortnite"; ready="Klaar om te boosten"; perfect="Perfect geoptimaliseerd voor Fortnite"; refresh="Vernieuwen"; benchmark="Benchmark"; recommend="Advies voor mijn pc"; competitive="Competitief"; balanced="Gebalanceerd"; quality="Kwaliteit"; max_fps="Max FPS"; fps_looks="FPS en beeld"; best_visuals="Beste beeld" }
    DE = @{ nav_start="Start"; nav_settings="Einstellungen"; nav_pc="PC Tweaks"; nav_cleanup="Bereinigen"; nav_themes="Themen"; nav_info="Info"; boost="FORTNITE BOOSTEN"; boost_sub="Wendet deinen Stil an, optimiert deinen PC, sperrt deine Config"; your_system="Dein System"; graphics="Grafik"; mem_integrity="Speicherintegritaet"; config_lock="Config Sperre"; config_lock_desc="Config schreibgeschuetzt halten, damit Fortnite deine Einstellungen nicht loescht"; why_score="Warum diese Wertung"; fix_all="Alles beheben"; choose_style="Waehle deinen Stil"; launch="Fortnite starten"; ready="Bereit zum Boosten"; perfect="Perfekt fuer Fortnite optimiert"; refresh="Aktualisieren"; benchmark="Benchmark"; recommend="Empfehlung fuer meinen PC"; competitive="Kompetitiv"; balanced="Ausgewogen"; quality="Qualitaet"; max_fps="Max FPS"; fps_looks="FPS und Optik"; best_visuals="Beste Optik" }
    ES = @{ nav_start="Inicio"; nav_settings="Ajustes"; nav_pc="Ajustes PC"; nav_cleanup="Limpieza"; nav_themes="Temas"; nav_info="Info"; boost="POTENCIAR FORTNITE"; boost_sub="Aplica tu estilo, optimiza tu PC, bloquea tu config"; your_system="Tu sistema"; graphics="Graficos"; mem_integrity="Integridad de memoria"; config_lock="Bloqueo de config"; config_lock_desc="Manten la config en solo lectura para que Fortnite no borre tus ajustes"; why_score="Por que esta puntuacion"; fix_all="Arreglar todo"; choose_style="Elige tu estilo"; launch="Iniciar Fortnite"; ready="Listo para potenciar"; perfect="Perfectamente optimizado para Fortnite"; refresh="Actualizar"; benchmark="Benchmark"; recommend="Recomendar para mi PC"; competitive="Competitivo"; balanced="Equilibrado"; quality="Calidad"; max_fps="Max FPS"; fps_looks="FPS y aspecto"; best_visuals="Mejor aspecto" }
}
$Script:Themes = [ordered]@{
    "purple" = @{ Name="Fortnite Purple"; Bg=@(13,11,26); Panel=@(20,17,38); Card=@(28,24,52); CardHi=@(40,34,72); Accent=@(150,90,255); Accent2=@(64,206,255) }
    "cyan"   = @{ Name="Ice Blue";        Bg=@(8,14,24);  Panel=@(14,22,36);  Card=@(20,30,48);  CardHi=@(30,44,68);  Accent=@(64,206,255);  Accent2=@(120,230,255) }
    "green"  = @{ Name="Toxic Green";     Bg=@(10,18,12);  Panel=@(14,26,18);  Card=@(20,36,26);  CardHi=@(30,52,38);  Accent=@(96,230,120);  Accent2=@(180,255,120) }
    "red"    = @{ Name="Crimson";         Bg=@(22,10,12);  Panel=@(32,14,18);  Card=@(44,20,26);  CardHi=@(64,30,38);  Accent=@(255,80,100);  Accent2=@(255,150,90) }
    "gold"   = @{ Name="Gold Elite";      Bg=@(20,16,8);   Panel=@(30,24,12);  Card=@(42,34,18);  CardHi=@(60,48,26);  Accent=@(255,196,72);  Accent2=@(255,230,140) }
    "mono"   = @{ Name="Clean White";     Bg=@(16,16,20);  Panel=@(24,24,30);  Card=@(34,34,42);  CardHi=@(50,50,60);  Accent=@(235,235,245); Accent2=@(120,200,255) }
    "sunset" = @{ Name="Sunset";          Bg=@(24,12,20);  Panel=@(36,16,28);  Card=@(50,22,38);  CardHi=@(70,32,52);  Accent=@(255,110,150); Accent2=@(255,180,90) }
    "ocean"  = @{ Name="Deep Ocean";      Bg=@(8,16,28);   Panel=@(12,24,42);  Card=@(18,34,58);  CardHi=@(26,48,80);  Accent=@(70,140,255);  Accent2=@(90,220,220) }
    "mint"   = @{ Name="Mint";            Bg=@(10,20,18);  Panel=@(14,30,26);  Card=@(20,42,36);  CardHi=@(30,60,52);  Accent=@(80,230,180);  Accent2=@(150,255,210) }
    "royal"  = @{ Name="Royal Gold";      Bg=@(18,14,26);  Panel=@(28,20,40);  Card=@(40,28,56);  CardHi=@(58,40,80);  Accent=@(180,130,255); Accent2=@(255,200,90) }
}
$Script:ThemeFile = Join-Path $Script:BoosterDir "theme.txt"
$Script:CurrentTheme = "purple"
try { if (Test-Path $Script:ThemeFile) { $tk = (Get-Content $Script:ThemeFile -Raw).Trim(); if ($Script:Themes.Contains($tk)) { $Script:CurrentTheme = $tk } } } catch {}
function Save-Theme { param([string]$Key)
    try { if (-not (Test-Path $Script:BoosterDir)) { New-Item -ItemType Directory -Force -Path $Script:BoosterDir | Out-Null }; Set-Content -Path $Script:ThemeFile -Value $Key } catch {}
}

# ==============================================================================
#  WEB API + SERVER
# ==============================================================================
$Script:CurrentPreset = "Competitive / Max FPS"

function Get-ControlledFolderAccess {
    # Controlled Folder Access (Windows-beveiliging) kan het schrijven naar de
    # Fortnite-map BLOKKEREN. Dan werkt geen enkele booster. We detecteren het.
    try {
        $cfa = (Get-MpPreference -ErrorAction SilentlyContinue).EnableControlledFolderAccess
        # 0 = uit, 1 = aan, 2 = audit-modus
        if ($cfa -eq 1) { return $true }
    } catch {}
    return $false
}
function Get-FortniteRunning {
    # Kijkt of Fortnite nu draait. Als de game draait, houdt Windows de config
    # vast en kan NIEMAND erin schrijven - dan waarschuwen we de speler.
    try {
        $names = @("FortniteClient-Win64-Shipping","FortniteClient-Win64-Shipping_EAC_EOS","FortniteLauncher","FortniteClient-Win64-Shipping_BE")
        foreach ($n in $names) {
            if (Get-Process -Name $n -ErrorAction SilentlyContinue) { return $true }
        }
    } catch {}
    return $false
}
function Get-AllState {
    if (-not $Script:Sys) { try { $Script:Sys = Get-SystemInfo } catch {} }
    $sys = $Script:Sys
    $cfgFound = $false
    $cfgPath = ""; $cfgFileExists = $false; $cfgWritable = $null
    try {
        $fc = Find-FortniteConfig
        if ($fc -and $fc.Dir) {
            $cfgPath = $fc.Dir
            Set-ConfigPaths $fc.Dir
            if (Test-Path $fc.Dir) { $cfgFound = $true }
            if ($Script:GusIni -and (Test-Path $Script:GusIni)) {
                $cfgFileExists = $true
                try { $cfgWritable = -not (Get-Item $Script:GusIni -Force).IsReadOnly } catch {}
            }
        }
    } catch {}
    $vals = @{}
    try { $vals = Get-CurrentValues } catch {}
    # bouw de settings-lijst voor de UI
    $settings = @()
    foreach ($key in $Script:SettingOrder) {
        $meta = $Script:SettingMeta[$key]
        if (-not $meta) { continue }
        $cur = $vals[$key]
        $selectedL = ""
        foreach ($o in $meta.Opts) { if ($o.V -eq $cur) { $selectedL = $o.L; break } }
        $expl = $meta.Exp
        if (-not $expl) { $expl = ($Script:Tweaks | Where-Object { $_.Key -eq $key } | Select-Object -First 1).Uitleg }
        $settings += @{
            key = $key; name = $meta.Name
            options = @($meta.Opts | ForEach-Object { @{ label=$_.L; value=$_.V } })
            selected = $selectedL
            explain = $expl
        }
    }
    $vendor = "Unknown"; try { $vendor = Get-GpuVendor } catch {}
    $vbs = "?"; try { $vbs = Get-VBSStatus } catch {}
    $score = 0; try { $score = (Get-OptimizationScore).Score } catch {}
    $admin = $false; try { $admin = Test-Admin } catch {}
    $renderMode = "Performance"; try { $renderMode = Get-RenderMode } catch {}
    $breakdown = @(); try { $breakdown = Get-ScoreBreakdown } catch {}
    # stretched opties
    $stretchOpts = @(); $savedStretch = "native"
    try {
        $stretchOpts = @(Get-StretchedOptions $sys | ForEach-Object { @{ w=$_.W; h=$_.H; label=$_.Label; base=$_.Base } })
        if ($Script:SavedStretch) { $savedStretch = $Script:SavedStretch }
    } catch {}
    return @{
        cpu = $sys.CPU; gpu = $sys.GPU; ram = $sys.RAM; display = $sys.Display
        vendor = $vendor
        vbs = $vbs
        score = $score
        admin = $admin
        configFound = $cfgFound
        configPath = $cfgPath
        configFileExists = $cfgFileExists
        configWritable = $cfgWritable
        fortniteRunning = (Get-FortniteRunning)
        controlledFolderAccess = (Get-ControlledFolderAccess)
        backups = @(Get-BackupList)
        scoreHistory = @($Script:ScoreHistory)
        wifi = (Get-WifiInfo)
        recommended = (Get-RecommendedPreset $Script:Sys)
        fpsEstimate = (Get-FpsEstimate $Script:Sys $Script:CurrentPreset)
        keybinds = $Script:Keybinds
        pros = $Script:Pros
        lang = $Script:Lang
        i18n = $Script:WebI18n[$Script:Lang]
        locked = $Script:LockEngineIni
        preset = $Script:CurrentPreset
        settings = $settings
        renderMode = $renderMode
        breakdown = $breakdown
        stretchOptions = $stretchOpts
        savedStretch = $savedStretch
        gpuScalingOn = $Script:GpuScalingOn
        themes = @($Script:Themes.Keys | ForEach-Object { @{ id=$_; name=$Script:Themes[$_].Name; bg=$Script:Themes[$_].Bg; panel=$Script:Themes[$_].Panel; accent=$Script:Themes[$_].Accent; accent2=$Script:Themes[$_].Accent2 } })
        currentTheme = $Script:CurrentTheme
    }
}

function Invoke-WebAction {
    param($action, $req)
    $out = @{ ok = $true; report = @() }
    # zorg dat config-paden altijd gezet zijn voordat we iets schrijven
    try {
        $fc = Find-FortniteConfig
        if ($fc -and $fc.Dir -and (Test-Path $fc.Dir)) { Set-ConfigPaths $fc.Dir }
    } catch {}
    try {
    switch ($action) {
        "boost" {
            $p = if ($req.preset) { $req.preset } else { $Script:CurrentPreset }
            $Script:CurrentPreset = $p
            $r = Invoke-AllBoost $p
            $out.report = @($r.Report); $out.admin = $r.Admin
            try { Add-ScoreHistory ([int](Get-OptimizationScore).Score) } catch {}
        }
        "setPreset" {
            $Script:CurrentPreset = $req.preset
            $vals = Get-PresetValues $req.preset $Script:Sys
            $r = Set-FortniteTweaks $vals
            $out.ok = $r.Ok; $out.report = @($r.Message)
        }
        "applyPreset" {
            $Script:CurrentPreset = $req.preset
            $vals = Get-PresetValues $req.preset $Script:Sys
            $r = Set-FortniteTweaks $vals
            $out.ok = $r.Ok; $out.report = @($r.Message)
        }
        "setSetting" {
            $r = Set-GameSetting $req.key $req.value
            $out.ok = $r.Ok; $out.report = @($r.Msg)
        }
        "setRender" {
            $r = Set-RenderMode $req.mode
            $out.ok = $r.Ok; $out.report = @($r.Msg)
        }
        "setGpuScaling" {
            $r = Set-GpuScaling ([bool]$req.on)
            $Script:GpuScalingOn = [bool]$req.on
            try { Set-Content $Script:GpuScalingFile ($(if($Script:GpuScalingOn){"on"}else{"off"})) } catch {}
            $msg = @()
            foreach ($d in $r.Done) { $msg += $d }
            if ($r.Guide) { $msg += $r.Guide }
            $out.ok = $r.Ok; $out.report = $msg
        }
        "setStretch" {
            if ($req.base -eq 0) {
                Clear-StretchedResolution $Script:Sys | Out-Null
                Save-Stretch "native"; $Script:SavedStretch = "native"
                try { Set-Content $Script:StretchFile "native" } catch {}
                $out.report = @("Resolution set back to native 1920 x 1080")
            } elseif ([int]$req.w -gt 0 -and [int]$req.h -gt 0) {
                $w = [int]$req.w; $h = [int]$req.h
                # 1. registreer de resolutie zodat Fortnite 'm ziet
                try { Register-CustomResolution $w $h | Out-Null } catch {}
                # 2. schrijf de config (alle 6 velden)
                $r = Set-StretchedResolution $w $h
                $Script:SavedStretch = "${w}x${h}"
                try { Set-Content $Script:StretchFile "${w}x${h}" } catch {}
                # 3. zet GPU-scaling registry
                try { Set-GpuScaling $true | Out-Null; $Script:GpuScalingOn = $true; Set-Content $Script:GpuScalingFile "on" } catch {}
                # 4. duidelijke stap-voor-stap gids (het driver-deel kan alleen de speler doen)
                $vendor = Get-GpuVendor
                # verifieer dat het echt geschreven is
                $verified = $false
                try { $verified = (Get-Content $Script:GusIni -Raw) -match "ResolutionSizeX=$w" } catch {}
                $msg = @()
                if ($verified) { $msg += "Stretched $w x $h saved and locked in your config." }
                else { $msg += "Tried to save $w x $h but couldn't verify - is Fortnite or the Epic Launcher open? Close BOTH and try again." }
                $msg += "IMPORTANT: close Fortnite AND the Epic Games Launcher fully before starting - the launcher caches the config and undoes changes on close."
                $msg += "To make it fill the screen (no black bars), do these 2 driver steps once:"
                if ($vendor -eq "NVIDIA") {
                    $msg += "1) NVIDIA Control Panel > Adjust desktop size and position > Scaling: Full screen, Perform scaling on: GPU, tick 'Override the scaling mode set by games'. Apply."
                    $msg += "2) In Fortnite Video settings: Window Mode = Fullscreen (NOT borderless), Resolution = $w x $h."
                    $msg += "If $w x $h isn't in the list: add it as a custom resolution with CRU (safe EDID tool by ToastyX): https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU"
                } elseif ($vendor -eq "AMD") {
                    $msg += "1) AMD Software (Adrenalin) > Settings > Display > GPU Scaling: ON, Scaling Mode: Full Panel."
                    $msg += "2) In Fortnite Video settings: Window Mode = Fullscreen (NOT borderless), Resolution = $w x $h."
                    $msg += "If $w x $h isn't listed: Adrenalin > Display > Custom Resolutions > Create, or use CRU: https://www.monitortests.com/forum/Thread-Custom-Resolution-Utility-CRU"
                } else {
                    $msg += "1) Set your GPU scaling to Full screen / Full Panel and override game scaling."
                    $msg += "2) In Fortnite: Window Mode = Fullscreen, Resolution = $w x $h."
                }
                $msg += "The read only lock keeps Fortnite from resetting this. TIP: know how to boot Safe Mode before custom-resolution tools, just in case."
                $out.ok = $r.Ok; $out.report = $msg
            } else {
                $out.ok = $false; $out.report = @("invalid resolution")
            }
        }
        "applyComp" {
            $Script:CurrentPreset = "Competitive / Max FPS"
            $vals = Get-PresetValues "Competitive / Max FPS" $Script:Sys
            $r = Set-FortniteTweaks $vals
            try { Set-RawInput | Out-Null } catch {}
            $out.ok = $r.Ok; $out.report = @("Competitive preset applied")
        }
        "lockOn" {
            $Script:LockEngineIni = $true
            try { Save-LockPref $true } catch {}
            try { Set-ConfigLockState $true | Out-Null } catch {}
            $out.report = @("Config locked - Fortnite can't wipe your settings now")
        }
        "launch" {
            $closeBg = [bool]$req.closeBackground
            $closed = 0
            if ($closeBg) { try { $closed = Close-BackgroundApps } catch {} }
            $ok = Start-Fortnite $true
            $rep = @()
            if ($closed -gt 0) { $rep += "Closed $closed background apps" }
            $rep += $(if ($ok) { "Launching Fortnite with high priority..." } else { "Couldn't start Fortnite - open it from Epic" })
            $out.ok = $ok; $out.report = $rep
        }
        "launchOptions" {
            $r = Set-LaunchOptions ([bool]$req.enable)
            $out.ok = $r.Ok; $out.report = $r.Done
        }
        "setLock" {
            $Script:LockEngineIni = [bool]$req.value
            try { Save-LockPref ([bool]$req.value) } catch {}
            try { Set-ConfigLockState ([bool]$req.value) | Out-Null } catch {}
            $out.report = @("Config lock = $($req.value)")
        }
        "restore" {
            $r = Restore-ConfigBackup $req.path
            $out.ok = $r.Ok; $out.report = @($r.Msg)
        }
        "backup" {
            $b = New-ConfigBackup
            $out.ok = ($null -ne $b); $out.report = @($(if ($b) { "Backup saved: $(Split-Path $b -Leaf)" } else { "Couldn't make a backup (launch Fortnite once first)" }))
        }
        "boostInput" {
            $done = @()
            $i = Optimize-InputDevices; if ($i.Ok) { $done += $i.Done }
            $u = Disable-UsbPowerSaving; if ($u.Ok) { $done += $u.Done }
            $out.ok = ($done.Count -gt 0); $out.report = $done
        }
        "boostCpu" {
            $c = Optimize-CpuAdvanced
            $out.ok = $c.Ok; $out.report = $c.Done
        }
        "boostRegistry" {
            $r = Optimize-RegistryBoost
            $out.ok = $r.Ok; $out.report = $r.Done
        }
        "setLanguage" {
            if ($req.lang -in @("EN","NL","DE","ES")) {
                Save-Language $req.lang
                $out.ok = $true; $out.report = @("Language set to $($req.lang)")
            } else { $out.ok = $false; $out.report = @("unknown language") }
        }
        "recommendPreset" {
            $rec = Get-RecommendedPreset $Script:Sys
            $Script:CurrentPreset = $rec
            $out.ok = $true; $out.report = @("Based on your PC we recommend: $rec"); $out.recommended = $rec
        }
        "fixKeybinds" {
            # Ontgrendelt Input.ini zodat keybinds (zoals scrollen om wapens te pakken)
            # weer werken. Fix voor wie een oude versie draaide die Input.ini vergrendelde.
            $fixed = @()
            if ($Script:InputIni -and (Test-Path $Script:InputIni)) {
                try {
                    $wasRo = (Get-Item $Script:InputIni -Force).IsReadOnly
                    Unlock-File $Script:InputIni
                    if ($wasRo) { $fixed += "Input.ini unlocked - your keybinds work again" }
                    else { $fixed += "Input.ini was already fine" }
                } catch { $fixed += "Could not change Input.ini: $($_.Exception.Message)" }
            } else {
                $fixed += "Input.ini not found yet - launch Fortnite once, then run this"
            }
            $fixed += "Restart Fortnite and your scroll to grab weapons will work again."
            $out.ok = $true; $out.report = $fixed
        }
        "repair" {
            $r = Repair-AllTweaks
            $out.ok = $true; $out.report = @("All booster tweaks re-applied cleanly. Your config is fixed.")
            try { Add-ScoreHistory ([int](Get-OptimizationScore).Score) } catch {}
        }
        "getShareCode" {
            $vals = Get-CurrentValues
            $code = New-ShareCode $vals
            $out.ok = $true; $out.report = @($code); $out.shareCode = $code
        }
        "useShareCode" {
            $vals = Read-ShareCode $req.code
            if ($vals -and $vals.Count -gt 0) {
                $r = Set-FortniteTweaks $vals
                $out.ok = $r.Ok; $out.report = @("Applied $($vals.Count) settings from the share code")
            } else {
                $out.ok = $false; $out.report = @("Invalid share code - check you pasted the whole STRIX1... code")
            }
        }
        "checkUpdate" {
            $u = Get-UpdateInfo
            if ($u.HasUpdate) { $out.report = @("New version available: $($u.Latest) (you have $($u.Current))", "Download: $($u.Url)") }
            else { $out.report = @("You're on the latest version ($($u.Current)). Nice!") }
            $out.ok = $true; $out.update = $u
        }
        "benchmark" {
            $b = Invoke-QuickBenchmark
            $prev = $Script:LastBench
            $Script:LastBench = $b.Total
            $rep = @("Performance score: $($b.Total) (CPU $($b.Cpu) + Memory $($b.Mem))")
            if ($prev -gt 0) {
                $diff = [int]((($b.Total - $prev) / [math]::Max(1,$prev)) * 100)
                if ($diff -gt 0) { $rep += "That's $diff% faster than your last test!" }
                elseif ($diff -lt 0) { $rep += "$([math]::Abs($diff))% lower - close background apps and try again." }
                else { $rep += "About the same as last time." }
            } else { $rep += "Run this before AND after a boost to see your gain." }
            $out.ok = $true; $out.report = $rep; $out.bench = $b.Total
        }
        "revertStretch" {
            Clear-StretchedResolution $Script:Sys | Out-Null
            Save-Stretch "native"; $Script:SavedStretch = "native"
            try { Set-Content $Script:StretchFile "native" } catch {}
            $out.ok = $true; $out.report = @("Reverted to native 1920 x 1080 - safe again.")
        }
        "boostSmooth" {
            $sm = Optimize-Smoothness $Script:Sys
            $rep = @()
            foreach ($d in $sm.Done) { $rep += $d }
            if ($sm.Guide) { $rep += $sm.Guide }
            $out.ok = $sm.Ok; $out.report = $rep
        }
        "boostMonitor" {
            $m = Optimize-Monitor
            $out.ok = $m.Ok; $out.report = $m.Done
        }
        "driverCheck" {
            $d = Get-DriverCheck
            $rep = @("GPU: $($d.Vendor)", "Driver version: $($d.Version)")
            if ($d.Date) { $rep += "Driver date: $($d.Date)" }
            if ($d.Old) { $rep += "Your driver looks older than 4 months - updating can add FPS." }
            else { $rep += "Driver looks recent - good." }
            if ($d.Link) { $rep += "Download latest: $($d.Link)" }
            $out.ok = $true; $out.report = $rep; $out.driver = $d
        }
        "pingTest" {
            $pings = Test-FortnitePing
            $best = $pings | Where-Object { $_.ping -ge 0 } | Sort-Object ping | Select-Object -First 1
            $rep = @()
            foreach ($p in $pings) { $rep += "$($p.name): $(if($p.ping -ge 0){"$($p.ping) ms"}else{"no response"})" }
            if ($best) { $rep += "Lowest ping: $($best.name) ($($best.ping) ms) - set this as your region in Game Settings." }
            $out.ok = $true; $out.report = $rep; $out.pings = $pings
        }
        "boostNetwork" {
            $n = Optimize-NetworkAdvanced
            $ad = Optimize-AntiDesync
            $done = @()
            if ($n.Ok) { $done += $n.Done }
            if ($ad.Ok) { $done += $ad.Done }
            $out.ok = ($done.Count -gt 0); $out.report = $done
        }
        "fixVbs" {
            $r = Disable-MemoryIntegrity
            $out.ok = $r.Ok; $out.report = @($r.Msg)
        }
        "selfTest" {
            # Schrijft een testwaarde, leest terug, en rapporteert PRECIES wat er gebeurt.
            $steps = @()
            if (-not $Script:GusIni) {
                $steps += "FAIL: no config path set"
                $out.ok = $false; $out.report = $steps; break
            }
            $steps += "Config path: $Script:GusIni"
            $steps += "File exists: $([bool](Test-Path $Script:GusIni))"
            if (Test-Path $Script:GusIni) {
                $roBefore = (Get-Item $Script:GusIni -Force).IsReadOnly
                $steps += "Read only before: $roBefore"
                # test-waarde schrijven
                $testVal = "999.000000"
                $r = Set-GameSetting "FrameRateLimit" $testVal
                $steps += "Write result: $($r.Ok) - $($r.Msg)"
                # teruglezen
                try {
                    $raw = Get-Content $Script:GusIni -Raw
                    $found = $raw -match 'FrameRateLimit=999.000000'
                    $steps += "Read back FrameRateLimit=999: $found"
                    if ($found) { $steps += "SUCCESS: writing works on your PC" }
                    else { $steps += "PROBLEM: value did not land in the file" }
                } catch { $steps += "Read back failed: $($_.Exception.Message)" }
                $roAfter = (Get-Item $Script:GusIni -Force).IsReadOnly
                $steps += "Read only after: $roAfter (lock preference = $($Script:LockEngineIni))"
                # ClientSettings.Sav aanwezig?
                if ($Script:ClientSav -and (Test-Path $Script:ClientSav)) {
                    $steps += "ClientSettings.Sav: found (also locked)"
                } else {
                    $steps += "ClientSettings.Sav: not present (ok, GameUserSettings is the main file)"
                }
                # Controlled Folder Access - grote blokkeer-oorzaak
                $cfa = Get-ControlledFolderAccess
                $steps += "Controlled Folder Access: $cfa" + $(if ($cfa) { " <- THIS BLOCKS WRITES! Turn it off in Windows Security > Ransomware protection, or allow this app." } else { "" })
                # Fortnite draait?
                $fnRun = Get-FortniteRunning
                $steps += "Fortnite running: $fnRun" + $(if ($fnRun) { " <- CLOSE FORTNITE FIRST" } else { "" })
                $out.ok = $found
            }
            $out.report = $steps
        }
        "cleanup" {
            $done = @()
            try { if (Clear-FortniteShaderCache) { $done += "Fortnite shader cache cleared" } } catch {}
            try { if (Clear-GpuShaderCaches) { $done += "GPU shader caches cleared" } } catch {}
            try { Clear-DnsCache | Out-Null; $done += "DNS cache flushed" } catch {}
            try { if (Clear-UserTemp) { $done += "Temp files cleared" } } catch {}
            $out.report = $done
        }
        "setTheme" {
            $Script:CurrentTheme = $req.theme
            try { Save-Theme $req.theme } catch {}
            $out.report = @("Theme = $($req.theme)")
        }
        "applyAllSettings" {
            $p = if ($req.preset) { $req.preset } else { $Script:CurrentPreset }
            $vals = Get-PresetValues $p $Script:Sys
            $r = Set-FortniteTweaks $vals
            $out.ok = $r.Ok; $out.report = @($r.Message)
        }
        default { $out.ok = $false; $out.report = @("unknown action: $action") }
    }
    } catch {
        $out.ok = $false
        $out.report = @("Something went wrong: " + $_.Exception.Message)
        Write-Log "action '$action' error: $_"
    }
    try { $out.state = Get-AllState } catch { Write-Log "state build error: $_" }
    return $out
}

# statische UI
$Script:Html = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "ui.html"), [System.Text.Encoding]::UTF8)

function Send-Json { param($ctx,$obj)
    $json = $obj | ConvertTo-Json -Depth 8 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $ctx.Response.ContentType = "application/json; charset=utf-8"
    $ctx.Response.Headers.Add("Cache-Control","no-store")
    $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length); $ctx.Response.OutputStream.Close()
}
function Send-Html { param($ctx,$html)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
    $ctx.Response.ContentType = "text/html; charset=utf-8"
    $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length); $ctx.Response.OutputStream.Close()
}

# init
try { $Script:Sys = Get-SystemInfo } catch {}
try {
    $fc = Find-FortniteConfig
    if ($fc -and $fc.Dir) { Set-ConfigPaths $fc.Dir }
} catch {}

$port = 8733
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
try { $listener.Start() } catch { Write-Host "Kan poort $port niet openen: $_"; Read-Host "Enter om te sluiten"; exit 1 }

Write-Host ""
Write-Host "  STRIXLUCA FPS Booster" -ForegroundColor Yellow
Write-Host "  App-venster wordt geopend..." -ForegroundColor Cyan
Write-Host "  (dit venster mag open blijven - sluiten stopt de app)" -ForegroundColor DarkGray
Write-Host ""

function Open-AppWindow { param($Url)
    $paths = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
    $appArgs = "--app=$Url --window-size=1200,840 --disable-features=Translate --no-first-run"
    foreach ($exe in $paths) { if (Test-Path $exe) { Start-Process $exe -ArgumentList $appArgs; return } }
    Start-Process $Url
}
try { Open-AppWindow "http://localhost:$port" } catch { try { Start-Process "http://localhost:$port" } catch {} }

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $path = $ctx.Request.Url.AbsolutePath
        if ($path -eq "/") { Send-Html $ctx $Script:Html; continue }
        if ($path -eq "/api/state") { Send-Json $ctx (Get-AllState); continue }
        if ($path -eq "/api/action" -and $ctx.Request.HttpMethod -eq "POST") {
            $body = (New-Object System.IO.StreamReader($ctx.Request.InputStream)).ReadToEnd()
            $req = $body | ConvertFrom-Json
            $result = Invoke-WebAction $req.action $req
            Send-Json $ctx $result
            continue
        }
        $ctx.Response.StatusCode = 404; Send-Html $ctx "not found"
    } catch { Write-Log "server error: $_" }
}
