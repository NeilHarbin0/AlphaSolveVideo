@Echo off
rem This is essentially a function to compare two frames A and B, and see which has a greater scene score compared to black and hopefully therefore greater brightness
rem Errorlevel will be set to 0 if A is brighter, and 1 if B is brighter

rem Take the input, add a black frame to it
"%~1" -hide_banner -y -i "%~2" -i "%~2" -filter_complex "[0:v]format=argb,geq=a='alpha(X,Y)':r='0':g='0':b='0'[blackened],[blackened][1:v]concat=n=2,select='gte(scene,0)',metadata=print" -an -f null - 2> sceneDetect.txt

rem Find like scene_score=0.04534
set scoreA=0
set scoreB=0

set counter=3
SETLOCAL EnableDelayedExpansion
FOR /F "tokens=3 delims=@=" %%x in (sceneDetect.txt) DO (
    set /a counter=!counter!-1
    if !counter!==0 (
        set scoreA=%%x
    )
)
echo Detected scene scoreA from black=%scoreA%

"%~1" -hide_banner -y -i "%~3" -i "%~3" -filter_complex "[0:v]format=argb,geq=a='alpha(X,Y)':r='0':g='0':b='0'[blackened],[blackened][1:v]concat=n=2,select='gte(scene,0)',metadata=print" -an -f null - 2> sceneDetect.txt

set counter=3
SETLOCAL EnableDelayedExpansion
FOR /F "tokens=3 delims=@=" %%x in (sceneDetect.txt) DO (
    set /a counter=!counter!-1
    if !counter!==0 (
        set scoreB=%%x
    )
)
echo Detected scene scoreB from black=%scoreB%
del /F sceneDetect.txt
rem Set errorlevel=0
(call)
if %scoreA% gtr %scoreB% (
    rem Set errorlevel=1
    (call )
)
ENDLOCAL