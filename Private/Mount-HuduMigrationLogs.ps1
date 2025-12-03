$varMap = @{
    MatchedCompanies           = "Companies.json"
    MatchedLocations           = "Locations.json"
    MatchedContacts            = "Contacts.json"
    MatchedCoonfigurations     = "Configurations.json"
    MatchedAssetLayouts        = "AssetLayouts.json"
    MatchedAssetLayoutsFields  = "AssetLayoutsFields.json"
    MatchedAssets              = "Assets.json"
    MatchedPasswords           = "Passwords.json"
    MatchedAssetPasswords      = "AssetPasswords.json"
    MatchedArticles            = "Articles.json"
    ManualActions              = "ManualActions.json"
    RelationsToCreate          = "RelationsToCreate.json"
}

$eligibleItems = @(
    @{ varname = "ImportCompanies";            job = "Start-Companies" }
    @{ varname = "ImportLocations";            job = "Start-Locations" }
    @{ varname = "ImportDomains";              job = "Start-Websites" }
    @{ varname = "ImportConfigurations";       job = "Start-Configurations" }
    @{ varname = "ImportContacts";             job = "Start-Contacts" }
    @{ varname = "ImportFlexibleAssetLayouts"; job = "Start-FlexAssetLayouts" }
    @{ varname = "ImportFlexibleAssets";       job = "Start-FlexAssets" }
    @{ varname = "ImportArticles";             job = "Start-ArticleStubs" }
    @{ varname = "ImportArticles";             job = "Start-ArticleContent" }
    @{ varname = "ImportPasswords";            job = "Start-Passwords" }
    @{ varname = "FirstTimeLoad";              job = "Start-PostTasks" }
)

function Mount-HuduMigrationLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MigrationLogs,

        [switch]$ForceRefresh
    )

    if (-not (Test-Path -LiteralPath $MigrationLogs)) {
        throw "MigrationLogs path does not exist: $MigrationLogs"
    }

    foreach ($kvp in $script:varMap.GetEnumerator()) {
        $varName = $kvp.Key
        $file    = Join-Path -Path $MigrationLogs -ChildPath $kvp.Value

        $varValue = $null
        $varExists = $false
        try {
            $varValue = Get-Variable -Name $varName -ValueOnly -ErrorAction Stop
            $varExists = $true
        } catch {
            $varExists = $false
        }

        if ($ForceRefresh.IsPresent -or -not $varExists) {
            if (Test-Path -LiteralPath $file) {
                try {
                    $data = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -Depth 100
                    Set-Variable -Name $varName -Value $data -Scope Script
                } catch {
                    Write-Error "Error loading '$file' into `$${varName}: $_"
                    Set-Variable -Name $varName -Value @() -Scope Script
                }
            }
            else {
                Write-Warning "Skipping non-existent migration log file: $file"
            }
        }
    }
}

function Ensure-MigrationLogsDir {
    param ([string]$MigrationLogs)
    $ResumeFound = $false
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
    return $ResumeFound
}