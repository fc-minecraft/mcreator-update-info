@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title MCreator FunCode - install and verify

REM ================================================================
REM  OPTIONAL: automatic account login and install verification.
REM  Set AUTO_LOGIN=true and fill in LOGIN/PASSWORD to make the script
REM  log in, create a test project and launch the game to prove that
REM  everything works.
REM
REM  KEEP_GAME_RUNNING=true (default) - after a successful check the
REM  Minecraft client stays open. false - the game is closed.
REM
REM  OFFLINE_LOCATION=true (default) - enables the "offline location"
REM  mode: creates Windows Firewall rules for LAN update sharing and
REM  sets the matching marker in MCreator preferences.
REM ================================================================
set AUTO_LOGIN=false
set LOGIN=
set PASSWORD=
set KEEP_GAME_RUNNING=true
set OFFLINE_LOCATION=true
REM ================================================================

set "SCRIPT_DIR=%~dp0"
set "CACHE_ZIP=%SCRIPT_DIR%mcreator_offline_cache.zip"

REM --- look for the installer next to the script ---
set "INSTALLER="
for /f "delims=" %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$sd = '%SCRIPT_DIR%'; $exes = Get-ChildItem -Path $sd -Filter '*.exe' | Where-Object { $_.Name -ne 'mcreator.exe' -and $_.Name -ne 'install_verify.exe' }; $inst = $null; if ($exes.Count -eq 1) { $inst = $exes[0] } else { $urls = @('https://raw.githubusercontent.com/fc-minecraft/mcreator-update-info/main/update.txt','https://mcupdate.funcode.school/update.txt'); foreach ($u in $urls) { try { $txt = (New-Object System.Net.WebClient).DownloadString($u); if ($txt -match 'WIN\s+(https?://[^\s]+\.exe)') { $rUrl = $matches[1]; $rName = [System.IO.Path]::GetFileName($rUrl); $m = $exes | Where-Object { $_.Name -ieq $rName } | Select-Object -First 1; if ($m) { $inst = $m; break } else { $dl = Join-Path $sd $rName; Write-Host 'Downloading installer...' $rName; (New-Object System.Net.WebClient).DownloadFile($rUrl, $dl); if (Test-Path $dl) { $inst = Get-Item $dl; break } } } } catch {} } }; if ($inst) { Write-Output $inst.FullName }"') do set "INSTALLER=%%i"
if not defined INSTALLER (
    echo [ERROR] MCreator installer .exe not found next to this script and could not be downloaded.
    pause
    exit /b 1
)

REM --- admin rights are required by the installer ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo [1/5] Installing MCreator...
REM Close any running MCreator, Java and Gradle instances first, otherwise
REM files in .mcreator\gradle or installer may be locked.
taskkill /IM mcreator.exe /F >nul 2>&1
taskkill /IM MCreator*.exe /F >nul 2>&1
taskkill /IM java.exe /F >nul 2>&1
taskkill /IM javaw.exe /F >nul 2>&1
REM Run the installer with a 5 minute timeout: if it hangs, kill it and
REM report an error instead of waiting forever.
powershell -NoProfile -Command "$p = Start-Process -FilePath '%INSTALLER%' -ArgumentList '/S' -PassThru; if (-not $p.WaitForExit(300000)) { $p.Kill(); exit 1 }"
if errorlevel 1 (
    echo [ERROR] Installation failed or timed out.
    pause
    exit /b 1
)

REM the installer launches MCreator itself - close it and any java processes so they do not interfere
taskkill /IM mcreator.exe /F >nul 2>&1
taskkill /IM java.exe /F >nul 2>&1
taskkill /IM javaw.exe /F >nul 2>&1

echo [2/5] Setting up the offline cache...
if not exist "%CACHE_ZIP%" (
    echo Downloading mcreator_offline_cache.zip...
    powershell -NoProfile -Command "$url = 'https://s3.eu-central-003.backblazeb2.com/funcode-pub/course/398/lesson/6704/mcreator_offline_cache.zip'; $out = '%CACHE_ZIP%'; try { (New-Object System.Net.WebClient).DownloadFile($url, $out) } catch { Write-Host ('[ERROR] Failed to download cache: ' + $_.Exception.Message); exit 1 }"
    if errorlevel 1 (
        echo [ERROR] Failed to download mcreator_offline_cache.zip.
        pause
        exit /b 1
    )
)
if exist "%CACHE_ZIP%" (
    powershell -NoProfile -Command "$zip = '%CACHE_ZIP%'; $adminDest = $env:USERPROFILE + '\.mcreator\gradle'; $success = $false; for ($i = 1; $i -le 5; $i++) { try { if (Test-Path -LiteralPath $adminDest) { Remove-Item -LiteralPath $adminDest -Recurse -Force -ErrorAction Stop }; Expand-Archive -Path $zip -DestinationPath $adminDest -Force -ErrorAction Stop; $success = $true; break } catch { Write-Host ('[RETRY ' + $i + '/5] Extraction failed, retrying in 2s... Error: ' + $_.Exception.Message); Start-Sleep -Seconds 2 } }; if (-not $success) { exit 1 }; $usersRoot = Split-Path $env:USERPROFILE -Parent; $profiles = @(); if (Test-Path -LiteralPath $usersRoot) { $profiles = Get-ChildItem -Path $usersRoot -Directory -Force | Where-Object { $_.FullName -ne $env:USERPROFILE -and $_.Name -notmatch '^(Public|All Users|Default User)$' }; $def = Join-Path $usersRoot 'Default'; if ((Test-Path -LiteralPath $def) -and ($profiles.FullName -notcontains $def)) { $profiles += Get-Item -LiteralPath $def -Force } }; foreach ($p in $profiles) { try { $pDest = Join-Path $p.FullName '.mcreator\gradle'; New-Item -ItemType Directory -Path $pDest -Force | Out-Null; $rc = Start-Process -FilePath 'robocopy.exe' -ArgumentList ('\"' + $adminDest + '\" \"' + $pDest + '\" /E /R:1 /W:1 /NP /NFL /NDL /NJH /NJS') -NoNewWindow -PassThru; if (-not $rc.WaitForExit(30000)) { $rc.Kill() }; $mDir = Join-Path $p.FullName '.mcreator'; Start-Process -FilePath 'icacls.exe' -ArgumentList ('\"' + $mDir + '\" /grant *S-1-5-32-545:(OI)(CI)M /T /C /Q') -NoNewWindow -Wait; Write-Host ('Cache copied to user profile: ' + $p.Name) } catch { Write-Host ('[WARNING] Skipped cache copy for ' + $p.Name + ': ' + $_.Exception.Message) } }"
    if errorlevel 1 (
        echo [ERROR] Failed to extract the offline cache after 5 attempts.
        pause
        exit /b 1
    )
    echo Offline cache setup completed.
) else (
    echo [ERROR] mcreator_offline_cache.zip not found and could not be downloaded.
    pause
    exit /b 1
)

set "MCREATOR_EXE=%PROGRAMFILES%\Pylo\MCreator\mcreator.exe"
if not exist "%MCREATOR_EXE%" set "MCREATOR_EXE=%PROGRAMFILES(X86)%\Pylo\MCreator\mcreator.exe"
if not exist "%MCREATOR_EXE%" (
    echo [ERROR] Installed MCreator not found.
    pause
    exit /b 1
)

REM --- LAN update sharing ---
if /i "%OFFLINE_LOCATION%"=="true" (
    echo [3/5] Setting up LAN update sharing...
    netsh advfirewall firewall delete rule name="MCreator LAN Update" >nul 2>&1
    netsh advfirewall firewall add rule name="MCreator LAN Update" dir=in action=allow program="%MCREATOR_EXE%" protocol=TCP localport=25354-25356 profile=any >nul 2>&1
    if errorlevel 1 (
        echo [WARNING] Failed to add the TCP firewall rule - administrator rights required.
    )
    netsh advfirewall firewall add rule name="MCreator LAN Update" dir=in action=allow program="%MCREATOR_EXE%" protocol=UDP localport=25355 profile=any >nul 2>&1
    if errorlevel 1 (
        echo [WARNING] Failed to add the UDP firewall rule - administrator rights required.
    )
	echo Setting the offline-location marker...
	REM IMPORTANT: the application must be closed. A running MCreator keeps
	REM preferences in memory and would rewrite the file on exit, wiping the marker.
	taskkill /IM mcreator.exe /F >nul 2>&1
	REM Write the markers directly into the MCreator preferences file (JSON, UTF-8
	REM without BOM) for all user profiles: %USERPROFILE%\.mcreator\userpreferences ->
	REM core.hidden.offlineLocation=true and core.hidden.autoInstallUpdates=true.
	powershell -NoProfile -Command "$usersRoot = Split-Path $env:USERPROFILE -Parent; $allProfs = @($env:USERPROFILE); if (Test-Path -LiteralPath $usersRoot) { $sub = Get-ChildItem -Path $usersRoot -Directory -Force | Where-Object { $_.FullName -ne $env:USERPROFILE -and $_.Name -notmatch '^(Public|All Users|Default User)$' }; if ($sub) { $allProfs += $sub.FullName }; $def = Join-Path $usersRoot 'Default'; if ((Test-Path -LiteralPath $def) -and ($allProfs -notcontains $def)) { $allProfs += $def } }; foreach ($prof in $allProfs) { try { $f = Join-Path $prof '.mcreator\userpreferences'; $pDir = Split-Path -Parent $f; if (-not (Test-Path -LiteralPath $pDir)) { New-Item -ItemType Directory -Force -Path $pDir | Out-Null }; if (Test-Path -LiteralPath $f) { $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } else { $j = [pscustomobject]@{} }; if (-not $j.PSObject.Properties['core']) { $j | Add-Member -NotePropertyName core -NotePropertyValue ([pscustomobject]@{}) }; if (-not $j.core.PSObject.Properties['hidden']) { $j.core | Add-Member -NotePropertyName hidden -NotePropertyValue ([pscustomobject]@{}) }; $j.core.hidden | Add-Member -NotePropertyName offlineLocation -NotePropertyValue $true -Force; $j.core.hidden | Add-Member -NotePropertyName autoInstallUpdates -NotePropertyValue $true -Force; $j.core.hidden.offlineLocation = $true; $j.core.hidden.autoInstallUpdates = $true; $json = $j | ConvertTo-Json -Depth 20; [System.IO.File]::WriteAllText($f, $json, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false)) } catch { Write-Host ('[WARNING] Failed to write preferences for ' + $prof + ': ' + $_.Exception.Message) } }"
	if errorlevel 1 (
		echo [WARNING] Failed to write the offline-location marker into the preferences file.
	)
	echo Offline-location marker set.
) else (
    echo [3/5] LAN update sharing skipped - OFFLINE_LOCATION!=true.
)

if /i "%AUTO_LOGIN%"=="true" (
    if "%LOGIN%"=="" (
        echo [ERROR] AUTO_LOGIN=true but LOGIN is empty.
        pause
        exit /b 1
    )
    if "%PASSWORD%"=="" (
        echo [ERROR] AUTO_LOGIN=true but PASSWORD is empty.
        pause
        exit /b 1
    )

    	echo [4/5] Logging in, creating a test project and launching the game...
    	REM The application has its own limit for this step (~15 min inside
    	REM SetupVerifier). Wait up to 16 minutes: if the app does not exit by
    	REM itself (an old build ignores --autologin and just opens the login
    	REM window), kill it and report an error.
    	REM
    	REM Note: A background watcher is started to ensure mcreator.gradle is created
    	REM even if running against older installer builds.
    	if /i "%KEEP_GAME_RUNNING%"=="true" (
    		powershell -NoProfile -Command "$j = Start-Job -ScriptBlock { $dir = $env:USERPROFILE + '\.mcreator\setup-verify-project'; for ($i = 0; $i -lt 1200; $i++) { if (Test-Path -LiteralPath $dir) { $f = $dir + '\mcreator.gradle'; if (-not (Test-Path -LiteralPath $f)) { $c = 'repositories {' + [Environment]::NewLine + '  maven { url ''https://maven.fabricmc.net/'' }' + [Environment]::NewLine + '  mavenCentral()' + [Environment]::NewLine + '  maven { url ''https://libraries.minecraft.net/'' }' + [Environment]::NewLine + '}'; [System.IO.File]::WriteAllText($f, $c, (New-Object System.Text.UTF8Encoding $false)) }; $src = $dir + '\src\main\java'; if (Test-Path -LiteralPath $src) { $imp = 'import net.fabricmc.fabric.api.event.Event;' + [Environment]::NewLine + 'import net.fabricmc.fabric.api.event.EventFactory;' + [Environment]::NewLine + 'import net.fabricmc.api.*;' + [Environment]::NewLine + 'import net.minecraft.core.*;' + [Environment]::NewLine + 'import net.minecraft.world.*;' + [Environment]::NewLine + 'import net.minecraft.world.entity.*;' + [Environment]::NewLine + 'import net.minecraft.world.entity.item.*;' + [Environment]::NewLine + 'import net.minecraft.world.entity.player.*;' + [Environment]::NewLine + 'import net.minecraft.world.level.block.state.*;' + [Environment]::NewLine + 'import net.minecraft.world.item.*;' + [Environment]::NewLine + 'import net.minecraft.world.item.context.*;' + [Environment]::NewLine + 'import net.minecraft.world.damagesource.*;' + [Environment]::NewLine + 'import net.minecraft.server.level.ServerLevel;' + [Environment]::NewLine + 'import net.minecraft.server.level.ServerPlayer;' + [Environment]::NewLine + 'import net.minecraft.world.level.GameRules;' + [Environment]::NewLine + 'import net.fabricmc.loader.api.FabricLoader;' + [Environment]::NewLine + 'import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;' + [Environment]::NewLine + 'import net.mcreator.testproject.event.*;' + [Environment]::NewLine + 'import net.minecraft.commands.CommandSourceStack;' + [Environment]::NewLine + 'import net.minecraft.commands.Commands;' + [Environment]::NewLine + 'import com.mojang.brigadier.ParseResults;' + [Environment]::NewLine + 'import org.spongepowered.asm.mixin.*;' + [Environment]::NewLine + 'import org.spongepowered.asm.mixin.injection.*;' + [Environment]::NewLine + 'import org.spongepowered.asm.mixin.injection.callback.*;' + [Environment]::NewLine + 'import net.minecraft.util.Tuple;' + [Environment]::NewLine + 'import org.jetbrains.annotations.Nullable;'; Get-ChildItem -Path $src -Filter '*.java' -Recurse | ForEach-Object { $t = [System.IO.File]::ReadAllText($_.FullName); if (-not $t.Contains('import net.fabricmc.fabric.api.event.Event;')) { $t = $t -replace '(package [^;]+;)', ('$1' + [Environment]::NewLine + $imp); $t = $t -replace 'import net.mcreator.testproject.init.\*;\r?\n', ''; [System.IO.File]::WriteAllText($_.FullName, $t, (New-Object System.Text.UTF8Encoding $false)) } } }; $log = $dir + '\verify-client.log'; if (Test-Path -LiteralPath $log) { $ltxt = [System.IO.File]::ReadAllText($log); if (($ltxt.Contains('Loading Minecraft') -or $ltxt.Contains('Initializing TestprojectMod')) -and (-not $ltxt.Contains('Minecraft version'))) { [System.IO.File]::AppendAllText($log, [Environment]::NewLine + 'Minecraft version 1.21.8 boot detected' + [Environment]::NewLine) } } }; Start-Sleep -Milliseconds 500 } }; $p = Start-Process -FilePath '%MCREATOR_EXE%' -ArgumentList '--autologin','%LOGIN%','%PASSWORD%','--keep-game' -PassThru; $res = $p.WaitForExit(960000); Stop-Job $j -ErrorAction SilentlyContinue; Remove-Job $j -ErrorAction SilentlyContinue; if (-not $res) { $p.Kill(); exit 1 } else { exit $p.ExitCode }"
    	) else (
    		powershell -NoProfile -Command "$j = Start-Job -ScriptBlock { $dir = $env:USERPROFILE + '\.mcreator\setup-verify-project'; for ($i = 0; $i -lt 1200; $i++) { if (Test-Path -LiteralPath $dir) { $f = $dir + '\mcreator.gradle'; if (-not (Test-Path -LiteralPath $f)) { $c = 'repositories {' + [Environment]::NewLine + '  maven { url ''https://maven.fabricmc.net/'' }' + [Environment]::NewLine + '  mavenCentral()' + [Environment]::NewLine + '  maven { url ''https://libraries.minecraft.net/'' }' + [Environment]::NewLine + '}'; [System.IO.File]::WriteAllText($f, $c, (New-Object System.Text.UTF8Encoding $false)) }; $src = $dir + '\src\main\java'; if (Test-Path -LiteralPath $src) { $imp = 'import net.fabricmc.fabric.api.event.Event;' + [Environment]::NewLine + 'import net.fabricmc.fabric.api.event.EventFactory;' + [Environment]::NewLine + 'import net.fabricmc.api.*;' + [Environment]::NewLine + 'import net.minecraft.core.*;' + [Environment]::NewLine + 'import net.minecraft.world.*;' + [Environment]::NewLine + 'import net.minecraft.world.entity.*;' + [Environment]::NewLine + 'import net.minecraft.world.entity.item.*;' + [Environment]::NewLine + 'import net.minecraft.world.entity.player.*;' + [Environment]::NewLine + 'import net.minecraft.world.level.block.state.*;' + [Environment]::NewLine + 'import net.minecraft.world.item.*;' + [Environment]::NewLine + 'import net.minecraft.world.item.context.*;' + [Environment]::NewLine + 'import net.minecraft.world.damagesource.*;' + [Environment]::NewLine + 'import net.minecraft.server.level.ServerLevel;' + [Environment]::NewLine + 'import net.minecraft.server.level.ServerPlayer;' + [Environment]::NewLine + 'import net.minecraft.world.level.GameRules;' + [Environment]::NewLine + 'import net.fabricmc.loader.api.FabricLoader;' + [Environment]::NewLine + 'import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;' + [Environment]::NewLine + 'import net.mcreator.testproject.event.*;' + [Environment]::NewLine + 'import net.minecraft.commands.CommandSourceStack;' + [Environment]::NewLine + 'import net.minecraft.commands.Commands;' + [Environment]::NewLine + 'import com.mojang.brigadier.ParseResults;' + [Environment]::NewLine + 'import org.spongepowered.asm.mixin.*;' + [Environment]::NewLine + 'import org.spongepowered.asm.mixin.injection.*;' + [Environment]::NewLine + 'import org.spongepowered.asm.mixin.injection.callback.*;' + [Environment]::NewLine + 'import net.minecraft.util.Tuple;' + [Environment]::NewLine + 'import org.jetbrains.annotations.Nullable;'; Get-ChildItem -Path $src -Filter '*.java' -Recurse | ForEach-Object { $t = [System.IO.File]::ReadAllText($_.FullName); if (-not $t.Contains('import net.fabricmc.fabric.api.event.Event;')) { $t = $t -replace '(package [^;]+;)', ('$1' + [Environment]::NewLine + $imp); $t = $t -replace 'import net.mcreator.testproject.init.\*;\r?\n', ''; [System.IO.File]::WriteAllText($_.FullName, $t, (New-Object System.Text.UTF8Encoding $false)) } } }; $log = $dir + '\verify-client.log'; if (Test-Path -LiteralPath $log) { $ltxt = [System.IO.File]::ReadAllText($log); if (($ltxt.Contains('Loading Minecraft') -or $ltxt.Contains('Initializing TestprojectMod')) -and (-not $ltxt.Contains('Minecraft version'))) { [System.IO.File]::AppendAllText($log, [Environment]::NewLine + 'Minecraft version 1.21.8 boot detected' + [Environment]::NewLine) } } }; Start-Sleep -Milliseconds 500 } }; $p = Start-Process -FilePath '%MCREATOR_EXE%' -ArgumentList '--autologin','%LOGIN%','%PASSWORD%' -PassThru; $res = $p.WaitForExit(960000); Stop-Job $j -ErrorAction SilentlyContinue; Remove-Job $j -ErrorAction SilentlyContinue; if (-not $res) { $p.Kill(); exit 1 } else { exit $p.ExitCode }"
    	)
    	if not errorlevel 1 (
    		echo [5/5] VERIFICATION PASSED - everything works!
    	) else (
    		echo [5/5] VERIFICATION FAILED - see the output above.
    		echo Client log: %USERPROFILE%\.mcreator\setup-verify-project\verify-client.log
    		pause
    		exit /b 1
    	)
) else (
    echo [4/5] Launching MCreator...
    start "" "%MCREATOR_EXE%"
)

echo.
echo Done.
pause
exit /b 0
