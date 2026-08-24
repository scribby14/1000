<#
  check-av-injection.ps1

  Detects Kaspersky interference with Claude Code:
    1. Kaspersky services / kernel drivers present and running
       (klhk.sys is the hooking driver that injects code into user processes)
    2. Kaspersky DLLs injected into Claude processes (incl. the GPU process)
    3. TLS interception: is the api.anthropic.com certificate issued by Kaspersky

  Run as the same user that runs Claude Code, with Claude Code running:
    powershell -ExecutionPolicy Bypass -File .\check-av-injection.ps1
  Admin is not required.
#>

$ErrorActionPreference = 'Continue'
Write-Host "== Kaspersky interference check =="
Write-Host ""

# --- 1. Kaspersky services and kernel drivers ---
Write-Host "-- Kaspersky services / drivers --"
$avSvc = Get-Service | Where-Object { $_.Name -like 'AVP*' -or $_.DisplayName -match 'Kaspersky' }
if ($avSvc) {
    foreach ($s in $avSvc) {
        Write-Host ("  service: {0,-14} {1,-9} {2}" -f $s.Name, $s.Status, $s.DisplayName)
    }
} else {
    Write-Host "  no Kaspersky services found"
}
$klDrv = Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match '^(kl|kneps)' }
foreach ($d in $klDrv) {
    Write-Host ("  driver : {0,-14} {1,-9} {2}" -f $d.Name, $d.State, $d.DisplayName)
}
$hook = $klDrv | Where-Object { ($_.Name -eq 'klhk') -and ($_.State -eq 'Running') }
if ($hook) {
    Write-Host "  NOTE: klhk (Kaspersky hooking driver) is RUNNING - it injects code into user processes."
}

# --- 2. Kaspersky modules inside Claude processes ---
Write-Host ""
Write-Host "-- Claude processes --"
$procs = @(Get-Process | Where-Object { $_.Name -like 'claude*' })
if ($procs.Count -eq 0) {
    Write-Host "  no Claude processes running - start Claude Code and re-run for a full check"
}
$injectedAny = $false
foreach ($p in $procs) {
    $kind = ''
    try {
        $ci = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id)
        if ($ci.CommandLine -match '--type=gpu-process') { $kind = '   <-- GPU process' }
        elseif ($ci.CommandLine -match '--type=(\S+)')   { $kind = ('   (type={0})' -f $Matches[1]) }
    } catch { }
    Write-Host ("  PID {0,-7} {1}{2}" -f $p.Id, $p.Name, $kind)
    try {
        $kavMods = @($p.Modules | Where-Object {
            ($_.FileName -match '(?i)kaspersky') -or ($_.ModuleName -match '^(?i)(kl\w*|avp\w*)\.dll$')
        })
        if ($kavMods.Count -gt 0) {
            $injectedAny = $true
            foreach ($m in $kavMods) {
                Write-Host ("      INJECTED: {0}  ({1})" -f $m.ModuleName, $m.FileName)
            }
        } else {
            Write-Host "      no Kaspersky modules loaded"
        }
    } catch {
        Write-Host ("      cannot list modules: {0}" -f $_.Exception.Message)
    }
}

# --- 3. TLS interception check ---
Write-Host ""
Write-Host "-- TLS to api.anthropic.com --"
$mitm = $false
try {
    $tcp = New-Object Net.Sockets.TcpClient
    $tcp.Connect('api.anthropic.com', 443)
    $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, ({ $true }))
    $ssl.AuthenticateAsClient('api.anthropic.com', $null,
        [Security.Authentication.SslProtocols]::Tls12, $false)
    $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
    Write-Host ("  certificate issuer: {0}" -f $cert.Issuer)
    if ($cert.Issuer -match '(?i)kaspersky') {
        $mitm = $true
        Write-Host "  TLS IS INTERCEPTED by Kaspersky - expect certificate errors in Claude Code / node."
    } else {
        Write-Host "  TLS is NOT intercepted."
    }
    $ssl.Dispose()
    $tcp.Close()
} catch {
    Write-Host ("  TLS check failed: {0}" -f $_.Exception.Message)
}

# --- verdict ---
Write-Host ""
if ($injectedAny) {
    Write-Host "VERDICT: Kaspersky IS injecting into Claude processes."
    Write-Host "Add Claude to Kaspersky trusted applications (docs/kaspersky-exclusions.md),"
    Write-Host "otherwise GPU-process crashes may continue even after the driver rollback."
} elseif ($mitm) {
    Write-Host "VERDICT: no DLL injection detected, but TLS is intercepted -"
    Write-Host "exclude Claude traffic from scanning (docs/kaspersky-exclusions.md)."
} else {
    Write-Host "VERDICT: no Kaspersky interference detected (or processes were not inspectable)."
}
