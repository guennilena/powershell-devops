Set-StrictMode -Version Latest

function Test-WinNetHealth {
    <#
    .SYNOPSIS
        Runs health checks for Windows networking and SMB readiness.

    .DESCRIPTION
        Returns a rich object with:
        - Network profiles
        - SMB Server service status
        - Port 445 listening status
        - Firewall rules for File & Printer Sharing (inbound)
        - Overall assessment

    .PARAMETER ComputerName
        Defaults to local machine. Included for future extension.

    .EXAMPLE
        Test-WinNetHealth

    .EXAMPLE
        Test-WinNetHealth | ConvertTo-Json -Depth 6
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $ComputerName = $env:COMPUTERNAME,

        [Parameter()]
        [string] $TestRemoteHost,

        [Parameter()]
        [int] $RemotePort = 445
    )

    # Network profiles
    $profiles = Get-NetConnectionProfile | ForEach-Object {
        [pscustomobject]@{
            Name          = $_.Name
            InterfaceAlias= $_.InterfaceAlias
            InterfaceIndex= $_.InterfaceIndex
            NetworkCategory = $_.NetworkCategory
            IPv4Connectivity= $_.IPv4Connectivity
            IPv6Connectivity= $_.IPv6Connectivity
        }
    }

    # SMB Server service
    $svc = Get-Service -Name LanmanServer -ErrorAction Stop
    $smbService = [pscustomobject]@{
        Name      = $svc.Name
        DisplayName = $svc.DisplayName
        Status    = $svc.Status.ToString()
        StartType = (Get-CimInstance Win32_Service -Filter "Name='LanmanServer'").StartMode
    }

    # Port 445 listen state
    $listen445 = $false
    $listenEndpoints = @()
    try {
        $conns = Get-NetTCPConnection -LocalPort 445 -State Listen -ErrorAction Stop
        if ($conns) {
            $listen445 = $true
            $listenEndpoints = $conns | Select-Object LocalAddress, LocalPort, OwningProcess
        }
    } catch {
        $listen445 = $false
        $listenEndpoints = @()
    }

    # Firewall rules for File & Printer Sharing (inbound)
    $fwRules = Get-NetFirewallRule -DisplayGroup "Datei- und Druckerfreigabe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Direction -eq 'Inbound' } |
        ForEach-Object {
            $profiles = @()
            if ($_.Profile -band 1) { $profiles += 'Domain' }
            if ($_.Profile -band 2) { $profiles += 'Private' }
            if ($_.Profile -band 4) { $profiles += 'Public' }
            if ($profiles.Count -eq 0) { $profiles = @('Any') }

            [pscustomobject]@{
                DisplayName = $_.DisplayName
                Enabled     = [bool]$_.Enabled
                Profiles    = $profiles -join ', '
                Action      = $_.Action
            }
        }

    $items = @($fwRules)
    $fwInboundTotal  = $items.Count
    $fwInboundEnabled = ($items | Where-Object Enabled | Measure-Object).Count

    # Remote connectivity tests (optional)
    $remote = $null
    if ($TestRemoteHost) {
        $pingOk = $false
        $portOk = $false
        $tncInfo = $null

        try {
            $pingOk = Test-Connection -ComputerName $TestRemoteHost -Count 1 -Quiet -ErrorAction Stop
        } catch {
            $pingOk = $false
        }

        try {
            # Test-NetConnection exists on Windows PowerShell 5.1+ and pwsh on Windows
            $tnc = Test-NetConnection -ComputerName $TestRemoteHost -Port $RemotePort -WarningAction SilentlyContinue
            $tncInfo = $tnc | Select-Object ComputerName, RemoteAddress, RemotePort, PingSucceeded, TcpTestSucceeded
            $portOk = [bool]$tnc.TcpTestSucceeded
        } catch {
            $portOk = $false
        }

        $remote = [pscustomobject]@{
            Host           = $TestRemoteHost
            Port           = $RemotePort
            PingSucceeded  = $pingOk
            TcpSucceeded   = $portOk
            Details        = $tncInfo
        }
    }

    # Assessment
    $issues = New-Object System.Collections.Generic.List[string]

    if ($smbService.Status -ne 'Running') {
        $issues.Add("LanmanServer service is not running.")
    }
    if (-not $listen445) {
        $issues.Add("Port 445 is not listening.")
    }
    if ($fwInboundEnabled -eq 0) {
        $issues.Add("Inbound 'File and Printer Sharing' firewall rules are disabled.")
    }

    $status =
        if ($issues.Count -eq 0) { 'OK' }
        elseif ($issues.Count -le 2) { 'WARN' }
        else { 'FAIL' }

    [pscustomobject]@{
        Timestamp       = (Get-Date).ToString("s")
        ComputerName    = $ComputerName
        NetworkProfiles = $profiles
        SMBService      = $smbService
        SMBPort445      = [pscustomobject]@{
            Listening  = $listen445
            Endpoints  = $listenEndpoints
        }
        Firewall        = [pscustomobject]@{
            InboundFilePrinterSharingRules = $fwRules
            InboundTotal   = $fwInboundTotal
            InboundEnabled = $fwInboundEnabled
        }
        RemoteTests     = $remote
        Assessment      = [pscustomobject]@{
            Status  = $status
            Issues  = $issues
        }
    }
}

function Repair-WinNetHealth {
    <#
    .SYNOPSIS
        Applies safe fixes to make SMB reachable.

    .DESCRIPTION
        - Optionally set all network profiles to Private
        - Enable inbound firewall rules for "Datei- und Druckerfreigabe"
        - Ensure LanmanServer is running
        Returns an object describing changes.

    .PARAMETER SetPrivate
        Sets NetworkCategory to Private for current profiles.

    .PARAMETER EnableFilePrinterSharing
        Enables inbound firewall rules for the display group.

    .PARAMETER EnsureSMBServiceRunning
        Starts LanmanServer if stopped.

    .EXAMPLE
        Repair-WinNetHealth -SetPrivate -EnableFilePrinterSharing -EnsureSMBServiceRunning
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch] $SetPrivate,
        [switch] $EnableFilePrinterSharing,
        [switch] $EnsureSMBServiceRunning
    )

    $changes = New-Object System.Collections.Generic.List[object]

    if ($SetPrivate) {
        $profiles = Get-NetConnectionProfile
        foreach ($p in $profiles) {
            if ($p.NetworkCategory -ne 'Private') {
                if ($PSCmdlet.ShouldProcess($p.InterfaceAlias, "Set NetworkCategory to Private")) {
                    Set-NetConnectionProfile -InterfaceIndex $p.InterfaceIndex -NetworkCategory Private
                    $changes.Add([pscustomobject]@{
                        Change = "SetPrivate"
                        Interface = $p.InterfaceAlias
                        From = $p.NetworkCategory.ToString()
                        To = "Private"
                    })
                }
            }
        }
    }

    if ($EnableFilePrinterSharing) {
        if ($PSCmdlet.ShouldProcess("Firewall", "Enable inbound File & Printer Sharing rules")) {
            Set-NetFirewallRule -DisplayGroup "Datei- und Druckerfreigabe" -Enabled True -Profile Any
            $changes.Add([pscustomobject]@{
                Change = "EnableFirewallRules"
                Group  = "Datei- und Druckerfreigabe"
                Profile= "Any"
            })
        }
    }

    if ($EnsureSMBServiceRunning) {
        $svc = Get-Service LanmanServer
        if ($svc.Status -ne 'Running') {
            if ($PSCmdlet.ShouldProcess("LanmanServer", "Start SMB Server service")) {
                Start-Service LanmanServer
                $changes.Add([pscustomobject]@{
                    Change = "StartService"
                    Service= "LanmanServer"
                })
            }
        }
    }

    [pscustomobject]@{
        Timestamp   = (Get-Date).ToString("s")
        Changes     = $changes
    }
}

Export-ModuleMember -Function Test-WinNetHealth, Repair-WinNetHealth
