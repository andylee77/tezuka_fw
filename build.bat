@echo off
REM ============================================================================
REM build.bat — Tezuka Firmware Builder (Fishball Z7020)
REM
REM Builds firmware from the clean fork at:
REM   C:\Users\Andy\Projects\Tezuka\tezuka_fw
REM
REM Uses Docker with a persistent build volume for fast builds.
REM
REM Usage:
REM   build.bat                  Full build (reuses cache if available)
REM   build.bat --clean          Delete build cache, start fresh
REM   build.bat --interactive    Open Docker shell for manual work
REM
REM Prerequisites:
REM   - Docker Desktop running
REM   - Docker image: br_tezuka:2025.02.3
REM ============================================================================
setlocal enabledelayedexpansion

echo.
echo === Tezuka Firmware Build (Fishball Z7020) ===
echo.

REM ── Check Docker ────────────────────────────────────────────────────────────
docker --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not running. Please start Docker Desktop.
    pause
    exit /b 1
)
echo [OK] Docker is available.

REM ── Paths ───────────────────────────────────────────────────────────────────
set "PROJECT_DIR=%~dp0"
REM Remove trailing backslash
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

set "DOCKER_IMAGE=br_tezuka:2025.02.3"
set "DOCKER_VOLUME=tezuka-build"

REM Convert Windows path to Docker mount format (/c/Users/...)
set "WIN_PATH=%PROJECT_DIR%"
set "DRIVE=%WIN_PATH:~0,1%"
set "REST=%WIN_PATH:~2%"
set "REST=%REST:\=/%"
REM Lowercase drive letter
for %%L in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do (
    if /i "%DRIVE%"=="%%L" set "DRIVE_LOWER=%%L"
)
set "DOCKER_SRC=/%DRIVE_LOWER%%REST%"

echo [OK] Project: %PROJECT_DIR%
echo [OK] Docker mount: %DOCKER_SRC%

REM ── Check Docker image ─────────────────────────────────────────────────────
docker image inspect %DOCKER_IMAGE% >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker image '%DOCKER_IMAGE%' not found.
    echo Run getbuildroot.sh first to set up the Docker image.
    pause
    exit /b 1
)
echo [OK] Docker image: %DOCKER_IMAGE%

REM ── Parse arguments ─────────────────────────────────────────────────────────
set "MODE=build"
set "INTERACTIVE=false"

if "%~1"=="--clean" (
    echo.
    echo [WARN] This will delete the build cache volume '%DOCKER_VOLUME%'.
    echo        Next build will take 1-3 hours to rebuild everything.
    set /p "CONFIRM=Continue? [y/N] "
    if /i not "!CONFIRM!"=="y" exit /b 0
    docker volume rm %DOCKER_VOLUME% 2>nul
    echo [OK] Build volume deleted.
    echo.
)
if "%~1"=="--interactive" (
    set "INTERACTIVE=true"
)

echo.

REM ── Launch Docker ───────────────────────────────────────────────────────────
if "%INTERACTIVE%"=="true" (
    echo Launching interactive Docker shell...
    echo Inside the container:
    echo   bash /mnt/src/build.sh
    echo.

    docker run -it --rm ^
        --user 0:0 ^
        -v "%PROJECT_DIR%:%DOCKER_SRC%" ^
        -v %DOCKER_VOLUME%:/home/br-user/tezuka_build ^
        -e "SRC_MOUNT=%DOCKER_SRC%" ^
        -w /home/br-user/tezuka_build ^
        %DOCKER_IMAGE% ^
        /bin/bash
) else (
    echo Starting firmware build...
    echo   Image:  %DOCKER_IMAGE%
    echo   Volume: %DOCKER_VOLUME% (persistent build cache)
    echo   Source: %DOCKER_SRC%
    echo.

    docker run -i --rm ^
        --user 0:0 ^
        -v "%PROJECT_DIR%:%DOCKER_SRC%" ^
        -v %DOCKER_VOLUME%:/home/br-user/tezuka_build ^
        -e "SRC_MOUNT=%DOCKER_SRC%" ^
        -w /home/br-user/tezuka_build ^
        %DOCKER_IMAGE% ^
        /bin/bash "%DOCKER_SRC%/build.sh"
)

if errorlevel 1 (
    echo.
    echo [ERROR] Build failed. Check output above.
    pause
    exit /b 1
)

echo.
echo ============================================================================
echo BUILD COMPLETE
echo ============================================================================
echo.
echo Firmware images: %PROJECT_DIR%\output_images\
echo.
echo Deploy:
echo   1. Format SD card as FAT32
echo   2. Copy contents of output_images\sdimg\ to SD card root
echo   3. Boot Fishball 7020 from SD card
echo   4. Verify: ssh root@192.168.120.50 "cat /sys/firmware/devicetree/base/model"
echo      Expected: FISH Ball PlutoSDR Rev.A (Z7020/AD9361)
echo.
pause
