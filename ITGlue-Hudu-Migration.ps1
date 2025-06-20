# Main settings load
. $PSScriptRoot\Initialize-Module.ps1 -InitType 'Full'

# Use this to set the context of the script runs
$FirstTimeLoad = 1

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

# Get Configurations Option
. $PSScriptRoot\Private\Get-ConfigurationsImportMode.ps1

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

# Add numeral casting helper method
. $PSScriptRoot\Public\Get-CastIfNumeric.ps1

# Add migration scope helper
. $PSScriptRoot\Public\Set-MigrationScope.ps1

############################### End of Functions ###############################


###################### Initial Setup and Confirmations ###############################
Write-Host "#######################################################" -ForegroundColor Green
Write-Host "#                                                     #" -ForegroundColor Green
Write-Host "#          IT Glue to Hudu Migration Script           #" -ForegroundColor Green
Write-Host "#                                                     #" -ForegroundColor Green
Write-Host "#          Version: 2.0  -Beta                        #" -ForegroundColor Green
Write-Host "#          Date: 02/07/2023                           #" -ForegroundColor Green
Write-Host "#                                                     #" -ForegroundColor Green
Write-Host "#          Author: Luke Whitelock                     #" -ForegroundColor Green
Write-Host "#                  https://mspp.io                    #" -ForegroundColor Green
Write-Host "#          Contributors: John Duprey                  #" -ForegroundColor Green
Write-Host "#                        Mendy Green                  #" -ForegroundColor Green
Write-Host "#                  https://MSPGeek.org                #" -ForegroundColor Green
Write-Host "#                  https://mendyonline.com            #" -ForegroundColor Green
Write-Host "#                                                     #" -ForegroundColor Green
Write-Host "#######################################################" -ForegroundColor Green
Write-Host "# Note: This is an unofficial script, please do not   #" -ForegroundColor Green
Write-Host "# contact Hudu support if you run into issues.        #" -ForegroundColor Green
Write-Host "# For support please visit the Hudu Sub-Reddit:       #" -ForegroundColor Green
Write-Host "# https://www.reddit.com/r/hudu/                      #" -ForegroundColor Green
Write-Host "# The #v-hudu channel on the MSPGeek Slack/Discord:   #" -ForegroundColor Green
Write-Host "# https://join.mspgeek.com/                           #" -ForegroundColor Green
Write-Host "# Or log an issue in the Github Respository:          #" -ForegroundColor Green
Write-Host "# https://github.com/lwhitelock/ITGlue-Hudu-Migration #" -ForegroundColor Green
Write-Host "#######################################################" -ForegroundColor Green
Write-Host " Instructions:                                       " -ForegroundColor Green
Write-Host " Please view Luke's blog post:                       " -ForegroundColor Green
Write-Host " https://mspp.io/automated-it-glue-to-hudu-migration-script/     " -ForegroundColor Green
Write-Host " for detailed instructions                           " -ForegroundColor Green
Write-Host "#######################################################" -ForegroundColor Green
Write-Host "# Please keep ALL COPIES of the Migration Logs folder. This can save you." -ForegroundColor Gray
Write-Host "# Please DO NOT CHANGE ANYTHING in the Migration Logs folder. This can save you." -ForegroundColor Gray

# CMA
Write-Host "######################################################" -ForegroundColor Red
Write-Host "Have you taken a full backup of your Hudu Environment?" -ForegroundColor Red
Write-Host "Things could go wrong and you need to be able to " -ForegroundColor Red
Write-Host "recover to the state from before the script was run" -ForegroundColor Red
Write-Host "######################################################" -ForegroundColor Red
Write-Host "######################################################" -ForegroundColor Red
Write-Host "This Script has the potential to ruin your Hudu environment" -ForegroundColor Red
Write-Host "It is unofficial and you run it entirely at your own risk" -ForegroundColor Red
Write-Host "You accept full responsibility for any problems caused by running it" -ForegroundColor Red
Write-Host "######################################################" -ForegroundColor Red

$backups=$(if ($true -eq $NonInteractive) {"Y"} else {Read-Host "Y/n"})

$ScriptStartTime = $(Get-Date -Format "o")

if ($backups -ne "Y" -or $backups -ne "y") {
    Write-Host "Please take a backup and run the script again"
    exit 1
}

if ((get-host).version.major -ne 7) {
    Write-Host "Powershell 7 Required" -foregroundcolor Red
    exit 1
}


#Get the Hudu API Module if not installed

$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1"
if (Test-Path $HAPImodulePath) {
    Import-Module $HAPImodulePath -Force
    Write-Host "Module imported from $HAPImodulePath"
} elseif ((Get-Module -ListAvailable -Name HuduAPI).version -ge '2.4.4') {
    Write-Host "Module imported from $HAPImodulePath"
    Import-Module HuduAPI
} else {
    Install-Module HuduAPI -MinimumVersion 2.4.5 -Scope CurrentUser
    Import-Module HuduAPI
}
  
  
#Login to Hudu
New-HuduAPIKey $HuduAPIKey
New-HuduBaseUrl $HuduBaseDomain

# Check we have the correct version
$RequiredHuduVersion = "2.37.1"
$DisallowedVersions = @([version]"2.37.0")
$HuduAppInfo = Get-HuduAppInfo
$CurrentVersion = [version]$HuduAppInfo.version

if ($CurrentVersion -lt [version]$RequiredHuduVersion -or $DisallowedVersions -contains $CurrentVersion) {
    Write-Host "This script requires at least version $RequiredHuduVersion and cannot run with version $CurrentVersion. Please update your version of Hudu."
    exit 1
}

try {
    remove-module ITGlueAPI -ErrorAction SilentlyContinue
} catch {
}
#Grabbing ITGlue Module and installing.
If (Get-Module -ListAvailable -Name "ITGlueAPIv2") { 
    Import-module ITGlueAPIv2 
} Else { 
    Install-Module ITGlueAPIv2 -Force
    Import-Module ITGlueAPIv2
}


#Settings IT-Glue logon information
Add-ITGlueBaseURI -base_uri $ITGAPIEndpoint
Add-ITGlueAPIKey $ITGKey

# Check if we have a logs folder
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


# Setup some variables

$ManualActions = [System.Collections.ArrayList]@()


############################### Companies ###############################

#Grab existing companies in Hudu
$HuduCompanies = Get-HuduCompanies

#Check for Company Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Companies.json")) {
    Write-Host "Loading Previous Companies Migration"
    $MatchedCompanies = Get-Content "$MigrationLogs\Companies.json" -raw | Out-String | ConvertFrom-Json
} else {

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
        Write-Host "Companies scoped... $OriginalCompanyCount => $($Itgcompanies.count)"
    }

	$ScopedITGCompanyIds = $ITGCompanies.id

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

        $HuduCompany = $HuduCompanies | Where-Object -Filter { $_.name -eq $originalName }

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

    # Check if the internal company was found and that there was only 1 of them
    $PrimaryCompany = $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.InternalCompany -eq $true } | Select-Object CompanyName

    if (($PrimaryCompany | measure-object).count -ne 1) {
        Write-Host "A single Internal Company was not found please run the script again and check the company name entered exactly matches what is in ITGlue" -foregroundcolor red
        exit 1
    }

    # Lets confirm it is the correct one
    Write-Host ""
    Write-Host "Your Internal Company has been matched to: $(($MatchedCompanies | Sort-Object CompanyName | Where-Object {$_.InternalCompany -eq $true} | Select-Object CompanyName).companyname) in IT Glue"
    Write-Host "The documents under this customer will be migrated to the Global KB in Hudu"
    Write-Host ""
    Write-TimedMessage -Message "Internal Company Correct? Press Return to continue or CTRL+C to quit if this is not correct" -Timeout 12 -DefaultResponse "Assuming found match on '$(($MatchedCompanies | Sort-Object CompanyName | Where-Object {$_.InternalCompany -eq $true} | Select-Object CompanyName).companyname)' is correct."

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
        $ITGLocations         = $ITGLocations | Where-Object { $ScopedITGCompanyIds -contains $_.attributes.'organization-id' }
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

############################### Locations ###############################
#Check for Location Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Locations.json")) {
    Write-Host "Loading Previous Locations Migration"
    $MatchedLocations = Get-Content "$MigrationLogs\Locations.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {


    $LocHuduItemFilter = { ($_.name -eq $itgimport.attributes.name -and $_.company_name -eq $itgimport.attributes."organization-name")`
            -or ($ITGPrimaryLocationNames -contains $itgimport.attributes.name -and $HuduPrimaryLocationNames -contains $_.name -and $_.company_name -eq $itgimport.attributes."organization-name")`
            -or ($itgimport.attributes.primary -eq $true -and $HuduPrimaryLocationNames -contains $_.name -and $_.company_name -eq $itgimport.attributes."organization-name") }

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
        }
    )



    $LocAssetFieldsMap = { @{ 
            'address_1'   = $unmatchedImport."ITGObject".attributes."address-1"
            'address_2'   = $unmatchedImport."ITGObject".attributes."address-2"
            'city'        = $unmatchedImport."ITGObject".attributes."city"
            'postal_code' = $unmatchedImport."ITGObject".attributes."postal-code"
            'region'      = $unmatchedImport."ITGObject".attributes."region-name"
            'country'     = $unmatchedImport."ITGObject".attributes."country-name"
            'phone'       = $unmatchedImport."ITGObject".attributes."phone"
            'fax'         = $unmatchedImport."ITGObject".attributes."fax"
            'notes'       = $unmatchedImport."ITGObject".attributes."notes"		
        } }


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
    $MatchedLocations | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Locations.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Locations Migrated Continue?"  -DefaultResponse "continue to Websites, please."

}


############################### Websites ###############################

#Check for Website Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Websites.json")) {
    Write-Host "Loading Previous Websites Migration"
    $MatchedWebsites = Get-Content "$MigrationLogs\Websites.json" -raw | Out-String | ConvertFrom-Json
} else {

    #Grab existing Websites in Hudu
    $HuduWebsites = Get-HuduWebsites

    #Import Websites
    Write-Host "Fetching Domains from IT Glue" -ForegroundColor Green
    $DomainSelect = { (Get-ITGlueDomains -page_size 1000 -page_number $i).data }
    $ITGDomains = Import-ITGlueItems -ItemSelect $DomainSelect

    if ($ScopedMigration) {
        $OriginalDomainsCount = $($ITGDomains.count)
        Write-Host "Setting domains to those in scope..." -foregroundcolor Yellow
        $ITGDomains          = $ITGdomains | Where-Object { $ScopedITGCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "domains scoped... $OriginalDomainsCount => $($ITGDomains.count)"
    }

    Write-Host "$($ITGDomains.count) ITG Glue Domains Found" 

    $MatchedWebsites = foreach ($itgdomain in $ITGDomains ) {
        $HuduWebsite = $HuduWebsites | where-object -filter { ($_.name -eq "https://$($itgdomain.attributes.name)" -and $_.company_name -eq $itgdomain.attributes."organization-name") }

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
	
$ConfigMigrationName = "Configurations"
$ConfigImportAssetLayoutName = "Configurations"
	
#Check for Configuration Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Configurations.json")) {
    Write-Host "Loading Previous Configurations Migration"
    $MatchedConfigurations = Get-Content "$MigrationLogs\Configurations.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {

    #Get Configurations from IT Glue
    Write-Host "Fetching Configurations from IT Glue" -ForegroundColor Green
    $ConfigurationsSelect = { (Get-ITGlueConfigurations -page_size 1000 -page_number $i -include related_items).data }
    $ITGConfigurations = Import-ITGlueItems -ItemSelect $ConfigurationsSelect

    if ($ScopedMigration) {
        $OriginalConfigurationCount = $($ITGConfigurations.count)
        Write-Host "Setting configurations to those in scope..." -foregroundcolor Yellow        
        $ITGConfigurations    = $ITGConfigurations | Where-Object { $ScopedITGCompanyIds -contains $_.attributes.'organization-id' }
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
            label        = 'Location Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 21
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
        }
    )


    $ConfigHuduItemFilter = { ($_.name -eq $itgimport.attributes.name -and $_.company_name -eq $itgimport.attributes."organization-name") }
	
    $ConfigImportEnabled = $ImportConfigurations

	
    $ConfigAssetFieldsMap = { @{ 
            # 'name'                      = $unmatchedImport."ITGObject".attributes."name"
            'hostname'                  = $unmatchedImport."ITGObject".attributes."hostname"
            'primary_ip'                = $unmatchedImport."ITGObject".attributes."primary-ip"
            'mac_address'               = $unmatchedImport."ITGObject".attributes."mac-address"
            'default_gateway'           = $unmatchedImport."ITGObject".attributes."default-gateway"
            'serial_number'             = $unmatchedImport."ITGObject".attributes."serial-number"
            'asset_tag'                 = $unmatchedImport."ITGObject".attributes."asset-tag"
            'position'                  = $unmatchedImport."ITGObject".attributes."position"
            'installed_by'              = $unmatchedImport."ITGObject".attributes."installed-by"
            'purchased_by'              = $unmatchedImport."ITGObject".attributes."purchased-by"
            'notes'                     = $unmatchedImport."ITGObject".attributes."notes"
            'operating_system_notes'    = $unmatchedImport."ITGObject".attributes."operating-system-notes"
            'warranty_expires_at'       = $unmatchedImport."ITGObject".attributes."warranty-expires-at"
            'installed_at'              = $unmatchedImport."ITGObject".attributes."installed-at"
            'purchased_at'              = $unmatchedImport."ITGObject".attributes."purchased-at"
            # 'created_at'                = $unmatchedImport."ITGObject".attributes."created-at"
            # 'updated_at'                = $unmatchedImport."ITGObject".attributes."updated-at"
            'configuration_type_name'   = $unmatchedImport."ITGObject".attributes."configuration-type-name"
            'configuration_type_kind'   = $unmatchedImport."ITGObject".attributes."configuration-type-kind"
            'configuration_status_name' = $unmatchedImport."ITGObject".attributes."configuration-status-name"
            'operating_system_name'     = $unmatchedImport."ITGObject".attributes."operating-system-name"
            'location_name'             = $unmatchedImport."ITGObject".attributes."location-name"
            'model_name'                = $unmatchedImport."ITGObject".attributes."model-name"
            'contact_name'              = $unmatchedImport."ITGObject".attributes."contact-name"	
        } }


    # First we need to decide on if we are going to do one Asset type or many
    Write-Host "Hudu does not have the same standard configuration type as IT Glue."
    Write-Host "With the migration there are a few options of how to approach this"
    Write-Host "1) The script can create a new Hudu Asset Layout for all configurations to go into, like how IT Glue works"
    Write-Host "2) The script can create an Asset layout for each in use Configuration Type you have in IT Glue and then split up configurations into them"
    Write-Host "3) The script can prompt for each Configuration type you have, asking you for the new Hudu Asset Layout to map to, this will allow you to have a mix of 1 and 2"

    $ConfigurationOption = Get-ConfigurationsImportMode

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

            $ParsedITGConfigs = $ITGConfigurations | Where-Object -filter { $_.attributes."configuration-type-name" -eq $ConfigType }

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

	
	
    } elseif ($ConfigurationOption -eq 3) {
        $ITGConfigTypes = $ITGConfigurations.attributes."configuration-type-name" | Select-Object -unique
        $MatchedConfigurations = New-Object System.Collections.ArrayList

        foreach ($ConfigType in $ITGConfigTypes) {
            Write-Host ""
            Write-Host "Processing $ConfigType"
            Write-Host "Please provide the Asset Layout name for $ConfigType in Hudu." -foregroundcolor green
            $ConfigImportAssetLayoutName = $(Write-TimedMessage -Timeout 12 -Message "Please enter layout name" -DefaultResponse $ConfigType)
		

            $ParsedITGConfigs = $ITGConfigurations | Where-Object -filter { $_.attributes."configuration-type-name" -eq $ConfigType }

            $ConfigMigrationName = $ConfigImportAssetLayoutName
			
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
        Write-Error "This should never have happened some how you selected something other than 1, 2 or 3 :/"
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


    Write-Host "Fetching Contacts from IT Glue" -ForegroundColor Green
    $ContactsSelect = { (Get-ITGlueContacts -page_size 1000 -page_number $i -include related_items).data }
    $ITGContacts = Import-ITGlueItems -ItemSelect $ContactsSelect
    #($ITGContacts.attributes | sort-object -property name, "organization-name" -Unique)


    if ($ScopedMigration) {
        $OriginalContactsCount = $($ITGContacts.count)
        Write-Host "Setting contacts to those in scope..." -foregroundcolor Yellow               
        $ITGContacts          = $ITGContacts | Where-Object { $ScopedITGCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "Contacts scoped... $OriginalContactsCount => $($ITGContacts.count)"
    }

    $ConHuduItemFilter = { ($_.name -eq $itgimport.attributes.name -and $_.company_name -eq $itgimport.attributes."organization-name") }

    $ConImportEnabled = $ImportContacts

    $ConMigrationName = "Contacts"

    $LocationLayout = Get-HuduAssetLayouts -name $LocImportAssetLayoutName

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
            label        = 'Location'
            field_type   = 'AssetTag'
            show_in_list = 'false'
            linkable_id  = $LocationLayout.ID
            position     = 5
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
        }
    )



    $ConAssetFieldsMap = { @{ 
            'first_name'   = $unmatchedImport."ITGObject".attributes."first-name"
            'last_name'    = $unmatchedImport."ITGObject".attributes."last-name"
            'title'        = $unmatchedImport."ITGObject".attributes."title"
            'contact_type' = $unmatchedImport."ITGObject".attributes."contact-type-name"
            'location'     = "[$($MatchedLocations | where-object -filter {$_.ITGID -eq $unmatchedImport."ITGObject".attributes."location-id"} | Select-Object @{N='id';E={$_.HuduID}}, @{N='name';E={$_.Name}} | convertto-json -compress | out-string)]" -replace "`r`n", ""
            'important'    = $unmatchedImport."ITGObject".attributes."important"
            'notes'        = $unmatchedImport."ITGObject".attributes."notes"
            'emails'       = $unmatchedImport."ITGObject".attributes."contact-emails" | convertto-html -fragment | out-string
            'phones'       = $unmatchedImport."ITGObject".attributes."contact-phones"	| convertto-html -fragment | out-string
        } }


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

    $ConfigImportAssetLayoutName = ($MatchedConfigurations.HuduObject | Select-Object name, asset_type | group-object -property asset_type | sort-object count -descending | Select-Object -first 1).name

    Write-Host "Fetching Flexible Asset Layouts from IT Glue" -ForegroundColor Green
    $FlexLayoutSelect = { (Get-ITGlueFlexibleAssetTypes -page_size 1000 -page_number $i -include related_items).data }
    $FlexLayouts = Import-ITGlueItems -ItemSelect $FlexLayoutSelect

    $HuduLayouts = Get-HuduAssetLayouts

    Write-Host "The script will now migrate IT Glue Flexible Asset Layouts to Hudu"
    Write-Host "Please select the option you would like"
    Write-Host "1) Move all Flexible Asset Layouts to Hudu"
    Write-Host "2) Determine on a layout by layout basis if you want to migrate"
    $ImportOption = Get-FlexLayoutImportMode

    $AllFields = [System.Collections.ArrayList]@()

    # Match to existing layouts
    $MatchedLayouts = foreach ($ITGLayout in $FlexLayouts) {
        $HuduLayout = $HuduLayouts | where-object -filter { $_.name -eq "$($FlexibleLayoutPrefix)$($ITGLayout.attributes.name)" }
		
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

        foreach ($UnmatchedLayout in $MatchedLayouts | Where-Object { $_.Matched -eq $false }) {
            if ($ImportOption -eq 2) {
                Confirm-Import -ImportObjectName "$($ITGLayout.attributes.name)" -ImportObject $null -ImportSetting $ImportOption
            }

            $TempLayoutFields = @(
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
		
		
            $NewLayout = New-HuduAssetLayout -name "$($FlexibleLayoutPrefix)$($UnmatchedLayout.ITGObject.attributes.name)" -icon "fas fa-$NewIcon" -color "00adef" -icon_color "#ffffff" -include_passwords $true -include_photos $true -include_comments $true -include_files $true -fields $TempLayoutFields 
            $MatchedNewLayout = Get-HuduAssetLayouts -layoutid $NewLayout.asset_layout.id

            $UnmatchedLayout.HuduObject = $MatchedNewLayout
            $UnmatchedLayout.HuduID = $NewLayout.asset_layout.id
            $UnmatchedLayout.Imported = "Created-By-Script"



        }


        foreach ($UpdateLayout in $MatchedLayouts) {
            Write-Host "Starting $($UpdateLayout.Name)" -ForegroundColor Green

            # Grab the fields for the layout
            Write-Host "Fetching Flexible Asset Fields from IT Glue"
            $FlexLayoutFieldsSelect = { (Get-ITGlueFlexibleAssetFields -page_size 1000 -page_number $i -flexible_asset_type_id $UpdateLayout.ITGID).data }
            $FlexLayoutFields = Import-ITGlueItems -ItemSelect $FlexLayoutFieldsSelect

				
            # Grab all the Assets for the layout
            Write-Host "Fetching Flexible Assets from IT Glue (This may take a while)"
            $FlexAssetsSelect = { (Get-ITGlueFlexibleAssets -page_size 1000 -page_number $i -filter_flexible_asset_type_id $UpdateLayout.ITGID -include related_items).data }
            $FlexAssets = Import-ITGlueItems -ItemSelect $FlexAssetsSelect
		
				
		
            $UpdateLayoutFields = foreach ($ITGField in $FlexLayoutFields) {
                $LayoutField = @{
                    label        = $ITGField.Attributes.name
                    show_in_list = $ITGField.Attributes."show-in-list"
                    position     = $ITGField.Attributes.order
                    required     = $ITGField.Attributes.required
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
                        $LayoutField.add("field_type", "Dropdown")
                        $LayoutField.add("options", $($ITGField.Attributes."default-value"))
                    }
                    "Text" {
                        $LayoutField.add("field_type", "Text")
                    }
                    "Textbox" {
                        $LayoutField.add("field_type", "RichText")
                    }
                    "Upload" {
                        Write-Host "Upload fields are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) this will be added when the Hudu API supports it, Sorry!"
                        $supported = $false
                    }
                    "Tag" {
                        switch (($ITGField.Attributes."tag-type").split(":")[0]) {
                            "AccountsUsers" { Write-Host "Tags to Account Users are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!" ; $supported = $false }
                            "Checklists" { Write-Host "Tags to Checklists are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "ChecklistTemplates" { Write-Host "Tags to Checklists Templates are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Contacts" {
                                $ContactLayout = Get-HuduAssetLayouts -name $ConImportAssetLayoutName
                                $LayoutField.add("field_type", "AssetTag")
                                $LayoutField.add("linkable_id", $ContactLayout.ID)
                            }
                            "Configurations" {
                                $ConfigLayout = Get-HuduAssetLayouts -name $ConfigImportAssetLayoutName
                                $LayoutField.add("field_type", "AssetTag")
                                $LayoutField.add("linkable_id", $ConfigLayout.ID)
                            }
                            "Documents" { Write-Host "Tags to Documents are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!"; $supported = $false } 
                            "Domains" { Write-Host "Tags to Websites are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Passwords" { Write-Host "Tags to Passwords are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Locations" {
                                $LocationLayout = Get-HuduAssetLayouts -name $LocImportAssetLayoutName
                                $LayoutField.add("field_type", "AssetTag")
                                $LayoutField.add("linkable_id", $LocationLayout.ID)
                            }
                            "Organizations" { Write-Host "Tags to Companies are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "SslCertificates" { Write-Host "Tags to SSL Certificates are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Tickets" { Write-Host "Tags to Tickets are not supported $($ITGField.Attributes.name) in $($UpdateLayout.name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "FlexibleAssetType" {	
                                $MatchedLayoutID = ($MatchedLayouts | where-object -filter { $_.ITGID -eq ($ITGField.Attributes."tag-type").split(" ")[1] }).HuduID
                                $LayoutField.add("field_type", "AssetTag")
                                $LayoutField.add("linkable_id", $MatchedLayoutID)
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
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Assets.json")) {
    Write-Host "Loading Previous Asset Migration"
    $MatchedAssets = Get-Content "$MigrationLogs\Assets.json" -raw | Out-String | ConvertFrom-Json -depth 100
    $MatchedAssetPasswords = Get-Content "$MigrationLogs\AssetPasswords.json" -raw | Out-String | ConvertFrom-Json -depth 100
    $RelationsToCreate = [System.Collections.ArrayList](Get-Content "$MigrationLogs\RelationsToCreate.json" -raw | Out-String | ConvertFrom-Json -depth 100)
    $ManualActions = [System.Collections.ArrayList](Get-Content "$MigrationLogs\ManualActions.json" -raw | Out-String | ConvertFrom-Json -depth 100)
} else {
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
            $MatchedLayouts = Filter-ScopedAssets -Layouts $MatchedLayouts -ScopedCompanyIds $ScopedITGCompanyIds
            Write-Host "Layouts scoped... $OriginalLayoutsCount => $($MatchedLayouts.count)"
        }

        Foreach ($Layout in $MatchedLayouts) {
            Write-Host "Creating base assets for $($layout.name)"
            foreach ($ITGAsset in $Layout.ITGAssets) {
                # Match Company
                $HuduCompanyID = ($MatchedCompanies | where-object -filter { $_.ITGID -eq $ITGAsset.attributes.'organization-id' }).HuduID

                $AssetFields = @{ 
                    'imported_from_itglue' = Get-Date -Format "o"
                    'itglue_url' = $ITGAsset.attributes.'resource-url'
                    'itglue_id' = $ITGAsset.id
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
        foreach ($UpdateAsset in $MatchedAssets) {
            Write-Host "Populating $($UpdateAsset.Name)"
		
            $AssetFields = @{ 
                'imported_from_itglue' = Get-Date -Format "o"
            }

            $traits = $UpdateAsset.ITGObject.attributes.traits
            $traits.PSObject.Properties | ForEach-Object {
                # Find the corresponding field we are working on
                $ITGParsed = $_.name
                $ITGValues = $_.value
                $field = $AllFields | where-object -filter { $_.IGLayoutID -eq $UpdateAsset.ITGObject.attributes.'flexible-asset-type-id' -and $_.ITGParsedName -eq $ITGParsed }
                if ($field) {
                    $supported = $true

                    if ($field.FieldType -eq "Tag") {
				
                        switch ($field.FieldSubType) {
                            "AccountsUsers" { Write-Host "Tags to Account Users are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Checklists" { Write-Host "Tags to Checklists are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "ChecklistTemplates" { Write-Host "Tags to Checklists Templates are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Contacts" {
                                $ContactsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $($MatchedContacts | where-object -filter { $_.ITGID -eq $IDMatch.id } | Select-Object @{N = 'id'; E = { $_.HuduID } }, @{N = 'name'; E = { $_.Name } })
                                }
                                $ReturnData = $ContactsLinked | convertto-json -compress -AsArray | Out-String
                                $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))
											
											
                            }
                            "Configurations" {
                                $ConfigsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $($MatchedConfigurations | where-object -filter { $_.ITGID -eq $IDMatch.id } | Select-Object @{N = 'id'; E = { $_.HuduID } }, @{N = 'name'; E = { $_.Name } })
                                }
                                $ReturnData = $ConfigsLinked | convertto-json -compress -AsArray | Out-String
                                $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))
											
                            }
                            "Documents" { $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) { @{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'Article'; itg_to_id = $IDMatch.id}} ;Write-Host "Tags to Articles $($field.FieldName) in $($UpdateAsset.Name) has been recorded for later."; $supported = $true }
                            "Domains" { 
                                $DomainsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $MatchedWebsites | Where-Object -filter { $_.ITGID -eq $IDMatch.id }
                                } 
                                $DomainsLinked | ForEach-Object {
                                     if ($WebsiteRelation = New-HuduRelation -FromableType 'Asset' -ToableType 'Website' -FromableID $UpdateAsset.HuduID -ToableID $_.HuduID) {
                                        Write-Host "Successully Created relation to $($WebsiteRelation.relation.name)"
                                     } else { Write-Host "Tags to Websites are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                                    }
                            }
                            "Passwords" { $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) { @{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'AssetPassword'; itg_to_id = $IDMatch.id}}; Write-Host "Tags to Password $($field.FieldName) in $($UpdateAsset.Name) has been recorded for later."; $supported = $true }
                            "Locations" {
                                $LocationsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $($MatchedLocations | where-object -filter { $_.ITGID -eq $IDMatch.id } | Select-Object @{N = 'id'; E = { $_.HuduID } }, @{N = 'name'; E = { $_.Name } })
                                }
                                $ReturnData = $LocationsLinked | convertto-json -compress -AsArray | Out-String
                                $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))
											
                            }
                            "Organizations" { $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) {@{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'Company'; itg_to_id = $IDMatch.id}}; Write-Host "Tags to Companies $($field.FieldName) in $($UpdateAsset.Name) has been recorded later."; $supported = $true }
                            "SslCertificates" { Write-Host "Tags to SSL Certificates are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Tickets" { Write-Host "Tags to Tickets are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "FlexibleAssetType" {	
                                $AssetsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $($MatchedAssets | where-object -filter { $_.ITGID -eq $IDMatch.id } | Select-Object @{N = 'id'; E = { $_.HuduID } }, @{N = 'name'; E = { $_.Name } })
                                }
                                $ReturnData = $AssetsLinked | convertto-json -compress -AsArray | Out-String
                                $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))
											
                            }
					

                        }

                        if ($Supported -eq $False) {
                            $ManualLog = [PSCustomObject]@{
                                Document_Name = $UpdateAsset.Name
                                Asset_Type    = $UpdateAsset.HuduObject.asset_type
                                Company_Name  = $UpdateAsset.HuduObject.company_name
                                HuduID        = $UpdateAsset.HuduID
                                Field_Name    = $($field.FieldName)
                                Notes         = "Unsupported Tag Type Manual Tag Required"
                                Action        = "Manually tag to Asset"
                                Data          = $ITGValues.values.name -join ","
                                Hudu_URL      = $UpdateAsset.HuduObject.url
                                ITG_URL       = $UpdateAsset.ITGObject.attributes."resource-url"
                            }
                            $null = $ManualActions.add($ManualLog)
                        }

                    } else {
                        if ($field.FieldType -eq "Upload") {
                            $ManualLog = [PSCustomObject]@{
                                Document_Name = $UpdateAsset.Name
                                Asset_Type    = $UpdateAsset.HuduObject.asset_type
                                Company_Name  = $UpdateAsset.HuduObject.company_name
                                HuduID        = $UpdateAsset.HuduID
                                Field_Name    = $($field.FieldName)
                                Notes         = "Uploads not supported"
                                Action        = "Manually Upload files to Related Files"
                                Data          = $ITGValues.values -join ","
                                Hudu_URL      = $UpdateAsset.HuduObject.url
                                ITG_URL       = $UpdateAsset.ITGObject.attributes."resource-url"
                            }
                            $null = $ManualActions.add($ManualLog)
                        } else {

                            if ($field.FieldType -eq "Password") {
                                $ITGPassword = (Get-ITGluePasswords -id $ITGValues -include related_items).data
				                $ITGPasswordValue = ($ITGPasswordsRaw |Where-Object {$_.id -eq $ITGPassword.id}).password
                                try {
                                    if ($ITGPasswordValue) {
                                        $NewPasswordObject = [pscustomobject]@{
                                        Name =  "$($UpdateAsset.name) $($Field.fieldname) $($ITGPassword.Username) Password"
                                        Username = $ITGPassword.Username
                                        URL = $ITGPassword.url
                                        ITGID = $ITGPassword.id
                                        Description = $ITGpassword.notes
                                        CompanyId = $UpdateAsset.HuduObject.company_id
                                        Password = $ITGPasswordValue};
                                        $null = $AssetFields.add("$($field.HuduParsedName)", $ITGPasswordValue)
                                        $MigratedPasswordStatus = "Into Asset"
                                        }
                                    } catch {
                                    Write-Host "Error occured adding field, possible duplicate name" -ForegroundColor Red
                                    $ManualLog = [PSCustomObject]@{
                                        Document_Name = $UpdateAsset.Name
                                        Asset_Type    = "Asset Field"
                                        Company_Name  = $UpdateAsset.HuduObject.company_name
                                        HuduID        = $UpdateAsset.HuduID
                                        Field_Name    = "$field.HuduParsedName"
                                        Notes         = "Failed to add password to Asset"
                                        Action        = "Manually add the password to the asset"
                                        Data          = ($ITGPassword.attributes.'resource-url' -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')                                        
                                        Hudu_URL      = $UpdateAsset.HuduObject.url
                                        ITG_URL       = $UpdateAsset.ITGObject.attributes.'resource-url'
                                    }
                                    $null = $ManualActions.add($ManualLog)
                                    $MigratedPasswordStatus = "Failed to add"
                                }
                                $MigratedPassword = [PSCustomObject]@{
                                    "Name"      = $ITGPassword.attributes.name
                                    "ITGID"     = $ITGPassword.id
                                    "HuduID"    = $UpdateAsset.HuduID
                                    "Matched"   = $true
                                    "ITGObject" = $ITGPassword
                                    "Imported"  = $MigratedPasswordStatus
                                }
                                $null = $MatchedAssetPasswords.add($MigratedPassword)
                            } else {
                                if ($CurrentVersion  -eq [version]"2.37.1") {
                                    # This version won't cast doubles for 'number' fields. It expects only integers.
                                    $coerced = Get-CastIfNumeric ($_.value -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')
                                    $null = $AssetFields.add("$($field.HuduParsedName)", $coerced)
                                }  else {
                                    $null = $AssetFields.add("$($field.HuduParsedName)", ($_.value -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]'))
                                }
                            }
                        }
                    }

                } else {
                    Write-Host "Warning $ITGParsed : $ITGValues Could not be added" -ForegroundColor Red
                }
            }

            $UpdatedHuduAsset = (Set-HuduAsset -asset_id $UpdateAsset.HuduID -name $UpdateAsset.name -company_id $($UpdateAsset.HuduObject.company_id) -asset_layout_id $UpdateAsset.HuduObject.asset_layout_id -fields $AssetFields).asset

            $UpdateAsset.HuduObject = $UpdatedHuduAsset
            $UpdateAsset.Imported = "Created-By-Script"
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

    if ($ImportArticles -eq $true) {

        if ($GlobalKBFolder -in ('y','yes','ye')) {
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

        # First lets find each article in the file system and then create blank stubs for them all so we can match relations later
        $MatchedArticles = Foreach ($doc in $ITGDocuments) {
            Write-Host "Starting $($doc.name)" -ForegroundColor Green
            $dir = $files | Where-Object { $_.PSIsContainer -eq $true -and $_.Name -match $doc.locator }
            $RelativePath = ($dir.FullName).Substring($ITGDocumentsPath.Length)
            $folders = $RelativePath -split '\\'
            $FilenameFromFolder = ($folders[$folders.count - 1] -split ' ', 2)[1]
            $Filename = $FilenameFromFolder

            $pathtest = Test-Path -LiteralPath "$($dir.Fullname)\$($filename).html"

            if ($pathtest -eq $false) {
                $filename = $doc.name
                $pathtest = Test-Path -LiteralPath "$($dir.Fullname)\$($filename).html"
                if ($pathtest -eq $false) {
                    $filename = $FilenameFromFolder -replace '_', '$1,$2'
                    $pathtest = Test-Path -LiteralPath "$($dir.Fullname)\$($filename).html"
                    if ($pathtest -eq $false) {
                        Write-Host "Not Found $($dir.Fullname)\$($filename).html this article will need to be migrated manually" -foregroundcolor red
                        continue
                    }
                }
	
            }


            $company = $MatchedCompanies | where-object -filter { $_.CompanyName -eq $doc.organization }
            if (($company | Measure-Object).count -eq 1) {

                $art_folder_id = $null
                if ($company.InternalCompany -eq $false) {
                    if (($folders | Measure-Object).count -gt 2) {
                        # Make / Check Folders

                        $art_folder_id = (Initialize-HuduFolder $folders[1..$($folders.count - 2)] -company_id $company.HuduID).id
                    }
                    $ArticleSplat = @{
                        name       = $doc.name
                        content    = "Migration in progress"
                        company_id = $company.HuduID
                        folder_id  = $art_folder_id
                    }	
                } else {
                    if (($folders | Measure-Object).count -gt 2) {
                        # Make / Check Folders
                        $folders = $folders[1..$($folders.count - 2)]
                        if ($GlobalKBFolder) {
                            $folders = @($GlobalKBFolder.name) + $folders
                        }
                        $art_folder_id = (Initialize-HuduFolder $folders).id
                    }
                    else {
                        # Check for GlobalKB Folder being set
                        if ($GlobalKBFolder) {
                            $art_folder_id = $GlobalKBFolder.id
                        }
                    }
                    $ArticleSplat = @{
                        name      = $doc.name
                        content   = "Migration in progress"
                        folder_id = $art_folder_id
                    }	
                }
		



            } else {
                Write-Host "Company $($doc.organization) Not Found Please migrate $($doc.name) manually"
                continue
            }


            $NewArticle = (New-HuduArticle @ArticleSplat).article
            if ($company.InternalCompany -eq $false) {
                Write-Host "Article created in $($company.CompanyName)"
            } else {
                Write-Host "Article created in GlobaL KB"
            }


            [PSCustomObject]@{
                "Name"       = $doc.name
                "Filename"   = $Filename
                "Path"       = $($dir.Fullname)
                "FullPath"   = "$($dir.Fullname)\$($filename).html"
                "ITGID"      = $doc.id
                "ITGLocator" = $doc.locator
                "HuduID"     = $NewArticle.ID
                "HuduObject" = $NewArticle
                "Folders"    = $folders
                "Imported"   = "Stub-Created"
                "Company"    = $company
            }

	

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
        $Attachfiles = Get-ChildItem (Join-Path -Path $ITGLueExportPath -ChildPath "attachments\documents") -recurse

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

                $ManualLog = [PSCustomObject]@{
                    Document_Name = $Article.Name
                    Asset_Type    = "Article"
                    Company_Name  = $Article.HuduObject.company_name
                    HuduID        = $Article.HuduID
                    Field_Name    = "N/A"
                    Notes         = "Attached Files not Supported"
                    Action        = "Manually Upload files to Related Files"
                    Data          = $attachdir.fullname
                    Hudu_URL      = $Article.HuduObject.url
                    ITG_URL       = "$ITGURL/$($Article.ITGLocator)"
                }
                $null = $ManualActions.add($ManualLog)

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

                $images | ForEach-Object {
                    
                    
                    if (($_.src -notmatch '^http[s]?://') -or ($_.src -match [regex]::Escape($ITGURL))) {
                        $script:HasImages = $true
                        $imgHTML = $_.outerHTML
                        Write-Host "Processing HTML: $imgHTML"
                        if ($_.src -match [regex]::Escape($ITGURL)) {
                            $matchedImage = Update-StringWithCaptureGroups -inputString $imgHTML -type 'img' -pattern $ImgRegexPatternToMatch
                            if ($matchedImage) {
                                $tnImgUrl = $matchedImage.url
                                $tnImgPath = $matchedImage.path
                            } else {
                                $tnImgPath = $_.src
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
                            Asset_Type    = "Article"
                            Company_Name  = $Article.Company.CompanyName
                            HuduID        = $Article.HuduID
                            Notes = 'Missing image, file not found'
                            Actions = "Neither $fullImgPath or $tnImgPath were found, validate the images exist in the export, or retrieve them from ITGlue directly"
                            Data = "$InFile"
                            Hudu_URL = $Article.HuduObject.url
			    ITG_URL = "$ITGURL/$($Article.ITGLocator)"
                            }

                            $null = $ManualActions.add($ManualLog)

                    }

                        # Test the path to ensure that a file extension exists, if no file extension we get problems later on. We rename it if there's no ext.
                        if ($imagePath -and (Test-Path $imagePath -ErrorAction SilentlyContinue)) {
                            if ((Get-Item -path $imagePath).extension -eq '') {
                                Write-Warning "$imagePath is undetermined image. Testing..."
                                if ($Magick = New-Object ImageMagick.MagickImage($imagePath)) {
                                    $OriginalFullImagePath = $imagePath
                                    $imagePath = "$($imagePath).$($Magick.format)"
                                    $MovedItem = Move-Item -Path $OriginalFullImagePath -Destination $imagePath
                                }
                            }                        
                            $imageType = Invoke-ImageTest($imagePath)
                            if ($imageType) {
                                Write-Host "Uploading new image"
                                try {
                                    $UploadImage = New-HuduPublicPhoto -FilePath "$imagePath" -record_id $Article.HuduID -record_type 'Article'
                                    $NewImageURL = $UploadImage.public_photo.url.replace($HuduBaseDomain, '')
                                    $ImgLink = $html.Links | Where-Object {$_.innerHTML -eq $imgHTML}
                                    Write-Host "Setting image to: $NewImageURL"
                                    $_.src = [string]$NewImageURL
                                    
                                    # Update Links for this image
                                    $ImgLink.href = [string]$NewImageUrl

                                }
                                catch {
                                    $ManualLog = [PSCustomObject]@{
                                        Document_Name = $Article.Name
                                        Asset_Type    = "Article"
                                        Company_Name  = $Article.Company.CompanyName
                                        HuduID        = $Article.HuduID
                                        Notes = 'Failed to Upload to Backend Storage'
                                        Action = "$imagePath failed to upload to Hudu backend with error $_`n Validate that uploads are working and you still have disk space."
                                        Data = "$InFile"
                                        Hudu_URL = $Article.HuduObject.url
					ITG_URL = "$ITGURL/$($Article.ITGLocator)"
                                    }

                                    $null = $ManualActions.add($ManualLog)
                                }

                                if ($Magick -and $MovedItem) {
                                    Move-Item -Path $imagePath -Destination $OriginalFullImagePath
                                }
        
                            }
                            else {

                                $ManualLog = [PSCustomObject]@{
                                    Document_Name = $Article.Name
                                    Asset_Type    = "Article"
                                    Company_Name  = $Article.Company.CompanyName
                                    HuduID        = $Article.HuduID
                                    Notes       = 'Image Not Detected'
                                    Action         = "$imagePath not detected as image, validate the identified file is an image, or imagemagick modules are loaded"        
                                    Data = "$InFile"
                                    Hudu_URL = $Article.HuduObject.url
				    ITG_URL = "$ITGURL/$($Article.ITGLocator)"
                                }

                                $null = $ManualActions.add($ManualLog)

                            }
                        }
                        else {
                            Write-Warning "Image $tnImgUrl file is missing"
                            $ManualLog = [PSCustomObject]@{
                                    Document_Name = $Article.Name
                                    Asset_Type    = "Article"
                                    Company_Name  = $Article.Company.CompanyName
				    Field_Name = 'N/A'
                                    HuduID        = $Article.HuduID
                                    Notes       = 'Image File Missing'
                                    Action         = "$tnImgUrl is not present in export,validate the image exists in ITGlue and manually replace in Hudu"   
                                    Data = "$InFile"
                                    Hudu_URL = $Article.HuduObject.url
				    ITG_URL = "$ITGURL/$($Article.ITGLocator)"
                                }

                                $null = $ManualActions.add($ManualLog)
                        }
                    }
                }
            
                $page_Source = $html.documentelement.outerhtml
                $page_out = [regex]::replace($page_Source , '\xa0+', ' ')
                        
            }
        
            if ($page_out -eq '') {
                $page_out = 'Empty Document in IT Glue Export - Please Check IT Glue'
                $ManualLog = [PSCustomObject]@{
                    Document_Name   = $Article.name
                    Asset_Type      = 'Article'
		    Company_Name = $Article.Company.CompanyName
		    Field_Name	   = 'N/A'
		    HuduID = $Article.HuduID                    
		    Notes       = 'Empty Document'
		    Action	  = 'Validate the document is blank in ITGlue, or manually copy the content across. Note that embedded documents in ITGlue will be migrated in blank with an attachment of the original doc'
                    Data          = "$InFile"
                    Hudu_URL = $Article.HuduObject.url
		    ITG_URL = "$ITGURL/$($Article.ITGLocator)"
                }

                $null = $ManualActions.add($ManualLog)
            }
			
				
            if ($_.company.InternalCompany -eq $false) {
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

    #Import Passwords
    Write-Host "Fetching Passwords from IT Glue" -ForegroundColor Green
    $PasswordSelect = { (Get-ITGluePasswords -page_size 1000 -page_number $i).data }

    $ITGPasswords = Import-ITGlueItems -ItemSelect $PasswordSelect -MigrationName 'Passwords'

    if ($ScopedMigration) {
        $OriginalPasswordsCount = $($ITGPasswords.count)
        Write-Host "Setting passwords to those in scope..." -foregroundcolor Yellow        
        $ITGPasswords         = $ITGPasswords | Where-Object { $ScopedITGCompanyIds -contains $_.attributes.'organization-id' }
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
                                    Asset_Type    = "Asset password field"
                                    Company_Name  = $unmatchedPassword.ITGObject."organization-name"
                                    HuduID        = $unmatchedPassword.HuduID
                                    Notes         = "Password from FA Field not found."
                                    Action        = "Manually create password"
                                    Data          = "Type: $($unmatchedPassword.ITGObject.attributes.`"resource-type`")"
                                    Hudu_URL      = $FoundItem.HuduObject.url
                                    ITG_URL       = $unmatchedPassword.ITGObject.attributes."parent-url"
                                }
                                $null = $ManualActions.add($ManualLog)
                            } else {
                                Write-Host "Migrated with Asset: $FoundItem.HuduID"
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
                                        Asset_Type    = $unmatchedPassword.HuduObject.asset_type
                                        Company_Name  = $unmatchedPassword.HuduObject.company_name
                                        HuduID        = $unmatchedPassword.HuduID
                                        Notes         = "Password could not be related."
                                        Action        = "Manually relate password"
                                        Data          = "Type: $($unmatchedPassword.ITGObject.attributes.`"resource-type`")"
                                        Hudu_URL      = $unmatchedPassword.HuduObject.url
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
                                    Write-Host "Could not find asset to Match. ParentID: $($unmatchedPassword.ITGObject.attributes.`"resource-id`")"
                                    $ManualLog = [PSCustomObject]@{
                                        Document_Name = $unmatchedPassword.ITGObject.attributes.name
                                        Field_Name    = "N/A"
                                        Asset_Type    = $unmatchedPassword.HuduObject.asset_type
                                        Company_Name  = $unmatchedPassword.HuduObject.company_name
                                        HuduID        = $unmatchedPassword.HuduID
                                        Notes         = "Password could not be related."
                                        Action        = "Manually relate password"
                                        Data          = "Type: $($unmatchedPassword.ITGObject.attributes.`"resource-type`")"
                                        Hudu_URL      = $unmatchedPassword.HuduObject.url
                                        ITG_URL       = $unmatchedPassword.ITGObject.attributes."parent-url"
                                    }
                                    $null = $ManualActions.add($ManualLog)
                                }
                            }
                        }
                    }
					
                    if (!($($unmatchedPassword.ITGObject.attributes."resource-type") -eq "flexible-asset-traits")) {

                        $validated_otp = "$($unmatchedPassword.ITGObject.attributes.otp_secret)".Trim().ToUpper()

                        $isValidBase32 = $validated_otp -match '^[A-Z2-7]+$'
                        $lengthOK = $validated_otp.Length -ge 16 -and $validated_otp.Length -le 80

                        $validated_otp = if ($isValidBase32 -and $lengthOK) { $validated_otp } else { $null }

                        if (-not ($isValidBase32 -and $lengthOK)) {
                            Write-Warning "Invalid OTP secret for $($unmatchedPassword.ITGObject.attributes.name): $($unmatchedPassword.ITGObject.attributes.otp_secret)... valid base32? $isValidBase32 length ok? $lengthOK (min / max is 16 / 80 chars)"
                        }
                        $passwordRaw = "$($unmatchedPassword.ITGObject.attributes.password)"
                        $PasswordSplat = @{
                            name              = "$($unmatchedPassword.ITGObject.attributes.name)"
                            company_id        = $company.HuduCompanyObject.ID
                            description       = $unmatchedPassword.ITGObject.attributes.notes
                            passwordable_type = $PasswordableType
                            passwordable_id   = $ParentItemID
                            in_portal         = $false
                            password          = $unmatchedPassword.ITGObject.attributes.password
                            username          = $unmatchedPassword.ITGObject.attributes.username
                            otpsecret         = $validated_otp

                        }
                        if ([string]::IsNullOrWhiteSpace($passwordRaw) -or $passwordRaw.Length -lt 1) {                            
                            $manualActions.add([PSCustomObject]@{
                                name              = "$($unmatchedPassword.ITGObject.attributes.name)"
                                company_id        = $company.HuduCompanyObject.ID
                                description       = $unmatchedPassword.ITGObject.attributes.notes
                                passwordable_type = $PasswordableType
                                passwordable_id   = $ParentItemID
                                in_portal         = $false
                                password          = ""
				Hudu_URL      	  = $unmatchedPassword.HuduObject.url
                                ITG_URL           = $unmatchedPassword.ITGObject.attributes.url
				username          = $unmatchedPassword.ITGObject.attributes.username
                                otpsecret         = "removed for security purposes"
                                problem           = "password was null or empty"
                            })
                            $unmatchedPassword.matched = $false
                            Write-host "$($HuduNewPassword.Name) Has been skipped and added to manual actions due to being empty"                            
                        } else {
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

############################### Generate Manual Actions Report ###############################

$ManualActions | ForEach-Object {
    if ($_.Hudu_URL -notmatch "http:" -and $_.Hudu_URL -notmatch "https:") {
        $_.Hudu_URL = "$HuduBaseDomain$($_.Hudu_URL)"
    }
}


$Head = @"
<html>
<head>
<Title>Manual Actions Required Report</Title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.0.1/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-+0n0xVW2eSR5OomGNYDnhzAbDsOXxcvSN1TPprVMTNDbiYZCxYbOOl7+AMvyTG2x" crossorigin="anonymous">
<style type="text/css">
<!–
body {
    font-family: Verdana, Geneva, Arial, Helvetica, sans-serif;
}
h2{ clear: both; font-size: 100%;color:#354B5E; }
h3{
    clear: both;
    font-size: 75%;
    margin-left: 20px;
    margin-top: 30px;
    color:#475F77;
}
table{
	border-collapse: collapse;
	margin: 5px 0;
	font-size: 0.8em;
	font-family: sans-serif;
	min-width: 400px;
	box-shadow: 0 0 20px rgba(0, 0, 0, 0.15);
}

th, td {
	padding: 5px 5px;
	max-width: 400px;
	width:auto;
}
thead tr {
	background-color: #009879;
	color: #ffffff;
	text-align: left;
}
tr {
	border-bottom: 1px solid #dddddd;
}
tr:nth-of-type(even) {
	background-color: #f3f3f3;
}
->
</style>
</head>
<body>
<div style="padding:40px">


"@


$MigrationReport = @"
<h1> Migration Report </h1>
Started At: $ScriptStartTime <br />
Completed At: $(Get-Date -Format "o") <br />
$(($MatchedCompanies | Measure-Object).count) : Companies Migrated <br />
$(($MatchedLocations | Measure-Object).count) : Locations Migrated <br />
$(($MatchedWebsites | Measure-Object).count) : Websites Migrated <br />
$(($MatchedConfigurations | Measure-Object).count) : Configurations Migrated <br />
$(($MatchedContacts | Measure-Object).count) : Contacts Migrated <br />
$(($MatchedLayouts | Measure-Object).count) : Layouts Migrated <br />
$(($MatchedAssets | Measure-Object).count) : Assets Migrated <br />
$(($MatchedArticles | Measure-Object).count) : Articles Migrated <br />
$(($MatchedPasswords | Measure-Object).count) : Passwords Migrated <br />
If you found this script useful please consider sponsoring me at: <a href=https://github.com/sponsors/lwhitelock?frequency=one-time>https://github.com/sponsors/lwhitelock?frequency=one-time</a>
<hr>
<h1>Manual Actions Required Report</h1>
"@

$footer = "</div></body></html>"

$UniqueItems = $ManualActions | Select-Object huduid, hudu_url -unique

$ManualActionsReport = foreach ($item in $UniqueItems) {
    $items = $ManualActions | where-object { $_.huduid -eq $item.huduid -and $_.hudu_url -eq $item.Hudu_url }
    $core_item = $items | Select-Object -First 1
    $Header = "<h2><strong>Name: $($core_item.Document_Name)</strong></h2>
				<h2>Type: $($core_item.Asset_Type)</h2>
				<h2>Company: $($core_item.Company_name)</h2>
				<h2>Hudu URL: <a href=$($core_item.Hudu_URL)>$($core_item.Hudu_URL)</a></h2>
				<h2>IT Glue URL: <a href=$($core_item.ITG_URL)>$($core_item.ITG_URL)</a></h2>
				"
    $Actions = $items | Select-Object Field_Name, Notes, Action, Data | ConvertTo-Html -fragment | Out-String

    $OutHTML = "$Header $Actions <hr>"

    $OutHTML

}

$FinalHtml = "$Head $MigrationReport $ManualActionsReport $footer"
$FinalHtml | Out-File ManualActions.html



############################### End ###############################


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
Write-TimedMessage -Message "Press any key to view the manual actions report or Ctrl+C to end" -Timeout 120  -DefaultResponse "continue, view generative Manual Actions webpage, please."

Start-Process ManualActions.html
