@echo off
setlocal

pushd "%~dp0"
if errorlevel 1 (
    echo Failed to open the script directory.
    echo.
    echo Press any key to exit...
    pause >nul
    exit /b 1
)

set "SUMMERDREAM_STORY_LAUNCHER=cmd"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Build-StoryText.ps1"
set "STORY_EXTRACT_EXIT_CODE=%ERRORLEVEL%"

if not "%STORY_EXTRACT_EXIT_CODE%"=="0" (
    echo.
    echo Story extraction failed. Exit code: %STORY_EXTRACT_EXIT_CODE%
    echo Press any key to exit...
    pause >nul
    popd
    exit /b %STORY_EXTRACT_EXIT_CODE%
)

popd
exit /b 0
