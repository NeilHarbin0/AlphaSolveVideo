@ECHO OFF
setlocal EnableExtensions EnableDelayedExpansion

set "REPLAY="
set "STAGE_MODE=nostage"
set "HUD_MODE=nohud"
set "OPAQUE_MODE=0"
set "NO_GECKO=0"
set "FORMAT=png"
set "SCALE=1"
set "RAW_RES=0"
set "ISO_PATH=%MELEE_ISO%"
if not defined ISO_PATH set "ISO_PATH=%SLP2ALPHA_ISO%"
set "DOLPHIN_EXE=%ASV_DOLPHIN%"
set "OUT_DIR="
set "BACKEND=D3D"
set "KEEP_TEMP=0"

:parseArgs
if "%~1"=="" goto doneArgs
if /I "%~1"=="--stage" (set "STAGE_MODE=stage" & shift & goto parseArgs)
if /I "%~1"=="--no-stage" (set "STAGE_MODE=nostage" & shift & goto parseArgs)
if /I "%~1"=="--hud" (set "HUD_MODE=hud" & shift & goto parseArgs)
if /I "%~1"=="--no-hud" (set "HUD_MODE=nohud" & shift & goto parseArgs)
if /I "%~1"=="--opaque" (set "OPAQUE_MODE=1" & shift & goto parseArgs)
if /I "%~1"=="--no-gecko" (set "OPAQUE_MODE=1" & set "NO_GECKO=1" & shift & goto parseArgs)
if /I "%~1"=="--raw" (set "RAW_RES=1" & shift & goto parseArgs)
if /I "%~1"=="--keep" (set "KEEP_TEMP=1" & shift & goto parseArgs)
if /I "%~1"=="--format" (set "FORMAT=%~2" & shift & shift & goto parseArgs)
if /I "%~1"=="--scale" (set "SCALE=%~2" & shift & shift & goto parseArgs)
if /I "%~1"=="--iso" (set "ISO_PATH=%~2" & shift & shift & goto parseArgs)
if /I "%~1"=="--dolphin" (set "DOLPHIN_EXE=%~2" & shift & shift & goto parseArgs)
if /I "%~1"=="--out" (set "OUT_DIR=%~2" & shift & shift & goto parseArgs)
if /I "%~1"=="--backend" (set "BACKEND=%~2" & shift & shift & goto parseArgs)
if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if not defined REPLAY (
    set "REPLAY=%~f1"
    shift
    goto parseArgs
)
if "%~1" NEQ "" (
    set "FORMAT=%~1"
    shift
    goto parseArgs
)

:usage
ECHO Usage: RenderSlp.bat ^<replay.slp^> [options]
ECHO.
ECHO Options:
ECHO   --no-stage     Hide stage and particles; works on all stages (default)
ECHO   --stage        Keep stage geometry; removes background on Dream Land and Battlefield
ECHO   --no-hud       Hide percents, stocks, timer, name tags, and overlays (default)
ECHO   --hud          Keep HUD and overlays
ECHO   --opaque       Keep background (no flicker/alpha solve; opaque video on all stages)
ECHO   --no-gecko     No AlphaSolve Gecko codes (Slippi playback codes only; opaque video)
ECHO   --format EXT   png (default), prores, mov, mkv, avi, webm, gif, mp4 (opaque only)
ECHO   --scale N      Internal resolution multiplier 1..4 (default: 1)
ECHO   --raw          Dump unstretched 640x480*scale instead of aspect-corrected 640x528
ECHO   --iso PATH     Melee NTSC 1.02 ISO (or set MELEE_ISO / Slippi Launcher Settings)
ECHO   --dolphin EXE  Path to headless dolphin-emu-nogui.exe
ECHO   --backend B    D3D (default), D3D12, Vulkan, OGL
ECHO   --out DIR      Output directory (default: next to replay)
ECHO   --keep         Keep temporary work folder
if not defined ASV_NO_PAUSE pause
exit /b 2

:doneArgs
if not defined REPLAY goto usage
if not exist "%REPLAY%" (
    ECHO ERROR: Replay not found: "%REPLAY%"
    if not defined ASV_NO_PAUSE pause
    exit /b 1
)

for %%F in ("%REPLAY%") do (
    set "REPLAY_DIR=%%~dpF"
    set "REPLAY_STEM=%%~nF"
)
if "%REPLAY_DIR:~-1%"=="\" set "REPLAY_DIR=%REPLAY_DIR:~0,-1%"
if not defined OUT_DIR set "OUT_DIR=%REPLAY_DIR%"
if "%OUT_DIR:~-1%"=="\" set "OUT_DIR=%OUT_DIR:~0,-1%"
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

rem --- Locate headless Dolphin ---
if not defined DOLPHIN_EXE if exist "%~dp0..\packages\slippi-playback-mainline\dolphin-emu-nogui.exe" (
    set "DOLPHIN_EXE=%~dp0..\packages\slippi-playback-mainline\dolphin-emu-nogui.exe"
)
if not defined DOLPHIN_EXE if exist "%~dp0..\dolphin-emu-nogui.exe" (
    set "DOLPHIN_EXE=%~dp0..\dolphin-emu-nogui.exe"
)
if not defined DOLPHIN_EXE (
    for /f "delims=" %%D in ('where dolphin-emu-nogui.exe 2^>nul') do if not defined DOLPHIN_EXE set "DOLPHIN_EXE=%%D"
)
if not defined DOLPHIN_EXE (
    ECHO ERROR: Could not find dolphin-emu-nogui.exe.
    ECHO Download the Windows playback Dolphin artifact into packages\slippi-playback-mainline\.
    if not defined ASV_NO_PAUSE pause
    exit /b 1
)

rem --- Locate FFmpeg ---
set "FFMPEG_EXE="
if defined ALPHASOLVE_FFMPEG if exist "%ALPHASOLVE_FFMPEG%" set "FFMPEG_EXE=%ALPHASOLVE_FFMPEG%"
if not defined FFMPEG_EXE if exist "%~dp0..\ffmpeg.exe" set "FFMPEG_EXE=%~dp0..\ffmpeg.exe"
if not defined FFMPEG_EXE if exist "%~dp0..\packages\ffmpeg-6.0-full_build\bin\ffmpeg.exe" set "FFMPEG_EXE=%~dp0..\packages\ffmpeg-6.0-full_build\bin\ffmpeg.exe"
if not defined FFMPEG_EXE if exist "%~dp0..\packages\ffmpeg\bin\ffmpeg.exe" set "FFMPEG_EXE=%~dp0..\packages\ffmpeg\bin\ffmpeg.exe"
if not defined FFMPEG_EXE if exist "%~dp0..\packages\ffmpeg\ffmpeg.exe" set "FFMPEG_EXE=%~dp0..\packages\ffmpeg\ffmpeg.exe"
if not defined FFMPEG_EXE if exist "C:\Program Files\Simple Video Editor\ffmpeg.exe" set "FFMPEG_EXE=C:\Program Files\Simple Video Editor\ffmpeg.exe"
if not defined FFMPEG_EXE (
    for /f "delims=" %%F in ('where ffmpeg.exe 2^>nul') do if not defined FFMPEG_EXE set "FFMPEG_EXE=%%F"
)
if not defined FFMPEG_EXE (
    ECHO ERROR: Could not find ffmpeg.exe.
    if not defined ASV_NO_PAUSE pause
    exit /b 1
)

rem --- Locate Melee ISO ---
if not defined ISO_PATH if exist "%APPDATA%\Slippi Launcher\Settings" (
    set "RAW_ISO="
    for /f "tokens=1,* delims=:" %%A in ('findstr /I "\"isoPath\"" "%APPDATA%\Slippi Launcher\Settings" 2^>nul') do set "RAW_ISO=%%B"
    if defined RAW_ISO (
        for /f "tokens=* delims= " %%I in ("!RAW_ISO!") do set "RAW_ISO=%%I"
        if "!RAW_ISO:~-1!"=="," set "RAW_ISO=!RAW_ISO:~0,-1!"
        set "RAW_ISO=!RAW_ISO:"=!"
        set "RAW_ISO=!RAW_ISO:\\=\!"
        if exist "!RAW_ISO!" set "ISO_PATH=!RAW_ISO!"
    )
)
if not defined ISO_PATH (
    ECHO ERROR: Melee NTSC 1.02 ISO not found. Pass --iso PATH or set MELEE_ISO.
    if not defined ASV_NO_PAUSE pause
    exit /b 1
)

rem --- Output variant label ---
set "LABEL="
if "%OPAQUE_MODE%"=="1" (
    if "%NO_GECKO%"=="1" (
        set "LABEL=no gecko"
    ) else (
        set "LABEL=with background"
        if "%HUD_MODE%"=="nohud" set "LABEL=!LABEL!, no HUD"
    )
) else (
    if "%STAGE_MODE%"=="nostage" (set "LABEL=no stage") else (set "LABEL=with stage")
    if "%HUD_MODE%"=="nohud" (set "LABEL=!LABEL!, no HUD") else (set "LABEL=!LABEL!, with HUD")
)
set "OUT_NAME=%REPLAY_STEM% (!LABEL!)"

set "WORK=%TEMP%\asv-render-%RANDOM%-%RANDOM%"
set "USER_DIR=%WORK%\user"
mkdir "%USER_DIR%\Config"
mkdir "%USER_DIR%\GameSettings"

set "ENABLE_CHEATS=True"

set "RES_TYPE=1"
if "%RAW_RES%"=="1" set "RES_TYPE=2"

rem --- Write Dolphin.ini and GFX.ini ---
(
    echo [Core]
    echo GFXBackend = %BACKEND%
    echo EmulationSpeed = 0
    echo EnableCheats = %ENABLE_CHEATS%
    echo [Slippi]
    echo EnableSpectator = False
    echo EnableJukebox = False
    echo SaveReplays = False
    echo [Movie]
    echo DumpFrames = True
    echo DumpFramesSilent = True
    echo [DSP]
    echo Backend = No Audio Output
    echo DumpAudio = False
    echo [Interface]
    echo ConfirmStop = False
    echo UsePanicHandlers = False
    echo OnScreenDisplayMessages = False
    echo [Analytics]
    echo Enabled = False
    echo PermissionAsked = True
) > "%USER_DIR%\Config\Dolphin.ini"

(
    echo [Settings]
    echo InternalResolution = %SCALE%
    echo AspectRatio = 0
    echo FrameDumpsResolutionType = %RES_TYPE%
    echo DumpFormat = mkv
    echo DumpCodec = ffv1
    echo ShowFPS = False
    echo [Hacks]
    echo ImmediateXFBEnable = False
    echo [Hardware]
    echo VSync = False
) > "%USER_DIR%\Config\GFX.ini"

rem --- Write GameSettings\GALE01.ini ---
set "RES_DIR=%~dp0..\Resources"
(
    echo [Gecko]
    if exist "%RES_DIR%\Required Codes.txt" findstr /R "^[\$\*#0-9A-Fa-f]" "%RES_DIR%\Required Codes.txt"
    if exist "%RES_DIR%\Characters Only Codes.txt" findstr /R "^[\$\*#0-9A-Fa-f]" "%RES_DIR%\Characters Only Codes.txt"
    echo [Gecko_Enabled]
    if "%NO_GECKO%"=="0" (
        echo $Increase Input Timing Accuracy
        if "%OPAQUE_MODE%"=="0" (
            echo $(EPILEPSY WARNING^) Flicker Background Black/White asm v5
            if "%STAGE_MODE%"=="nostage" (
                echo $Hide Stage - Characters Only
                echo $Hide Stage Particles
                echo $Hide Screen Flash
                echo $Hide Shy Guys (Yoshi's Story^)
            ) else (
                echo $Disable Dreamland Background
                echo $Disable Battlefield Background + Particles
            )
        )
        if "%HUD_MODE%"=="nohud" echo $Hide HUD and Overlays
    )
    echo [Gecko_Disabled]
    echo $Optional: Show Player Names
) > "%USER_DIR%\GameSettings\GALE01.ini"

rem --- Write comm.json (startFrame=-124 records frame -123; omitting endFrame plays to end) ---
set "REPLAY_JSON=%REPLAY:\=\\%"
(
    echo {
    echo   "mode": "normal",
    echo   "replay": "%REPLAY_JSON%",
    echo   "startFrame": -124,
    echo   "isRealTimeMode": false,
    echo   "shouldResync": true,
    echo   "rollbackDisplayMethod": "off",
    echo   "commandId": "asv-%RANDOM%"
    echo }
) > "%WORK%\comm.json"

ECHO Rendering "%REPLAY%" [!LABEL!]...
"%DOLPHIN_EXE%" -p headless -e "%ISO_PATH%" -i "%WORK%\comm.json" -u "%USER_DIR%" --hide-seekbar --exit-on-end
if errorlevel 1 (
    ECHO ERROR: Dolphin exited with error %errorlevel%. Work dir kept: "%WORK%"
    if not defined ASV_NO_PAUSE pause
    exit /b 1
)

set "DUMP_FILE="
for /f "delims=" %%V in ('dir /b /a-d "%USER_DIR%\Dump\Frames\*.mkv" "%USER_DIR%\Dump\Frames\*.avi" 2^>nul') do (
    if not defined DUMP_FILE set "DUMP_FILE=%USER_DIR%\Dump\Frames\%%V"
)
if not defined DUMP_FILE (
    ECHO ERROR: No frame dump was written in "%USER_DIR%\Dump\Frames\". Work dir kept: "%WORK%"
    if not defined ASV_NO_PAUSE pause
    exit /b 1
)

if "%OPAQUE_MODE%"=="1" (
    set "OUT_EXT=%FORMAT%"
    if /I "%FORMAT%"=="prores" set "OUT_EXT=mov"
    set "OUT_FILE=%OUT_DIR%\fullOpaque - %OUT_NAME%.!OUT_EXT!"
    if /I "%FORMAT%"=="mp4" (
        "%FFMPEG_EXE%" -nostdin -y -v error -stats -i "%DUMP_FILE%" -vf "settb=1001/60000,setpts=N" -c:v libx264 -crf 16 -pix_fmt yuv420p "!OUT_FILE!"
    ) else if /I "%FORMAT%"=="prores" (
        "%FFMPEG_EXE%" -nostdin -y -v error -stats -i "%DUMP_FILE%" -vf "settb=1001/60000,setpts=N" -c:v prores_ks -profile:v 4444 -pix_fmt yuv444p10le -vendor apl0 "!OUT_FILE!"
    ) else if /I "%FORMAT%"=="webm" (
        "%FFMPEG_EXE%" -nostdin -y -v error -stats -i "%DUMP_FILE%" -vf "settb=1001/60000,setpts=N" -c:v libvpx-vp9 -crf 10 -b:v 0 -pix_fmt yuv420p "!OUT_FILE!"
    ) else if /I "%FORMAT%"=="gif" (
        "%FFMPEG_EXE%" -nostdin -y -v error -stats -i "%DUMP_FILE%" -vf "settb=1001/60000,setpts=N,split[g1][g2];[g1]palettegen[pal];[g2][pal]paletteuse=dither=none" -r 50 "!OUT_FILE!"
    ) else if /I "%FORMAT%"=="png" (
        "%FFMPEG_EXE%" -nostdin -y -v error -stats -i "%DUMP_FILE%" -vf "settb=1001/60000,setpts=N" -f apng -plays 0 "!OUT_FILE!"
    ) else (
        "%FFMPEG_EXE%" -nostdin -y -v error -stats -i "%DUMP_FILE%" -vf "settb=1001/60000,setpts=N" -c:v ffv1 -pix_fmt bgr0 "!OUT_FILE!"
    )
    set "STEP_ERR=!errorlevel!"
) else (
    set "ASV_NO_PAUSE=1"
    set "ASV_OUT_DIR=%OUT_DIR%"
    set "ASV_OUT_NAME=%OUT_NAME%"
    call "%~dp0AlphaSolve.bat" "%DUMP_FILE%" "%FORMAT%"
    set "STEP_ERR=!errorlevel!"
)

if "%KEEP_TEMP%"=="0" rmdir /s /q "%WORK%" 2>nul
if "%KEEP_TEMP%"=="1" ECHO Work folder kept: "%WORK%"

if not "%STEP_ERR%"=="0" (
    ECHO ERROR: Encoding/solving failed with exit code %STEP_ERR%.
    if not defined ASV_NO_PAUSE pause
    exit /b %STEP_ERR%
)

ECHO Done! Output saved in "%OUT_DIR%"
if not defined ASV_NO_PAUSE pause
exit /b 0
