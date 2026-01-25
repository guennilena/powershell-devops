# WinNetHealth

Health checks and repair helpers for Windows networking + SMB readiness.

## Run
From the project folder:

```powershell
.\WinNetHealth.ps1
```

## Fix typical issues

```powershell
.\WinNetHealth.ps1 -Fix
```

Fine-grained control:

```powershell
.\WinNetHealth.ps1 -Fix -EnableFilePrinterSharing
```

## JSON Output
```powershell
.\WinNetHealth.ps1 -AsJson
```

## Import as module

```powershell
Import-Module .\WinNetHealth.psd1 -Force
Test-WinNetHealth
Repair-WinNetHealth -SetPrivate -EnableFilePrinterSharing -EnsureSMBServiceRunning
```

---


