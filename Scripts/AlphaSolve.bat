@ECHO OFF
cls
rem (Tested with dolphin 17995 and headless slippi-playback-mainline)
ECHO Input should be lossless dolphin .avi or .mkv
ECHO Should use at minimum the following gecko codes:
rem (Ensures white->black pairs will always be in the same order)
ECHO 1. Increase Input Timing Accuracy
ECHO 2. Disable specific stage background (or Characters Only codes)
rem (Allows white->black pairs to occur on the same physics frame, instead of every other frame)
ECHO 3. 120 fps mode
ECHO 4. (EPILEPSY WARNING) Flicker Background Black/White asm v5
ECHO.

if "%~1"=="" (
    ECHO Usage: AlphaSolve.bat ^<video^> [ext]
    if not defined ASV_NO_PAUSE pause
    exit /b 2
)

set "inputFile=%~f1"
set "inputDir=%~dp1"
if "%inputDir:~-1%"=="\" set "inputDir=%inputDir:~0,-1%"
set "inputName=%~n1"
if defined ASV_OUT_DIR (
    set "outDir=%ASV_OUT_DIR%"
) else (
    set "outDir=%inputDir%"
)
if "%outDir:~-1%"=="\" set "outDir=%outDir:~0,-1%"
if defined ASV_OUT_NAME (
    set "outName=%ASV_OUT_NAME%"
) else (
    set "outName=%inputName%"
)

ECHO #Batch inputs
ECHO WorkingDir= %cd%
ECHO BatchDir= %~dp0
ECHO File= "%inputFile%"
ECHO Ext= %2
ECHO.

rem Check a few places where ffmpeg might be
ECHO #Checking for ffmpeg.exe
set "ffmpegPath="
if defined ALPHASOLVE_FFMPEG (
    if exist "%ALPHASOLVE_FFMPEG%" (
        ECHO Detected ffmpeg in ALPHASOLVE_FFMPEG
        set ffmpegPath="%ALPHASOLVE_FFMPEG%"
    )
)
if not defined ffmpegPath if exist "%~dp0..\ffmpeg.exe" (
    ECHO Detected ffmpeg in script parent folder
    set ffmpegPath="%~dp0..\ffmpeg.exe"
)
if not defined ffmpegPath if exist "%~dp0..\packages\ffmpeg-6.0-full_build\bin\ffmpeg.exe" (
    ECHO Detected ffmpeg in packages folder
    set ffmpegPath="%~dp0..\packages\ffmpeg-6.0-full_build\bin\ffmpeg.exe"
)
if not defined ffmpegPath if exist "%~dp0..\packages\ffmpeg\bin\ffmpeg.exe" (
    ECHO Detected ffmpeg in packages\ffmpeg\bin folder
    set ffmpegPath="%~dp0..\packages\ffmpeg\bin\ffmpeg.exe"
)
if not defined ffmpegPath if exist "%~dp0..\packages\ffmpeg\ffmpeg.exe" (
    ECHO Detected ffmpeg in packages\ffmpeg folder
    set ffmpegPath="%~dp0..\packages\ffmpeg\ffmpeg.exe"
)
if not defined ffmpegPath if exist "C:\Program Files\Simple Video Editor\ffmpeg.exe" (
    ECHO Detected ffmpeg in SVE installation
    set ffmpegPath="C:\Program Files\Simple Video Editor\ffmpeg.exe"
)
if not defined ffmpegPath if exist "ffmpeg.exe" (
    ECHO Detected ffmpeg in working directory
    set ffmpegPath="ffmpeg.exe"
)
if not defined ffmpegPath (
    where ffmpeg.exe >nul 2>&1 && (
        ECHO Detected ffmpeg on PATH
        set ffmpegPath="ffmpeg.exe"
    )
)
if not defined ffmpegPath (
    ECHO ERROR: Could not find ffmpeg.exe
    if not defined ASV_NO_PAUSE pause
    exit /b 1
)
ECHO.

set "outputExt=%~2"
if "%outputExt%"=="" set "outputExt=png"

set "workDir=%TEMP%\asv-solve-%RANDOM%-%RANDOM%"
mkdir "%workDir%"
pushd "%workDir%"

rem Use info from https://superuser.com/questions/1615310/how-to-use-ffmpeg-blend-difference-filter-mode-to-identify-frame-differences-bet to automatically figure out what is what so we don't have to ask the user. Just knowing if the frame is black or not will tell us everything, as if the flicker doesn't get misaligned, it should always go black-white or white-black without any change.

ECHO #Checking background color
%ffmpegPath% -nostdin -hide_banner -y -i "%inputFile%" -vf "select=eq(n\,0)" -an -f apng -y tempFrame0.png >nul 2>&1
%ffmpegPath% -nostdin -hide_banner -y -i "%inputFile%" -vf "select=eq(n\,1)" -an -f apng -y tempFrame1.png >nul 2>&1

call "%~dp0\Brightest.bat" %ffmpegPath% tempFrame0.png tempFrame1.png
set whiteIndex=%errorlevel%
if %whiteIndex%==0 (
    goto :isWhite
)
goto :isBlack


:isBlack
ECHO Detected black start frame
set polarity1=n
set polarity2=n-1
set firstColor=BLACK
set secondColor=WHITE
ECHO Exporting black frame
%ffmpegPath% -nostdin -hide_banner -y -i "%inputFile%" -vf "select=eq(n\,0)" -an -f apng -y tempBlkFrameA.png  >nul 2>&1
%ffmpegPath% -nostdin -hide_banner -y -i "%inputFile%" -vf "select=eq(n\,2)" -an -f apng -y tempBlkFrameB.png  >nul 2>&1
goto endPolarity
:isWhite
ECHO Detected white start frame
set polarity1=n-1
set polarity2=n
set firstColor=WHITE
set secondColor=BLACK
ECHO Exporting black frame
%ffmpegPath% -nostdin -hide_banner -y -i "%inputFile%" -vf "select=eq(n\,1)" -an -f apng -y tempBlkFrameA.png  >nul 2>&1
%ffmpegPath% -nostdin -hide_banner -y -i "%inputFile%" -vf "select=eq(n\,1)" -an -f apng -y tempBlkFrameB.png  >nul 2>&1
:endPolarity
ECHO.

rem Check alignment by taking the first 3 frames, applying the technique both ways, then checking the images against eachother
ECHO #Checking frame pair alignment
ECHO Processing alignment 0-1

set difThreshold=2
rem frame 0-1
%ffmpegPath% -nostdin -hide_banner -y -i "%inputFile%" -filter_complex "[0] split=2 [a][b],[a]select=eq(n\,1)[blk],[b]select=eq(n\,0)[wht],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[alphaMapUse],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax]" -map "[alphaMax]" -q:v 0 -f apng "alphaMapAlignmentTest0-1.png"  >nul 2>&1

%ffmpegPath% -nostdin -hide_banner -y -i "alphaMapAlignmentTest0-1.png" -i "tempBlkFrameA.png" -filter_complex "[0]split=2[alpha1][alpha2],[alpha1]blend=all_mode=lighten[lighten],[alpha2][lighten]blend=all_mode=difference,geq=a='255':r='min(max(0,r(X,Y)-%difThreshold%)*255,255)':g='min(max(0,g(X,Y)-%difThreshold%)*255,255)':b='min(max(0,b(X,Y)-%difThreshold%)*255,255)'" -f apng "lightenedDif0-1.png" >nul 2>&1

ECHO Processing alignment 1-2
rem frame 1-2
%ffmpegPath% -nostdin -hide_banner -y -i "%inputFile%" -filter_complex "[0] split=2 [a][b],[a]select=eq(n\,2)[blk],[b]select=eq(n\,1)[wht],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[alphaMapUse],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax]" -map "[alphaMax]" -q:v 0 -f apng "alphaMapAlignmentTest1-2.png"  >nul 2>&1

%ffmpegPath% -nostdin -hide_banner -y -i "alphaMapAlignmentTest1-2.png" -i "tempBlkFrameB.png" -filter_complex "[0]split=2[alpha1][alpha2],[alpha1]blend=all_mode=lighten[lighten],[alpha2][lighten]blend=all_mode=difference,geq=a='255':r='min(max(0,r(X,Y)-%difThreshold%)*255,255)':g='min(max(0,g(X,Y)-%difThreshold%)*255,255)':b='min(max(0,b(X,Y)-%difThreshold%)*255,255)'" -f apng "lightenedDif1-2.png" >nul 2>&1

call "%~dp0\Brightest.bat" %ffmpegPath% lightenedDif0-1.png lightenedDif1-2.png
set badPairIndex=%errorlevel%
if %badPairIndex%==0 (
    goto :secondPairAligned
)
goto :firstPairAligned


:firstPairAligned
Echo Pairs are aligned 0-1 (%firstColor%-%secondColor%)
set Aligned=y
goto endAlignmentCheck
:secondPairAligned
Echo Pairs are aligned 1-2 (%secondColor%-%firstColor%), offset +1
set Aligned=n
:endAlignmentCheck
ECHO.

ECHO Cleaning up temp files...
popd
rmdir /s /q "%workDir%" 2>nul

if /I "%Aligned%"=="y" goto aligned
goto misaligned
:aligned
set select1="mod(%polarity2%\,2)"
set select2="mod(%polarity1%\,2)"
set select3=%select1%
goto endAlignment
rem Discard the first frame when misaligned so pairs match black->white
:misaligned
set select1="gt(n\,0)*mod(%polarity2%\,2)"
set select2="gt(n\,0)*mod(%polarity1%\,2)"
set select3=%select1%
:endAlignment
ECHO.
rem Retime selected frames by index at NTSC field rate so Matroska millisecond timestamps pair accurately
set ptsAdjust=,settb=1001/60000,setpts=N

if not exist "%outDir%" mkdir "%outDir%"

ECHO Checking output extension "%outputExt%"
ECHO Solving for video output...
if /I "%outputExt%"=="mkv" goto ffv1Ext
if /I "%outputExt%"=="mov" goto ffv1Ext
if /I "%outputExt%"=="avi" goto ffv1Ext
if /I "%outputExt%"=="prores" goto proresSelect
if /I "%outputExt%"=="webm" goto vp9Select
if /I "%outputExt%"=="gif" goto gifSelect
goto apngSelect

:ffv1Ext
rem This works MKV MOV AVI
%ffmpegPath% -nostdin -y -v error -stats -i "%inputFile%" -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[d],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference:shortest=1,negate,format=yuv420p[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -c:v ffv1 -pix_fmt yuva420p "%outDir%\fullTransparent - %outName%.%outputExt%" -map "[out2]" -c:v ffv1 -pix_fmt yuva420p "%outDir%\alphaMap - %outName%.%outputExt%"
goto endExtSelect

:proresSelect
rem ProRes 4444 with alpha (.mov) for video editors (Premiere, Resolve, Final Cut, After Effects)
%ffmpegPath% -nostdin -y -v error -stats -i "%inputFile%" -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[d],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference:shortest=1,negate,format=yuv420p[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -c:v prores_ks -profile:v 4444 -pix_fmt yuva444p10le -alpha_bits 16 -vendor apl0 "%outDir%\fullTransparent - %outName%.mov" -map "[out2]" -c:v prores_ks -profile:v 4444 -pix_fmt yuv444p10le -vendor apl0 "%outDir%\alphaMap - %outName%.mov"
goto endExtSelect

:vp9Select
ECHO Note: Webm files may appear to have strange chromatic artifacts around edges when viewed in discord embeds while still, windows file explorer, or windows media player, but will appear correctly in many web applications.
rem This works WEBM, though many players produce ugly artifacts
%ffmpegPath% -nostdin -y -v error -stats -i "%inputFile%" -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[d],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference:shortest=1,negate,format=yuv420p[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -c:v vp9 -crf 0 -pix_fmt yuva420p "%outDir%\fullTransparent - %outName%.%outputExt%" -map "[out2]" -c:v vp9 -crf 0 -pix_fmt yuva420p "%outDir%\alphaMap - %outName%.%outputExt%"
goto endExtSelect

:gifSelect
ECHO WARNING: Gif files do not support 8-bit transparency, may have less accurate color, and may skip frames due to using 50fps
ECHO Solving for gif, this may appear stuck for many seconds before the gif starts to build...
rem This works GIF, though 1 bit depth for alpha is not ideal
rem Unboosted
%ffmpegPath% -nostdin -y -v error -stats -i "%inputFile%" -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[d],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference:shortest=1,negate,format=yuv420p[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[out2]split [ia][ka];[ia] palettegen [pa];[ka][pa] paletteuse=dither=none[out3],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[d][alphaMax]alphamerge,split [i][k];[i] palettegen [p];[k][p] paletteuse=dither=none:alpha_threshold=64" -q:v 0 -r 50 "%outDir%\fullTransparent - %outName%.%outputExt%" -map "[out3]" -q:v 0 -r 50 "%outDir%\alphaMap - %outName%.%outputExt%"
goto endExtSelect

:apngSelect
rem Assume apng as fallback
set outputExt=png
rem This works APNG
%ffmpegPath% -nostdin -y -v error -stats -i "%inputFile%" -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[d],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference:shortest=1,negate,format=yuv420p[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -q:v 0 -f apng -plays 0 "%outDir%\fullTransparent - %outName%.%outputExt%" -map "[out2]" -q:v 0 -f apng -plays 0 "%outDir%\alphaMap - %outName%.%outputExt%"

:endExtSelect
set "solveErr=%errorlevel%"
ECHO Process finished.
if not defined ASV_NO_PAUSE pause
exit /b %solveErr%
