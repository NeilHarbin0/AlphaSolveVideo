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

set ffmpegPath="C:\Program Files\Simple Video Editor\ffmpeg.exe"
set outputExt=%~2
if NOT DEFINED [%2] set outputExt=png

rem Use info from https://superuser.com/questions/1615310/how-to-use-ffmpeg-blend-difference-filter-mode-to-identify-frame-differences-bet to automatically figure out what is what so we don't have to ask the user. Just knowing if the frame is black or not will tell us everything, as if the flicker doesn't get misaligned, it should always go black-white or white-black without any change.

ECHO Detecting first frame background color
%ffmpegPath% -hide_banner -i %1 -vf "select=eq(n\,0)" -an -f apng -y tempFrame0.png
pause
%ffmpegPath% -hide_banner -i tempFrame0.png -vf "blackdetect=d=0.01:pix_th=0.05:pic_th=0.1" -an -f null - 2> tempBlackDetect.txt

findstr "black_start:0 black_end:" tempBlackDetect.txt && goto :isBlack || goto :isWhite

:isBlack
ECHO Detected black start frame
set polarity1=n
set polarity2=n-1
set blkFrame=0
goto endPolarity
:isWhite
ECHO Failed to detect black start frame, assuming white
set polarity1=n-1
set polarity2=n
set blkFrame=1
:endPolarity

ECHO Exporting black frame
%ffmpegPath% -hide_banner -i %1 -vf "select=eq(n\,%blkFrame%)" -an -f apng -y tempBlkFrame%blkFrame%.png

rem Check alignment by taking the first 3 frames, applying the technique both ways, then checking the images against eachother
ECHO Detecting frame pair alignment

rem frame 0-1
%ffmpegPath% -hide_banner -i %1 -filter_complex "[0] split=3 [a][b][c],[a]select=eq(n\,1)[blk],[b]select=eq(n\,0)[wht],[c]select=eq(n\,1)[blk2],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[blk2]setpts=0.5*PTS[d],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -q:v 0 -f apng -plays 0 "transparentAlignmentTest0-1.png" -map "[out2]" -q:v 0 -f apng "alphaMapAlignmentTest0-1.png"

rem frame 1-2
%ffmpegPath% -hide_banner -i %1 -filter_complex "[0] split=3 [a][b][c],[a]select=eq(n\,2)[blk],[b]select=eq(n\,1)[wht],[c]select=eq(n\,2)[blk2],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[blk2]setpts=0.5*PTS[d],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -q:v 0 -f apng -plays 0 "transparentAlignmentTest1-2.png" -map "[out2]" -q:v 0 -f apng  "alphaMapAlignmentTest1-2.png"

rem Apply transparent image to pure background, then compare

rem Apply to white (Applying to white won't actually help us compare because Melee seems to not do the overlay the same as applying putting on a white background)
rem %ffmpegPath% -hide_banner -i "transparentAlignmentTest0-1.png" -filter_complex "[0]format=argb,geq=a='255':r='r(X,Y)*(alpha(X,Y)/255)+255*(1-alpha(X,Y)/255)':g='g(X,Y)*(alpha(X,Y)/255)+255*(1-alpha(X,Y)/255)':b='b(X,Y)*(alpha(X,Y)/255)+255*(1-alpha(X,Y)/255)',format=argb[out1]" -map "[out1]" -q:v 0 -f apng -plays 0 "alignment0-1OnWhite.png"

rem Apply to black
%ffmpegPath% -hide_banner -i "transparentAlignmentTest0-1.png" -filter_complex "[0]format=argb,geq=a='255':r='r(X,Y)*(alpha(X,Y)/255)':g='g(X,Y)*(alpha(X,Y)/255)':b='b(X,Y)*(alpha(X,Y)/255)',format=argb[out1]" -map "[out1]" -q:v 0 -f apng "alignment0-1OnBlack.png"

%ffmpegPath% -hide_banner -i "transparentAlignmentTest1-2.png" -filter_complex "[0]format=argb,geq=a='255':r='r(X,Y)*(alpha(X,Y)/255)':g='g(X,Y)*(alpha(X,Y)/255)':b='b(X,Y)*(alpha(X,Y)/255)',format=argb[out1]" -map "[out1]" -q:v 0 -f apng "alignment1-2OnBlack.png"

rem Get the difference between the black overlaid transparent png and a source version
rem If they are different basically at all (with a very small amount of rounding error), then that should mean the opposite pair is good
%ffmpegPath% -hide_banner -i "alignment0-1OnBlack.png" -i tempBlkFrame%blkFrame%.png -filter_complex "blend=all_mode=difference,geq=a='255':r='r(X,Y)':g='g(X,Y)':b='b(X,Y)',blackdetect=d=0.01:pix_th=0.01:pic_th=0.99" -an -f null - 2> tempDifDetect0-1.txt
%ffmpegPath% -hide_banner -i "alignment0-1OnBlack.png" -i tempBlkFrame%blkFrame%.png -filter_complex "blend=all_mode=difference,geq=a='255':r='r(X,Y)':g='g(X,Y)':b='b(X,Y)'" -q:v 0 -f apng "tempDifDetect0-1.png"

rem %ffmpegPath% -hide_banner -i "alignment1-2OnBlack.png" -i tempBlkFrame%blkFrame%.png -filter_complex "blend=all_mode=difference,geq=a='255':r='r(X,Y)':g='g(X,Y)':b='b(X,Y)',blackdetect=d=0.01:pix_th=0.01:pic_th=0.99" -an -f null - 2> tempDifDetect1-2.txt
rem %ffmpegPath% -hide_banner -i "alignment1-2OnBlack.png" -i tempBlkFrame%blkFrame%.png -filter_complex "blend=all_mode=difference,geq=a='255':r='r(X,Y)':g='g(X,Y)':b='b(X,Y)'" -q:v 0 -f apng "tempDifDetect1-2.png"

findstr "black_start:0 black_end:" tempDifDetect0-1.txt && goto :firstPair || goto :secondPair

:firstPair
Echo Pairs are aligned 0-1
set Aligned=y
goto endAlignmentCheck
:secondPair
Echo Pairs are not aligned 0-1, offset +1
set Aligned=n
:endAlignmentCheck

ECHO Cleaning up temp files...
del /F tempFrame0.png
del /F tempBlackDetect.txt
del /F transparentAlignmentTest0-1.png
del /F alphaMapAlignmentTest0-1.png
del /F transparentAlignmentTest1-2.png
del /F alphaMapAlignmentTest1-2.png
del /F alphaMapAlignmentTest1-2.png
del /F tempDifDetect0-1.txt
del /F tempDifDetect0-1.png
del /F alignment0-1OnBlack.png
del /F alignment1-2OnBlack.png
del /F tempBlkFrame%blkFrame%.png

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

rem %ffmpegPath% -i %1 -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[blk2],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],[alphaMap]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[blk2]setpts=0.5*PTS[d],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',split [i][k];[i] palettegen [p];[k]fifo[m];[m][p] paletteuse=dither=bayer" -q:v 0 "fullTransparent - %~n1.gif"

ECHO Checking output extension "%outputExt%"
if %outputExt%==mkv goto ffv1Ext
if %outputExt%==mov goto ffv1Ext
if %outputExt%==avi goto ffv1Ext
if %outputExt%==webm goto vp9Select
goto apngSelect

:ffv1Ext
rem This works MKV MOV AVI
%ffmpegPath% -hide_banner -i %1 -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[blk2],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[blk2]setpts=0.5*PTS[d],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -c:v ffv1 -pix_fmt yuva420p "%~dp1\fullTransparent - %~n1.%outputExt%" -map "[out2]" -c:v ffv1 -pix_fmt yuva420p "%~dp1\alphaMap - %~n1.%outputExt%"
goto endExtSelect

:vp9Select
rem This works WEBM, though many players produce ugly artifacts
%ffmpegPath% -hide_banner -i %1 -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[blk2],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[blk2]setpts=0.5*PTS[d],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -c:v vp9 -crf 0 -pix_fmt yuva420p "%~dp1\fullTransparent - %~n1.%outputExt%" -map "[out2]" -c:v vp9 -crf 0 -pix_fmt yuva420p "%~dp1\alphaMap - %~n1.%outputExt%"
goto endExtSelect

:apngSelect
rem Assume apng as fallback
set outputExt=png
rem This works APNG
%ffmpegPath% -hide_banner -i %1 -filter_complex "[0] split=3 [a][b][c],[a]select=%select1%%ptsAdjust%[blk],[b]select=%select2%%ptsAdjust%[wht],[c]select=%select3%%ptsAdjust%[blk2],[blk]format=gbrp[v1],[wht]format=gbrp[v2],[v1][v2]blend=all_mode=difference,negate,format=yuv420p[map],[map]setpts=0.5*PTS[alphaMap],[alphaMap]split=2[alphaMapUse][out2],[alphaMapUse]format=argb,geq=a='255':r='max(max(r(X,Y),g(X,Y)),b(X,Y))':g='max(max(r(X,Y),g(X,Y)),b(X,Y))':b='max(max(r(X,Y),g(X,Y)),b(X,Y))'[alphaMax],[blk2]setpts=0.5*PTS[d],[d][alphaMax]alphamerge[transparent1],[transparent1]format=argb,geq=a='alpha(X,Y)':r='min(255,r(X,Y)*(255/alpha(X,Y)))':g='min(255,g(X,Y)*(255/alpha(X,Y)))':b='min(255,b(X,Y)*(255/alpha(X,Y)))',format=argb[out1]" -map "[out1]" -q:v 0 -f apng -plays 0 "%~dp1\fullTransparent - %~n1.%outputExt%" -map "[out2]" -q:v 0 -f apng -plays 0 "%~dp1\alphaMap - %~n1.%outputExt%"

:endExtSelect

pause