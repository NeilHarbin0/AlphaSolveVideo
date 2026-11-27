@ECHO OFF
if "%~2"=="" (
    call "%~dp0RenderSlp.bat" "%~1" --no-gecko
) else (
    call "%~dp0RenderSlp.bat" "%~1" --no-gecko --format "%~2"
)
