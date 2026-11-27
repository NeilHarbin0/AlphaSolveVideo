@ECHO OFF
if "%~2"=="" (
    call "%~dp0RenderSlp.bat" "%~1" --stage --no-hud
) else (
    call "%~dp0RenderSlp.bat" "%~1" --stage --no-hud --format "%~2"
)
