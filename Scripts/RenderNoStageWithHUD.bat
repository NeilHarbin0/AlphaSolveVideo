@ECHO OFF
if "%~2"=="" (
    call "%~dp0RenderSlp.bat" "%~1" --no-stage --hud
) else (
    call "%~dp0RenderSlp.bat" "%~1" --no-stage --hud --format "%~2"
)
