if ((get-host).version.major -ne 7) {Write-Host "Powershell 7 Required" -foregroundcolor Red; exit 1;}
$FirstTimeLoad = 1
. $PSScriptRoot\Initialize-Module.ps1 -InitType 'Full'
foreach ($f in $(get-childitem ".\Public" -Filter "*.ps1" -File)){write-host "loading $f" . $f.FullName}
foreach ($f in $(get-childitem ".\Private" -Filter "*.ps1" -File)){write-host "loading $f" . $f.FullName}
# check versions, set some vars
$ErroredItemsFolder = $ErroredItemsFolder ?? $(Get-EnsuredPath -path $(join-path $(Resolve-Path .).path "debug"))
$ManualActions = [System.Collections.ArrayList]@()
$MergedOrganizationSettings = @{Types        = @(); TargetCompany = $null;}
$MatchedPasswordFolders = @()
$MatchedChecklists = @()
$ITGErrors = @{}
$ITGMigJobs = @()
if (-not $ITGErrors) { $ITGErrors = @{} }

# Prompt for backups, initialize modules
$backups=$(if ($true -eq $NonInteractive) {"Y"} else {Read-Host "Y/n"})
$ScriptStartTime = $(Get-Date -Format "o")
$CurrentVersion =  Set-ExternalModulesInitialized -RequiredHuduVersion ([version]"2.39.4") -DisallowedVersions @([version]"2.37.0")

if ($backups -ne "Y" -or $backups -ne "y") {Write-Host "Please take a backup and run the script again"; exit 1;}

$ResumeFound = Ensure-MigrationLogsDir $MigrationLogs
$ITGMigJobs = Build-JobsArray -eligibleItems $eligibleItems

foreach ($job in $ITGMigJobs) {
    Write-Host "Beginning Job: $job"
    if (-not (Get-Command $job -ErrorAction SilentlyContinue)) {
        Write-Warning "Job '$job' not found as a function/command. Skipping."
        continue
    }
    try {
        & $job
    }
    catch {
        $ErrorEncountered = @{
            Job       = $job
            Exception = $_.Exception
            Message   = $_.Exception.Message
        }
        Write-Host $ErrorEncountered.Message
        if (-not $ITGErrors.ContainsKey($job)) {
            $ITGErrors[$job] = @()
        }
        $ITGErrors[$job] += $ErrorEncountered
    }
}