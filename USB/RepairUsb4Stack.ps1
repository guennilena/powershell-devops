# Repair-Usb4Stack.ps1
# Ziel: USB4 / Thunderbolt Stack (XPS 16 + WD22TB4) gezielt resetten
# Voraussetzung: Adminrechte

$BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath  = Join-Path $BasePath "Logs"
$LogFile  = Join-Path $LogPath ("Usb4Fix_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath | Out-Null
}

function Log {
    param([string]$Message)
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

Log "=== USB4 Repair gestartet ==="

$patterns = @(
  'USB4 (TM) Host-Router',
  'USB4-Router (1.0), Dell',
  'USB4-Stammrouter'
)

$devices = Get-PnpDevice -Class USB -PresentOnly |
    Where-Object {
        $name = $_.FriendlyName
        $patterns | Where-Object { $name -like "*$_*" }
    } |
    Sort-Object FriendlyName

if (-not $devices) {
    Log "WARNUNG: Keine USB4-Geräte gefunden."
    exit 1
}

Log "Gefundene USB4-Geräte:"
$devices | ForEach-Object {
    Log (" - {0} [{1}]" -f $_.FriendlyName, $_.Status)
}

Log "USB4-Geräte deaktivieren..."
foreach ($d in $devices) {
    Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
}

Start-Sleep -Milliseconds 800

Log "USB4-Geräte aktivieren..."
foreach ($d in $devices) {
    Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
}

Start-Sleep -Milliseconds 800

Log "Status nach Reset:"
Get-PnpDevice -Class USB -PresentOnly |
    Where-Object {
        $name = $_.FriendlyName
        $patterns | Where-Object { $name -like "*$_*" }
    } |
    ForEach-Object {
        Log (" - {0} [{1}]" -f $_.FriendlyName, $_.Status)
    }

Log "Letzte relevante Eventlog-Einträge (Kernel-PnP / USB / Thunderbolt):"

Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    ProviderName = @('Kernel-PnP','USBXHCI','USBHUB','Thunderbolt')
    StartTime = (Get-Date).AddMinutes(-10)
} -ErrorAction SilentlyContinue |
Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
ForEach-Object {
    Log ("[{0}] {1} {2} - {3}" -f $_.TimeCreated, $_.ProviderName, $_.Id, $_.LevelDisplayName)
}

Log "=== USB4 Repair abgeschlossen ==="
