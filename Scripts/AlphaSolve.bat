@ECHO OFF
cls
rem (Tested with dolphin 17995)
ECHO Input should be lossless dolphin .avi 
ECHO Should use at minimum the following gecko codes:
rem (Ensures white->black pairs will always be in the same order)
ECHO 1. Increase Input Timing Accuracy
ECHO 2. Disable specific stage background
rem (Allows white->black pairs to occur on the same physics frame, instead of every other frame)
ECHO 3. 120 fps mode 
ECHO 4. (EPILEPSY WARNING) Flicker Background Black/White asm v3
ECHO.
ECHO #Batch inputs
ECHO WorkingDir= %cd%
ECHO BatchDir= %~dp0
ECHO File= %1
ECHO Ext= %2
ECHO.

rem Check a few places where ffmpeg might be
ECHO #Checking for ffmpeg.exe
rem Expected path for downloaded zip
set ffmpegPath="%~dp0..\ffmpeg.exe"
if exist "%~dp0..\ffmpeg.exe" (
    ECHO Detected ffmpeg in script parent folder
)
rem Path for working within repo
if exist "%~dp0..\packages\ffmpeg-6.0-full_build\bin\ffmpeg.exe" (
    ECHO Detected ffmpeg in packages folder
    set ffmpegPath="%~dp0..\packages\ffmpeg-6.0-full_build\bin\ffmpeg.exe"
)
rem Path for SVE users
if exist "C:\Program Files\Simple Video Editor\ffmpeg.exe" (
    ECHO Detected ffmpeg in SVE installation
    set ffmpegPath="C:\Program Files\Simple Video Editor\ffmpeg.exe"
)
rem Path for people who put the exe in the same folder as the scripts or system PATH because why not
if exist "ffmpeg.exe" (
    ECHO Detected ffmpeg in working directory
    set ffmpegPath="ffmpeg.exe"
)
ECHO.

set outputExt=%~2
if [%2] == [] set outputExt=png

rem Use info from https://superuser.com/questions/1615310/how-to-use-ffmpeg-blend-difference-filter-mode-to-identify-frame-differences-bet to automatically figure out what is what so we don't have to ask the user. Just knowing if the frame is black or not will tell us everything, as if the flicker doesn't get misaligned, it should always go black-white or white-black without any change.

ECHO #Checking background color
%ffmpegPath% -hide_banner -y -i %1 -vf "select=eq(n\,0)" -an -f apng -y tempFrame0.png >nul 2>&1
%ffmpegPath% -hide_banner -y -i %1 -vf "select=eq(n\,1)" -an -f apng -y tempFrame1.png >nul 2>&1

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
%ffmpegPath% -hide_banner -y -i %1 -vf "select=eq(n\,0)" -an -f apng -y tempBlkFrameA.png  >nul 2>&1
%ffmpegPath% -hide_banner -y -i %1 -vf "select=eq(n\,2)" -an -f apng -y tempBlkFrameB.png  >nul 2>&1
goto endPolarity
:isWhite
ECHO Detected white start frame
set polarity1=n-1
set polarity2=n
set firstColor=WHITE
set secondColor=BLACK
ECHO Exporting black frame
%ffmpegPath% -hide_banner -y -i %1 -vf "select=eq(n\,1)" -an -f apng -y tempBlkFrameA.png  >nul 2>&1
%ffmpegPath% -hide_banner -y -i %1 -vf "select=eq(n\,1)" -an -f apng -y tempBlkFrameB.png  >nul 2>&1
:endPolarity
ECHO.

rem Check alignment by taking the first 3 frames, applying the technique both ways, then checking the images against eachother
ECHO #Checking frame pair alignment
ECHO Processing alignment 0-1

set difThreshold=2
rem frame 0-1
%ffmpegPath% -hide_banner -y -i %1 -filter_complex "[0] split=2 [a][b],[a]select=eq(n\,1)[blk],[b]select=eq(n\,0)[wht],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[alphaMapUse],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax]" -map "[alphaMax]" -q:v 0 -f apng "alphaMapAlignmentTest0-1.png"  >nul 2>&1

rem Use lighten blend filter as a check to see if the alpha map is correct as lightening should do nothing with a proper map, but create abberations with improper maps
rem Threshold the output to maximize detection possibility via blackdetect
rem %ffmpegPath% -hide_banner -y -i "alphaMapAlignmentTest0-1.png" -i "tempBlkFrameA.png" -filter_complex "[0]split=2[alpha1][alpha2],[alpha1]blend=all_mode=lighten[lighten],[alpha2][lighten]blend=all_mode=difference,geq=a='255':r='r(X,Y)':g='g(X,Y)':b='b(X,Y)'" -f apng "lightenedDif0-1.png" >nul 2>&1

rem %ffmpegPath% -hide_banner -y -i "alphaMapAlignmentTest0-1.png" -i "tempBlkFrameA.png" -filter_complex "[0]split=2[alpha1][alpha2],[alpha1]blend=all_mode=lighten[lighten],[alpha2][lighten]blend=all_mode=difference,geq=a='255':r='r(X,Y)':g='g(X,Y)':b='b(X,Y)'" -f apng "lightenedDif0-1.png" >nul 2>&1

%ffmpegPath% -hide_banner -y -i "alphaMapAlignmentTest0-1.png" -i "tempBlkFrameA.png" -filter_complex "[0]split=2[alpha1][alpha2],[alpha1]blend=all_mode=lighten[lighten],[alpha2][lighten]blend=all_mode=difference,geq=a='255':r='min(max(0,r(X,Y)-%difThreshold%)*255,255)':g='min(max(0,g(X,Y)-%difThreshold%)*255,255)':b='min(max(0,b(X,Y)-%difThreshold%)*255,255)'" -f apng "lightenedDif0-1.png" >nul 2>&1

rem %ffmpegPath% -hide_banner -y -i "lightenedDif0-1.png" -filter_complex "blackdetect=d=0.01:pix_th=0.01:pic_th=0.9985" -an -f null - 2> tempDifDetect0-1.txt

rem findstr sets errorlevel to 0 on found
rem findstr "black_start:0 black_end:" tempDifDetect0-1.txt
rem set detections=%errorlevel%

ECHO Processing alignment 1-2
rem frame 1-2
%ffmpegPath% -hide_banner -y -i %1 -filter_complex "[0] split=2 [a][b],[a]select=eq(n\,2)[blk],[b]select=eq(n\,1)[wht],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[alphaMapUse],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax]" -map "[alphaMax]" -q:v 0 -f apng "alphaMapAlignmentTest1-2.png"  >nul 2>&1

rem Use lighten blend filter as a check to see if the alpha map is correct as lightening should do nothing with a proper map, but create abberations with improper maps
rem %ffmpegPath% -hide_banner -y -i "alphaMapAlignmentTest1-2.png" -i "tempBlkFrameB.png" -filter_complex "[0]split=2[alpha1][alpha2],[alpha1]blend=all_mode=lighten[lighten],[alpha2][lighten]blend=all_mode=difference,geq=a='255':r='r(X,Y)':g='g(X,Y)':b='b(X,Y)'" -f apng "lightenedDif1-2.png" >nul 2>&1

rem %ffmpegPath% -hide_banner -y -i "alphaMapAlignmentTest1-2.png" -i "tempBlkFrameB.png" -filter_complex "[0]split=2[alpha1][alpha2],[alpha1]blend=all_mode=lighten[lighten],[alpha2][lighten]blend=all_mode=difference,geq=a='255':r='r(X,Y)':g='g(X,Y)':b='b(X,Y)'" -f apng "lightenedDif1-2.png" >nul 2>&1

%ffmpegPath% -hide_banner -y -i "alphaMapAlignmentTest1-2.png" -i "tempBlkFrameB.png" -filter_complex "[0]split=2[alpha1][alpha2],[alpha1]blend=all_mode=lighten[lighten],[alpha2][lighten]blend=all_mode=difference,geq=a='255':r='min(max(0,r(X,Y)-%difThreshold%)*255,255)':g='min(max(0,g(X,Y)-%difThreshold%)*255,255)':b='min(max(0,b(X,Y)-%difThreshold%)*255,255)'" -f apng "lightenedDif1-2.png" >nul 2>&1

rem %ffmpegPath% -hide_banner -y -i "lightenedDif1-2.png" -filter_complex "blackdetect=d=0.01:pix_th=0.01:pic_th=0.9985" -an -f null - 2> tempDifDetect1-2.txt

rem findstr "black_start:0 black_end:" tempDifDetect1-2.txt
rem set /a "detections=detections+%errorlevel%"
rem set pairAssumption=Pairs
rem if %detections%==0 (
rem     Echo WARNING: Failed to detect frame pair alignment, both pairs look good, output may contain ghosting if guess is incorrect.
rem 	set pairAssumption=Guessing pairs
rem )
rem if %detections%==2 (
rem     Echo WARNING: Failed to detect frame pair alignment, both pairs look bad, output may contain ghosting if guess is incorrect.
rem 	set pairAssumption=Guessing pairs
rem )
rem 
rem findstr "black_start:0 black_end:" tempDifDetect0-1.txt >nul 2>&1 && goto :firstPairAligned || goto :secondPairAligned

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

rem Use pause here to debug and take a look at intermediate data files
rem pause

ECHO Cleaning up temp files...
del /F tempFrame0.png
del /F tempFrame1.png
rem del /F tempBlackDetect.txt
del /F alphaMapAlignmentTest0-1.png
del /F alphaMapAlignmentTest1-2.png
rem del /F tempDifDetect0-1.txt
rem del /F tempDifDetect1-2.txt
del /F tempBlkFrameA.png
del /F tempBlkFrameB.png
del /F lightenedDif0-1.png
del /F lightenedDif1-2.png
rem del /F lightenedDifT0-1.png
rem del /F lightenedDifT1-2.png

if /I "%Aligned%"=="y" goto aligned
goto misaligned
:aligned
set select1="mod(%polarity2%\,2)"
set select2="mod(%polarity1%\,2)"
set select3=%select1%
goto endAlignment
rem I need to do something to discard the first frame, as a misaligned input means I cant grab the right black frame for comparing
:misaligned
set select1="gt(n\,0)*mod(%polarity2%\,2)"
set select2="gt(n\,0)*mod(%polarity1%\,2)"
set select3=%select1%
:endAlignment
ECHO.
set ptsAdjust=,setpts=PTS-STARTPTS

rem Take a 120 FPS video input, splitting it into white/black
rem Extract alphamap video from all pairs
rem %ffmpegPath% -i %1 -filter_complex "[0] asplit=3 [a][b][c],[a]select="mod(n-1\,2)"[evens],[b]select="mod(n\,2)"[odds],[evens]format=gbrp[v1],[odds]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],

rem Max channels of extracted alpha, setting each to the max of r,g,b
rem [alphaMap]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],

rem Use alphamerge to apply the rgb intensity from the maxed alpha to the alpha channel of the black frameset
rem [c][alphaMax]alphamerge[transparent1],

rem use alphaboost to boost the color intensity to the proper target values
rem [transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))'"

ECHO Checking output extension "%outputExt%"
ECHO Solving for video output...
if %outputExt%==mkv goto ffv1Ext
if %outputExt%==mov goto ffv1Ext
if %outputExt%==avi goto ffv1Ext
if %outputExt%==webm goto vp9Select
if %outputExt%==gif goto gifSelect
goto apngSelect

:ffv1Ext
rem This works MKV MOV AVI
%ffmpegPath% -v error -stats -i %1 -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[blk2],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[blk2]setpts=0.5*PTS[d],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -c:v ffv1 -pix_fmt yuva420p "%~dp1\fullTransparent - %~n1.%outputExt%" -map "[out2]" -c:v ffv1 -pix_fmt yuva420p "%~dp1\alphaMap - %~n1.%outputExt%"
goto endExtSelect

:vp9Select
rem This works WEBM, though many players produce ugly artifacts
%ffmpegPath% -v error -stats -i %1 -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[blk2],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[blk2]setpts=0.5*PTS[d],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -c:v vp9 -crf 0 -pix_fmt yuva420p "%~dp1\fullTransparent - %~n1.%outputExt%" -map "[out2]" -c:v vp9 -crf 0 -pix_fmt yuva420p "%~dp1\alphaMap - %~n1.%outputExt%"
goto endExtSelect

:gifSelect
ECHO Solving for gif, this may appear stuck for many seconds before the gif starts to build...
rem This works GIF, though 1 bit depth for alpha is not ideal
%ffmpegPath% -v error -stats -i %1 -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[blk2],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[out2]split [ia][ka];[ia] palettegen [pa];[ka]fifo[ma];[ma][pa] paletteuse=dither=none[out3],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[blk2]setpts=0.5*PTS[d],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',split [i][k];[i] palettegen [p];[k]fifo[m];[m][p] paletteuse=dither=none:alpha_threshold=120" -q:v 0 -r 50 "%~dp1\fullTransparent - %~n1.%outputExt%" -map "[out3]" -q:v 0 -r 50 "%~dp1\alphaMap - %~n1.%outputExt%"
goto endExtSelect

:apngSelect
rem Assume apng as fallback
set outputExt=png
rem This works APNG
%ffmpegPath% -v error -stats -i %1 -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[blk2],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[blk2]setpts=0.5*PTS[d],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -q:v 0 -f apng -plays 0 "%~dp1\fullTransparent - %~n1.%outputExt%" -map "[out2]" -q:v 0 -f apng -plays 0 "%~dp1\alphaMap - %~n1.%outputExt%"

:endExtSelect

ECHO Process finished, you may close this window.
pause