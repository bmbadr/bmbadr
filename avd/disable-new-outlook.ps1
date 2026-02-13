# Remove the New Outlook app for all users and prevent it from being re-provisioned
Remove-AppxProvisionedPackage -AllUsers -Online -PackageName (Get-AppxPackage Microsoft.OutlookForWindows).PackageFullName -ErrorAction Ignore
# Also remove the orchestrator value that could reinstall it (documented by Microsoft)
reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe" /v OutlookUpdate /f -ErrorAction Ignore
