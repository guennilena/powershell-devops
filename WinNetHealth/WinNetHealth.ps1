[CmdletBinding()]
param(
    [switch] $Fix,
    [switch] $SetPrivate,
    [switch] $EnableFilePrinterSharing,
    [switch] $EnsureSMBServiceRunning,
    [switch] $AsJson,
    [string] $TestRemoteHost,
    [int]    $RemotePort = 445,
    [string] $OutFile,
    [string] $OutDir = ".\logs"

)

# Remove-Module $modulePath
# Import-Module $modulePath -Force
# Invoke-Pester .\tests -Output Detailed

# --- Self-elevate if needed ---
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PowerShellEngine {
    # Prefer PowerShell 7 if available
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        return @{
            Name = 'pwsh'
            Args = @('-NoProfile')
        }
    }

    # Fallback to Windows PowerShell 5.1
    $ps = Get-Command powershell -ErrorAction SilentlyContinue
    if ($ps) {
        return @{
            Name = 'powershell'
            Args = @('-NoProfile')
        }
    }

    throw "No PowerShell engine found (pwsh or powershell)."
}

# If -Fix was requested and we are not elevated, re-run via gsudo in the SAME terminal session.
if ($Fix -and -not (Test-IsAdmin)) {
    if (-not (Get-Command gsudo -ErrorAction SilentlyContinue)) {
        Write-Error "Fix requires elevation. Please install gsudo or run this script as Administrator."
        exit 1
    }

    Write-Host "Elevating via gsudo (same terminal)..." -ForegroundColor Yellow

    $engine = Get-PowerShellEngine

    # Rebuild argument list exactly as provided
    $argTokens = @()
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) {
            if ($v) { $argTokens += "-$k" }
        } else {
            $argTokens += "-$k"
            if ($v -is [string] -and $v -match '\s') {
                $argTokens += "`"$v`""
            } else {
                $argTokens += $v
            }
        }
    }

    & gsudo $engine.Name @($engine.Args + @('-File', $PSCommandPath) + $argTokens)
    exit $LASTEXITCODE
}
# --- end self-elevate ---

$ErrorActionPreference = 'Stop'

# Import local module (works from project folder)
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'WinNetHealth.psd1'
Import-Module $modulePath -Force

if ($Fix) {
    # Sensible defaults if -Fix is used without fine-grained flags
    if (-not ($SetPrivate -or $EnableFilePrinterSharing -or $EnsureSMBServiceRunning)) {
        $SetPrivate = $true
        $EnableFilePrinterSharing = $true
        $EnsureSMBServiceRunning = $true
    }

    $repair = Repair-WinNetHealth -SetPrivate:$SetPrivate `
                                  -EnableFilePrinterSharing:$EnableFilePrinterSharing `
                                  -EnsureSMBServiceRunning:$EnsureSMBServiceRunning

    if ($AsJson) {
        $repair | ConvertTo-Json -Depth 8
    } else {
        Write-Host "Applied changes:" -ForegroundColor Cyan
        $repair.Changes | Format-Table -AutoSize
        Write-Host ""
    }
}

$result = Test-WinNetHealth -TestRemoteHost $TestRemoteHost -RemotePort $RemotePort

# --- Logging ---
if ($OutFile -or $OutDir) {
    $json = $result | ConvertTo-Json -Depth 10

    if (-not $OutFile) {
        if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
        $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $OutFile = Join-Path $OutDir "WinNetHealth-$($result.ComputerName)-$ts.json"
    } else {
        $parent = Split-Path -Parent $OutFile
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    }

    Set-Content -Path $OutFile -Value $json -Encoding UTF8
    Write-Host "Wrote JSON log: $OutFile" -ForegroundColor Cyan
    Write-Host ""
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 10
    exit 0
}

# Pretty human output
Write-Host "=== WinNetHealth ===" -ForegroundColor Cyan
Write-Host ("Timestamp   : {0}" -f $result.Timestamp)
Write-Host ("Computer    : {0}" -f $result.ComputerName)
Write-Host ""

Write-Host "Network Profiles:" -ForegroundColor Yellow
$result.NetworkProfiles | Format-Table Name, InterfaceAlias, NetworkCategory, IPv4Connectivity, IPv6Connectivity -AutoSize
Write-Host ""

Write-Host "SMB Service:" -ForegroundColor Yellow
$result.SMBService | Format-List
Write-Host ""

Write-Host "SMB Port 445:" -ForegroundColor Yellow
if ($result.SMBPort445.Listening) {
    Write-Host "Listening: True" -ForegroundColor Green
    $result.SMBPort445.Endpoints | Format-Table -AutoSize
} else {
    Write-Host "Listening: False" -ForegroundColor Red
}
Write-Host ""

Write-Host "Firewall (Inbound File & Printer Sharing):" -ForegroundColor Yellow
Write-Host ("Enabled rules: {0} / {1}" -f $result.Firewall.InboundEnabled, $result.Firewall.InboundTotal)
# Show only SMB-specific inbound rules first (usually contain SMB)
$result.Firewall.InboundFilePrinterSharingRules |
    Sort-Object DisplayName |
    Format-Table DisplayName, Enabled, Profiles, Action -AutoSize
Write-Host ""

if ($null -ne $result.RemoteTests) {
    Write-Host "Remote Tests:" -ForegroundColor Yellow
    $result.RemoteTests | Select-Object Host, Port, PingSucceeded, TcpSucceeded | Format-Table -AutoSize
    if ($result.RemoteTests.Details) {
        $result.RemoteTests.Details | Format-Table -AutoSize
    }
    Write-Host ""
}

Write-Host "Assessment:" -ForegroundColor Cyan

switch ($result.Assessment.Status) {
    'OK'   { $color = 'Green' }
    'WARN' { $color = 'Yellow' }
    'FAIL' { $color = 'Red' }
    default { $color = 'White' }
}

Write-Host ("Status: {0}" -f $result.Assessment.Status) -ForegroundColor $color

if ($result.Assessment.Issues.Count -gt 0) {
    Write-Host "Issues:" -ForegroundColor Red
    $result.Assessment.Issues | ForEach-Object {
        Write-Host (" - {0}" -f $_) -ForegroundColor Red
    }
}
else {
    Write-Host "No issues found." -ForegroundColor Green
}

switch ($result.Assessment.Status) {
  'OK'   { exit 0 }
  'WARN' { exit 2 }
  'FAIL' { exit 3 }
  default { exit 1 }
}

