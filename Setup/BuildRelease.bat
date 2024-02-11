rem Copy files to a release directory
rem Copy everything from scripts to bin
xcopy "..\Scripts\*.bat" ".\bin\Release\Scripts" /c /i /y
rem Copy example videos from resources to bin
xcopy "..\Resources\*.avi" ".\bin\Release\Resources" /c /i /y
rem Copy ffmpeg to bin
xcopy "..\packages\ffmpeg-6.0-full_build\bin\ffmpeg.exe" ".\bin\Release\" /c /y
rem Copy license
xcopy "..\LICENSE" ".\bin\Release\" /c /y

rem Zip bin into a release
"C:\Program Files\7-Zip\7z.exe" a ".\bin\AlphaSolveVideo.zip" ".\bin\Release\*" -aoa
pause