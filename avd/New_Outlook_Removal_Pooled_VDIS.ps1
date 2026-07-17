$ErrorActionPreference = "Continue"

$AppName = "Microsoft.OutlookForWindows"

$LogRoot = "C:\ProgramData\RemoveNewOutlook"
$LogFile = Join-Path $LogRoot "RemoveNewOutlook.log"
$HelperScript = Join-Path $LogRoot "HideNewOutlookToggle.ps1"

$PolicySubKey = "Software\Policies\Microsoft\office\16.0\outlook\options\general"
$PolicyName = "HideNewOutlookToggle"

$ActiveSetupGuid = "{A20915E0-282C-4BB3-9E74-0B14514D6E5A}"
$ActiveSetupKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\$ActiveSetupGuid"

New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Message)

    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$TimeStamp - $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Write-Log "Starting New Outlook removal script."

# 1. Stop New Outlook if running
try {
    Write-Log "Stopping New Outlook processes if running."

    Get-Process -Name "olk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name "OutlookForWindows" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Log "Process stop step completed."
}
catch {
    Write-Log "Process stop step failed. Error: $($_.Exception.Message)"
}

# 2. Remove installed New Outlook package for all existing users
try {
    $InstalledApps = Get-AppxPackage -AllUsers -Name $AppName -ErrorAction SilentlyContinue

    if ($InstalledApps) {
        foreach ($InstalledApp in $InstalledApps) {
            try {
                Write-Log "Removing installed package: $($InstalledApp.PackageFullName)"
                Remove-AppxPackage -AllUsers -Package $InstalledApp.PackageFullName -ErrorAction Stop
                Write-Log "Successfully removed installed package: $($InstalledApp.PackageFullName)"
            }
            catch {
                Write-Log "Failed to remove installed package: $($InstalledApp.PackageFullName). Error: $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Log "No installed New Outlook package found."
    }
}
catch {
    Write-Log "Installed package removal step failed. Error: $($_.Exception.Message)"
}

# 3. Remove provisioned New Outlook package so it does not return for new profiles
try {
    $ProvisionedApps = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -eq $AppName
    }

    if ($ProvisionedApps) {
        foreach ($ProvisionedApp in $ProvisionedApps) {
            try {
                Write-Log "Removing provisioned package: $($ProvisionedApp.PackageName)"
                Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $ProvisionedApp.PackageName -ErrorAction Stop | Out-Null
                Write-Log "Successfully removed provisioned package: $($ProvisionedApp.PackageName)"
            }
            catch {
                Write-Log "Failed to remove provisioned package: $($ProvisionedApp.PackageName). Error: $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Log "No provisioned New Outlook package found."
    }
}
catch {
    Write-Log "Provisioned package removal step failed. Error: $($_.Exception.Message)"
}

# 4. Remove Windows Update / OOBE OutlookUpdate trigger
$OobePath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe"
$OutlookUpdateKey = Join-Path $OobePath "OutlookUpdate"

try {
    if (Test-Path $OutlookUpdateKey) {
        Remove-Item -Path $OutlookUpdateKey -Recurse -Force -ErrorAction Stop
        Write-Log "Removed OutlookUpdate registry key."
    }
    else {
        Write-Log "OutlookUpdate registry key not found."
    }
}
catch {
    Write-Log "Failed to remove OutlookUpdate registry key. Error: $($_.Exception.Message)"
}

try {
    if (Test-Path $OobePath) {
        Remove-ItemProperty -Path $OobePath -Name "OutlookUpdate" -Force -ErrorAction SilentlyContinue
        Write-Log "Removed OutlookUpdate registry value if present."
    }
}
catch {
    Write-Log "Failed to remove OutlookUpdate registry value. Error: $($_.Exception.Message)"
}

# 5. Create helper script to apply HideNewOutlookToggle at user logon
try {
    $HelperScriptContent = @'
$PolicyPath = "HKCU:\Software\Policies\Microsoft\office\16.0\outlook\options\general"

New-Item -Path $PolicyPath -Force | Out-Null

New-ItemProperty `
    -Path $PolicyPath `
    -Name "HideNewOutlookToggle" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null
'@

    $HelperScriptContent | Out-File -FilePath $HelperScript -Encoding UTF8 -Force
    Write-Log "Created helper script: $HelperScript"
}
catch {
    Write-Log "Failed to create helper script. Error: $($_.Exception.Message)"
}

# 6. Apply HideNewOutlookToggle to currently loaded user profiles
try {
    $LoadedUserSids = Get-ChildItem "Registry::HKEY_USERS" -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match "^S-1-5-21-" -and $_.PSChildName -notmatch "_Classes$"
    }

    if ($LoadedUserSids) {
        foreach ($UserSid in $LoadedUserSids) {
            $UserPolicyPath = "Registry::HKEY_USERS\$($UserSid.PSChildName)\$PolicySubKey"

            try {
                New-Item -Path $UserPolicyPath -Force | Out-Null

                New-ItemProperty `
                    -Path $UserPolicyPath `
                    -Name $PolicyName `
                    -PropertyType DWord `
                    -Value 1 `
                    -Force | Out-Null

                Write-Log "Applied HideNewOutlookToggle for loaded user SID: $($UserSid.PSChildName)"
            }
            catch {
                Write-Log "Failed to apply HideNewOutlookToggle for SID $($UserSid.PSChildName). Error: $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Log "No loaded user profiles found. Active Setup will apply setting at next user logon."
    }
}
catch {
    Write-Log "Loaded user registry step failed. Error: $($_.Exception.Message)"
}

# 7. Configure Active Setup so future users get HideNewOutlookToggle at logon
try {
    New-Item -Path $ActiveSetupKey -Force | Out-Null

    New-ItemProperty -Path $ActiveSetupKey -Name "Version" -PropertyType String -Value "1,0,0,0" -Force | Out-Null
    New-ItemProperty -Path $ActiveSetupKey -Name "ComponentID" -PropertyType String -Value "HideNewOutlookToggle" -Force | Out-Null
    New-ItemProperty -Path $ActiveSetupKey -Name "StubPath" -PropertyType String -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HelperScript`"" -Force | Out-Null
    New-ItemProperty -Path $ActiveSetupKey -Name "IsInstalled" -PropertyType DWord -Value 1 -Force | Out-Null

    Write-Log "Configured Active Setup for future user logons."
}
catch {
    Write-Log "Failed to configure Active Setup. Error: $($_.Exception.Message)"
}

Write-Log "New Outlook removal script completed."
exit 0
