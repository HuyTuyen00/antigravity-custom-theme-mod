param(
    [switch]$NoStartup
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$DaemonJs = Join-Path $RepoRoot 'daemon\theme_daemon.js'
$PayloadJs = Join-Path $RepoRoot 'dist\theme_payload.js'
$BuildPy = Join-Path $RepoRoot 'scripts\build_payload.py'
$PidFile = Join-Path $RepoRoot 'daemon.pid'
$VbsPath = Join-Path $RepoRoot 'silent-start.vbs'

$NodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $NodeCmd) {
    $CommonNodePaths = @(
        'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Microsoft\VisualStudio\NodeJs\node.exe',
        'C:\Program Files\nodejs\node.exe',
        'C:\Program Files (x86)\nodejs\node.exe'
    )
    foreach ($p in $CommonNodePaths) {
        if (Test-Path $p) {
            $NodeExe = $p
            break
        }
    }
    if (-not $NodeExe) {
        Write-Error "Node.js not found in PATH or standard paths. Install Node.js >= 22 first."
    }
} else {
    $NodeExe = $NodeCmd.Source
}
$NodeMajor = [int]((& $NodeExe -p "process.versions.node.split('.')[0]").Trim())
if ($NodeMajor -lt 22) {
    Write-Error "Node.js >= 22 is required (found v$NodeMajor at $NodeExe)."
}

if (-not (Test-Path $PayloadJs)) {
    $BuildJs = Join-Path $RepoRoot 'scripts\build_payload.js'
    if (Test-Path $BuildJs) {
        Write-Host "[install-win] Building dist/theme_payload.js via Node..."
        & $NodeExe $BuildJs
    } else {
        $PyCmd = Get-Command python -ErrorAction SilentlyContinue
        if (-not $PyCmd) {
            $PyCmd = Get-Command python3 -ErrorAction SilentlyContinue
        }
        if (-not $PyCmd) {
            Write-Error "Neither build_payload.js nor Python was found to build dist/theme_payload.js."
        }
        Write-Host "[install-win] Building dist/theme_payload.js via Python..."
        & $PyCmd.Source $BuildPy
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Payload build failed with exit code $LASTEXITCODE."
    }
}

if (Test-Path $PidFile) {
    $OldPidText = (Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    $OldPid = 0
    if ([int]::TryParse(($OldPidText -as [string]), [ref]$OldPid) -and $OldPid -gt 0) {
        $ExistingProc = Get-Process -Id $OldPid -ErrorAction SilentlyContinue
        if ($ExistingProc -and $ExistingProc.ProcessName -eq 'node') {
            Write-Host "[install-win] Stopping existing daemon (PID $OldPid)..."
            Stop-Process -Id $OldPid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 350
        }
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

# Generate silent-start.vbs dynamically without hardcoding user or Node paths.
$EscapedNode = $NodeExe.Replace('"', '""')
$EscapedDaemon = $DaemonJs.Replace('"', '""')
$VbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "$($RepoRoot.Replace('"', '""'))"
WshShell.Run """$EscapedNode"" ""$EscapedDaemon""", 0, False
"@
Set-Content -Path $VbsPath -Value $VbsContent -Encoding ASCII

if (-not $NoStartup) {
    $StartupDir = [Environment]::GetFolderPath('Startup')
    $ShortcutPath = Join-Path $StartupDir 'AntigravityCustomTheme.lnk'
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = 'wscript.exe'
    $Shortcut.Arguments = """$VbsPath"""
    $Shortcut.WorkingDirectory = $RepoRoot
    $Shortcut.WindowStyle = 7
    $Shortcut.Description = 'Antigravity Custom Theme Daemon'
    $Shortcut.Save()
    Write-Host "[install-win] Startup shortcut created: $ShortcutPath"
}

Write-Host "[install-win] Launching daemon via wscript.exe..."
$launched = $false
try {
    $cimRes = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = "wscript.exe `"$VbsPath`""
        CurrentDirectory = $RepoRoot
    }
    if ($cimRes -and $cimRes.ReturnValue -eq 0) { $launched = $true }
} catch {}
if (-not $launched) {
    Start-Process -FilePath 'wscript.exe' -ArgumentList """$VbsPath""" -WorkingDirectory $RepoRoot
}

for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Milliseconds 250
    if (Test-Path $PidFile) {
        $NewPidText = (Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        $NewPid = 0
        if ([int]::TryParse(($NewPidText -as [string]), [ref]$NewPid) -and $NewPid -gt 0) {
            if (Get-Process -Id $NewPid -ErrorAction SilentlyContinue) {
                Write-Host "[install-win] Daemon running silently (PID $NewPid)."
                exit 0
            }
        }
    }
}

Write-Warning "[install-win] Daemon did not write daemon.pid in time. Check $RepoRoot\daemon.log."
exit 1
