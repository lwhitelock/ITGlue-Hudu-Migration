if ($MyInvocation.InvocationName -eq '.') {
    Write-Host "Script was dot-sourced" -ForegroundColor Green
} else {
    Write-Host "Script was executed without dot-sourcing, this is the recommended method of running the script to ensure settings are retained in the session" -ForegroundColor Yellow; write-warning "exiting to prevent issues later on, please dot-source the script by running `. .\ITGlue-Hudu-Migration.ps1` from powershell 7 or using the provided ITGlue-Hudu-Migration.exe frontend.";
    exit 1
}

if (-not (Get-Command -Name Get-EnsuredPath -ErrorAction SilentlyContinue)) { . $PSScriptRoot\Public\Init-OptionsAndLogs.ps1 }
$ErroredItemsFolder = $(Get-EnsuredPath -path $(join-path $(Resolve-Path .).path "debug"))

# Main settings load
. $PSScriptRoot\Initialize-Module.ps1 -InitType 'Full'

# Use this to set the context of the script runs
$FirstTimeLoad = 1

if ((get-host).version.major -ne 7) {
    Write-Host "Powershell 7 Required" -foregroundcolor Red
    exit 1
}

try {Set-StrictMode -Off} catch {}

############################### Functions ###############################
# Import ImageMagick for Invoke-ImageTest Function (Disabled)
 . $PSScriptRoot\Private\Initialize-ImageMagik.ps1

# Used to determine if a file is an image and what type of image
. $PSScriptRoot\Private\Invoke-ImageTest.ps1

# Confirm Object Import
. $PSScriptRoot\Private\Confirm-Import.ps1

# Matches items from IT Glue to Hudu and creates new items in Hudu
. $PSScriptRoot\Private\Import-Items.ps1

# Select Item Import Mode
. $PSScriptRoot\Private\Get-ImportMode.ps1

# Get Flexible Asset Layout Option
. $PSScriptRoot\Private\Get-FlexLayoutImportMode.ps1

# Fetch Items from ITGlue
. $PSScriptRoot\Private\Import-ITGlueItems.ps1

# Find migrated items
. $PSScriptRoot\Private\Find-MigratedItem.ps1

# Lookup table to upgrade from Font Awesome 4 to 5
. $PSScriptRoot\Private\Get-FontAwesomeMap.ps1
$FontAwesomeUpgrade = Get-FontAwesomeMap

# Add Replace URL functions
. $PSScriptRoot\Private\ConvertTo-HuduURL.ps1

# Add Hudu Relations Function
. $PSScriptRoot\Public\Add-HuduRelation.ps1

# Add Timed (Noninteractive) Messages Helper
. $PSScriptRoot\Public\Write-TimedMessage.ps1

# Add numeral casting, password folder fetching, and article stub starting helpers
. $PSScriptRoot\Public\Get-CastIfNumeric.ps1
. $PSScriptRoot\Public\Start-ArticleStubs.ps1
. $PSScriptRoot\Public\Get-PasswordFolders.ps1

# Add migration scope helper
. $PSScriptRoot\Public\Set-MigrationScope.ps1

# Other JWT-Auth / Advanced Post-Run Imports
. $PSScriptRoot\Public\Get-Checklists.ps1

# Add String/Filename Normalization Helper, image Normalization helper
. $PSScriptRoot\Public\Normalize-String.ps1
. $PSScriptRoot\Public\Normalize-And-ConvertImage.ps1
# initialization helper and field requirement helper, logging, selection helper
. $PSScriptRoot\Public\Get-ITGFieldPopulated.ps1
. $PSScriptRoot\Public\JWT-Auth.ps1
. $PSScriptRoot\Public\NetworkInformation.ps1
. $PSScriptRoot\Public\PreFlightTests.ps1
. $PSScriptRoot\Public\ReplaceAttachmentLinks.ps1
$JobStartTime = $JobStartTime ?? @{}
$MigrationJobTimeline = $MigrationJobTimeline ?? [System.Collections.ArrayList]@()
. $PSScriptRoot\Public\Timed-Job.ps1


############################### End of Functions ###############################
if (-not (Get-Command -Name Get-UserFlagSetup -ErrorAction SilentlyContinue)) { . $PSScriptRoot\Public\Add-OptionalFlags.ps1 }

###################### Initial Setup and Confirmations ###############################
Write-Host $InvocationWelcomeText -ForegroundColor Green
write-host $BackupSafetyText -ForegroundColor DarkCyan
Write-Host $LiabilityWarning -ForegroundColor Red

# Prompt for backups, initialize modules, check versions
$backups=$(if ($true -eq $NonInteractive) {"Y"} else {Read-Host "Y/n"})

$CurrentVersion =  Set-ExternalModulesInitialized `
        -RequiredHuduVersion ([version]"2.42.0") `
        -DisallowedVersions @([version]"2.37.0") `
        -HuduBaseURL $($hudubaseurl ?? $settings.HuduBaseDomain ?? $null) `
        -HuduAPIKey $($huduapikey ?? $settings.HuduApiKey ?? $null)
$ScriptStartTime = $(Get-Date)
$JobStartTime = $JobStartTime ?? @{}
$MigrationJobTimeline = $MigrationJobTimeline ?? [System.Collections.ArrayList]@()

write-host "Checking your API keys to make sure they are scoped for password access" -ForegroundColor DarkCyan
$itglueScopeOk = Test-ITGlueAPIKeyPasswordScope
$huduScopeOk = Test-HuduAPIKeyScope
write-host "Hudu API Key Scope for Password Access: $huduScopeOk"
write-host "IT Glue API Key Scope for Password Access: $itglueScopeOk"
if (-not $true -eq $itglueScopeOk -or -not $true -eq $huduScopeOk) {
    Write-Host "One or both of your API keys do not have the required scope for password access. Please update the key scopes and try again." -ForegroundColor Red
    exit 1
}

write-host "Checking available disk space for migration artifacts" -ForegroundColor DarkCyan
$preflightExportPath = $settings.ITGLueExportPath ?? $environmentSettings.ITGLueExportPath ?? $ITGLueExportPath
$preflightTargetPath = $settings.MigrationLogs ?? $environmentSettings.MigrationLogs ?? $MigrationLogs ?? $preflightExportPath
$diskSpaceCheck = Test-ITGlueExportDiskSpace -ExportPath $preflightExportPath -TargetPath $preflightTargetPath -BufferPercent 15 -Detailed
Write-Host $diskSpaceCheck.Message -ForegroundColor $(if ($diskSpaceCheck.Success) { 'Green' } else { 'Red' })
if (-not $diskSpaceCheck.Success) {
    Write-Host "Exiting before making migration changes. Free up space on the target drive or move MigrationLogs to a drive with enough space." -ForegroundColor Red
    exit 1
}
if ($diskSpaceCheck.EnumerationErrorCount -gt 0) {
    Write-Warning "Could not read $($diskSpaceCheck.EnumerationErrorCount) item(s) while estimating export size. Disk space estimate may be low."
}

write-host "Checking your Incoming and Existing Layouts for Possible Layout-Collision" -ForegroundColor DarkCyan
$PreflightFlexLayouts = $null; $PreflightHuduLayouts = $null; $PreflightFlexibleTargetLayouts = @(); $PreflightITGConfigurations = $null; $PreflightConfigurationTargetLayouts = @(); $PreflightOutlierTargetLayouts = @(); $PreflightCollisionFound = $false;
. .\public\Check-LayoutCollisions.ps1
if ($PreflightCollisionFound) {
    Write-Host "Exiting before making migration changes because one or more pre-flight asset layout collision checks failed." -ForegroundColor Red
    exit 1
}

if ($true -eq $allowSettingFlagsAndTypes){. .\Public\Get-UserFlagPreferences.ps1} else {$allowSettingFlagsAndTypes = $false; $flagPasswordsByType = $false; $ObjectFlagMap = @{};}

if ($backups -notin @("Y", "y")) {
    Write-Host "Please take a backup and run the script again"
    exit 1
}

    if (Test-Path -Path "$MigrationLogs") {
        if (-not ([string]::IsNullOrEmpty($guiSettingsDir)) -and (test-path $guiSettingsDir)){
            Write-Host "Settings loaded from frontend, skipping path checks for logs/errors dir. Migration log dir was set to: $MigrationLogs; Gui settings at $guiSettingsDir" -ForegroundColor Green
        } elseif ($ResumePrevious -eq $true) {
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



# Setup some variables
$MatchedInterfaces = [System.Collections.ArrayList]@()
$ManualActions = [System.Collections.ArrayList]@()
$MergedOrganizationSettings = @{Types        = @(); TargetCompany = $null;}; $ITGLocationsHashTable = @{};
$MatchedPasswordFolders = $MatchedPasswordFolders ?? @(); $preloadedPassFolders = $preloadedPassFolders ?? @{}; $ITGlueSSLCerts = @(); $objectFlagMap = $objectFlagMap ?? @{};
$MatchedChecklists = $MatchedChecklists ?? @(); $ITGlueRawChecklists = $ITGlueRawChecklists ?? @(); $ITglueChecklists = $ITglueChecklists ?? [System.Collections.ArrayList]@(); 
$ErroredItemsFolder = if ($ErroredItemsFolder) {$ErroredItemsFolder} else {(Get-EnsuredPath -path $(join-path $(Resolve-Path .).path "debug"))}

function Get-HuduLocationAssetTagValue {
    param(
        [AllowNull()]
        $ITGLocationId
    )

    if ([string]::IsNullOrWhiteSpace([string]$ITGLocationId)) {
        return $null
    }

    $matchedLocation = $ITGLocationsHashTable["$ITGLocationId"]
    if ($null -eq $matchedLocation) {
        return $null
    }

    $huduLocationId = $matchedLocation.HuduID ?? $matchedLocation.id
    if ([string]::IsNullOrWhiteSpace([string]$huduLocationId)) {
        return $null
    }

    $locationName = $matchedLocation.Name ?? $matchedLocation.name
    return @([pscustomobject]@{
        id   = $huduLocationId
        name = $locationName
    }) | ConvertTo-Json -AsArray -Compress | Out-String
}

function Add-HuduLocationAssetTagLayoutField {
    param(
        [Parameter(Mandatory)]
        [ref]$AssetLayoutFields,

        [Parameter(Mandatory)]
        [int]$Position,

        [Parameter(Mandatory)]
        [string]$LayoutName
    )

    if ($null -eq $LocationLayout -or [string]::IsNullOrWhiteSpace([string]$LocationLayout.ID)) {
        Write-Host "Skipping Location AssetTag field in $LayoutName because no Hudu location layout was found." -ForegroundColor Yellow
        return $false
    }

    $AssetLayoutFields.Value += @{
        label        = 'Location'
        field_type   = 'AssetTag'
        show_in_list = 'false'
        linkable_id  = $LocationLayout.ID
        position     = $Position
    }
    return $true
}

############################### Companies ###############################

#Grab existing companies in Hudu
$HuduCompanies = Get-HuduCompanies

#Check for Company Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Companies.json")) {
    Write-Host "Loading Previous Companies Migration"
    $MatchedCompanies = Get-Content "$MigrationLogs\Companies.json" -raw | Out-String | ConvertFrom-Json
} else {
    $null = Start-MigrationJob -Name "Companies"
    #Import Companies
    Write-Host "Fetching Companies from IT Glue" -ForegroundColor Green
    $CompanySelect = { (Get-ITGlueOrganizations -page_size 1000 -page_number $i).data }
    $ITGCompanies = Import-ITGlueItems -ItemSelect $CompanySelect
    $ITGCompaniesFromCSV = Import-CSV (Join-Path -Path $ITGlueExportPath -ChildPath "organizations.csv")
    Write-Host "$($ITGCompanies.count) ITG Glue Companies Found" 

    if ($ScopedMigration) {
        $OriginalCompanyCount = $($ITGcompanies.count)
        Write-Host "Setting companies to those in scope..." -foregroundcolor Yellow 
        if ($null -ne $Prescoped) {
            $ITGCompanies = Set-PredefinedScope -AllITGCompanies $ITGCompanies -Prescoped $Prescoped -InternalCompany $InternalCompany
        } else {
            $ITGCompanies = Set-MigrationScope -AllITGCompanies $ITGCompanies -InternalCompany $InternalCompany
        }
        $ScopedCompanyIds = $ITGCompanies.id
        Write-Host "Companies scoped... $OriginalCompanyCount => $($Itgcompanies.count)"
    }
    $uniqueOrgTypes = $($ITGCompanies.attributes.'organization-type-name' | Select-Object -unique)
    if ($true -eq $MergedOrganizationTypes){
        $MergedOrganizationSettings.Types+=$(select-objectfromlist -objects $uniqueOrgTypes -message "Select a type to include in type-scoping (from ITGlue). These company types will be attributed to a single company.")
        $MergedOrganizationSettings.TargetCompany = $(Get-HuduCompanies -id $(read-host "To which company will you be scoping $($MergedOrganizationSettings.types) to? [enter company id]"))
        Write-Host "$($($MergedOrganizationSettings.Types | ForEach-Object { $_ }) -join ', ') org types in ITGlue will be attributed to $($MergedOrganizationSettings.TargetCompany.name) in Hudu."
        if ($null -ne $MergedOrganizationSettings.TargetCompany){
            foreach ($kind in $uniqueOrgTypes){
                if ($MergedOrganizationSettings.Types -contains $kind){
                    Write-Host "$($($ITGCompanies | where-object {"$($_.attributes.'organization-type-name')" -eq $kind}).count) of $kind will be migrated to $($MergedOrganizationSettings.TargetCompany.name)" -ForegroundColor Yellow 
                } else {
                    Write-Host "$($($ITGCompanies | where-object {"$($_.attributes.'organization-type-name')" -eq $kind}).count) of $kind will be migrated in the typical fashion" -ForegroundColor Green
                }
            }
    }}
    if ($MergedOrganizationSettings.Types.Count -gt 0 -and -not $MergedOrganizationSettings.TargetCompany){
        Write-Host "Youve designated $($MergedOrganizationSettings.Types.Count) company types to be merged into hudu, but don't have a valid company. Verify that a hudu company exists with the ID that you elected to merge into"
        exit 1
    }
    $ITGCompaniesHashTable = @{}


    $nameTracker = @{}
    $MatchedCompanies = foreach ($itgcompany in $ITGCompanies) {
        $originalName = $itgcompany.attributes.name

        # Create a unique name if it's already been seen
        if ($nameTracker.ContainsKey($originalName)) {
            $nameTracker[$originalName]++
            $uniqueName = "$originalName-$($nameTracker[$originalName])"
        } else {
            $nameTracker[$originalName] = 0
            $uniqueName = $originalName
        }

        $HuduCompany = $HuduCompanies | where-object { $_.name -eq $itgcompany.attributes.name }

        if ($MergedOrganizationSettings.Types -contains "$($itgcompany.attributes.'organization-type-name')"){
            $HuduCompany = $MergedOrganizationSettings.TargetCompany
        }

        $intCompany = $InternalCompany -eq $originalName

        if ($HuduCompany) {
            [PSCustomObject]@{
                "CompanyName"       = $uniqueName
                "ITGID"             = $itgcompany.id
                "HuduID"            = $HuduCompany.id
                "Matched"           = $true
                "InternalCompany"   = $intCompany
                "HuduCompanyObject" = $HuduCompany
                "ITGCompanyObject"  = $itgcompany
                "Imported"          = "Pre-Existing"
            }
        } else {
            [PSCustomObject]@{
                "CompanyName"       = $uniqueName
                "ITGID"             = $itgcompany.id
                "HuduID"            = ""
                "Matched"           = $false
                "InternalCompany"   = $intCompany
                "HuduCompanyObject" = ""
                "ITGCompanyObject"  = $itgcompany
                "Imported"          = ""
            }
        }
    }
    foreach ($ITGC in $MatchedCompanies) {
        $ITGCompaniesHashTable[$ITGC.itgid] = $ITGC
    }
    # Check if the internal company was found and that there was only 1 of them
    $PrimaryCompany = $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.InternalCompany -eq $true } | Select-Object CompanyName

    if (($PrimaryCompany | measure-object).count -ne 1 -and -not ($PlaceInternalDocsInInternalCompany ?? $false)) {
        Write-Host "A single Internal Company was not found please run the script again and check the company name entered exactly matches what is in ITGlue" -foregroundcolor red
        exit 1
    }

    # Lets confirm it is the correct one
    Write-Host "Your Internal Company has been matched to: $(($MatchedCompanies | Sort-Object CompanyName | Where-Object {$_.InternalCompany -eq $true} | Select-Object CompanyName).companyname) in IT Glue. $(if ($true -eq $PlaceInternalDocsInInternalCompany){'The articles under this company will stay in that company in Hudu'} else {'The articles under this company will be migrated to the Global KB in Hudu'})" -ForegroundColor Green
    if ($true -eq $PlaceInternalDocsInInternalCompany){Write-TimedMessage -Message "Internal Company Correct? Press Return to continue or CTRL+C to quit if this is not correct" -Timeout 12 -DefaultResponse "Assuming found match on '$(($MatchedCompanies | Sort-Object CompanyName | Where-Object {$_.InternalCompany -eq $true} | Select-Object CompanyName).companyname)' is correct."}

    Write-Host "Matched Companies (Already exist so will not be migrated)"
    $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.Matched -eq $true } | Select-Object CompanyName | Format-Table

    Write-Host "Unmatched Companies"
    $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.Matched -eq $false } | Select-Object CompanyName | Format-Table

    #Import Locations
    Write-Host "Fetching Locations from IT Glue" -ForegroundColor Green
    $LocationsSelect = { (Get-ITGlueLocations -page_size 1000 -page_number $i -include related_items).data }
    $ITGLocations = Import-ITGlueItems -ItemSelect $LocationsSelect
    if ($ScopedMigration) {
        $OriginalLocationsCount = $($ITGLocations.count)
        Write-Host "Setting locations to those in scope..." -foregroundcolor Yellow
        $ITGLocations         = $ITGLocations | Where-Object { $ScopedCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "locations scoped... $OriginalLocationsCount => $($ITGLocations.count)"
    }

    # Import Companies
    $UnmappedCompanyCount = ($MatchedCompanies | Where-Object { $_.Matched -eq $false } | measure-object).count
    if ($ImportCompanies -eq $true -and $UnmappedCompanyCount -gt 0) {
	
        $importCOption = Get-ImportMode -ImportName "Companies"
	
        if (($importCOption -eq "A") -or ($importCOption -eq "S") ) {		
            foreach ($unmatchedcompany in ($MatchedCompanies | Where-Object { $_.Matched -eq $false })) {

                $unmatchedcompany.ITGCompanyObject.attributes.'quick-notes' = ($ITGCompaniesFromCSV | Where-Object {$_.id -eq $unmatchedcompany.ITGID}).quick_notes
                $unmatchedcompany.ITGCompanyObject.attributes.alert = ($ITGCompaniesFromCSV | Where-Object {$_.id -eq $unmatchedcompany.ITGID}).alert
                Confirm-Import -ImportObjectName $($unmatchedcompany.CompanyName) -ImportObject $unmatchedcompany -ImportSetting $importCOption
						
                Write-Host "Starting $($unmatchedcompany.CompanyName)"
                $PrimaryLocation = $ITGLocations | Where-Object { $unmatchedcompany.ITGID -eq $_.attributes."organization-id" -and $_.attributes.primary -eq $true }
                
                #Check for alerts in ITGlue on the organization
                if ($ITGlueAlert = $unmatchedcompany.ITGCompanyObject.attributes.alert) {
                    $CompanyNotes = "<div class='callout callout-warning'>$ITGlueAlert</div>" + $unmatchedcompany.ITGCompanyObject.attributes."quick-notes"
                } else {
                    $CompanyNotes = $unmatchedcompany.ITGCompanyObject.attributes."quick-notes"
                }

                if ($PrimaryLocation -and $PrimaryLocation.count -eq 1) {
                    $CompanySplat = @{
                        "name"           = $($unmatchedcompany.CompanyName)
                        "nickname"       = $unmatchedcompany.ITGCompanyObject.attributes."short-name"
                        "address_line_1" = $PrimaryLocation.attributes."address-1"
                        "address_line_2" = $PrimaryLocation.attributes."address-2"
                        "city"           = $PrimaryLocation.attributes.city
                        "state"          = $PrimaryLocation.attributes."region-name"
                        "zip"            = $PrimaryLocation.attributes."postal-code"
                        "country_name"   = $PrimaryLocation.attributes."country-name"
                        "phone_number"   = $PrimaryLocation.attributes.phone
                        "fax_number"     = $PrimaryLocation.attributes.fax
                        "notes"          = $CompanyNotes
                        "CompanyType"    = $unmatchedcompany.ITGCompanyObject.attributes.'organization-type-name'
                    }
                    $HuduNewCompany = (New-HuduCompany @CompanySplat).company
                    $CompaniesMigrated = $CompaniesMigrated + 1
                } else {
                    Write-Host "No Location Found, creating company without address details"
                    $HuduNewCompany = (New-HuduCompany -name $($unmatchedcompany.CompanyName) -nickname $unmatchedcompany.ITGCompanyObject.attributes."short-name" -notes $CompanyNotes -CompanyType $unmatchedcompany.attributes.'organization-type-name').company
                    $CompaniesMigrated = $CompaniesMigrated + 1
                }

                $unmatchedcompany.matched = $true
                $unmatchedcompany.HuduID = $HuduNewCompany.id
                $unmatchedcompany.HuduCompanyObject = $HuduNewCompany
                $unmatchedcompany.Imported = "Created-By-Script"
			
                Write-host "$($unmatchedcompany.CompanyName) Has been created in Hudu"
                Write-Host ""
            }
		
        }
		

    } else {
        if ($UnmappedCompanyCount -eq 0) {
            Write-Host "All Companies matched, no migration required" -foregroundcolor green
        } else {
            Write-Host "Warning Import Companies is set to disabled so the above unmatched companies will not have data migrated" -foregroundcolor red
            Write-TimedMessage -Message "Press any key to continue or CTRL+C to quit" -DefaultResponse "continue and wrap-up companies, please." -Timeout 6
        }
    }

    # Save the results to resume from if needed
    $MatchedCompanies | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Companies.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Companies Migrated Continue?"  -DefaultResponse "continue to Locations, please."


}
$CompaniesToMigrate = $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.Matched -eq $true }
$HuduCompanies = Get-HuduCompanies

if (-not ([string]::IsNullOrWhiteSpace($ItglueJWT)) -and ($true -eq $importPasswordFolders -or $true -eq $importChecklists)) {
    Write-Host "Since you have provided a JWT token and have checklist or password folder import enabled, we will preload these items from ITGlue before your credential becomes stale." -ForegroundColor Green
    . $PSScriptRoot\Public\Preload-JWTOnlyItems.ps1
}

############################### Locations ###############################
#Check for Location Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Locations.json")) {
    Write-Host "Loading Previous Locations Migration"
    $MatchedLocations = Get-Content "$MigrationLogs\Locations.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {
    $null = Start-MigrationJob -Name "Locations"
    $ITGLocations = $ITGLocations |select @{n='HuduCompanyId';e={ $ITGCompaniesHashTable["$($_.attributes.'organization-id')"].huduid}},*

    $LocHuduItemFilter = { ($_.name -eq $itgimport.attributes.name -and $_.company_id -eq $itgimport.HuduCompanyId)`
            -or ($ITGPrimaryLocationNames -contains $itgimport.attributes.name -and $HuduPrimaryLocationNames -contains $_.name -and $_.company_id -eq $itgimport.HuduCompanyId)`
            -or ($itgimport.attributes.primary -eq $true -and $HuduPrimaryLocationNames -contains $_.name -and $_.company_id -eq $itgimport.HuduCompanyId) }

    $LocImportEnabled = $ImportLocations

    $LocMigrationName = "Locations"


    $LocAssetLayoutFields = @(
        @{
            label        = 'Address 1'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 1
        },
        @{
            label        = 'Address 2'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 2
        },
        @{
            label        = 'City'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 3
        },
        @{
            label        = 'Postal Code'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 4
        },
        @{
            label        = 'Region'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 5
        },
        @{
            label        = 'Country'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 6
        },
        @{
            label        = 'Phone'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 7
        },
        @{
            label        = 'Fax'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 8
        },
        @{
            label        = 'Notes'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 9
        },
        @{
            label        = 'ITG Date Created'
            field_type   = 'Date'
            show_in_list = 'true'
            position     = 10
        },
        @{
            label        = 'ITG Date Last Updated'
            field_type   = 'Date'
            show_in_list = 'true'
            position     = 11
        }
    )
    if ($settings.IncludeITGlueID -and $true -eq $settings.IncludeITGlueID){
        $LocAssetLayoutFields+=@{
            label        = 'ITGlue ID'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 502}
        $LocAssetFieldsMap = { @{ 
            'address 1'   = $unmatchedImport."ITGObject".attributes."address-1"
            'address 2'   = $unmatchedImport."ITGObject".attributes."address-2"
            'city'        = $unmatchedImport."ITGObject".attributes."city"
            'postal code' = $unmatchedImport."ITGObject".attributes."postal-code"
            'region'      = $unmatchedImport."ITGObject".attributes."region-name"
            'country'     = $unmatchedImport."ITGObject".attributes."country-name"
            'phone'       = $unmatchedImport."ITGObject".attributes."phone"
            'fax'         = $unmatchedImport."ITGObject".attributes."fax"
            'notes'       = $unmatchedImport."ITGObject".attributes."notes"
            'ITG Date Created'          = $unmatchedImport."ITGObject".attributes."created-at"
            'ITG Date Last Updated'     = $unmatchedImport."ITGObject".attributes."updated-at"
            'ITGlue ID'   = $unmatchedImport."ITGObject".id
        } }            
    } else {
        $LocAssetFieldsMap = { @{ 
            'address 1'   = $unmatchedImport."ITGObject".attributes."address-1"
            'address 2'   = $unmatchedImport."ITGObject".attributes."address-2"
            'city'        = $unmatchedImport."ITGObject".attributes."city"
            'postal code' = $unmatchedImport."ITGObject".attributes."postal-code"
            'region'      = $unmatchedImport."ITGObject".attributes."region-name"
            'country'     = $unmatchedImport."ITGObject".attributes."country-name"
            'phone'       = $unmatchedImport."ITGObject".attributes."phone"
            'fax'         = $unmatchedImport."ITGObject".attributes."fax"
            'notes'       = $unmatchedImport."ITGObject".attributes."notes"		
            'ITG Date Created'          = $unmatchedImport."ITGObject".attributes."created-at"
            'ITG Date Last Updated'     = $unmatchedImport."ITGObject".attributes."updated-at"
        } }
    }


    $LocImportSplat = @{
        AssetFieldsMap        = $LocAssetFieldsMap
        AssetLayoutFields     = $LocAssetLayoutFields
        ImportIcon            = $LocImportIcon
        ImportEnabled         = $LocImportEnabled
        HuduItemFilter        = $LocHuduItemFilter
        ImportAssetLayoutName = $LocImportAssetLayoutName
        ItemSelect            = $LocItemSelect
        MigrationName         = $LocMigrationName
        ITGImports            = $ITGLocations

    }

    #Import Locations
    $MatchedLocations = Import-Items @LocImportSplat

    # Save the results to resume from if needed
    $($MatchedLocations ?? @()) | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Locations.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Locations Migrated Continue?"  -DefaultResponse "continue to Websites, please."

}

$ITGLocationsHashTable = @{}
foreach ($ITGL in $($MatchedLocations ?? @())) {
    $ITGLocationsHashTable["$($ITGL.itgid)"] = $ITGL
}
$LocationLayout = Get-HuduAssetLayouts -name $LocImportAssetLayoutName

############################### Websites ###############################

#Check for Website Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Websites.json")) {
    Write-Host "Loading Previous Websites Migration"
    $MatchedWebsites = Get-Content "$MigrationLogs\Websites.json" -raw | Out-String | ConvertFrom-Json
} else {
    $null = Start-MigrationJob -Name "Websites"
    #Grab existing Websites in Hudu
    $HuduWebsites = Get-HuduWebsites

    #Import Websites
    Write-Host "Fetching Domains from IT Glue" -ForegroundColor Green
    $DomainSelect = { (Get-ITGlueDomains -page_size 1000 -page_number $i).data }
    $ITGDomains = Import-ITGlueItems -ItemSelect $DomainSelect

    if ($ScopedMigration) {
        $OriginalDomainsCount = $($ITGDomains.count)
        Write-Host "Setting domains to those in scope..." -foregroundcolor Yellow
        $ITGDomains          = $ITGdomains | Where-Object { $ScopedCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "domains scoped... $OriginalDomainsCount => $($ITGDomains.count)"
    }

    Write-Host "$($ITGDomains.count) ITG Glue Domains Found" 

    $MatchedWebsites = foreach ($itgdomain in $ITGDomains ) {
        $HuduWebsite = $HuduWebsites | Where-Object { ($_.name -eq "https://$($itgdomain.attributes.name)" -and $_.company_name -eq $itgdomain.attributes."organization-name") }
        if ($HuduWebsite) {
            [PSCustomObject]@{
                "Name"       = $itgdomain.attributes.name
                "ITGID"      = $itgdomain.id
                "HuduID"     = $HuduWebsite.id
                "Matched"    = $true
                "HuduObject" = $HuduWebsite
                "ITGObject"  = $itgdomain
                "Imported"   = "Pre-Existing"

            }
        } else {
            [PSCustomObject]@{
                "Name"       = $itgdomain.attributes.name
                "ITGID"      = $itgdomain.id
                "HuduID"     = ""
                "Matched"    = $false
                "HuduObject" = ""
                "ITGObject"  = $itgdomain
                "Imported"   = ""
            }
        }
    }


    Write-Host "Matched Websites / Domains (Already exist so will not be migrated)"
    $MatchedWebsites | Sort-Object Name | Where-Object { $_.Matched -eq $true } | Select-Object Name | Format-Table

    Write-Host "Unmatched Websites / Domains"
    $MatchedWebsites | Sort-Object Name | Where-Object { $_.Matched -eq $false } | Select-Object Name | Format-Table

    $UnmappedWebsiteCount = ($MatchedWebsites | Where-Object { $_.Matched -eq $false } | measure-object).count

    if ($ImportDomains -eq $true -and $UnmappedWebsiteCount -gt 0) {

        $importOption = Get-ImportMode -ImportName "Websites / Domains"

        if (($importOption -eq "A") -or ($importOption -eq "S") ) {		

            foreach ($company in $CompaniesToMigrate) {
                Write-Host "Migrating $($company.CompanyName)" -ForegroundColor Green

                foreach ($unmatchedWebsite in ($MatchedWebsites | Where-Object { $_.Matched -eq $false -and $company.ITGCompanyObject.id -eq $_."ITGObject".attributes."organization-id" })) {
				

                    Confirm-Import -ImportObjectName "$($unmatchedWebsite.Name)" -ImportObject $unmatchedWebsite -ImportSetting $ImportOption

                    Write-Host "Starting $($unmatchedWebsite.Name);"
                    $HuduNewWebsite = New-HuduWebsite -name "https://$($unmatchedWebsite.ITGObject.attributes.name)" `
                                                -notes $unmatchedWebsite.ITGObject.attributes.notes `
                                                -paused $DisableWebsiteMonitoring `
                                                -companyid $company.HuduCompanyObject.ID `
                                                -DisableDNS $DisableWebsiteMonitoring.ToString().ToLower() `
                                                -DisableSSL $DisableWebsiteMonitoring.ToString().ToLower() `
                                                -DisableWhois $DisableWebsiteMonitoring.ToString().ToLower()


                    $unmatchedWebsite.matched = $true
                    $unmatchedWebsite.HuduID = $HuduNewWebsite.id
                    $unmatchedWebsite."HuduObject" = $HuduNewWebsite
                    $unmatchedWebsite.Imported = "Created-By-Script"

                    $ImportsMigrated = $ImportsMigrated + 1

                    Write-host "$($unmatchedWebsite.Name) Has been created in Hudu"
                }
            }
        }


    } else {
        if ($UnmappedWebsiteCount -eq 0) {
            Write-Host "All $MigrationName matched, no migration required" -foregroundcolor green
        } else {
            Write-TimedMessage -Timeout 12 -Message "Warning Import Websites is set to disabled so the above unmatched Websites will not have data migrated... Press any key to continue or CTRL+C to quit"  -DefaultResponse "continue and wrap-up Websites, please."
        }
    }

    # Save the results to resume from if needed
    $MatchedWebsites | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Websites.json"
    Write-TimedMessage -Timeout 3 -Message  "Snapshot Point: Websites Migrated Continue?"  -DefaultResponse "continue to Configurations, please."

}




		
############################### Configurations ###############################
	
$ConfigMigrationName = $ConfigMigrationName ?? "Configurations"
$ConfigImportAssetLayoutName = $ConfigImportAssetLayoutName ?? "$($ConfigurationPrefix)Configurations"
	
#Check for Configuration Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Configurations.json")) {
    Write-Host "Loading Previous Configurations Migration"
    $MatchedConfigurations = Get-Content "$MigrationLogs\Configurations.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {
    $null = Start-MigrationJob -Name "Configurations"

    #Get Configurations from IT Glue
    Write-Host "Fetching Configurations from IT Glue" -ForegroundColor Green
    if ($PreflightITGConfigurations) {
        $ITGConfigurations = $PreflightITGConfigurations
        Write-Host "Using IT Glue configurations retrieved during pre-flight." -ForegroundColor DarkGray
    } else {
        $ConfigurationsSelect = { (Get-ITGlueConfigurations -page_size 1000 -page_number $i -include related_items).data }
        $ITGConfigurations = Import-ITGlueItems -ItemSelect $ConfigurationsSelect
    }
    $ITGConfigurations = $ITGConfigurations |select @{n='HuduCompanyId';e={ $ITGCompaniesHashTable["$($_.attributes.'organization-id')"].huduid}},*
    if ($ScopedMigration) {
        $OriginalConfigurationCount = $($ITGConfigurations.count)
        Write-Host "Setting configurations to those in scope..." -foregroundcolor Yellow        
        $ITGConfigurations    = $ITGConfigurations | Where-Object { $ScopedCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "configurations scoped... $OriginalConfigurationCount => $($ITGConfigurations.count)"
    }

    $ConfigAssetLayoutFields = @(
        @{
            label        = 'Hostname'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 1
        },
        @{
            label        = 'Primary IP'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 2
        },
        @{
            label        = 'MAC Address'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 3
        },
        @{
            label        = 'Default Gateway'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 4
        },
        @{
            label        = 'Serial Number'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 5
        },
        @{
            label        = 'Asset Tag'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 6
        },
        @{
            label        = 'Position'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 7
        },
        @{
            label        = 'Installed By'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 8
        },
        @{
            label        = 'Purchased By'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 9
        },
        @{
            label        = 'Notes'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 10
        },
        @{
            label        = 'Operating System Notes'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 11
        },
        @{
            label        = 'Warranty Expires At'
            field_type   = 'Date'
            expiration   = 'true'
            show_in_list = 'false'
            position     = 12
        },
        @{
            label        = 'Installed At'
            field_type   = 'Date'
            show_in_list = 'false'
            position     = 13
        },
        @{
            label        = 'Purchased At'
            field_type   = 'Date'
            show_in_list = 'false'
            position     = 14
        },
        @{
            label        = 'Configuration Type Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 15
        },
        @{
            label        = 'Configuration Type Kind'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 16
        },
        @{
            label        = 'Configuration Status Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 17
        },
        @{
            label        = 'Manufacturer Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 18
        },
        @{
            label        = 'Model ID'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 19
        },
        @{
            label        = 'Operating System Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 20
        },
        @{
            label        = 'Model Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 22
        },
        @{
            label        = 'Contact Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 23
        },
        @{
            label        = 'ITG Date Created'
            field_type   = 'Date'
            show_in_list = 'true'
            position     = 24
        },
        @{
            label        = 'ITG Date Last Updated'
            field_type   = 'Date'
            show_in_list = 'true'
            position     = 25
        }
    )
    $null = Add-HuduLocationAssetTagLayoutField -AssetLayoutFields ([ref]$ConfigAssetLayoutFields) -Position 21 -LayoutName $ConfigImportAssetLayoutName
    $ConfigHuduItemFilter = { ($_.name -eq $itgimport.attributes.name -and $_.company_id -eq $itgimport.HuduCompanyId) }
	
    $ConfigImportEnabled = $ImportConfigurations
    if ($settings.IncludeITGlueID -and $true -eq $settings.IncludeITGlueID){
        $ConfigAssetLayoutFields+=@{
            label        = 'ITGlue ID'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 502}
        $ConfigAssetFieldsMap = {
            $AssetFields = @{
            'hostname'                  = $unmatchedImport."ITGObject".attributes."hostname"
            'primary ip'                = $unmatchedImport."ITGObject".attributes."primary-ip"
            'mac address'               = $unmatchedImport."ITGObject".attributes."mac-address"
            'default gateway'           = $unmatchedImport."ITGObject".attributes."default-gateway"
            'serial number'             = $unmatchedImport."ITGObject".attributes."serial-number"
            'asset tag'                 = $unmatchedImport."ITGObject".attributes."asset-tag"
            'position'                  = $unmatchedImport."ITGObject".attributes."position"
            'installed by'              = $unmatchedImport."ITGObject".attributes."installed-by"
            'purchased by'              = $unmatchedImport."ITGObject".attributes."purchased-by"
            'notes'                     = $unmatchedImport."ITGObject".attributes."notes"
            'operating system notes'    = $unmatchedImport."ITGObject".attributes."operating-system-notes"
            'warranty expires at'       = $unmatchedImport."ITGObject".attributes."warranty-expires-at"
            'installed at'              = $unmatchedImport."ITGObject".attributes."installed-at"
            'purchased at'              = $unmatchedImport."ITGObject".attributes."purchased-at"
            'configuration type name'   = $unmatchedImport."ITGObject".attributes."configuration-type-name"
            'configuration type kind'   = $unmatchedImport."ITGObject".attributes."configuration-type-kind"
            'manufacturer name'  		= $unmatchedImport."ITGObject".attributes."manufacturer-name"			
            'configuration status_name' = $unmatchedImport."ITGObject".attributes."configuration-status-name"
            'operating system name'     = $unmatchedImport."ITGObject".attributes."operating-system-name"
            'model name'                = $unmatchedImport."ITGObject".attributes."model-name"
            'contact name'              = $unmatchedImport."ITGObject".attributes."contact-name"
            'ITG Date Created'          = $unmatchedImport."ITGObject".attributes."created-at"	
            'ITG Date Last Updated'     = $unmatchedImport."ITGObject".attributes."updated-at"            
            'ITGlue ID'                 = $unmatchedImport."ITGObject".id
            }
            $LocationAssetTagValue = Get-HuduLocationAssetTagValue -ITGLocationId $unmatchedImport."ITGObject".attributes.'location-id'
            if ($LocationAssetTagValue) {
                $AssetFields['location'] = $LocationAssetTagValue
            }
            $AssetFields
        }
    } else {
        $ConfigAssetFieldsMap = {
            $AssetFields = @{
            'hostname'                  = $unmatchedImport."ITGObject".attributes."hostname"
            'primary ip'                = $unmatchedImport."ITGObject".attributes."primary-ip"
            'mac address'               = $unmatchedImport."ITGObject".attributes."mac-address"
            'default gateway'           = $unmatchedImport."ITGObject".attributes."default-gateway"
            'serial number'             = $unmatchedImport."ITGObject".attributes."serial-number"
            'asset tag'                 = $unmatchedImport."ITGObject".attributes."asset-tag"
            'position'                  = $unmatchedImport."ITGObject".attributes."position"
            'installed by'              = $unmatchedImport."ITGObject".attributes."installed-by"
            'purchased by'              = $unmatchedImport."ITGObject".attributes."purchased-by"
            'notes'                     = $unmatchedImport."ITGObject".attributes."notes"
            'operating system notes'    = $unmatchedImport."ITGObject".attributes."operating-system-notes"
            'warranty expires at'       = $unmatchedImport."ITGObject".attributes."warranty-expires-at"
            'installed at'              = $unmatchedImport."ITGObject".attributes."installed-at"
            'purchased at'              = $unmatchedImport."ITGObject".attributes."purchased-at"
            'configuration type name'   = $unmatchedImport."ITGObject".attributes."configuration-type-name"
            'configuration type kind'   = $unmatchedImport."ITGObject".attributes."configuration-type-kind"
            'manufacturer name'  		= $unmatchedImport."ITGObject".attributes."manufacturer-name"			
            'configuration status_name' = $unmatchedImport."ITGObject".attributes."configuration-status-name"
            'operating system name'     = $unmatchedImport."ITGObject".attributes."operating-system-name"
            'model name'                = $unmatchedImport."ITGObject".attributes."model-name"
            'contact name'              = $unmatchedImport."ITGObject".attributes."contact-name"
            'ITG Date Created'          = $unmatchedImport."ITGObject".attributes."created-at"	
            'ITG Date Last Updated'     = $unmatchedImport."ITGObject".attributes."updated-at"            	
            }
            $LocationAssetTagValue = Get-HuduLocationAssetTagValue -ITGLocationId $unmatchedImport."ITGObject".attributes.'location-id'
            if ($LocationAssetTagValue) {
                $AssetFields['location'] = $LocationAssetTagValue
            }
            $AssetFields
        }
    }

    $ConfigurationPrefix = $settings.ConPromptPrefix ?? $ConfigurationPrefix ?? ""
    $SplitConfigurations = [bool]($settings.SplitConfigurations ?? $false)
    $ConfigurationOption = if ($SplitConfigurations) { 2 } else { 1 }
    Write-Host "Using configuration import mode $ConfigurationOption from settings.SplitConfigurations=$SplitConfigurations." -ForegroundColor DarkGray

    # All Configurations to 1 Layout
    if ($ConfigurationOption -eq 1) {
	
	

        $ConfigImportSplat = @{
            AssetFieldsMap        = $ConfigAssetFieldsMap
            AssetLayoutFields     = $ConfigAssetLayoutFields
            ImportIcon            = $ConfigImportIcon
            ImportEnabled         = $ConfigImportEnabled
            HuduItemFilter        = $ConfigHuduItemFilter
            ImportAssetLayoutName = $ConfigImportAssetLayoutName
            ItemSelect            = $ConfigItemSelect
            MigrationName         = $ConfigMigrationName
            ITGImports            = $ITGConfigurations
        }

        $MatchedConfigurations = Import-Items @ConfigImportSplat


    } elseif ($ConfigurationOption -eq 2) {
        $ITGConfigTypes = $ITGConfigurations.attributes."configuration-type-name" | Select-Object -unique
        $MatchedConfigurations = New-Object System.Collections.ArrayList
        foreach ($ConfigType in $ITGConfigTypes) {

            Write-Host "Processing $ConfigType"

            $ParsedITGConfigs = $ITGConfigurations | Where-Object { $_.attributes."configuration-type-name" -eq $ConfigType }

            $ConfigMigrationName = "$($ConfigurationPrefix)$($ConfigType)"
            $ConfigImportAssetLayoutName = "$($ConfigurationPrefix)$($ConfigType)"
	
            $ConfigImportSplat = @{
                AssetFieldsMap        = $ConfigAssetFieldsMap
                AssetLayoutFields     = $ConfigAssetLayoutFields
                ImportIcon            = $ConfigImportIcon
                ImportEnabled         = $ConfigImportEnabled
                HuduItemFilter        = $ConfigHuduItemFilter
                ImportAssetLayoutName = $ConfigImportAssetLayoutName
                ItemSelect            = $ConfigItemSelect
                MigrationName         = $ConfigMigrationName
                ITGImports            = $ParsedITGConfigs
            }
	
            $ReturnedConfigurations = Import-Items @ConfigImportSplat

            if (($ReturnedConfigurations | measure-object).count -gt 1) {
                $MatchedConfigurations.addrange($ReturnedConfigurations)
            } else {
                $MatchedConfigurations.add($ReturnedConfigurations)
            }

        }

    } else {
        Write-Error "This should never have happened somehow you selected something other than 1 or 2."
        exit 1
    }



    # Save the results to resume from if needed
    $MatchedConfigurations | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Configurations.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Configurations Migrated Continue?"  -DefaultResponse "continue to Contacts, please."

}


############################### Contacts ###############################
#Check for Location Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Contacts.json")) {
    Write-Host "Loading Previous Contacts Migration"
    $MatchedContacts = Get-Content "$MigrationLogs\Contacts.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {

    $null = Start-MigrationJob -Name "Contacts"

    Write-Host "Fetching Contacts from IT Glue" -ForegroundColor Green
    $ContactsSelect = { (Get-ITGlueContacts -page_size 1000 -page_number $i -include related_items).data }
    $ITGContacts = Import-ITGlueItems -ItemSelect $ContactsSelect
    $ITGContacts = $ITGContacts |select @{n='HuduCompanyId';e={ $ITGCompaniesHashTable["$($_.attributes.'organization-id')"].huduid}},*

    #($ITGContacts.attributes | sort-object -property name, "organization-name" -Unique)


    if ($ScopedMigration) {
        $OriginalContactsCount = $($ITGContacts.count)
        Write-Host "Setting contacts to those in scope..." -foregroundcolor Yellow               
        $ITGContacts          = $ITGContacts | Where-Object { $ScopedCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "Contacts scoped... $OriginalContactsCount => $($ITGContacts.count)"
    }

    $ConHuduItemFilter = { ($_.name -eq $itgimport.attributes.name -and $_.company_id -eq $itgimport.HuduCompanyId) }

    $ConImportEnabled = $ImportContacts

    $ConMigrationName = "Contacts"

    $ConAssetLayoutFields = @(
        @{
            label        = 'First Name'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 1
        },
        @{
            label        = 'Last Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 2
        },
        @{
            label        = 'Title'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 3
        },
        @{
            label        = 'Contact Type'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 4
        },
        @{
            label        = 'Important'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 6
        },
        @{
            label        = 'Notes'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 7
        },
        @{
            label        = 'Emails'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 8
        },
        @{
            label        = 'Phones'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 9
        },
        @{
            label        = 'ITG Date Created'
            field_type   = 'Date'
            show_in_list = 'true'
            position     = 10
        }    
        @{
            label        = 'ITG Date Last Updated'
            field_type   = 'Date'
            show_in_list = 'true'
            position     = 11
        }
    )
    $null = Add-HuduLocationAssetTagLayoutField -AssetLayoutFields ([ref]$ConAssetLayoutFields) -Position 5 -LayoutName $ConImportAssetLayoutName
    if ($settings.IncludeITGlueID -and $true -eq $settings.IncludeITGlueID){
        $ConAssetLayoutFields+=@{
            label        = 'ITGlue ID'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 502}
        $ConAssetFieldsMap = {
            $AssetFields = @{
            'first name'   = $unmatchedImport."ITGObject".attributes."first-name"
            'last name'    = $unmatchedImport."ITGObject".attributes."last-name"
            'title'        = $unmatchedImport."ITGObject".attributes."title"
            'contact type' = $unmatchedImport."ITGObject".attributes."contact-type-name"
            'important'    = $unmatchedImport."ITGObject".attributes."important"
            'notes'        = $unmatchedImport."ITGObject".attributes."notes"
            'emails'       = $unmatchedImport."ITGObject".attributes."contact-emails" | convertto-html -fragment | out-string
            'phones'       = $unmatchedImport."ITGObject".attributes."contact-phones" | convertto-html -fragment | out-string
            'ITG Date Created'   = $unmatchedImport."ITGObject".attributes."created-at"
            'ITG Date Last Updated'   = $unmatchedImport."ITGObject".attributes."updated-at"
            'ITGlue ID'    = $unmatchedImport."ITGObject".id
            }
            $LocationAssetTagValue = Get-HuduLocationAssetTagValue -ITGLocationId $unmatchedImport."ITGObject".attributes.'location-id'
            if ($LocationAssetTagValue) {
                $AssetFields['location'] = $LocationAssetTagValue
            }
            $AssetFields
        }
    } else {
        $ConAssetFieldsMap = {
            $AssetFields = @{
            'first name'   = $unmatchedImport."ITGObject".attributes."first-name"
            'last name'    = $unmatchedImport."ITGObject".attributes."last-name"
            'title'        = $unmatchedImport."ITGObject".attributes."title"
            'contact type' = $unmatchedImport."ITGObject".attributes."contact-type-name"
            'important'    = $unmatchedImport."ITGObject".attributes."important"
            'notes'        = $unmatchedImport."ITGObject".attributes."notes"
            'emails'       = $unmatchedImport."ITGObject".attributes."contact-emails" | convertto-html -fragment | out-string
            'phones'       = $unmatchedImport."ITGObject".attributes."contact-phones"	| convertto-html -fragment | out-string
            'ITG Date Created'   = $unmatchedImport."ITGObject".attributes."created-at"
            'ITG Date Last Updated'   = $unmatchedImport."ITGObject".attributes."updated-at"        
            }
            $LocationAssetTagValue = Get-HuduLocationAssetTagValue -ITGLocationId $unmatchedImport."ITGObject".attributes.'location-id'
            if ($LocationAssetTagValue) {
                $AssetFields['location'] = $LocationAssetTagValue
            }
            $AssetFields
        }
    }

    $ConImportSplat = @{
        AssetFieldsMap        = $ConAssetFieldsMap
        AssetLayoutFields     = $ConAssetLayoutFields
        ImportIcon            = $ConImportIcon
        ImportEnabled         = $ConImportEnabled
        HuduItemFilter        = $ConHuduItemFilter
        ImportAssetLayoutName = $ConImportAssetLayoutName
        ItemSelect            = $ConItemSelect
        MigrationName         = $ConMigrationName
        ITGImports            = $ITGContacts

    }

    #Import Locations
    $MatchedContacts = Import-Items @ConImportSplat

    Write-Host "Contacts Complete"

    # Save the results to resume from if needed
    $MatchedContacts | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Contacts.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Contacts Migrated Continue?"  -DefaultResponse "continue to Flexible Asset Layouts, please."

}

	
############################### Flexible Asset Layouts and Assets ###############################
#Check for Layouts Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\AssetLayouts.json")) {
    Write-Host "Loading Previous Asset Layouts Migration"
    $MatchedLayouts = Get-Content "$MigrationLogs\AssetLayouts.json" -raw | Out-String | ConvertFrom-Json -depth 100
    $AllFields = Get-Content "$MigrationLogs\AssetLayoutsFields.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {
    $null = Start-MigrationJob -Name "Layouts"

    $ConfigImportAssetLayoutName = ($MatchedConfigurations.HuduObject | Select-Object name, asset_type | group-object -property asset_type | sort-object count -descending | Select-Object -first 1).name

    Write-Host "Fetching Flexible Asset Layouts from IT Glue" -ForegroundColor Green
    if ($PreflightFlexLayouts) {
        $FlexLayouts = $PreflightFlexLayouts
        Write-Host "Using IT Glue flexible asset layouts retrieved during pre-flight." -ForegroundColor DarkGray
    } else {
        $FlexLayoutSelect = { (Get-ITGlueFlexibleAssetTypes -page_size 1000 -page_number $i -include related_items).data }
        $FlexLayouts = Import-ITGlueItems -ItemSelect $FlexLayoutSelect
    }

    $HuduLayouts = if ($PreflightHuduLayouts) { $PreflightHuduLayouts } else { Get-HuduAssetLayouts }

    Write-Host "The script will now migrate IT Glue Flexible Asset Layouts to Hudu"
    Write-Host "Please select the option you would like"
    Write-Host "1) Move all Flexible Asset Layouts to Hudu"
    Write-Host "2) Determine on a layout by layout basis if you want to migrate"
    $ImportOption = Get-FlexLayoutImportMode

    $AllFields = [System.Collections.ArrayList]@()

    # Match to existing layouts
    $MatchedLayouts = foreach ($ITGLayout in $FlexLayouts) {
        if ($skipIntegratorLayouts -and $true -eq $skipIntegratorLayouts){
            if ("$($ITGLayout.attributes.name)" -ilike "*(auto)*" -or "$($ITGLayout.attributes.name)" -ilike "*(liongard)*"){
                Write-warning "Skipping Integrator Layout $($ITGLayout.attributes.name)"
                continue
            }
        }


        $HuduLayout = $HuduLayouts | Where-Object { $_.name -eq "$($FlexibleLayoutPrefix)$($ITGLayout.attributes.name)" }
		
        if ($HuduLayout) {
            [PSCustomObject]@{
                "Name"       = $ITGLayout.attributes.name
                "ITGID"      = $ITGLayout.id
                "HuduID"     = $HuduLayout.id
                "Matched"    = $true
                "HuduObject" = $HuduLayout
                "ITGObject"  = $ITGLayout
                "ITGAssets"  = ""
                "Imported"   = "Pre-Existing"
			
            }
        } else {
            [PSCustomObject]@{
                "Name"       = $ITGLayout.attributes.name
                "ITGID"      = $ITGLayout.id
                "HuduID"     = ""
                "Matched"    = $false
                "HuduObject" = ""
                "ITGObject"  = $ITGLayout
                "ITGAssets"  = ""
                "Imported"   = ""
            }
        }
    }



    Write-Host "Matched Flexible Layouts (Already exist so will not be migrated)"
    $MatchedLayouts | Sort-Object Name | Where-Object { $_.Matched -eq $true } | Select-Object Name | Format-Table

    Write-Host "Unmatched Flexible Layouts"
    $MatchedLayouts | Sort-Object Name | Where-Object { $_.Matched -eq $false } | Select-Object Name | Format-Table


    if ($ImportFlexibleAssetLayouts -eq $true) {
        $FlexAssetsByLayoutId = @{}

        foreach ($UnmatchedLayout in $MatchedLayouts | Where-Object { $_.Matched -eq $false }) {
            $LayoutCacheKey = [string]$UnmatchedLayout.ITGID
            if (-not $FlexAssetsByLayoutId.ContainsKey($LayoutCacheKey)) {
                Write-Host "Fetching Flexible Assets for $($UnmatchedLayout.Name) to determine whether the layout has assets in scope"
                $FlexAssetsSelect = { (Get-ITGlueFlexibleAssets -page_size 1000 -page_number $i -filter_flexible_asset_type_id $UnmatchedLayout.ITGID -include related_items).data }
                $FlexAssets = Import-ITGlueItems -ItemSelect $FlexAssetsSelect

                if ($ScopedMigration) {
                    $FlexAssets = @($FlexAssets | Where-Object {
                        $ScopedCompanyIds -contains $_.attributes.'organization-id'
                    })
                }

                $FlexAssetsByLayoutId[$LayoutCacheKey] = @($FlexAssets)
            }

            if (@($FlexAssetsByLayoutId[$LayoutCacheKey]).Count -eq 0) {
                Write-Host "Skipping layout '$($UnmatchedLayout.Name)' because it has no assets in scope." -ForegroundColor Yellow
                $UnmatchedLayout.ITGAssets = @()
                continue
            }

            if ($ImportOption -eq 2) {
                Confirm-Import -ImportObjectName "$($UnmatchedLayout.ITGObject.attributes.name)" -ImportObject $UnmatchedLayout -ImportSetting $ImportOption
            }


            $TempLayoutFields = @(
                @{
                    label        = 'ITG Date Created'
                    field_type   = 'Date'
                    show_in_list = 'true'
                    position     = 498
                },
                @{
                    label        = 'ITG Date Last Updated'
                    field_type   = 'Date'
                    show_in_list = 'true'
                    position     = 499
                },                
                @{
                    label        = 'Imported from ITGlue'
                    field_type   = 'Date'
                    show_in_list = 'false'
                    position     = 500
                },
                @{
                    label        = 'ITGlue URL'
                    field_type   = 'Text'
                    show_in_list = 'false'
                    position     = 501
                },
                @{
                    label        = 'ITGlue ID'
                    field_type   = 'Text'
                    show_in_list = 'false'
                    position     = 502
                }

            )
            if ($null -eq $UnmatchedLayout.ITGObject.attributes.icon) {
                $NewIcon = 'circle'

            } elseif ($($FontAwesomeUpgrade."$($UnmatchedLayout.ITGObject.attributes.icon)")) {
                $NewIcon = $($FontAwesomeUpgrade."$($UnmatchedLayout.ITGObject.attributes.icon)")
            } else {
                $CurrentIcon = ($UnmatchedLayout.ITGObject.attributes.icon -replace "-o-", "-")
                $LastTwo = $CurrentIcon.Substring($CurrentIcon.get_Length() - 2)
                if ($LastTwo -eq "-o") {
                    #strip last 2 digits
                    $CurrentIcon = $CurrentIcon.Substring(0, $CurrentIcon.get_Length() - 2)
                }
                $NewIcon = $CurrentIcon
            }
            $TargetLayoutName = "$($FlexibleLayoutPrefix)$($UnmatchedLayout.ITGObject.attributes.name)"
            # Defense-in-depth in case Hudu layout state changed after the pre-flight check.
            if ($(Get-HuduAssetLayouts | Where-Object { $_.name -ieq $TargetLayoutName })) {
                Write-Host "Flexible asset layout '$TargetLayoutName' now collides with an existing Hudu asset layout. Exiting instead of creating a renamed layout." -ForegroundColor Red
                exit 1
            }
            $NewLayout = New-HuduAssetLayout -name $TargetLayoutName -icon "fas fa-$NewIcon" -color "$($LayoutIconBackGroundColor)" -icon_color "$($LayoutIconForegroundColor)" -include_passwords $true -include_photos $true -include_comments $true -include_files $true -fields $TempLayoutFields

            $MatchedNewLayout = Get-HuduAssetLayouts -layoutid $NewLayout.asset_layout.id

            $UnmatchedLayout.HuduObject = $MatchedNewLayout
            $UnmatchedLayout.HuduID = $NewLayout.asset_layout.id
            $UnmatchedLayout.Imported = "Created-By-Script"
        }


        foreach ($UpdateLayout in $MatchedLayouts) {
            if ($skipIntegratorLayouts -and $true -eq $skipIntegratorLayouts){
                if ("$($UpdateLayout.Name)" -ilike "*(auto)*" -or "$($UpdateLayout.Name)" -ilike "*(liongard)*"){
                    Write-Host "Skipping Integrator Layout $($UpdateLayout.Name)" -ForegroundColor Yellow
                    continue
                }
            }

            Write-Host "Starting $($UpdateLayout.Name)" -ForegroundColor Green

            # Grab the fields for the layout
            Write-Host "Fetching Flexible Asset Fields from IT Glue"
            $FlexLayoutFieldsSelect = { (Get-ITGlueFlexibleAssetFields -page_size 1000 -page_number $i -flexible_asset_type_id $UpdateLayout.ITGID).data }
            $FlexLayoutFields = Import-ITGlueItems -ItemSelect $FlexLayoutFieldsSelect

				
            $LayoutCacheKey = [string]$UpdateLayout.ITGID
            if ($FlexAssetsByLayoutId.ContainsKey($LayoutCacheKey)) {
                $FlexAssets = @($FlexAssetsByLayoutId[$LayoutCacheKey])
            } else {
                # Grab all the Assets for the layout
                Write-Host "Fetching Flexible Assets from IT Glue (This may take a while)"
                $FlexAssetsSelect = { (Get-ITGlueFlexibleAssets -page_size 1000 -page_number $i -filter_flexible_asset_type_id $UpdateLayout.ITGID -include related_items).data }
                $FlexAssets = Import-ITGlueItems -ItemSelect $FlexAssetsSelect

                if ($ScopedMigration) {
                    $FlexAssets = @($FlexAssets | Where-Object {
                        $ScopedCompanyIds -contains $_.attributes.'organization-id'
                    })
                }

                $FlexAssetsByLayoutId[$LayoutCacheKey] = @($FlexAssets)
            }

            if (@($FlexAssets).Count -eq 0) {
                Write-Host "Skipping layout '$($UpdateLayout.Name)' because it has no assets in scope." -ForegroundColor Yellow
                $UpdateLayout.ITGAssets = @()
                continue
            }
            $fullyPopulated = if ($FlexLayoutFields -and $FlexLayoutFields.count -gt 1 -and $FlexAssets -and $FlexAssets.count -gt 1) {Get-ITGFieldPopulated -FlexLayoutFields $FlexLayoutFields -FlexAssets $FlexAssets} else {@{}}

            $UpdateLayoutFields = foreach ($ITGField in $FlexLayoutFields) {
                $ITGFieldRequired = [bool]$ITGField.Attributes.required
                if ($ITGField.attributes.kind -eq "Tag"){
                    $requiredForHudu = $false
                } else {
                    $requiredForHudu = $ITGFieldRequired -and ($($fullyPopulated[$ITGField.Attributes.name] ?? $false) -eq $true)
                }
                $LayoutField = @{
                    label        = $ITGField.Attributes.name
                    show_in_list = $ITGField.Attributes."show-in-list"
                    position     = $ITGField.Attributes.order
                    required     = $requiredForHudu
                    hint         = $ITGField.Attributes.hint
                }

                $supported = $true
		
                switch ($ITGField.Attributes.kind) {
                    "Checkbox" {
                        $LayoutField.add("field_type", "CheckBox")
                    }
                    "Date" {
                        $LayoutField.add("field_type", "Date")
                        $LayoutField.add("expiration", $($ITGField.Attributes.expiration))
                    }
                    "Header" {
                        $LayoutField.add("field_type", "Heading")
                    }
                    "Number" {
                        $LayoutField.add("field_type", "Number")
                    }
                    "Select" {
                        $ListName = "$($UpdateLayout.HuduObject.Name)-$($ITGField.Attributes.name)"
                        $ListItems = Get-NormalizedDropdownOptions -OptionsRaw "$($ITGField.Attributes.'default-value')"
                        $fieldKey = $ITGField.Attributes.'name-key'
                        # if there are other values than the list items ITG advertises, collect those for listselect as well.
                        if ($null -ne $FlexAssets -and $FlexAssets.count -gt 0) {
                            $ListItems = @(
                                $ListItems
                                Get-ITGFieldUniqueValues -FlexAssets $FlexAssets -FieldKey $fieldKey
                            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object { $_.ToLowerInvariant().Trim() } -Unique                                                    
                        }
                        $ListObject = $($(Get-HuduLists -name $ListName | Select-Object -First 1) ?? $(New-HuduList -Items $ListItems -Name "$(Get-UniqueListName -BaseName $ListName -allowReuse $false)"))
                        $LayoutField.add("list_id", $ListObject.Id)
                        $LayoutField.add("field_type", "ListSelect")
                    }
                    "Text" {
                        $LayoutField.add("field_type", "Text")
                    }
                    "Textbox" {
                        $LayoutField.add("field_type", "RichText")
                    }
                    "Upload" {
                        Write-Host "Upload fields are handled by an external script. $($ITGField.Attributes.name) in $($UpdateLayout.name)! Add-HuduAttachmentsViaAPI.ps1 will run after main migration to accomdate this."
                        $supported = $false
                    }
                    "Tag" {
                        switch (($ITGField.Attributes."tag-type").split(":")[0]) {
                            "AccountsUsers" { Write-Host "Tags to Account Users are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!" ; $supported = $false }
                            "Checklists" { 
                                Write-Host "Tags to Checklists are computed later, if migrating checklists is enabled."; $supported = $false 
                            }
                            "ChecklistTemplates" { Write-Host "Tags to Checklists Templates are computed later, if migrating checklists is enabled"; $supported = $false }
                            "Contacts" {
                                $ContactLayout = Get-HuduAssetLayouts -name $ConImportAssetLayoutName
                                $supported = Add-HuduAssetTagLayoutField -LayoutField $LayoutField -LinkableLayout $ContactLayout -FieldName $ITGField.Attributes.name -LayoutName $UpdateLayout.name
                            }
                            "Configurations" {
                                $ConfigLayout = Get-HuduAssetLayouts -name $ConfigImportAssetLayoutName
                                $supported = Add-HuduAssetTagLayoutField -LayoutField $LayoutField -LinkableLayout $ConfigLayout -FieldName $ITGField.Attributes.name -LayoutName $UpdateLayout.name
                            }
                            "Documents" { Write-Host "Tags to Documents are computed later, if migrating documents is enabled"; $supported = $false } 
                            "Domains" { Write-Host "Tags to websites are computed later, if migrating websites is enabled"; $supported = $false }
                            "Passwords" { Write-Host "Tags to Passwords are computed later, if migrating passwords is enabled"; $supported = $false }
                            "Locations" {
                                $LocationLayout = Get-HuduAssetLayouts -name $LocImportAssetLayoutName
                                $supported = Add-HuduAssetTagLayoutField -LayoutField $LayoutField -LinkableLayout $LocationLayout -FieldName $ITGField.Attributes.name -LayoutName $UpdateLayout.name
                            }
                            "Organizations" { Write-Host "Tags to Companies are computed later."; $supported = $false }
                            "SslCertificates" { Write-Host "Tags to SSL Certificates are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Tickets" { Write-Host "Tags to Tickets are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "FlexibleAssetType" {	
                                $MatchedLayoutID = ($MatchedLayouts | Where-Object { $_.ITGID -eq ($ITGField.Attributes."tag-type").split(" ")[1] }).HuduID
                                $supported = Add-HuduAssetTagLayoutField -LayoutField $LayoutField -LinkableLayout ([pscustomobject]@{ ID = $MatchedLayoutID }) -FieldName $ITGField.Attributes.name -LayoutName $UpdateLayout.name
                            }
                        }
                    }
                    "Percent" {
                        $LayoutField.add("field_type", "Number")
                    }
                    "Password" {
                        $LayoutField.add("field_type", "Password")
                    }
                }


                #Populate Global Field List
                if ($ITGField.Attributes.kind -eq "Tag") {
                    $SubKind = ($ITGField.Attributes."tag-type").split(":")[0]
                } else {
                    $SubKind = ""
                }

                $FieldDetails = [PSCustomObject]@{
                    LayoutName      = $UpdateLayout.Name
                    FieldName       = $ITGField.Attributes.name
                    FieldType       = $ITGField.Attributes.kind
                    FieldSubType    = $SubKind
                    HuduLayoutID    = $UpdateLayout.HuduID
                    IGLayoutID      = $UpdateLayout.ITGID
                    ITGParsedName   = $ITGField.Attributes."name-key"
                    HuduParsedName  = ($ITGField.Attributes.name -replace " ", "_").ToLower()
                    Supported       = $supported
                    HuduLayoutField = $LayoutField
                }
                $null = $AllFields.add($FieldDetails)


                if ($supported -eq $true) {
                    $LayoutField
                }

            }

            $null = Set-HuduAssetLayout -id $UpdateLayout.HuduID  -name $UpdateLayout.HuduObject.Name -icon $UpdateLayout.HuduObject.icon -color $UpdateLayout.HuduObject.color -icon_color $UpdateLayout.HuduObject.icon_color -include_passwords $true -include_photos $true -include_comments $true -include_files $true -fields @($UpdateLayoutFields)
            $UpdatedLayout = Get-HuduAssetLayouts -layoutid $UpdateLayout.HuduID
            Write-Host "Finished $($UpdateLayout.HuduObject.Name)"
            $UpdateLayout.HuduObject = $UpdatedLayout
            $UpdateLayout.ITGAssets = $FlexAssets
            $UpdateLayout.Matched = $true
        }
    }

    $AllFields | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\AssetLayoutsFields.json"
    $MatchedLayouts | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\AssetLayouts.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Layouts Migrated Continue?"  -DefaultResponse "continue to Flexible Assets, please."

}

############################### Flexible Assets ###############################
#Check for Assets Resume
$UploadFieldsArePresent = $false
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Assets.json")) {
    Write-Host "Loading Previous Asset Migration"
    $MatchedAssets = Get-Content "$MigrationLogs\Assets.json" -raw | Out-String | ConvertFrom-Json -depth 100
    $MatchedAssetPasswords = Get-Content "$MigrationLogs\AssetPasswords.json" -raw | Out-String | ConvertFrom-Json -depth 100
    $RelationsToCreate = [System.Collections.ArrayList](Get-Content "$MigrationLogs\RelationsToCreate.json" -raw | Out-String | ConvertFrom-Json -depth 100)
    $ManualActions = [System.Collections.ArrayList](Get-Content "$MigrationLogs\ManualActions.json" -raw | Out-String | ConvertFrom-Json -depth 100)
} else {
    $null = Start-MigrationJob -Name "Assets"

    # Load raw passwords for embedded fields and future use
    $ITGPasswordsRaw = Import-CSV -Path "$ITGLueExportPath\passwords.csv"
    
    if ($ImportFlexibleAssets -eq $true) {
        $RelationsToCreate = [System.Collections.ArrayList]@()
        $MatchedAssets = [System.Collections.ArrayList]@()
        $MatchedAssetPasswords = [System.Collections.ArrayList]@()

        #We need to do a first pass creating empty assets with just the ITG migrated data. This builds an array we need to use to lookup relations when populating the entire assets
        
        #limit scope for matched layouts.
        if ($ScopedMigration) {
            $OriginalLayoutsCount = $($MatchedLayouts.count)
            Write-Host "Setting layouts to those in scope..." -foregroundcolor Yellow               
            $MatchedLayouts = Filter-ScopedAssets -Layouts $MatchedLayouts -ScopedCompanyIds $ScopedCompanyIds
            Write-Host "Layouts scoped... $OriginalLayoutsCount => $($MatchedLayouts.count)"
        }

        Foreach ($Layout in $MatchedLayouts) {
            if ([string]::IsNullOrWhiteSpace([string]$Layout.HuduID) -or @($Layout.ITGAssets).Count -eq 0) {
                Write-Host "Skipping base asset creation for $($Layout.Name) because the layout was not created or has no assets in scope." -ForegroundColor Yellow
                continue
            }

            Write-Host "Creating base assets for $($layout.name)"
            foreach ($ITGAsset in $Layout.ITGAssets) {
                # Match Company
                $HuduCompanyID = ($MatchedCompanies | Where-Object { $_.ITGID -eq $ITGAsset.attributes.'organization-id' }).HuduID

                $AssetFields = @{ 
                    'Imported From ITGlue' = Get-Date -Format "o"
                    'ITGlue URL' = $ITGAsset.attributes.'resource-url'
                    'ITGlue ID' = $ITGAsset.id
                    'ITG Date Created' = $(Get-CoercedDate $ITGAsset.attributes.'created-at')
                    'ITG Date Last Updated' = $(Get-CoercedDate $ITGAsset.attributes.'updated-at')                    
                }
			
                $NewHuduAsset = (New-HuduAsset -name $ITGAsset.attributes.name -company_id $HuduCompanyID -asset_layout_id $Layout.HuduObject.id -fields $AssetFields).asset

                $AssetDetails = [PSCustomObject]@{
                    "Name"       = $ITGAsset.attributes.name
                    "ITGID"      = $ITGAsset.id
                    "HuduID"     = $NewHuduAsset.Id
                    "Matched"    = $false
                    "HuduObject" = $NewHuduAsset
                    "ITGObject"  = $ITGAsset
                    "Imported"   = "First Pass"
                }
                $null = $MatchedAssets.add($AssetDetails)
            }
        }
	
	
        #We now need to loop through all Assets again updating the assets to their final version
        
        # foreach ($UpdateAsset in $MatchedAssets | where-object {$_.ITGObject.attributes.archived -ne $true}) {
        foreach ($UpdateAsset in $MatchedAssets) {
            Write-Host "Populating $($UpdateAsset.Name)"
		
            $AssetFields = @{ 
                'Imported From ITGlue' = Get-Date -Format "o"
            }

            $traits = $UpdateAsset.ITGObject.attributes.traits
            $traits.PSObject.Properties | ForEach-Object {
                # Find the corresponding field we are working on
                $ITGParsed = $_.name
                $ITGValues = $_.value
                $field = $AllFields | Where-Object { $_.IGLayoutID -eq $UpdateAsset.ITGObject.attributes.'flexible-asset-type-id' -and $_.ITGParsedName -eq $ITGParsed }
                if ($field) {
                    $supported = $true
                    if ($field.FieldType -eq "Date") {
                        $raw = ($ITGValues.values ?? $ITGValues) -as [string]
                        $ReturnData = Get-CoercedDate -InputDate $raw -Cutoff '1000-01-01' -OutputFormat 'MM/DD/YYYY'
                        if (-not $ReturnData) {
                            if ($field.HuduLayoutField.required) {
                                $ReturnData = (Get-Date).ToString('MM/dd/yyyy', [CultureInfo]::InvariantCulture)
                            } else {
                                continue
                            }
                        }
                        $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))
                    } elseif ($field.FieldType -eq "Tag") {
                        switch ($field.FieldSubType) {
                            "Checklists" {
                                $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) { @{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'Procedure'; itg_to_id = $IDMatch.id}} ;Write-Host "Tags to Procedure from $($field.FieldName) in $($UpdateAsset.Name) has been recorded for later.";
                                $supported = $true
                            } "ChecklistTemplates" { 
                                $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) { @{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'Procedure'; itg_to_id = $IDMatch.id}} ;Write-Host "Tags to Procedure Template from $($field.FieldName) in $($UpdateAsset.Name) has been recorded for later.";
                                $supported = $true
                            } "Contacts" {
                                $ContactsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $MatchedContacts | Where-Object { $_.ITGID -eq $IDMatch.id }
                                }
                                $null = Add-HuduAssetTagFieldValue -AssetFields $AssetFields -Field $field -LinkedItems $ContactsLinked -AssetName $UpdateAsset.Name
                            } "Configurations" {
                                $ConfigsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $MatchedConfigurations | Where-Object { $_.ITGID -eq $IDMatch.id }
                                }
                                $null = Add-HuduAssetTagFieldValue -AssetFields $AssetFields -Field $field -LinkedItems $ConfigsLinked -AssetName $UpdateAsset.Name
											
                            } "Documents" { $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) { @{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'Article'; itg_to_id = $IDMatch.id}} ;Write-Host "Tags to Articles $($field.FieldName) in $($UpdateAsset.Name) has been recorded for later."; $supported = $true
                            } "Domains" {
                                if ($true -ne $ImportDomains) {
                                    Write-Host "Skipping website/domain tags for $($field.FieldName) in $($UpdateAsset.Name) because website migration is disabled." -ForegroundColor Yellow
                                    $supported = $false
                                } else {
                                    $DomainsLinked = foreach ($IDMatch in $ITGValues.values) {
                                        $MatchedWebsites | Where-Object { $_.ITGID -eq $IDMatch.id -and -not [string]::IsNullOrWhiteSpace([string]$_.HuduID) }
                                    }
                                    $DomainsLinked | ForEach-Object {
                                        if ($WebsiteRelation = New-HuduRelation -FromableType 'Asset' -ToableType 'Website' -FromableID $UpdateAsset.HuduID -ToableID $_.HuduID) {
                                            Write-Host "Successully Created relation to $($WebsiteRelation.relation.name)"
                                        } else {
                                            Write-Host "Tags to Websites are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false
                                    }}
                                }
                            } "Passwords" { 
                                $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) { @{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'AssetPassword'; itg_to_id = $IDMatch.id}}; Write-Host "Tags to Password $($field.FieldName) in $($UpdateAsset.Name) has been recorded for later."; $supported = $true 
                            } "Locations" {
                                $LocationsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $MatchedLocations | Where-Object { $_.ITGID -eq $IDMatch.id }
                                }
                                $null = Add-HuduAssetTagFieldValue -AssetFields $AssetFields -Field $field -LinkedItems $LocationsLinked -AssetName $UpdateAsset.Name
                            } "Organizations" { 
                                $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) {@{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'Company'; itg_to_id = $IDMatch.id}}; Write-Host "Tags to Companies $($field.FieldName) in $($UpdateAsset.Name) has been recorded later."; $supported = $true
                            } "FlexibleAssetType" {	
                                $AssetsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $MatchedAssets | Where-Object { $_.ITGID -eq $IDMatch.id }
                                }
                                $null = Add-HuduAssetTagFieldValue -AssetFields $AssetFields -Field $field -LinkedItems $AssetsLinked -AssetName $UpdateAsset.Name
                            } "SslCertificates" { 
                                Write-Host "Tags to SSL Certificates are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false;
                            } "Tickets" {
                                Write-Host "Tags to Tickets are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false;
                            } "AccountsUsers" {
                                Write-Host "Tags to Account Users are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false 
                            }
                        }
                        # the only untaggable entities that are left now are entities that we are not creating or cannot create, so there isnt really a manual action to be taken
                        # if ($Supported -eq $False) {
                        #     $ManualLog = [PSCustomObject]@{
                        #         Document_Name = $UpdateAsset.Name
                        #         Type          = ($UpdateAsset.HuduObject.asset_type ?? "Asset") + " Field - Tag"
                        #         Company_Name  = $UpdateAsset.HuduObject.company_name
                        #         HuduID        = $UpdateAsset.HuduID
                        #         Field_Name    = $($field.FieldName)
                        #         Notes         = "Unsupported Tag Type Manual Tag Required"
                        #         Action        = "Manually tag to Asset"
                        #         Data          = $ITGValues.values.name -join ","
                        #         Hudu_URL      = $UpdateAsset.HuduObject.url
                        #         ITG_URL       = $UpdateAsset.ITGObject.attributes."resource-url"
                        #     }; $null = $ManualActions.add($ManualLog);
                        # }
                    } elseif ($field.FieldType -eq "Password") {
                        $PasswordIds = @(
                            $ITGValues
                            $ITGValues.values
                        ) | ForEach-Object {
                            if ($null -ne $_) {
                                $candidate = if ($_.PSObject.Properties['id']) {
                                    $_.id
                                } elseif ($_.PSObject.Properties['resource-id']) {
                                    $_.'resource-id'
                                } elseif ($_.PSObject.Properties['resource_id']) {
                                    $_.'resource_id'
                                } elseif ($_ -is [string] -or $_.GetType().IsValueType) {
                                    $_
                                } else {
                                    $null
                                }

                                if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) {
                                    [string]$candidate
                                }
                            }
                        } | Select-Object -Unique

                        $PasswordFieldWasSet = $false
                        foreach ($PasswordId in $PasswordIds) {
                            $ITGPassword = $null
                            $ITGPasswordValue = $null
                            $MigratedPasswordStatus = "Skipped"

                            try {
                                $ITGPassword = (Get-ITGluePasswords -id $PasswordId -include related_items).data
                                $ITGPasswordValue = ($ITGPasswordsRaw | Where-Object { $_.id -eq $ITGPassword.id } | Select-Object -First 1).password

                                if ($ITGPasswordValue) {
                                    $NewPasswordObject = [pscustomobject]@{
                                        Name        = "$($UpdateAsset.name) $($Field.fieldname) $($ITGPassword.Username) Password"
                                        Username    = $ITGPassword.Username
                                        URL         = $ITGPassword.url
                                        ITGID       = $ITGPassword.id
                                        Description = $ITGpassword.notes
                                        CompanyId   = $UpdateAsset.HuduObject.company_id
                                        Password    = $ITGPasswordValue
                                    }

                                    if (-not $PasswordFieldWasSet) {
                                        $null = $AssetFields.add("$($field.HuduParsedName)", $ITGPasswordValue)
                                        $PasswordFieldWasSet = $true
                                        $MigratedPasswordStatus = "Into Asset"
                                    } else {
                                        $ManualLog = [PSCustomObject]@{
                                            Document_Name = $UpdateAsset.Name
                                            Type          = "Asset Field - Password"
                                            Company_Name  = $UpdateAsset.HuduObject.company_name
                                            HuduID        = $UpdateAsset.HuduID
                                            Field_Name    = "$($field.HuduParsedName)"
                                            Notes         = "Multiple embedded IT Glue passwords were found for one Hudu password field. The first value was added to the asset field."
                                            Action        = "Manually review whether this additional password should be migrated elsewhere"
                                            Data          = ($ITGPassword.attributes.'resource-url' -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')
                                            Hudu_URL      = $UpdateAsset.HuduObject.url
                                            ITG_URL       = $UpdateAsset.ITGObject.attributes.'resource-url'
                                        }; $null = $ManualActions.add($ManualLog)
                                        $MigratedPasswordStatus = "Manual Review - Additional Embedded Password"
                                    }
                                }
                            } catch {
                                Write-Host "Error occured adding field, possible duplicate name" -ForegroundColor Red
                                $ManualLog = [PSCustomObject]@{
                                    Document_Name = $UpdateAsset.Name
                                    Type          = "Asset Field - Password"
                                    Company_Name  = $UpdateAsset.HuduObject.company_name
                                    HuduID        = $UpdateAsset.HuduID
                                    Field_Name    = "$($field.HuduParsedName)"
                                    Notes         = "Failed to add password to Asset with error $_"
                                    Action        = "Manually add the password to the asset"
                                    Data          = ($ITGPassword.attributes.'resource-url' -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')
                                    Hudu_URL      = $UpdateAsset.HuduObject.url
                                    ITG_URL       = $UpdateAsset.ITGObject.attributes.'resource-url'
                                }; $null = $ManualActions.add($ManualLog); $MigratedPasswordStatus = "Failed to add";
                            }

                            if ($ITGPassword) {
                                $MigratedPassword = [PSCustomObject]@{
                                    "Name"      = $ITGPassword.attributes.name
                                    "ITGID"     = $ITGPassword.id
                                    "HuduID"    = $UpdateAsset.HuduID
                                    "Matched"   = $true
                                    "ITGObject" = $ITGPassword
                                    "Imported"  = $MigratedPasswordStatus
                                }
                                $null = $MatchedAssetPasswords.add($MigratedPassword)
                            }
                        }
                    } elseif ($field.FieldType -eq "Number") {
                        # This version won't cast doubles for 'number' fields. It expects only integers.
                        $coerced = Get-CastIfNumeric ($_.value -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')
                        $null = $AssetFields.add("$($field.HuduParsedName)", [string]"$coerced")
                    } elseif ($field.FieldType -ieq "Upload") {
                        $UploadFieldsArePresent = $true
                        continue
                    } else {
                        $null = $AssetFields.add("$($field.HuduParsedName)", [string]"$($_.value)")
                    }
                } else {
                    Write-Host "Warning $ITGParsed : $ITGValues Could not be added" -ForegroundColor Red
                }
            }
            $CleanedAssetFields = @()

            foreach ($entry in $AssetFields.GetEnumerator()) {
                $fieldName = ($entry.Key -replace '_', ' ').Trim()
                $value = $entry.Value

                if ([string]::IsNullOrWhiteSpace($fieldName)) { continue }
                if ($null -eq $value) { continue }
                if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { continue }
                if ($value -is [array] -and $value.Count -eq 0) { continue }
                if ($value -is [string] -and $value.Trim() -in @('[]', '[,,]', '[,]', 'null')) { continue }

                $CleanedAssetFields += @{ $fieldName = $value }
            }
            $UpdatedHuduAsset = (Set-HuduAsset -asset_id $UpdateAsset.HuduID -name $UpdateAsset.name -company_id $($UpdateAsset.HuduObject.company_id) -asset_layout_id $UpdateAsset.HuduObject.asset_layout_id -fields $CleanedAssetFields).asset

            $UpdateAsset.HuduObject = $UpdatedHuduAsset
            $UpdateAsset.Imported = "Created-By-Script"
        }
        if ($true -eq $UploadFieldsArePresent){
            Write-Host "One or more Upload fields were present on the assets, they will be processed during wrap-up" -ForegroundColor Yellow
        }


        $MatchedAssets | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Assets.json"
        $MatchedAssetPasswords | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\AssetPasswords.json"
        $ManualActions | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\ManualActions.json"
        $RelationsToCreate | ConvertTo-Json -Depth 20 | Out-File "$MigrationLogs\RelationsToCreate.json"
        Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Assets Migrated Continue?" -DefaultResponse "continue to Documents/Articles, please."
    }
}


############################### Documents / Articles ###############################

#Check for Article Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\ArticleBase.json")) {
    Write-Host "Loading Article Migration"
    $MatchedArticles = Get-Content "$MigrationLogs\ArticleBase.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {
    $null = Start-MigrationJob -Name "Articles"

    if ($ImportArticles -eq $true) {

        if (-not $PlaceInternalDocsInInternalCompany -and $GlobalKBFolder -in ('y','yes','ye')) {
            if (-not ($GlobalKBFolder = Get-HuduFolders -name $InternalCompany)) {
                $GlobalKBFolder = (New-HuduFolder -Name $InternalCompany).folder
            }
        } 
	else {
 	 $GlobalKBFolder = $null
   	}


    $ITGDocuments = Import-CSV -Path (Join-Path -path $ITGLueExportPath -ChildPath "documents.csv")
    [string]$ITGDocumentsPath = Join-Path -path $ITGLueExportPath -ChildPath "Documents"

    $files = Get-ChildItem -Path $ITGDocumentsPath -recurse
    $MatchedArticles = foreach ($doc in $ITGDocuments) {
        $article = Start-ArticleStubs `
            -Document $doc -Files $files `
            -ITGDocumentsPath $ITGDocumentsPath -MatchedCompanies $MatchedCompanies `
            -GlobalKBFolder $GlobalKBFolder `
            -IncludeIgnoredFirstArticleDirectory:$($IncludeIgnoredFirstArticleDirectory ?? $false) `
            -PlaceInternalDocsInInternalCompany:$($PlaceInternalDocsInInternalCompany ?? $false)

        if ($article) { $article }
    }

    
    $MatchedArticles | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\ArticleBase.json"
    $ManualActions | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\ManualActions.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Stub Articles Created Continue?"  -DefaultResponse "continue to Document/Article Bodies, please."
    }

}

############################### Documents / Articles Bodies ###############################

#Check for Articles Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Articles.json")) {
    Write-Host "Loading Article Content Migration"
    $MatchedArticles = Get-Content "$MigrationLogs\Articles.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {
	
    if ($ImportArticles -eq $true) {
        $null = Start-MigrationJob -Name "ArticleContents"

        $Attachfiles = Get-ChildItem (Join-Path -Path $ITGLueExportPath -ChildPath "attachments\documents") -recurse
        $ImageMap = $ImageMap ?? @{}
        # Now do the actual work of populating the content of articles
        $ArticleErrors = foreach ($Article in $MatchedArticles) {

            $page_out = ''
            $imagePath = $null
	    
            # Check for attachments
            $attachdir = $Attachfiles | Where-Object { $_.PSIsContainer -eq $true -and $_.Name -match $Article.ITGID }
            if ($Attachdir) {
                $InFile = ''
                $html = ''
                $rawsource = ''
            }


            Write-Host "Starting $($Article.Name) in $($Article.Company.CompanyName)" -ForegroundColor Green
				
            $InFile = $Article.FullPath
				
            $html = New-Object -ComObject "HTMLFile"
            $rawsource = Get-Content -encoding UTF8 -LiteralPath $InFile -Raw
            if ($rawsource.Length -gt 0) {
                $source = [regex]::replace($rawsource , '\xa0+', ' ')
                $src = [System.Text.Encoding]::Unicode.GetBytes($source)
                $html.write($src)
                $images = @($html.Images)

                foreach ($imageObject in $images) {                    
                    if (($imageObject.src -notmatch '^http[s]?://') -or ($imageObject.src -match [regex]::Escape($ITGURL))) {
                        $script:HasImages = $true
                        $imgHTML = $imageObject.outerHTML
                        Write-Host "Processing HTML: $imgHTML"
                        if ($imageObject.src -match [regex]::Escape($ITGURL)) {
                            $matchedImage = Update-StringWithCaptureGroups -inputString $imgHTML -type 'img' -pattern $ImgRegexPatternToMatch
                            if ($matchedImage) {
                                $tnImgUrl = $matchedImage.url
                                $tnImgPath = $matchedImage.path
                            } else {
                                $tnImgPath = $imageObject.src
                            }
                        }
                        else {
                            $basepath = Split-Path $InFile
                            
                            if ($fullImgUrl = $imgHTML.split('data-src-original="')[1]) {$fullImgUrl = $fullImgUrl.split('"')[0] }
                            $tnImgUrl = $imgHTML.split('src="')[1].split('"')[0]
                            if ($fullImgUrl) {$fullImgPath = Join-Path -Path $basepath -ChildPath $fullImgUrl.replace('/','\')}
                            $tnImgPath = Join-Path -Path $basepath -ChildPath $tnImgUrl.replace('/','\')
                        }
                        
                        Write-Host "Processing IMG: $tnImgPath"
                        
                        # Some logic to test for the original data source being specified vs the thumbnail. Grab the Thumbnail or final source.
                        if ($fullImgUrl -and ($foundFile = Get-Item -Path "$fullImgPath*" -ErrorAction SilentlyContinue)) {
                            $imagePath = $foundFile.FullName
                        } elseif ($tnImgUrl -and ($foundFile = Get-Item -Path "$tnImgPath*" -ErrorAction SilentlyContinue)) {
                            $imagePath = $foundFile.FullName
                        } else { 
                            Remove-Variable -Name imagePath -ErrorAction SilentlyContinue
                            Remove-Variable -Name foundFile -ErrorAction SilentlyContinue
                            Write-Warning "Unable to validate image file."
                            $ManualLog = [PSCustomObject]@{
                                    Document_Name = $Article.Name
                                    Company_Name  = $Article.Company.CompanyName
                                    HuduID        = $Article.HuduID
                                    Type          = "Article - Image"
                                    Field_Name    = "Image"
                                    Notes         = 'Missing image, file not found'
                                    Action        = "Neither $fullImgPath or $tnImgPath were found, validate the images exist in the export, or retrieve them from ITGlue directly"
                                    Data          = "$InFile"
                                    Hudu_URL      = $Article.HuduObject.url
                                    ITG_URL       = "$ITGURL/$($Article.ITGLocator)"
                            }
                            $null = $ManualActions.add($ManualLog)
                            continue
                    }
                    # Test the path to ensure that a file extension exists, if no file extension we get problems later on. We rename it if there's no ext.
                    if ($imagePath -and (Test-Path $imagePath -ErrorAction SilentlyContinue)) {
                        write-verbose "File present at purported image path: $imagePath... checking for image..."

                            $imageType = Invoke-ImageTest $imagePath
                            if ($imageType) {
                                write-verbose "$imagePath appears to contain image... normalizing..."
                                $imageInfo = Normalize-And-ConvertImage -InputPath $imagePath
                                write-verbose "$imagePath => $($imageInfo.FinalPath)"

                                $imagePath = $imageInfo.FinalPath ?? $imagePath
                                $OriginalFullImagePath = $imageInfo.Original

                                write-verbose "Uploading new/copied ITGlue image $OriginalFullImagePath => $imagePath"
                                try {
                                    $UploadImage = New-HuduPublicPhoto -FilePath $imagePath.ToLower() -record_id $Article.HuduID -record_type 'Article'
                                    $ImageMap["$OriginalFullImagePath"] = "$($UploadImage.public_photo.url)"
                                } catch {
                    # issue during Upload
                                    $ManualLog = [PSCustomObject]@{
                                        Document_Name = $Article.Name
                                        Type          = "Article - Image"
                                        Company_Name  = $Article.Company.CompanyName
                                        HuduID        = $Article.HuduID
                                        Field_Name    = "Image"
                                        Action        = "Failed to upload image to Hudu, manually upload and update the article with the new image URL"
                                        Notes         = 'Failed to upload image to Hudu'
                                        Data          = $_
                                        Hudu_URL      = $Article.HuduObject.url
				                        ITG_URL       = "$ITGURL/$($Article.ITGLocator)"
                                    }
                                    Write-ErrorObjectsToFile -ErrorObject $ManualLog -name "image-upload-err-$($imageInfo.basename)"
                                    $null = $ManualActions.add($ManualLog)
                                    continue
                                }
                                try {                                    
                                    $NewImageURL = $UploadImage.public_photo.url.replace($HuduBaseDomain, '')

                                    # Update the <img> tag src
                                    $imageObject.src = [string]$NewImageURL
                                    Write-Host "Setting <img>.src to: $NewImageURL"

                                    # Try to find a matching <a> link around the image
                                    $ImgLink = ($html.Links | Where-Object { $imageObject.innerHTML -eq $imgHTML }) | Select-Object -First 1
                                    
                                    if ($ImgLink) {
                                        if ($ImgLink.PSObject.Properties.Match("href")) {
                                            $ImgLink.href = [string]$NewImageURL
                                        } else {
                                            Write-Host "Image link object found but 'href' property is not present on it"
                                        }
                                    } else {
                                        write-verbose "Image link object was not found for innerHTML: $imgHTML"
                                    }
                                } catch {
                    # issue during HTML replace / parse
                                    $ManualLog = [PSCustomObject]@{
                                        Document_Name = $Article.Name
                                        Type          = "Article - Image"
                                        Company_Name  = $Article.Company.CompanyName
                                        HuduID        = $Article.HuduID
                                        Field_Name    = "Image"
                                        Notes         = "Issue encountered during HTML image replacement."
                                        Action        = "Manually update the article with the new image URL"
                                        Data          = "New image URL: $NewImageURL; Error: $_"
                                        Hudu_URL      = $Article.HuduObject.url
				                        ITG_URL       = "$ITGURL/$($Article.ITGLocator)"
                                    }
                                    Write-ErrorObjectsToFile -ErrorObject $ManualLog -name "image-err-$($imageInfo.basename)"
                                    $null = $ManualActions.add($ManualLog)
                                }
                            } else {
                    # image not detected by imagemagick
                                $ManualLog = [PSCustomObject]@{
                                    Document_Name = $Article.Name
                                    Company_Name  = $Article.Company.CompanyName
                                    HuduID        = $Article.HuduID
                                    Type          = "Article - Image"
                                    Field_Name    = "Image"
                                    Notes         = 'Image Not Detected'
                                    Action        = "$imagePath not detected as image, validate the identified file is an image, or imagemagick modules are loaded"        
                                    Data          = "$InFile"
                                    Hudu_URL      = $Article.HuduObject.url
				                    ITG_URL       = "$ITGURL/$($Article.ITGLocator)"
                                }
                                Write-ErrorObjectsToFile -ErrorObject $ManualLog -name "image-nd-$($imagePath)"
                                $null = $ManualActions.add($ManualLog)

                            }
                        }
                    }
                }
            
                $page_Source = $html.documentelement.outerhtml
                $page_out = [regex]::replace($page_Source , '\xa0+', ' ')
                        
            }
        
            if ($page_out -eq '') {
                $page_out = 'Empty Document in IT Glue Export - Please Check IT Glue'
            }
			
				
            $articleUsesGlobalKB = if ($null -ne $Article.PSObject.Properties['IsGlobalKBArticle']) {
                [bool]$Article.IsGlobalKBArticle
            } else {
                [bool]($Article.company.InternalCompany -and -not $PlaceInternalDocsInInternalCompany)
            }

            if (-not $articleUsesGlobalKB) {
                $ArticleSplat = @{
                    article_id = $Article.HuduID
                    name       = $Article.name
                    content    = $page_out
                    company_id = $Article.company.HuduID                   
                }	
            } else {
                $ArticleSplat = @{
                    article_id = $Article.HuduID
                    name       = $Article.name
                    content    = $page_out
                }	
            }
				
            $null = Set-HuduArticle @ArticleSplat
            Write-Host "$($Article.name) completed" -ForegroundColor Green
		
            $Article.Imported = "Created-By-Script"
			
        } 

        $MatchedArticles | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Articles.json"
        $ArticleErrors | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\ArticleErrors.json"
        $ManualActions | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\ManualActions.json"
        Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Articles Created Continue?" -DefaultResponse "continue to Passwords, please."

    }

}



############################### Passwords ###############################


#Check for Passwords Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Passwords.json")) {
    Write-Host "Loading Previous Paswords Migration"
    $MatchedPasswords = Get-Content "$MigrationLogs\Passwords.json" -raw | Out-String | ConvertFrom-Json
} else {
    $null = Start-MigrationJob -Name "Passwords"

    #Import Passwords
    Write-Host "Fetching Passwords from IT Glue" -ForegroundColor Green
    $PasswordSelect = { (Get-ITGluePasswords -page_size 1000 -page_number $i).data }

    $ITGPasswords = Import-ITGlueItems -ItemSelect $PasswordSelect -MigrationName 'Passwords'

    if ($ScopedMigration) {
        $OriginalPasswordsCount = $($ITGPasswords.count)
        Write-Host "Setting passwords to those in scope..." -foregroundcolor Yellow        
        $ITGPasswords         = $ITGPasswords | Where-Object { $ScopedCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "Passwords scoped... $OriginalPasswordsCount => $($ITGPasswords.count)"
    }

    try {
        Write-Host "Loading Passwords from CSV for faster import" -foregroundcolor Cyan
        $ITGPasswordsRaw = Import-CSV -Path "$ITGLueExportPath\passwords.csv"
    }
	catch {
        $ITGPasswordsSingle = foreach ($ITGRawPass in $ITGPasswords) {
            $ITGPassword = (Get-ITGluePasswords -id $ITGRawPass.id -include related_items).data
            $ITGPassword
        }
        $ITGPasswords = $ITGPasswordsSingle
    }
    
    Write-Host "$($ITGPasswords.count) IT Glue Passwords Found"

    $PasswordsInCSV = [System.Collections.ArrayList]::new()
    $PasswordsNotInCSV = [System.Collections.ArrayList]::new()

    $IdOrganizationMap = @{}
    foreach ($row in $ITGPasswordsRaw) {
        $IdOrganizationMap[[string]$row.id] = @{
            'password' = $row.password
            'otp_secret' = $row.otp_secret
        }
    }

    foreach ($row in $ITGPasswords) {
        if ($IdOrganizationMap.ContainsKey([string]$row.id) -eq $true) {
            $row.attributes | Add-Member -MemberType 'NoteProperty' -Name 'password' -Value $IdOrganizationMap[[string]$row.id].password
            $row.attributes | Add-Member -MemberType 'NoteProperty' -Name 'otp_secret' -Value $IdOrganizationMap[[string]$row.id].otp_secret
            [void]$PasswordsInCSV.Add($row)
        } else {
            [void]$PasswordsNotInCSV.Add($row)
        }
    }

    $MatchedPasswords = New-Object 'System.Collections.ArrayList'
    foreach ($itgpassword in $PasswordsInCSV) {
        [void]$MatchedPasswords.Add(
            [PSCustomObject]@{
                "Name"       = $itgpassword.attributes.name
                "ITGID"      = $itgpassword.id
                "HuduID"     = ""
                "Matched"    = $false
                "HuduObject" = ""
                "ITGObject"  = $itgpassword
                "Imported"   = ""
            }
        )
    }
    foreach ($itgpassword in $PasswordsNotInCSV) {
        $FullPassword = (Get-ITGluePasswords -id $itgpassword.id -include related_items).data
        [void]$MatchedPasswords.Add(
            [PSCustomObject]@{
                "Name"       = $itgpassword.attributes.name
                "ITGID"      = $itgpassword.id
                "HuduID"     = ""
                "Matched"    = $false
                "HuduObject" = ""
                "ITGObject"  = $FullPassword
                "Imported"   = ""
            }
        )
    }

    Write-Host "Passwords to Migrate"
    $MatchedPasswords | Sort-Object Name |  Select-Object Name | Format-Table


    $UnmappedPasswordCount = ($MatchedPasswords | Where-Object { $_.Matched -eq $false } | measure-object).count

    if ($ImportPasswords -eq $true -and $UnmappedPasswordCount -gt 0) {

        $importOption = Get-ImportMode -ImportName "Passwords"

        if (($importOption -eq "A") -or ($importOption -eq "S") ) {		

            foreach ($company in $CompaniesToMigrate) {
                Write-Host "Migrating $($company.CompanyName)" -ForegroundColor Green

                foreach ($unmatchedPassword in ($MatchedPasswords | Where-Object { $_.Matched -eq $false -and $company.ITGCompanyObject.id -eq $_."ITGObject".attributes."organization-id" })) {

                    Confirm-Import -ImportObjectName "$($unmatchedPassword.Name)" -ImportObject $unmatchedPassword -ImportSetting $ImportOption

                    Write-Host "Starting $($unmatchedPassword.Name)"

                    $PasswordableType = 'Asset'
                    $ParentItemID = $null
		    
                    if ($($unmatchedPassword.ITGObject.attributes."resource-id")) {
						
                        if ($unmatchedPassword.ITGObject.attributes."resource-type" -eq "flexible-asset-traits") {
                            # Check if it has already migrated with Assets
                            $FoundItem = $MatchedAssetPasswords | Where-Object { $_.ITGID -eq $($unmatchedPassword.ITGID) }
                            if (!$FoundItem) {
                                Write-Host "Could not find password field on asset. ParentID: $($unmatchedPassword.ITGObject.attributes.`"resource-id`")"
                                $FoundItem = $MatchedAssets | Where-Object { $_.ITGID -eq $unmatchedPassword.ITGObject.attributes."resource-id" }
                                $ManualLog = [PSCustomObject]@{
                                    Document_Name = $FoundItem.name
                                    Field_Name    = $unmatchedPassword.ITGObject.attributes.name
                                    Type          = "Asset password field"
                                    Company_Name  = $unmatchedPassword.ITGObject."organization-name"
                                    HuduID        = $unmatchedPassword.HuduID
                                    Notes         = "Password from FA Field not found."
                                    Action        = "Manually create password"
                                    Data          = "Type: $($unmatchedPassword.ITGObject.attributes.`"resource-type`")"
                                    Hudu_URL      = $FoundItem.HuduObject.url ?? $unmatchedPassword.HuduObject.url ?? $company.HuduCompanyObject.url
                                    ITG_URL       = $unmatchedPassword.ITGObject.attributes."parent-url"
                                }
                                $null = $ManualActions.add($ManualLog)
                            } else {
                                Write-Host "Migrated with Asset: $($FoundItem.HuduID)"
                            }
                        } else {
                            # Check if it needs to link to websites
                            if ($($unmatchedPassword.ITGObject.attributes."resource-type") -eq "domains") {
                                $ParentItemID = ($MatchedWebsites | Where-Object { $_.ITGID -eq $($unmatchedPassword.ITGObject.attributes."resource-id") }).HuduID
                                if ($ParentItemID) {
                                    Write-Host "Matched to $ParentItemID" -ForegroundColor Green
                                } else {
                                    Write-Host "Could not find asset to Match. ParentID: $($unmatchedPassword.ITGObject.attributes.`"resource-id`")"
                                    $ManualLog = [PSCustomObject]@{
                                        Document_Name = $unmatchedPassword.ITGObject.attributes.name
                                        Field_Name    = "N/A"
                                        Type          = $unmatchedPassword.HuduObject.asset_type ?? "Domain Password"
                                        Company_Name  = $company.CompanyName
                                        HuduID        = $unmatchedPassword.HuduID
                                        Notes         = "Password could not be related to domain."
                                        Action        = "Manually relate password"
                                        Data          = "Type: $($unmatchedPassword.ITGObject.attributes.`"resource-type`")"
                                        Hudu_URL      = $unmatchedPassword.HuduObject.url ?? $company.HuduCompanyObject.url
                                        ITG_URL       = $unmatchedPassword.ITGObject.attributes."parent-url"
                                    }
                                    $null = $ManualActions.add($ManualLog)
                                }

                            } else {
                                # Deal with all others
                                $ParentItemID = (Find-MigratedItem -ITGID $($unmatchedPassword.ITGObject.attributes."resource-id")).HuduID
                                if ($ParentItemID) {
                                    Write-Host "Matched to $ParentItemID" -ForegroundColor Green
                                } else {
                                    Write-Host "inter-company password relation will be resolved later."
                                }
                            }
                        }
                    }
					
                    if (!($($unmatchedPassword.ITGObject.attributes."resource-type") -eq "flexible-asset-traits")) {

                        $validated_otp = "$($unmatchedPassword.ITGObject.attributes.otp_secret)".Trim().ToUpper()
                        if ($validated_otp) {
                            $isValidBase32 = $validated_otp -match '^[A-Z2-7]+$'
                            $lengthOK = $validated_otp.Length -ge 16 -and $validated_otp.Length -le 80

                            $validated_otp = if ($isValidBase32 -and $lengthOK) { $validated_otp } else { $null }

                            if (-not ($isValidBase32 -and $lengthOK)) {
                                Write-Warning "Invalid OTP secret for $($unmatchedPassword.ITGObject.attributes.name): $($unmatchedPassword.ITGObject.attributes.otp_secret)... valid base32? $isValidBase32 length ok? $lengthOK (min / max is 16 / 80 chars)"
                            }                            
                        }


                        $PasswordSplat = @{
                            name              = "$($unmatchedPassword.ITGObject.attributes.name)"
                            company_id        = $company.HuduCompanyObject.ID
                            description       = $unmatchedPassword.ITGObject.attributes.notes
                            passwordable_type = $PasswordableType
                            passwordable_id   = $ParentItemID
                            in_portal         = $false
                            password          = $unmatchedPassword.ITGObject.attributes.password
                            url               = if ($url = $unmatchedPassword.ITGObject.attributes.url) {$url} Else {$unmatchedPassword.ITGObject.attributes.'resource-url'}
                            username          = $unmatchedPassword.ITGObject.attributes.username
                            otpsecret         = $validated_otp

                        }
                        if ([string]::IsNullOrWhiteSpace($unmatchedPassword.ITGObject.attributes.password) -or $unmatchedPassword.ITGObject.attributes.password.Length -lt 1) {
                            if ($true -eq $($AllowEmptyPasswords ?? $true)) {
                                write-host "Password value is empty for $($unmatchedPassword.ITGObject.attributes.name), assuming it is vaulted. setting blank password with A256GCM encryption to preserve the record and metadata for replacing later." -ForegroundColor DarkCyan
                                $PasswordSplat.password = "A256GCM.WAS-BLANK-REPLACE-WITH-REAL-PASSWORD"
                            } else {
                                $manualActions.add([PSCustomObject]@{
                                    name              = "$($unmatchedPassword.ITGObject.attributes.name)"
                                    company_id        = $company.HuduCompanyObject.ID
                                    description       = $unmatchedPassword.ITGObject.attributes.notes
                                    passwordable_type = $PasswordableType
                                    passwordable_id   = $ParentItemID
                                    in_portal         = $false
                                    password          = ""
                                    Type              = "Password"
                                    Hudu_URL      	  = $unmatchedPassword.HuduObject.url
                                    ITG_URL           = if ($url = $unmatchedPassword.ITGObject.attributes.url) {$url} Else {$unmatchedPassword.ITGObject.attributes.'resource-url'}
                                    username          = $unmatchedPassword.ITGObject.attributes.username
                                    otpsecret         = "removed for security purposes"
                                    problem           = "password was null or empty"
                                })
                                $unmatchedPassword.matched = $false
                                Write-Warning "$($HuduNewPassword.Name) Has been skipped and added to manual actions due to being empty"
                                continue
                            }
                        }
                        $HuduNewPassword = (New-HuduPassword @PasswordSplat).asset_password 
                        $unmatchedPassword.matched = $true
                        $unmatchedPassword.HuduID = $HuduNewPassword.id
                        $unmatchedPassword."HuduObject" = $HuduNewPassword
                        $unmatchedPassword.Imported = "Created-By-Script"
                        $ImportsMigrated = $ImportsMigrated + 1
                        Write-host "$($HuduNewPassword.Name) Has been created in Hudu"
                        
                    }
                }
            }
        }


    } else {
        if ($UnmappedPasswordCount -eq 0) {
            Write-Host "All Passwords matched, no migration required" -foregroundcolor green
        } else {
            Write-Host "Warning Import passwords is set to disabled so the above unmatched passwords will not have data migrated" -foregroundcolor red
            Write-TimedMessage -Timeout 3 -Message "Press any key to continue or CTRL+C to quit"  -DefaultResponse "continue wrap-up of passwords, please."
        }
    }

    # Save the results to resume from if needed
    $MatchedPasswords | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Passwords.json"
    $ManualActions | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\ManualActions.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Passwords Finished. Continue?"  -DefaultResponse "continue to Document/Article Updates, please."
}

############################## Update ITGlue URLs on All Areas to Hudu #######################

$null = Start-MigrationJob -Name "LinkReplacement"

$UpdateArticles = (Get-HuduArticles | Where-Object {$_.content -like "*$ITGURL*"})
$UpdateAssets = $MatchedAssets | Where-Object {$_.HuduObject.fields.value -like "*$ITGURL*"}
$UpdatePasswords = $MatchedPasswords | Where-Object {$_.HuduObject.description -like "*$ITGURL*"}
$UpdateAssetPasswords = $MatchedAssetPasswords | Where-Object {$_.ITGObject.attributes.notes -like "*$ITGURL*"}
$UpdateCompanyNotes = $MatchedCompanies | Where-Object {$_.HuduCompanyObject.notes -like "*$ITGURL*"}


# Articles
$articlesUpdated = @()
foreach ($articleFound in $UpdateArticles) {
    if ($NewContent = Update-StringWithCaptureGroups -inputString $articleFound.content -pattern $RichRegexPatternToMatchSansAssets -type "rich") {
        $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichRegexPatternToMatchWithAssets -type "rich"
	$NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichDocLocatorUrlPatternToMatch -type "rich"
 	$NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichDocLocatorRelativeURLPatternToMatch -type "rich"
        Write-Host "Updating Article $($articleFound.name) with replaced Content" -ForegroundColor 'Green'
	try {
        $ArticlePost = Set-HuduArticle -Name $articleFound.name -id $articleFound.id -Content $NewContent -ErrorAction Stop
        $articlesUpdated = $articlesUpdated + @{"status" = "replaced"; "original_article" = $articleFound; "updated_article" = $ArticlePost}
	} catch { $articlesUpdated = $articlesUpdated + @{"status" = "failed"; "original_article" = $articleFound; "attempted_changes" = $newContent} }
        }
    else {
        Write-Warning "Article $articleFound.id found ITGlue URL but didn't match"
        $articlesUpdated = $articlesUpdated + @{"status" = "clean"; "original_article" = $articleFound}
    }
}

$articlesUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedArticlesURL.json"
Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Article URLs Replaced. Continue?"  -DefaultResponse "continue to Assets, please."

# Assets
$assetsUpdated = @()
foreach ($assetFound in $UpdateAssets.HuduObject) {
    $originalAsset = $assetFound
    $replacedStatus = 'clean'
    $customFields = @()

    foreach ($field in $assetFound.fields) {
        # Convert the caption to snake_case to match API expectations for 2.37.1
        $label = ($field.caption -replace '[^\w\s]', '') -replace '\s+', '_' | ForEach-Object { $_.ToLower() }

        if ($label -in @('itglue_url', 'itglue_id', 'imported_from_itglue') -and $field.value -like "*$ITGURL*") {
            $NewContent = Update-StringWithCaptureGroups -inputString $field.value -pattern $RichRegexPatternToMatchSansAssets -type "rich"
            $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichRegexPatternToMatchWithAssets -type "rich"

            if ($NewContent -and $NewContent -ne $field.value) {
                Write-Host "Replacing Asset $($assetFound.name) field $($field.caption) with updated content" -ForegroundColor 'Red'
                $customFields += @{ $label = $NewContent }
                $replacedStatus = 'replaced'
            } else {
                $customFields += @{ $label = $field.value }
            }
        } else {
            # For other fields, preserve existing value (optional)
            $customFields += @{ $label = $field.value }
        }
    }

    if ($replacedStatus -eq 'replaced') {
        Write-Host "Updating Asset $($assetFound.name) with new custom_fields array" -ForegroundColor 'Green'
        $AssetPost = Invoke-HuduRequest -Method PUT -Resource "api/v1/companies/$($assetFound.company_id)/assets/$($assetFound.id)" -Body @{
            name              = $assetFound.name
            asset_layout_id   = $assetFound.asset_layout_id
            custom_fields     = $customFields
        }
    }

    $assetsUpdated += @{
        status         = $replacedStatus
        original_asset = $originalAsset
        updated_asset  = $AssetPost.asset
    }
}

$assetsUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedAssetsURL.json"
Write-TimedMessage -Timeout 3 -Message  "Snapshot Point: Assets URLs Replaced. Continue?" -DefaultResponse "continue to Passwords Matching, please."

# Passwords
$passwordsUpdated = @()
foreach ($passwordFound in $UpdatePasswords.HuduObject) {
    $NewContent = Update-StringWithCaptureGroups -inputString $passwordFound.description -pattern $TextRegexPatternToMatchSansAssets -type "plain"
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $TextRegexPatternToMatchWithAssets -type "plain"
    if ($NewContent) {
        Write-Host "Updating Password $($passwordFound.name) with updated description" -ForegroundColor 'Green'
        $passwordsUpdated = $passwordsUpdated + @{"original_password" = $passwordFound; "updated_password" = (Set-HuduPassword -id $passwordFound.id -Description $NewContent).asset_password}
    }
}
$passwordsUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedPasswordsURL.json"
Write-TimedMessage -Timeout 3 -Message  "Snapshot Point: Password URLs Replaced. Continue?"  -DefaultResponse "continue to Asset Passwords Matching, please."

# Asset Passwords
$assetPasswordsUpdated = @()
foreach ($passwordFound in $UpdateAssetPasswords) {
    $passwordFound = Get-HuduPasswords -id $passwordFound.HuduID
    $NewContent = Update-StringWithCaptureGroups -inputString $passwordFound.description -pattern $TextRegexPatternToMatchSansAssets -type "plain"
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $TextRegexPatternToMatchWithAssets -type "plain"
    if ($NewContent)   {
        Write-Host "Updating Asset Password $($passwordFound.name) with updated description" -ForegroundColor 'Green'
        $assetPasswordsUpdated = $assetPasswordsUpdated + @{"original_password" = $passwordFound; "updated_password" = (Set-HuduPassword -Id $passwordFound.id -Description $NewContent).asset_password}
    }
    
}
$assetPasswordsUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedAssetPasswordsURL.json"
Write-TimedMessage -Timeout 3 -Message  "Snapshot Point: Asset Passwords URLs Replaced. Continue?"  -DefaultResponse "continue to Company Notes, please."

# Company Notes
$companyNotesUpdated = @()
foreach ($companyFound in $UpdateCompanyNotes.HuduCompanyObject) {
    $NewContent = Update-StringWithCaptureGroups -inputString $companyFound.notes -pattern $RichRegexPatternToMatchSansAssets -type "rich"
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichRegexPatternToMatchWithAssets -type "rich"
    if ($NewContent) {
        Write-Host "Updating Company $($companyFound.name) with updated notes" -ForegroundColor 'Green'
        $companyNotesUpdated = $companyNotesUpdated + @{"original_company" = $companyFound; "updated_company" = (Set-HuduCompany -id $companyFound.id -Notes $NewContent).company}
    }

}
$companyNotesUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedCompaniesURL.json"
Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Company Notes URLs Replaced. Continue?"  -DefaultResponse "continue to Manual Actions, please."

Write-Host "Replacing links to hosted public photos in Hudu Articles"
if (-not $(get-command -name Set-HuduImageAnchorsReplaced -ErrorAction SilentlyContinue)){. $PSScriptRoot\Public\Set-HuduImageAnchorsReplaced.ps1}
. $PSScriptRoot\Public\Replace-HardCodedImages.ps1

Get-AllHuduHostedImageAnchorsReplaced -allhuduArticles $(get-huduarticles)

############################### Wrap-Up ###############################

write-host "wrapup 1/10... setting asset layouts as active, enabling advanced website monitoring features" -ForegroundColor DarkCyan; $null = Start-MigrationJob -Name "Wrap-Up - Layouts";
foreach ($layout in Get-HuduAssetLayouts) {write-host "setting $($(Set-HuduAssetLayout -id $layout.id -Active $true).asset_layout.name) as active" }
if ($true -eq $DisableWebsiteMonitoring) {write-host "leaving websites unmonitored per user-config"} else {$MatchedWebsites.HuduObject | Where-Object {$_.id -and $_.id -gt 0} | Foreach-Object {write-host "Enabling advanced monitoring features for $($(Set-HuduWebsite -id $_.id -EnableDMARC 'true' -EnableDKIM 'true' -EnableSPF 'true' -DisableDNS 'false' -DisableSSL 'false' -DisableWhois 'false' -Paused 'false').name)" -ForegroundColor DarkCyan}}

write-host "wrapup 2/10... adding attachments and replacing any found attachment links (this can take a while)" ; $null = Start-MigrationJob -Name "Wrap-Up - Attachments";
. .\Add-HuduAttachmentsViaAPI.ps1
Write-Host "Attachments - enumerating and replacing attachment links in articles"; $null = Start-MigrationJob -Name "Wrap-Up - Attachment Links";
$replacedAttachmentURLs = Start-HuduAttachmentLinkReplacement

write-host "wrapup 3/10... Creating IPAM/Networks and Addresses if user-configured to do so... $($importChecklists)"
if ($true -eq $ImportConfigInterfaces){
    write-host "Calculations for addresses can take a while. Please be patient. If it looks like it's stuck, it's just crunching numbers from your $($MatchedConfigurations.count) possible configurations"; $null = Start-MigrationJob -Name "Wrap-Up - IPAM/Networks/Addresses";
    $MatchedInterfaces = Invoke-HuduConfigurationIPAMSync -MatchedConfigurations $MatchedConfigurations
}

write-host "wrapup 4/10... $(if ($true -eq $allowSettingFlagsAndTypes) {"Setting"} else {"Skipping"}) optional flags and flag types..."
if ($true -eq $allowSettingFlagsAndTypes){
    $null = Start-MigrationJob -Name "Wrap-Up - Flags and Flag Types";
    . .\public\Add-HuduFlagsFlagtypes.ps1
}

write-host "wrapup 5/10... Setting Standalone articles with attachments to filename..."; $null = Start-MigrationJob -Name "Wrap-Up - Articles as Attachments";
foreach ($a in $(Get-HuduArticles | where-object {$_.content -eq "Empty Document in IT Glue Export - Please Check IT Glue" -and $_.name -ilike "*.*"})){Set-HuduArticle -id $a.id -content "Please see attached file, $($a.name)"}
if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $false} catch {}}

write-host "wrapup 6/10... Placing password folders if user-configured to do so... $($importPasswordFolders)"
if ($true -eq $importPasswordFolders){
    $null = Start-MigrationJob -Name "Wrap-Up - Password Folders";
    . .\public\Process-PasswordFolders.ps1
}
write-host "wrapup 7/10... Placing checklists / checklist templates if user-configured to do so... $($importChecklists)"
if ($true -eq $importChecklists){
    $null = Start-MigrationJob -Name "Wrap-Up - Checklists";
    . .\public\Process-Checklists.ps1
}

write-host "wrapup 8/10... adding missing relations (this can take a long while). Some errors may appear but can be safely ignored."  -ForegroundColor DarkCyan; $null = Start-MigrationJob -Name "Wrap-Up - Relations";
# set retry to off/false in HuduAPI module, this will save time during adding potentially existent relations.
if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
. .\Get-MissingRelations.ps1

write-host "wrapup 9/10... archiving items..."  -ForegroundColor DarkCyan; $null = Start-MigrationJob -Name "Wrap-Up - Archiving Items";
$DocsCsv = import-csv "$ITGLueExportPath\documents.csv"
$ArchivedPasswords = $MatchedPasswords | Where-Object {$_.itgobject.attributes.archived -eq $true}
$ArchivedConfigurations = $MatchedConfigurations | Where-Object {$_.ITGObject.attributes.archived -eq $true}    
$ArchivedAssets = $MatchedAssets | Where-Object {$_.ITGObject.attributes.archived -eq $true}

$ptaresults = $ArchivedPasswords | ForEach-Object {if ($_.huduid -and $_.huduid -gt 0) {Set-HuduPasswordArchive -id $_.huduid -Archive $true}}
$ctaresults = $ArchivedConfigurations |ForEach-Object {if ($_.huduid -and $_.huduid -gt 0) {Set-HuduAssetArchive -Id $_.huduid -CompanyId $_.huduobject.company_id -Archive $true}}
$ataresults = $ArchivedAssets |ForEach-Object {if ($_.huduid -and $_.huduid -gt 0) {Set-HuduAssetArchive -Id $_.huduid -CompanyId $_.huduobject.company_id -Archive $true}}
$documentsForArchive =  $($matchedarticles | Where-Object {@($($($DocsCsv) | Where-Object {$_.archived -ne "No"}) | ForEach-Object {"$($_.id)"}) -contains [string]($_.ITGID)})
$documentArchiveResults = foreach ($doc in $documentsForArchive) {if ($doc.huduid -and $doc.huduid -gt 0) {Set-HuduArticleArchive -id $doc.huduid -Archive $true -confirm:$false}};
foreach ($obj in @(
    @{Name = "passwords";       Archived = $ptaresults ?? @() },
    @{Name = "configs";         Archived = $ctaresults ?? @() },
    @{Name = "assets";          Archived = $ataresults ?? @() },
    @{Name = "docs";            Archived = $documentArchiveResults ?? @() })) {
    $obj.Archived | ConvertTo-Json -depth 75 | Out-File $(join-path $settings.MigrationLogs "archived-$($obj.Name).json")
}

write-host "wrapup 10/10... $(if ($true -eq ($shouldRunVaultJob ?? $false)) {"Running"} else {"Skipping"}) vault job to update vaulted passwords with real values..."
if ($true -eq ($shouldRunVaultJob ?? $false)){
    $null = Start-MigrationJob -Name "Wrap-Up - Vaulted Passwords";
    . .\Un-Vault-Passwords.ps1
    $null = Complete-MigrationJob -Name "Wrap-Up - Vaulted Passwords" -CompletedAt $(Get-Date)
} else {
    $null = Complete-MigrationJob -Name "Wrap-Up - Archiving Items" -CompletedAt $(Get-Date)
}

############################### End ###############################

$VaultedPasswords = $VaultedPasswords ?? @(); $unvaultedMatches = $unvaultedMatches ?? @();
$MatchedUploadFields = $MatchedUploadFields ?? @{}; $UnresolvedUploadFields = $UnresolvedUploadFields ?? @{};
foreach ($auxilliaryObj in @(@{Name="UnvaultedPasswords"; Created = $unvaultedMatches ?? @()}, @{Name = "passwordfolders"; Created = $MatchedPasswordFolders ?? @() }, @{Name="UploadFields"; Created = $MatchedUploadFields ?? @() }, @{Name="UnresolvedUploadFields"; Created = $UnresolvedUploadFields ?? @() }, @{Name = "checklists"; Created = $MatchedChecklists ?? @() }, @{Name="Interfaces-IPAM"; Created = ($MatchedInterfaces ?? @())})) {
    write-host "Writing json dump for $($auxilliaryObj.Name) created during migration for reference in manual actions and for audit purposes"
    $auxilliaryObj.Created | ConvertTo-Json -depth 75 | Out-File $(join-path $settings.MigrationLogs "created-$($auxilliaryObj.Name).json")
}

$CompletedAt = Get-Date
$Duration = $CompletedAt - $ScriptStartTime
$JobDurationReport = @(Get-MigrationJobDurationReport -ReportEndTime $CompletedAt)
$JobDurationSummary = ($JobDurationReport | Select-Object Job, Status, Started, Finished, Duration | Format-Table -AutoSize | Out-String).TrimEnd()

$MatchedChecklistsForSummary = @($MatchedChecklists | Where-Object { $_ })
$GlobalProcessTemplatesMigrated = @($MatchedChecklistsForSummary | Where-Object { $_.HuduProcedure -and -not $_.HuduProcedure.company_id }).Count
$CompanyProcessTemplatesMigrated = @($MatchedChecklistsForSummary | Where-Object { $_.HuduProcedure -and $_.HuduProcedure.company_id }).Count
$ProcessRunsMigrated = @($MatchedChecklistsForSummary | Where-Object { $_.HuduProcedureRun -and $_.HuduProcedureRun.id }).Count

$migratedItems = [ordered]@{
    'Companies Migrated'                         = Get-SafeCount $($MatchedCompanies | where-object {[int]($_.HuduID) -gt 0})
    'Locations Migrated'                         = Get-SafeCount $($MatchedLocations | where-object {[int]($_.HuduID) -gt 0})
    'Websites Migrated'                          = Get-SafeCount $($MatchedWebsites | where-object {[int]($_.HuduID) -gt 0})
    'Configurations Migrated'                    = Get-SafeCount $($MatchedConfigurations | where-object {[int]($_.HuduID) -gt 0})
    'IPAM Interfaces/Networks/Addresses Migrated'= Get-SafeCount $MatchedInterfaces
    'Contacts Migrated'                          = Get-SafeCount $($MatchedContacts | where-object {[int]($_.HuduID) -gt 0})
    'Layouts Migrated'                           = Get-SafeCount $($MatchedLayouts | where-object {[int]($_.HuduID) -gt 0})
    'Assets Migrated'                            = Get-SafeCount $($MatchedAssets | where-object {[int]($_.HuduID) -gt 0})
    'Articles Migrated'                          = Get-SafeCount $($MatchedArticles | where-object {[int]($_.HuduID) -gt 0})
    'Passwords Migrated'                         = Get-SafeCount $MatchedPasswords
    'Password Folders Migrated'                  = Get-SafeCount $($MatchedPasswordFolders | where-object {[int]($_.HuduPasswordFolder.ID) -gt 0})
    'Passwords From Vault'                       = $VaultedPasswords.count ?? 0
    'Passwords Left Unvaulted'                   = ([int]($VaultedPasswords.count ?? 0) - [int]($unvaultedMatches.count ?? 0))
    'Relations Created'                          = Get-SafeCount $NewRelationsCreated
    'Upload Fields Migrated'                     = $MatchedUploadFields.count ?? 0
    'Upload Fields Unresolved'                   = $UnresolvedUploadFields.count ?? 0
    'Checklists / Checklist Templates Migrated'  = Get-SafeCount ($MatchedChecklists ?? @())
    'Hudu Global Process Templates Migrated'     = $GlobalProcessTemplatesMigrated
    'Hudu Company Process Templates Migrated'    = $CompanyProcessTemplatesMigrated
    'Hudu Process Runs Migrated'                 = $ProcessRunsMigrated
}

$archivedItems = [ordered]@{
    'Passwords Archived'       = $ptaresults.count ?? 0
    'Configurations Archived'  = $ctaresults.count ?? 0
    'Assets Archived'          = $ataresults.count ?? 0
    'Documents Archived'       = $documentArchiveResults.count ?? 0
}
$MigrationSummary = "$(Format-MigrationSummary -ScriptStartTime $ScriptStartTime -CompletedAt $CompletedAt -Duration $Duration -DebugFolder ($debugFolder ?? "$PSScriptRoot\debug") -MigrationLogs ($MigrationLogs ?? "$PSScriptRoot\debug\logs") -migratedItems $migratedItems -archivedItems $archivedItems)"
if ($JobDurationReport.Count -gt 0) {
    $MigrationSummary = @(
        $MigrationSummary
        '-------------------------------------------------------'
        'Job Durations'
        '-------------------------------------------------------'
        $JobDurationSummary
    ) -join [Environment]::NewLine

    $JobDurationReport | ConvertTo-Json -Depth 5 | Out-File "$MigrationLogs\JobDurations.json" -Encoding utf8
    $JobDurationSummary | Out-File "$MigrationLogs\JobDurations.txt" -Encoding utf8
}
$MigrationSummary | Out-File -FilePath "$MigrationLogs\MigrationSummary.txt" -Encoding utf8
Format-ManualActionsReport -ManualActions $ManualActions -OutputPath "$MigrationLogs\ManualActions.html" -summary $MigrationSummary
Write-Host $MigrationSummary -ForegroundColor DarkCyan

Write-TimedMessage -Message "Press any key to view manual actions" -Timeout 5  -DefaultResponse "continue, view generative Manual Actions webpage, please."
Start-Process "$MigrationLogs\ManualActions.html"
