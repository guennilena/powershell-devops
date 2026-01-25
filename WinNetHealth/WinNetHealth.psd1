@{
    RootModule        = 'WinNetHealth.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b1c7f7c6-1b1a-4f2c-8d7c-5d2d2e8e6b20'
    Author            = 'Günni'
    CompanyName       = ''
    Copyright         = ''
    Description       = 'Windows Network & SMB Health Check and Repair.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('Test-WinNetHealth', 'Repair-WinNetHealth')
    CmdletsToExport   = @()
    VariablesToExport = '*'
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags = @('SMB','Networking','Firewall','Diagnostics')
            LicenseUri = ''
            ProjectUri = ''
        }
    }
}
