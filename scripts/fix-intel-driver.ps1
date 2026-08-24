#Requires -RunAsAdministrator
<#
  fix-intel-driver.ps1

  Rolls the Intel GPU driver back from 32.0.101.7088 (crashing) to
  32.0.101.5972 (already staged in the DriverStore) and blocks Windows
  Update from pushing GPU drivers again - without the block, WU would
  simply reinstall 7088 on the next update check.

  Usage (elevated PowerShell):
    powershell -ExecutionPolicy Bypass -File .\fix-intel-driver.ps1 [-Force]
      -Force   skip the confirmation prompt

  Close Claude Code before running: the screen will go black / flicker for
  a few seconds while the driver is swapped, and any running GPU process
  will exit with the benign code 34.
#>
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$BadVersion  = '32.0.101.7088'
$GoodVersion = '32.0.101.5972'

Write-Host "== Intel driver rollback $BadVersion -> $GoodVersion + block WU driver delivery =="
Write-Host ""

$gpu = Get-CimInstance Win32_VideoController |
       Where-Object { $_.Name -match 'Intel' } | Select-Object -First 1
if (-not $gpu) {
    Write-Host "No Intel GPU found - aborting."
    exit 1
}
Write-Host ("Active GPU    : {0}" -f $gpu.Name)
Write-Host ("Active driver : {0}" -f $gpu.DriverVersion)
Write-Host ""

Write-Host "Enumerating DriverStore (takes 10-60 s)..."
$allDrivers = Get-WindowsDriver -Online
$igfx = $allDrivers | Where-Object { $_.OriginalFileName -match '\\iigd_dch\.inf$' }
foreach ($d in $igfx) {
    Write-Host ("  staged: {0,-10} {1,-16} {2:yyyy-MM-dd}" -f $d.Driver, $d.Version, $d.Date)
}
$badPkgs = @($igfx | Where-Object { $_.Version -eq $BadVersion })
$goodPkgs = @($igfx | Where-Object { $_.Version -eq $GoodVersion })
Write-Host ""

if ($badPkgs.Count -eq 0) {
    Write-Host "Package $BadVersion is not in the DriverStore - nothing to remove."
    Write-Host "Will still make sure WU driver delivery is blocked."
} elseif (($gpu.DriverVersion -eq $BadVersion) -and ($goodPkgs.Count -eq 0)) {
    Write-Host "SAFETY STOP: $BadVersion is active but $GoodVersion is NOT staged."
    Write-Host "Removing the only driver would drop the GPU to Microsoft Basic Display."
    Write-Host "Download 32.0.101.5972 from intel.com first, then re-run this script."
    exit 1
} else {
    Write-Host "Plan:"
    foreach ($d in $badPkgs) {
        Write-Host ("  1. pnputil /delete-driver {0} /uninstall /force   (removes {1})" -f $d.Driver, $d.Version)
    }
    Write-Host  "  2. pnputil /scan-devices   (device re-binds to the best remaining package: $GoodVersion)"
    Write-Host  "  3. Block WU driver delivery (SearchOrderConfig=0, ExcludeWUDriversInQualityUpdate=1)"
    Write-Host  "The screen will go black / flicker for a few seconds during steps 1-2."
    if (-not $Force) {
        $ans = Read-Host "Proceed? (y/N)"
        if ($ans -notmatch '^[yY]') { Write-Host "Cancelled, nothing changed."; exit 0 }
    }
    foreach ($d in $badPkgs) {
        $oem = $d.Driver
        Write-Host ("Removing {0} ({1})..." -f $oem, $d.Version)
        pnputil /delete-driver $oem /uninstall /force
        if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne 3010)) {
            Write-Host ("  WARNING: pnputil exited with code {0}" -f $LASTEXITCODE)
        }
    }
    Write-Host "Rescanning devices..."
    pnputil /scan-devices | Out-Null
    Start-Sleep -Seconds 5
    $gpu2 = Get-CimInstance Win32_VideoController |
            Where-Object { $_.Name -match 'Intel|Basic Display' } | Select-Object -First 1
    if ($gpu2) {
        Write-Host ("Driver after rollback: {0}  {1}" -f $gpu2.Name, $gpu2.DriverVersion)
        if ($gpu2.DriverVersion -eq $BadVersion) {
            Write-Host "Still reporting $BadVersion - a reboot should finish the switch."
        }
    }
}

Write-Host ""
Write-Host "Blocking Windows Update driver delivery..."
$dsPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'
if (-not (Test-Path $dsPath)) { New-Item -Path $dsPath -Force | Out-Null }
Set-ItemProperty -Path $dsPath -Name SearchOrderConfig -Value 0 -Type DWord

$wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
Set-ItemProperty -Path $wuPath -Name ExcludeWUDriversInQualityUpdate -Value 1 -Type DWord

$ds = (Get-ItemProperty -Path $dsPath).SearchOrderConfig
$wu = (Get-ItemProperty -Path $wuPath).ExcludeWUDriversInQualityUpdate
Write-Host ("  SearchOrderConfig               = {0}   [0 = WU driver search blocked]" -f $ds)
Write-Host ("  ExcludeWUDriversInQualityUpdate = {0}   [1 = drivers excluded from quality updates]" -f $wu)

Write-Host ""
Write-Host "Done. Reboot now, then re-run check-gpu-health.ps1 and expect:"
Write-Host "  - DriverVersion = $GoodVersion"
Write-Host "  - Windows Update driver search = 0"
Write-Host "  - one more benign exit-34 event around this rollback is normal"
Write-Host "To undo the WU block later: SearchOrderConfig=1, delete ExcludeWUDriversInQualityUpdate."
