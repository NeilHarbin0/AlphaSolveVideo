@ECHO OFF
if "%~2"=="" (
    call "%~dp0RenderSlp.bat" "%~1" --stage --hud
) else (
    call "%~dp0RenderSlp.bat" "%~1" --stage --hud --format "%~2"
)
