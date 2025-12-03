if ((get-host).version.major -ne 7) {Write-Host "Powershell 7 Required" -foregroundcolor Red; exit 1;}
$FirstTimeLoad = 1
. $PSScriptRoot\Initialize-Module.ps1 -InitType 'Full'
foreach ($f in $(get-childitem ".\Public" -Filter "*.ps1" -File)){write-host "loading $f" . $f.FullName}
foreach ($f in $(get-childitem ".\Private" -Filter "*.ps1" -File)){write-host "loading $f" . $f.FullName}
############################### End of Functions ###############################
# Prompt for backups, initialize modules, check versions, set some vars
$ErroredItemsFolder = $ErroredItemsFolder ?? $(Get-EnsuredPath -path $(join-path $(Resolve-Path .).path "debug"))
$ManualActions = [System.Collections.ArrayList]@()
$MergedOrganizationSettings = @{Types        = @(); TargetCompany = $null;}
$MatchedPasswordFolders = @()
$MatchedChecklists = @()
$ITGErrors = @{}
$ITGMigJobs = @()
$backups=$(if ($true -eq $NonInteractive) {"Y"} else {Read-Host "Y/n"})
$ScriptStartTime = $(Get-Date -Format "o")
$CurrentVersion =  Set-ExternalModulesInitialized -RequiredHuduVersion ([version]"2.39.4") -DisallowedVersions @([version]"2.37.0")
if ($backups -ne "Y" -or $backups -ne "y") {
    Write-Host "Please take a backup and run the script again"
    exit 1
}

if (Test-Path -Path "$MigrationLogs") {
    if ($ResumePrevious -eq $true) {
        Write-Host "A previous attempt has been found job will be resumed from the last successful section" -ForegroundColor Green
        $ResumeFound = $true
    } else {
        Write-Host "A previous attempt has been found, resume is disabled so this will be lost, if you haven't reverted to a snapshot, a resume is recommended" -ForegroundColor Red
        Write-TimedMessage -Timeout 12 -Message "Press any key to continue or ctrl + c to quit and edit the ResumePrevious setting" -DefaultResponse "proceed with new migration, do not resume"
        $ResumeFound = $false
    }
} else {
    Write-Host "No previous runs found creating log directory"
    $null = New-Item "$MigrationLogs" -ItemType "directory"
    $ResumeFound = $false
}



# Generate Jobs Path based on user selection
if (-not $ITGErrors) { $ITGErrors = @{} }

foreach ($eligibleItem in $eligibleItems) {
    $jobAvail = Get-Variable -Name $eligibleItem.varname -ValueOnly -ErrorAction SilentlyContinue
    if ($jobAvail -eq 1) {
        $jobs += $eligibleItem.job
    }
}

foreach ($job in $ITGMigJobs) {
    Write-Host "Beginning Job: $job"

    # Optional: guard in case the function doesn't exist
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


Write-Host "#######################################################" -ForegroundColor Green
Write-Host "#                                                     #" -ForegroundColor Green
Write-Host "#        IT Glue to Hudu Migration Complete           #" -ForegroundColor Green
Write-Host "#                                                     #" -ForegroundColor Green
Write-Host "#######################################################" -ForegroundColor Green
Write-Host "Started At: $ScriptStartTime"
Write-Host "Completed At: $(Get-Date -Format "o")"
Write-Host "$(($MatchedCompanies | Measure-Object).count) : Companies Migrated" -ForegroundColor Green
Write-Host "$(($MatchedLocations | Measure-Object).count) : Locations Migrated" -ForegroundColor Green
Write-Host "$(($MatchedWebsites | Measure-Object).count) : Websites Migrated" -ForegroundColor Green
Write-Host "$(($MatchedConfigurations | Measure-Object).count) : Configurations Migrated" -ForegroundColor Green
Write-Host "$(($MatchedContacts | Measure-Object).count) : Contacts Migrated" -ForegroundColor Green
Write-Host "$(($MatchedLayouts | Measure-Object).count) : Layouts Migrated" -ForegroundColor Green
Write-Host "$(($MatchedAssets | Measure-Object).count) : Assets Migrated" -ForegroundColor Green
Write-Host "$(($MatchedArticles | Measure-Object).count) : Articles Migrated" -ForegroundColor Green
Write-Host "$(($MatchedPasswords | Measure-Object).count) : Passwords Migrated" -ForegroundColor Green

Write-Host "#######################################################" -ForegroundColor Green
Write-Host "Manual Actions report can be found in ManualActions.html in the folder the script was run from"
Write-Host "Logs of what was migrated can be found in the MigrationLogs folder"

Write-TimedMessage -Message "Press any key to view manual actions" -Timeout 120  -DefaultResponse "continue, view generative Manual Actions webpage, please."
Start-Process ManualActions.html