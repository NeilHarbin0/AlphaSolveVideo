@ECHO OFF
if "%~2"=="" (
    call "%~dp0RenderSlp.bat" "%~1" --no-stage --no-hud
) else (
    call "%~dp0RenderSlp.bat" "%~1" --no-stage --no-hud --format "%~2"
)
