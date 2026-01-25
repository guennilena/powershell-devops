#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe "WinNetHealth module" {

    BeforeAll {
        $manifest = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'WinNetHealth.psd1'

        # Make failures explicit and readable
        if (-not (Test-Path -Path $manifest)) {
            throw "Module manifest not found at: $manifest"
        }

        Remove-Module WinNetHealth -Force -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Core\Import-Module -Name $manifest -Force

        Write-Host "Loaded module from: $((Get-Module WinNetHealth).Path)"
    }

    It "exports Test-WinNetHealth" {
        (Get-Command Test-WinNetHealth -ErrorAction Stop).Name | Should -Be 'Test-WinNetHealth'
    }

    It "returns expected top-level properties" {
        $r = Test-WinNetHealth
        $r.PSObject.Properties.Name | Should -Contain 'Assessment'
        $r.PSObject.Properties.Name | Should -Contain 'NetworkProfiles'
        $r.PSObject.Properties.Name | Should -Contain 'Firewall'
        $r.PSObject.Properties.Name | Should -Contain 'SMBPort445'
    }

    It "can include remote tests when TestRemoteHost is set (mocked)" {
        InModuleScope WinNetHealth {
            Mock Test-Connection { $true }
            Mock Test-NetConnection {
                [pscustomobject]@{
                    ComputerName     = 'dummy'
                    RemoteAddress    = '1.2.3.4'
                    RemotePort       = 445
                    PingSucceeded    = $true
                    TcpTestSucceeded = $true
                }
            }

            $r = Test-WinNetHealth -TestRemoteHost 'dummy' -RemotePort 445

            $r.RemoteTests.PingSucceeded | Should -BeTrue
            $r.RemoteTests.TcpSucceeded  | Should -BeTrue

            Assert-MockCalled Test-Connection -Times 1 -Exactly
            Assert-MockCalled Test-NetConnection -Times 1 -Exactly
        }
    }
}
