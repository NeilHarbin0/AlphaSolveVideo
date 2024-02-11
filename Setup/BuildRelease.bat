rem Copy files to a release directory
rem Copy scripts
xcopy "..\Scripts\*.bat" ".\bin\Release\Scripts" /c /i /y
rem Copy example videos
xcopy "..\Resources\*.avi" ".\bin\Release\Resources" /c /i /y
rem Copy codes
xcopy "..\Resources\*.txt" ".\bin\Release\Resources" /c /i /y
rem Copy ffmpeg
xcopy "..\packages\ffmpeg-6.0-full_build\bin\ffmpeg.exe" ".\bin\Release\" /c /y
rem Copy license
xcopy "..\LICENSE" ".\bin\Release\" /c /y

rem Zip bin into a release
"C:\Program Files\7-Zip\7z.exe" a ".\bin\AlphaSolveVideo.zip" ".\bin\Release\*" -aoa
pause