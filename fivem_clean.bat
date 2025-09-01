@echo off
setlocal EnableExtensions EnableDelayedExpansion
title "FiveM Cleanup and Log Archiver"

rem ------------------ Config ------------------
set "RETENTION_DAYS=14"
set "ARCHIVE_ROOT=%USERPROFILE%\Documents\FiveM-Logs"
set "DO_WINSOCK_RESET=0"

rem Relaunch controls
set "RELAUNCH=1"                 rem 1 = relaunch Steam, Discord, FiveM at the end
set "LAUNCH_STEAM=1"             rem 1 = launch Steam unless /skip-steam
set "LAUNCH_DISCORD=1"           rem 1 = launch Discord unless /skip-discord
set "LAUNCH_FIVEM=1"             rem 1 = launch FiveM (unless you pass /norelaunch)

rem Boot timing (adjust if your PC is slow or very fast)
set "STEAM_BOOT_WAIT=15"         rem seconds to let Steam settle before Discord
set "DISCORD_BOOT_WAIT=8"        rem seconds before launching FiveM
set "FIVEM_POST_WAIT=2"          rem cosmetic pause at the end
rem -------------------------------------------

rem Flags:
rem   /winsock
rem   /retention:NN
rem   /norelaunch
rem   /skip-steam
rem   /skip-discord
for %%A in (%*) do (
  if /I "%%~A"=="/winsock" set "DO_WINSOCK_RESET=1"
  if /I "%%~A"=="/norelaunch" set "RELAUNCH=0"
  if /I "%%~A"=="/skip-steam" set "LAUNCH_STEAM=0"
  if /I "%%~A"=="/skip-discord" set "LAUNCH_DISCORD=0"
  for /f "tokens=1,2 delims=:" %%K in ("%%~A") do (
    if /I "%%~K"=="/retention" set "RETENTION_DAYS=%%~L"
  )
)

echo(
echo === FiveM Cleanup Tool ===
echo Retention: %RETENTION_DAYS% day(s)
if "%DO_WINSOCK_RESET%"=="1" (
  echo Winsock reset: ENABLED - admin required, reboot after run
) else (
  echo Winsock reset: disabled - use /winsock to enable
)
if "%RELAUNCH%"=="1" (
  echo Relaunch after cleanup: enabled
) else (
  echo Relaunch after cleanup: disabled
)
echo --------------------------------------------
echo(

rem Paths
set "FIVEM_APP=%LOCALAPPDATA%\FiveM\FiveM.app"
set "FIVEM_DATA=%FIVEM_APP%\data"
set "FIVEM_LOGS=%FIVEM_APP%\logs"
set "FIVEM_CRASHES=%FIVEM_APP%\crashes"
set "ROAMING_CFX=%APPDATA%\CitizenFX"

rem Launchers (edit if your install is nonstandard)
set "STEAM_EXE=%ProgramFiles(x86)%\Steam\steam.exe"
set "DISCORD_UPD=%LOCALAPPDATA%\Discord\Update.exe"
set "FIVEM_EXE=%LOCALAPPDATA%\FiveM\FiveM.exe"

if not exist "%FIVEM_APP%" (
  echo [WARN] FiveM not found at "%FIVEM_APP%"
  echo Adjust the FIVEM_APP path if needed
  echo(
) else (
  echo Found FiveM at: "%FIVEM_APP%"
)

if not exist "%ARCHIVE_ROOT%" mkdir "%ARCHIVE_ROOT%" >nul 2>&1

echo(
echo [STEP] Closing FiveM, Steam, and Discord if running...

rem Close FiveM first
taskkill /IM FiveM.exe /F >nul 2>&1
taskkill /IM FiveM_b2189_GTAProcess.exe /F >nul 2>&1
taskkill /IM GTA5.exe /F >nul 2>&1

rem Close Discord (all helper processes)
taskkill /IM Discord.exe /F >nul 2>&1
taskkill /IM Update.exe /F >nul 2>&1
taskkill /IM Squirrel.exe /F >nul 2>&1

rem Close Steam (and helpers)
taskkill /IM steam.exe /F >nul 2>&1
taskkill /IM steamservice.exe /F >nul 2>&1
taskkill /IM steamwebhelper.exe /F >nul 2>&1

rem --- Clear FiveM caches ---
if exist "%FIVEM_DATA%" (
  echo(
  echo [STEP] Clearing FiveM data caches in "%FIVEM_DATA%"
  set "FOUND_CACHE="
  for /D %%D in ("%FIVEM_DATA%\*cache*") do (
    set "FOUND_CACHE=1"
    echo   - Remove "%%~fD"
    rd /S /Q "%%~fD" 2>nul
  )
  for %%F in ("%FIVEM_DATA%\*cache*") do (
    if exist "%%~fF" (
      set "FOUND_CACHE=1"
      echo   - Delete "%%~fF"
      del /F /Q "%%~fF" 2>nul
    )
  )
  if not defined FOUND_CACHE echo   - No cache entries found
) else (
  echo [INFO] No FiveM data folder at "%FIVEM_DATA%"
)

rem --- Clear CitizenFX kvs ---
if exist "%ROAMING_CFX%\kvs" (
  echo(
  echo [STEP] Clearing CitizenFX kvs
  rd /S /Q "%ROAMING_CFX%\kvs" 2>nul
)

rem --- Archiving (PowerShell does discovery + de-dupe) ---
echo(
echo [STEP] Archiving logs and crash dumps...
for /f %%T in ('powershell -NoProfile -Command "(Get-Date).ToString(\"yyyyMMdd_HHmmss\")"') do set "STAMP=%%T"
set "ARCHIVE_FILE=%ARCHIVE_ROOT%\FiveM_Logs_%STAMP%.zip"

powershell -NoProfile -Command ^
  "$paths = @('%FIVEM_LOGS%','%FIVEM_CRASHES%','%FIVEM_APP%') | Where-Object { Test-Path $_ };" ^
  "$files = foreach($p in $paths){ Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.log(\.|$)|\.md?mp$|\.txt$' } };" ^
  "$files = $files | Sort-Object FullName -Unique | Where-Object { Test-Path $_.FullName };" ^
  "if($files -and $files.Count -gt 0){" ^
  "  if(Test-Path '%ARCHIVE_FILE%'){ Remove-Item -LiteralPath '%ARCHIVE_FILE%' -Force }" ^
  "  Compress-Archive -LiteralPath ($files.FullName) -DestinationPath '%ARCHIVE_FILE%' -Force;" ^
  "  Write-Host '   -> Archive complete'" ^
  "} else {" ^
  "  Write-Host '   -> No files to archive'" ^
  "}"

echo(
echo [STEP] Removing logs and dumps older than %RETENTION_DAYS% day(s)...
powershell -NoProfile -Command ^
  "$paths = @('%FIVEM_LOGS%','%FIVEM_CRASHES%','%FIVEM_APP%');" ^
  "foreach($p in $paths){ if(Test-Path $p){" ^
  "  Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue |" ^
  "  Where-Object { $_.Name -match '\.log(\.|$)|\.md?mp$|\.txt$' -and $_.LastWriteTime -lt (Get-Date).AddDays(-%RETENTION_DAYS%) } |" ^
  "  Remove-Item -Force -ErrorAction SilentlyContinue }}" ^
  "Write-Host '   -> Old files pruned'"

echo(
echo [STEP] Clearing GPU shader caches...
for %%D in (
  "%LOCALAPPDATA%\NVIDIA\GLCache"
  "%LOCALAPPDATA%\NVIDIA\DXCache"
  "%LOCALAPPDATA%\D3DSCache"
  "%LOCALAPPDATA%\AMD\DxCache"
  "%LOCALAPPDATA%\ATI\GLCache"
  "%LOCALAPPDATA%\Intel\ShaderCache"
) do (
  if exist "%%~fD" (
    echo   - Purge "%%~fD"
    rd /S /Q "%%~fD" 2>nul
  )
)
echo(
echo [STEP] Flushing DNS cache...
ipconfig /flushdns >nul

:: --- Winsock reset (guarded by GOTO to avoid ELSE parsing issues) ---
if not "%DO_WINSOCK_RESET%"=="1" goto :after_winsock
echo(
echo [STEP] Winsock reset requested
>nul 2>&1 net session
if errorlevel 1 (
  echo [ERROR] Admin rights required for winsock reset
) else (
  netsh winsock reset
  echo [INFO] Winsock reset complete - reboot Windows
)
:after_winsock

:: ---------------- Relaunch sequence ----------------
if not "%RELAUNCH%"=="1" goto :after_launch
echo(
echo [STEP] Relaunching in order to avoid steam ticket hangs

:: Steam
if "%LAUNCH_STEAM%"=="1" (
  if exist "%STEAM_EXE%" (
    echo   - Starting Steam
    start "" "%STEAM_EXE%" -silent
  ) else (
    echo   - Steam not found at "%STEAM_EXE%"
  )
) else (
  echo   - Skipping Steam launch by request
)

if "%LAUNCH_STEAM%"=="1" timeout /t %STEAM_BOOT_WAIT% /nobreak >nul

:: Discord
if "%LAUNCH_DISCORD%"=="1" (
  if exist "%DISCORD_UPD%" (
    echo   - Starting Discord
    start "" "%DISCORD_UPD%" --processStart "Discord.exe"
  ) else (
    echo   - Discord updater not found at "%DISCORD_UPD%"
  )
) else (
  echo   - Skipping Discord launch by request
)

if "%LAUNCH_DISCORD%"=="1" timeout /t %DISCORD_BOOT_WAIT% /nobreak >nul

:: FiveM
if "%LAUNCH_FIVEM%"=="1" (
  if exist "%FIVEM_EXE%" (
    echo   - Starting FiveM
    start "" "%FIVEM_EXE%"
  ) else (
    echo   - FiveM launcher not found at "%FIVEM_EXE%"
  )
) else (
  echo   - Skipping FiveM launch by request
)

if %FIVEM_POST_WAIT% GTR 0 timeout /t %FIVEM_POST_WAIT% /nobreak >nul
:after_launch

echo(
echo [DONE] Cleanup complete
if exist "%ARCHIVE_FILE%" echo - Archive: "%ARCHIVE_FILE%"
echo - Old logs/dumps older than %RETENTION_DAYS% day(s) removed
if "%DO_WINSOCK_RESET%"=="1" echo - Winsock reset attempted
echo(
pause
endlocal
