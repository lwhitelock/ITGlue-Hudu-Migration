#
# Please Read the blog post at https://mspp.io/itglue-to-hudu-migration-script/ before running this script
#
# References
# Determine image type https://devblogs.microsoft.com/scripting/psimaging-part-1-test-image/
# Parsing HTML https://stackoverflow.com/questions/28497902/finding-img-tags-in-html-files-in-powershell
# Nice Base64 conversion https://www.aaron-powell.com/posts/2010-11-07-base64-encoding-images-with-powershell/


############################### Settings ###############################
############################### API Settings ###############################

# Hudu
# Get a Hudu API Key from https://yourhududomain.com/admin/api_keys
$HuduAPIKey = "ABCDEFGHIJK123456"
# Set the base domain of your Hudu instance without a trailing /
$HuduBaseDomain = "https://your.hududomain.com"

# IT Glue - MAKE SURE TO USE AN API KEY WITH PASSWORD ACCESS
$ITGAPIEndpoint = "https://api.eu.itglue.com"
$ITGKey = "ITG.123455677890ABCDEFGHJKIL"

#Enter your primary IT Glue internal URL
$ITGURL = "https://yourdomain.eu.itglue.com"

# IT Glue Internal Company Name (The documents from this company will be migrated to the Global KB)
$InternalCompany = "Internal Company"

############################### Core Settings ###############################
# This should point to the folder where you extracted your IT Glue export
$ITGLueExportPath = "c:\temp\itglue\export\"

# Choose if you want to resume previous attempts from the last successful section
$ResumePrevious = $true

############################### Company Settings ###############################
$ImportCompanies = $true

############################### Location Settings ###############################
$ImportLocations = $true

# The asset layout name how locations will appear in Hudu
$LocImportAssetLayoutName = "Locations"

# The font awesome name for the locations icon in Hudu
$LocImportIcon = "fas fa-building"

# Here set two arrays of the different names you have used to identify the primary location in both ITGlue And Hudu
$ITGPrimaryLocationNames = @("Primary Address", "Main", "Head Office", "Main Office")
$HuduPrimaryLocationNames = @("Primary Address")

############################### Domain / Website Settings ###############################
$ImportDomains = $true

# Choose if you would like to enable monitoring for the imported websites.
$EnableWebsiteMonitoring = "false"

############################### Configuration Settings ###############################
$ImportConfigurations = $true

# The font awesome name for the locations icon in Hudu
$ConfigImportIcon = "fas fa-sitemap"

# Set if you would like a Prefix in front of configuration names created in Hudu. This can make it easy to review and you can rename them later set to "" if you dont want one
$ConfigurationPrefix = "ITGlue-"

############################### Contact Settings ###############################
$ImportContacts = $true

# The asset layout name how locations will appear in Hudu
$ConImportAssetLayoutName = "People"

# The font awesome name for the locations icon in Hudu
$ConImportIcon = "fas fa-users"

############################### Flexible Asset Layouts ###############################
$ImportFlexibleAssetLayouts = $true

# Set if you would like a Prefix in front of Layout names created in Hudu. This can make it easy to review and you can rename them later set to "" if you don't want one
$FlexibleLayoutPrefix = "ITGlue-"

############################### Flexible Assets ###############################
$ImportFlexibleAssets = $true

############################### Articles ###############################
$ImportArticles = $true

############################### Passwords ###############################
$ImportPasswords = $true

############################### End of Settings ###############################



############################### Functions ###############################

############################### Used to get the Base64 encoded version of a file
function ConvertToBase64 {
    Param([String]$path)
    [convert]::ToBase64String((get-content -LiteralPath $path -AsByteStream -raw))
}

############################### Used to determine if a file is an image and what type of image
function TestImage {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('PSPath')]
        [string] $Path
    )

    PROCESS {

        $knownHeaders = @{
            jpg = @( "FF", "D8" );
            bmp = @( "42", "4D" );
            gif = @( "47", "49", "46" );
            tif = @( "49", "49", "2A" );
            png = @( "89", "50", "4E", "47", "0D", "0A", "1A", "0A" );
            pdf = @( "25", "50", "44", "46" );
        }

        # coerce relative paths from the pipeline into full paths

        if ($_ -ne $null) {
            $Path = $_.FullName
        }

        # read in the first 8 bits
        $bytes = Get-Content -LiteralPath $Path -AsByteStream -ReadCount 1 -TotalCount 8 -ErrorAction Ignore
        $retval = 'NONIMAGE'
        
        foreach ($key in $knownHeaders.Keys) {
            # make the file header data the same length and format as the known header
            $fileHeader = $bytes |
            Select-Object -First $knownHeaders[$key].Length |
            ForEach-Object { $_.ToString("X2") }
            if ($fileHeader.Length -eq 0) {
                continue
            }
            # compare the two headers
            $diff = Compare-Object -ReferenceObject $knownHeaders[$key] -DifferenceObject $fileHeader
            if (($diff | Measure-Object).Count -eq 0) {
                $retval = $key
            }
        }
        return $retval
    }
}


############################### Confirm Object Import
function Confirm-Import {
    param(
        [string]$ImportObjectName,
        [PSCustomObject]$ImportObject,
        [String]$ImportSetting
    )
    if ($ImportSetting -eq "S") {
        $ImportConfirm = Read-Host "Would you like to migrate: $ImportObjectName Y/n"
        if ($ImportConfirm -ne "Y" -or $ImportConfirm -ne "y") {
            Write-Host "$ImportObjectName has been skipped"
            $ImportObject.imported = "Not-Migrated"
            continue
        }	
    }
}

############################### Matches items from IT Glue to Hudu and creates new items in Hudu
function Import-Items {
    Param(
        $AssetFieldsMap,
        $AssetLayoutFields,
        $ImportIcon,
        $ImportEnabled,
        $HuduItemFilter,
        $ImportAssetLayoutName,
        $ItemSelect,
        $MigrationName,
        $ITGImports
    )


    $ImportsMigrated = 0

    $ImportLayout = $null
	
    Write-Host "Processing $ImportAssetLayoutName"

    # Lets try to match itemss
    $ImportLayout = Get-HuduAssetLayouts -name $ImportAssetLayoutName
	
    if ($ImportLayout) {
		
        $HuduImports = Get-HuduAssets -assetlayoutid $ImportLayout.id
        Write-Host "$MigrationName layout found attempting to match existing entries"
        $MatchedImports = foreach ($itgimport in $ITGImports ) {

            $HuduImport = $HuduImports | where-object -filter $HuduItemFilter
			
	
            if ($HuduImport) {
                [PSCustomObject]@{
                    "Name"        = $itgimport.attributes.name
                    "CompanyName" = $itgimport.attributes."organization-name"
                    "ITGID"       = $itgimport.id
                    "HuduID"      = $HuduImport.id
                    "Matched"     = $true
                    "HuduObject"  = $HuduImport
                    "ITGObject"   = $itgimport
                    "Imported"    = "Pre-Existing"
					
                }
            }
            else {
                [PSCustomObject]@{
                    "Name"        = $itgimport.attributes.name
                    "CompanyName" = $itgimport.attributes."organization-name"
                    "ITGID"       = $itgimport.id
                    "HuduID"      = ""
                    "Matched"     = $false
                    "HuduObject"  = ""
                    "ITGObject"   = $itgimport
                    "Imported"    = ""
                }
            }
        }
    }
    else {
        $MatchedImports = foreach ($itgimport in $ITGImports ) {
            [PSCustomObject]@{
                "Name"        = $itgimport.attributes.name
                "CompanyName" = $itgimport.attributes."organization-name"
                "ITGID"       = $itgimport.id
                "HuduID"      = ""
                "Matched"     = $false
                "HuduObject"  = ""
                "ITGObject"   = $itgimport
                "Imported"    = ""
            }
		
        }

    }
	
    Write-Host "Matched $MigrationName (Already exist so will not be migrated)"
    Write-Host $($MatchedImports | Sort-Object CompanyName | Where-Object { $_.Matched -eq $true } | Select-Object CompanyName, Name | Format-Table | Out-String)
	
    Write-Host "Unmatched $MigrationName"
    Write-Host $($MatchedImports | Sort-Object CompanyName | Where-Object { $_.Matched -eq $false } | Select-Object CompanyName, Name | Format-Table | Out-String)
	
    # Import Items
    $UnmappedImportCount = ($MatchedImports | Where-Object { $_.Matched -eq $false } | measure-object).count
    if ($ImportEnabled -eq $true -and $UnmappedImportCount -gt 0) {
		
        if (!$ImportLayout) { 
            Write-Host "Creating New Asset Layout $ImportAssetLayoutName"
            $Null = New-HuduAssetLayout -name $ImportAssetLayoutName -icon $ImportIcon -color "#6e00d5" -icon_color "#ffffff" -include_passwords $true -include_photos $true -include_comments $true -include_files $true -fields $AssetLayoutFields
            $ImportLayout = Get-HuduAssetLayouts -name $ImportAssetLayoutName
		
        }
	
        $ImportOption = Get-ImportMode -ImportName $MigrationName
	
        if (($importOption -eq "A") -or ($importOption -eq "S") ) {		
	
            foreach ($company in $CompaniesToMigrate) {
                Write-Host "Migrating $($company.CompanyName) $MigrationName"
	
                foreach ($unmatchedImport in ($MatchedImports | Where-Object { $_.Matched -eq $false -and $company.ITGCompanyObject.id -eq $_."ITGObject".attributes."organization-id" })) {
	
                    $AssetFields = & $AssetFieldsMap

					

                    Confirm-Import -ImportObjectName "$($unmatchedImport.Name): $($AssetFields | Out-String)" -ImportObject $unmatchedImport -ImportSetting $ImportOption
	
                    Write-Host "Starting $($unmatchedImport.Name)"
	
                    $HuduAssetName = $($unmatchedImport.Name)
					
                    $HuduNewImport = (New-HuduAsset -name $HuduAssetName -company_id $company.HuduCompanyObject.ID -asset_layout_id $ImportLayout.id -fields $AssetFields).asset
	
                    $unmatchedImport.matched = $true
                    $unmatchedImport.HuduID = $HuduNewImport.id
                    $unmatchedImport."HuduObject" = $HuduNewImport
                    $unmatchedImport.Imported = "Created-By-Script"
	
                    $ImportsMigrated = $ImportsMigrated + 1
	
                    Write-host "$($unmatchedImport.Name) Has been created in Hudu"
                    Write-Host ""
                }
            }
        }
			
	
    }
    else {
        if ($UnmappedImportCount -eq 0) {
            Write-Host "All $MigrationName matched, no migration required" -foregroundcolor green
        }
        else {
            Write-Host "Warning Import $MigrationName is set to disabled so the above unmatched $MigrationName will not have data migrated" -foregroundcolor red
            Read-Host -Prompt "Press any key to continue or CTRL+C to quit" 
        }
    }
	
    Return $MatchedImports

}

############################### Select Item Import Mode
function Get-ImportMode {
    param(
        [string]$ImportName
    )
    Write-Host "Importing $ImportName"
    $ImportOption = Read-Host "[A] Import All unmapped $ImportName. [N] Import None of the unmapped $ImportName. [S] Select for each individual $ImportName (A/N/S)"
    if (!($ImportOption -in @("A", "N", "S"))) {
        Write-Host "Please select A, N or S"
        $ImportOption = Get-ImportMode -ImportName $ImportName
    }
		
    return $ImportOption
}

############################### Get Configurations Option
function Get-ConfigurationsImportMode {
    $ImportOption = Read-Host "[1] [2] [3]"
    if (!($ImportOption -in @(1, 2, 3))) {
        Write-Host "Please select 1, 2 or 3"
        $ImportOption = Get-ConfigurationsImportMode -ImportName $ImportName
    }
		
    return $ImportOption
}

############################### Get Flexible Asset Layout Option
function Get-FlexLayoutImportMode {
    $ImportOption = Read-Host "[1] [2]"
    if (!($ImportOption -in @(1, 2))) {
        Write-Host "Please select 1 or 2"
        $ImportOption = Get-FlexLayoutImportMode -ImportName $ImportName
    }
		
    return $ImportOption
}



############################### Fetch Items from ITGlue
function Import-ITGlueItems {
    Param(
        $ItemSelect
    )
    $i = 1
    $ITGImports = do {
        $itgimport = & $ItemSelect
        $i++
        $itgimport
        Write-Host "Retrieved $($itgimport.count) $MigrationName" -ForegroundColor Yellow
    }while ($itgimport.count % 1000 -eq 0 -and $itgimport.count -ne 0)
    return $ITGImports
}

############################### Fetch Items from ITGlue
function Find-MigratedItem {
    param (
        $ITGID
    )

    $FoundItem = $MatchedAssets | Where-Object { $_.ITGID -eq $ITGID }
	
    if (!$FoundItem) {
        $FoundItem = $MatchedContacts | Where-Object { $_.ITGID -eq $ITGID }
    }
 	
    if (!$FoundItem) {
        $FoundItem = $MatchedConfigurations | Where-Object { $_.ITGID -eq $ITGID }
    }
 	
    if (!$FoundItem) {
        $FoundItem = $MatchedLocations | Where-Object { $_.ITGID -eq $ITGID }
    }

		
    return $FoundItem

}

############################### Lookup table to upgrade from Font Awesome 4 to 5
$FontAwesomeUpgrade = [PSCustomObject]@{
    "address-book-o"       = "address-book"
    "address-card-o"       = "address-card"
    "arrow-circle-o-down"  = "arrow-alt-circle-down"
    "arrow-circle-o-left"  = "arrow-alt-circle-left"
    "arrow-circle-o-right" = "arrow-alt-circle-right"
    "arrow-circle-o-up"    = "arrow-alt-circle-up"
    "arrows"               = "arrows-alt"
    "arrows-alt"           = "expand-arrows-alt"
    "arrows-h"             = "arrows-alt-h"
    "arrows-v"             = "arrows-alt-v"
    "bell-o"               = "bell"
    "bell-slash-o"         = "bell-slash"
    "bookmark-o"           = "bookmark"
    "building-o"           = "building"
    "caret-square-o-right" = "caret-square-right"
    "check-circle-o"       = "check-circle"
    "check-square-o"       = "check-square"
    "circle-o"             = "circle"
    "circle-thin"          = "circle"
    "clipboard"            = "clipboard"
    "cloud-download"       = "cloud-download-alt"
    "cloud-upload"         = "cloud-upload-alt"
    "comment-o"            = "comment"
    "commenting"           = "comment-dots"
    "commenting-o"         = "comment-dots"
    "comments-o"           = "comments"
    "credit-card-alt"      = "credit-card"
    "cutlery"              = "utensils"
    "diamond"              = "gem"
    "envelope-o"           = "envelope"
    "envelope-open-o"      = "envelope-open"
    "exchange"             = "exchange-alt"
    "external-link"        = "external-link-alt"
    "external-link-square" = "external-link-square-alt"
    "folder-o"             = "folder"
    "folder-open-o"        = "folder-open"
    "file-o"               = "file"
    "heart-o"              = "heart"
    "hourglass-o"          = "hourglass"
    "hand-o-right"         = "hand-point-right"
    "id-card-o"            = "id-card"
    "level-down"           = "level-down-alt"
    "level-up"             = "level-up-alt"
    "long-arrow-down"      = "long-arrow-alt-down"
    "long-arrow-left"      = "long-arrow-alt-left"
    "long-arrow-right"     = "long-arrow-alt-right"
    "long-arrow-up"        = "long-arrow-alt-up"
    "map-marker"           = "map-marker-alt"
    "map-o"                = "map"
    "minus-square-o"       = "minus-square"
    "mobile"               = "mobile-alt"
    "money"                = "money-bill-alt"
    "paper-plane-o"        = "paper-plane"
    "pause-circle-o"       = "pause-circle"
    "pencil"               = "pencil-alt"
    "play-circle-o"        = "play-circle"
    "plus-square-o"        = "plus-square"
    "question-circle-o"    = "question-circle"
    "share-square-o"       = "share-square"
    "shield"               = "shield-alt"
    "sign-in"              = "sign-in-alt"
    "sign-out"             = "sign-out-alt"
    "spoon"                = "utensil-spoon"
    "square-o"             = "square"
    "star-half-o"          = "star-half"
    "star-o"               = "star"
    "sticky-note-o"        = "sticky-note"
    "stop-circle-o"        = "stop-circle"
    "tablet"               = "tablet-alt"
    "tachometer"           = "tachometer-alt"
    "thumbs-o-down"        = "thumbs-down"
    "thumbs-o-up"          = "thumbs-up"
    "ticket"               = "ticket-alt"
    "times-circle-o"       = "times-circle"
    "trash"                = "trash-alt"
    "trash-o"              = "trash-alt"
    "user-circle-o"        = "user-circle"
    "user-o"               = "user"
    "window-close-o"       = "window-close"
    "calendar"             = "calendar"
    "reply"                = "reply"
    "refresh"              = "sync-alt"
    "window-close"         = "window-close"

}




############################### End of Functions ###############################


###################### Initial Setup and Confimations ###############################
Write-Host "#######################################################" -ForegroundColor Green
Write-Host "#                                                     #" -ForegroundColor Green
Write-Host "#          IT Glue to Hudu Migration Script           #" -ForegroundColor Green
Write-Host "#                                                     #" -ForegroundColor Green
Write-Host "#          Version: 0.2 - Beta                        #" -ForegroundColor Green
Write-Host "#          Date: 2021-04-02                           #" -ForegroundColor Green
Write-Host "#                                                     #" -ForegroundColor Green
Write-Host "#          Author: Luke Whitelock                     #" -ForegroundColor Green
Write-Host "#                  https://mspp.io                    #" -ForegroundColor Green
Write-Host "#                                                     #" -ForegroundColor Green
Write-Host "#######################################################" -ForegroundColor Green
Write-Host "# Note: This is an unofficial script, please do not   #" -ForegroundColor Green
Write-Host "# contact Hudu support if you run into issues.        #" -ForegroundColor Green
Write-Host "# For support please visit the Hudu Sub-Reddit:       #" -ForegroundColor Green
Write-Host "# https://www.reddit.com/r/hudu/                      #" -ForegroundColor Green
Write-Host "# The #v-hudu channel on the MSPGeek Slack:           #" -ForegroundColor Green
Write-Host "# https://join.mspgeek.com/                           #" -ForegroundColor Green
Write-Host "# Or log an issue in the Github Respository:          #" -ForegroundColor Green
Write-Host "# https://github.com/lwhitelock/ITGlue-Hudu-Migration #" -ForegroundColor Green
Write-Host "#######################################################" -ForegroundColor Green
Write-Host "# Instructions:                                       #" -ForegroundColor Green
Write-Host "# Please view my blog post:                           #" -ForegroundColor Green
Write-Host "# https://mspp.io/itglue-to-hudu-migration-script     #" -ForegroundColor Green
Write-Host "# for detailed instructions                           #" -ForegroundColor Green
Write-Host "#######################################################" -ForegroundColor Green


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

$backups = Read-Host "Y/n"

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
if (Get-Module -ListAvailable -Name HuduAPI) {
    Import-Module HuduAPI 
}
else {
    Install-Module HuduAPI -Force
    Import-Module HuduAPI
}
  
#Login to Hudu
New-HuduAPIKey $HuduAPIKey
New-HuduBaseUrl $HuduBaseDomain

# Check we have the correct version
$RequiredHuduVersion = "2.1.5.6"
$HuduAppInfo = Get-HuduAppInfo
If ([version]$HuduAppInfo.version -lt [version]$RequiredHuduVersion) {
    Write-Host "This script requires at least version $RequiredHuduVersion. Please update your version of Hudu and run the script again. Your version is $($HuduAppInfo.version)"
    exit 1
}



#Grabbing ITGlue Module and installing.
If (Get-Module -ListAvailable -Name "ITGlueAPI") { 
    Import-module ITGlueAPIv2 
}
Else { 
    Install-Module ITGlueAPIv2 -Force
    Import-Module ITGlueAPIv2
}
#Settings IT-Glue logon information
Add-ITGlueBaseURI -base_uri $ITGAPIEndpoint
Add-ITGlueAPIKey $ITGKey

# Check if we have a logs folder
if (Test-Path -Path "MigrationLogs") {
    if ($ResumePrevious -eq $true) {
        Write-Host "A previous attempt has been found job will be resumed from the last successful section" -ForegroundColor Green
        $ResumeFound = $true
    }
    else {
        Write-Host "A previous attempt has been found, resume is disabled so this will be lost, if you haven't reverted to a snapshot, a resume is recommended" -ForegroundColor Red
        Read-Host "Press any key to continue or ctrl + c to quit and edit the ResumePrevious setting"
        $ResumeFound = $false
    }
}
else {
    Write-Host "No previous runs found creating log directory"
    $null = New-Item -Name "MigrationLogs" -ItemType "directory"
    $ResumeFound = $false
}


# Setup some variables

$ManualActions = [System.Collections.ArrayList]@()


############################### Companies ###############################

#Grab existing companies in Hudu
$HuduCompanies = Get-HuduCompanies

#Check for Company Resume
if ($ResumeFound -eq $true -and (Test-Path "MigrationLogs\Companies.json")) {
    Write-Host "Loading Previous Companies Migration"
    $MatchedCompanies = Get-Content 'MigrationLogs\Companies.json' -raw | Out-String | ConvertFrom-Json
}
else {

    #Import Companies
    Write-Host "Fetching Companies from IT Glue" -ForegroundColor Green
    $CompanySelect = { (Get-ITGlueOrganizations -page_size 1000 -page_number $i).data }
    $ITGCompanies = Import-ITGlueItems -ItemSelect $CompanySelect


    Write-Host "$($ITGCompanies.count) ITG Glue Companies Found" 
	
	
	

    $MatchedCompanies = foreach ($itgcompany in $ITGCompanies ) {
        $HuduCompany = $HuduCompanies | where-object -filter { $_.name -eq $itgcompany.attributes.name }
        if ($InternalCompany -eq $itgcompany.attributes.name) {
            $intCompany = $true
        }
        else {
            $intCompany = $false
        }
	
        if ($HuduCompany) {
            [PSCustomObject]@{
                "CompanyName"       = $itgcompany.attributes.name
                "ITGID"             = $itgcompany.id
                "HuduID"            = $HuduCompany.id
                "Matched"           = $true
                "InternalCompany"   = $intCompany
                "HuduCompanyObject" = $HuduCompany
                "ITGCompanyObject"  = $itgcompany
                "Imported"          = "Pre-Existing"
			
            }
        }
        else {
            [PSCustomObject]@{
                "CompanyName"       = $itgcompany.attributes.name
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
    Read-Host -Prompt "Press Return to continue or CTRL+C to quit if this is not correct" 

    Write-Host "Matched Companies (Already exist so will not be migrated)"
    $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.Matched -eq $true } | Select-Object CompanyName | Format-Table

    Write-Host "Unmatched Companies"
    $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.Matched -eq $false } | Select-Object CompanyName | Format-Table

    #Import Locations
    Write-Host "Fetching Locations from IT Glue" -ForegroundColor Green
    $LocationsSelect = { (Get-ITGlueLocations -page_size 1000 -page_number $i).data }
    $ITGLocations = Import-ITGlueItems -ItemSelect $LocationsSelect


    # Import Companies
    $UnmappedCompanyCount = ($MatchedCompanies | Where-Object { $_.Matched -eq $false } | measure-object).count
    if ($ImportCompanies -eq $true -and $UnmappedCompanyCount -gt 0) {
	
        $importCOption = Get-ImportMode -ImportName "Companies"
	
        if (($importCOption -eq "A") -or ($importCOption -eq "S") ) {		
            foreach ($unmatchedcompany in ($MatchedCompanies | Where-Object { $_.Matched -eq $false })) {
                Confirm-Import -ImportObjectName $unmatchedcompany.CompanyName -ImportObject $unmatchedcompany -ImportSetting $importCOption
						
                Write-Host "Starting $($unmatchedcompany.CompanyName)"
                $PrimaryLocation = $ITGLocations | Where-Object { $unmatchedcompany.ITGID -eq $_.attributes."organization-id" -and $_.attributes.primary -eq $true }
                if ($PrimaryLocation) {
                    $CompanySplat = @{
                        "name"           = $unmatchedcompany.CompanyName
                        "nickname"       = $unmatchedcompany.ITGCompanyObject.attributes."short-name"
                        "address_line_1" = $PrimaryLocation.attributes."address-1"
                        "address_line_2" = $PrimaryLocation.attributes."address-2"
                        "city"           = $PrimaryLocation.attributes.city
                        "state"          = $PrimaryLocation.attributes."region-name"
                        "zip"            = $PrimaryLocation.attributes."postal-code"
                        "country_name"   = $PrimaryLocation.attributes."country-name"
                        "phone_number"   = $PrimaryLocation.attributes.phone
                        "fax_number"     = $PrimaryLocation.attributes.fax
                        "notes"          = $unmatchedcompany.ITGCompanyObject.attributes."quick-notes"
                    }
                    $HuduNewCompany = (New-HuduCompany @CompanySplat).company
                    $CompaniesMigrated = $CompaniesMigrated + 1
                }
                else {
                    Write-Host "No Location Found, creating company without address details"
                    $HuduNewCompany = (New-HuduCompany -name $unmatchedcompany.CompanyName -nickname $unmatchedcompany.ITGCompanyObject.attributes."short-name" -notes $unmatchedcompany.ITGCompanyObject.attributes."quick-notes").company
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
		

    }
    else {
        if ($UnmappedCompanyCount -eq 0) {
            Write-Host "All Companies matched, no migration required" -foregroundcolor green
        }
        else {
            Write-Host "Warning Import Companies is set to disabled so the above unmatched companies will not have data migrated" -foregroundcolor red
            Read-Host -Prompt "Press any key to continue or CTRL+C to quit" 
        }
    }

    # Save the results to resume from if needed
    $MatchedCompanies | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\Companies.json'
    Read-Host "Snapshot Point: Companies Migrated Continue?"

}

$CompaniesToMigrate = $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.Matched -eq $true }

$HuduCompanies = Get-HuduCompanies

############################### Locations ###############################
#Check for Location Resume
if ($ResumeFound -eq $true -and (Test-Path "MigrationLogs\Locations.json")) {
    Write-Host "Loading Previous Locations Migration"
    $MatchedLocations = Get-Content 'MigrationLogs\Locations.json' -raw | Out-String | ConvertFrom-Json -depth 100
}
else {


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
    $MatchedLocations | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\Locations.json'
    Read-Host "Snapshot Point: Locations Migrated Continue?"

}


############################### Websites ###############################

#Check for Website Resume
if ($ResumeFound -eq $true -and (Test-Path "MigrationLogs\Websites.json")) {
    Write-Host "Loading Previous Websites Migration"
    $MatchedWebsites = Get-Content 'MigrationLogs\Websites.json' -raw | Out-String | ConvertFrom-Json
}
else {

    #Grab existing Websites in Hudu
    $HuduWebsites = Get-HuduWebsites

    #Import Websites
    Write-Host "Fetching Domains from IT Glue" -ForegroundColor Green
    $DomainSelect = { (Get-ITGlueDomains -page_size 1000 -page_number $i).data }
    $ITGDomains = Import-ITGlueItems -ItemSelect $DomainSelect

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
        }
        else {
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

                    Write-Host "Starting $($unmatchedWebsite.Name)"

                    $HuduNewWebsite = New-HuduWebsite -name "https://$($unmatchedWebsite.ITGObject.attributes.name)" -notes $unmatchedWebsite.ITGObject.attributes.notes -paused $EnableWebsiteMonitoring -companyid $company.HuduCompanyObject.ID -disabledns $EnableWebsiteMonitoring -disablessl $EnableWebsiteMonitoring -disablewhois $EnableWebsiteMonitoring


                    $unmatchedWebsite.matched = $true
                    $unmatchedWebsite.HuduID = $HuduNewWebsite.id
                    $unmatchedWebsite."HuduObject" = $HuduNewWebsite
                    $unmatchedWebsite.Imported = "Created-By-Script"

                    $ImportsMigrated = $ImportsMigrated + 1

                    Write-host "$($unmatchedWebsite.Name) Has been created in Hudu"
                }
            }
        }


    }
    else {
        if ($UnmappedWebsiteCount -eq 0) {
            Write-Host "All $MigrationName matched, no migration required" -foregroundcolor green
        }
        else {
            Write-Host "Warning Import Websites is set to disabled so the above unmatched Websites will not have data migrated" -foregroundcolor red
            Read-Host -Prompt "Press any key to continue or CTRL+C to quit" 
        }
    }

    # Save the results to resume from if needed
    $MatchedWebsites | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\Websites.json'
    Read-Host "Snapshot Point: Websites Migrated Continue?"

}




		
############################### Configurations ###############################
	
$ConfigMigrationName = "Configurations"
$ConfigImportAssetLayoutName = "Configurations"
	
#Check for Configuration Resume
if ($ResumeFound -eq $true -and (Test-Path "MigrationLogs\Configurations.json")) {
    Write-Host "Loading Previous Configurations Migration"
    $MatchedConfigurations = Get-Content 'MigrationLogs\Configurations.json' -raw | Out-String | ConvertFrom-Json -depth 100
}
else {

    #Get Configurations from IT Glue
    Write-Host "Fetching Configurations from IT Glue" -ForegroundColor Green
    $ConfigurationsSelect = { (Get-ITGlueConfigurations -page_size 1000 -page_number $i).data }
    $ITGConfigurations = Import-ITGlueItems -ItemSelect $ConfigurationsSelect

		
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
            'name'                      = $unmatchedImport."ITGObject".attributes."name"
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
            'created_at'                = $unmatchedImport."ITGObject".attributes."created-at"
            'updated_at'                = $unmatchedImport."ITGObject".attributes."updated-at"
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


    }
    elseif ($ConfigurationOption -eq 2) {
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
            }
            else {
                $MatchedConfigurations.add($ReturnedConfigurations)
            }

        }

	
	
    }
    elseif ($ConfigurationOption -eq 3) {
        $ITGConfigTypes = $ITGConfigurations.attributes."configuration-type-name" | Select-Object -unique
        $MatchedConfigurations = New-Object System.Collections.ArrayList

        foreach ($ConfigType in $ITGConfigTypes) {
            Write-Host ""
            Write-Host "Processing $ConfigType"
            Write-Host "Please provide the Asset Layout name for $ConfigType in Hudu." -foregroundcolor green
            $ConfigImportAssetLayoutName = Read-Host "Please enter layout name"
		

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
            $MatchedConfigurations.addrange($ReturnedConfigurations)

        }



    }
    else {
        Write-Error "This should never have happened some how you selected something other than 1, 2 or 3 :/"
        exit 1
    }

    # Save the results to resume from if needed
    $MatchedConfigurations | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\Configurations.json'
    Read-Host "Snapshot Point: Configurations Migrated Continue?"

}


############################### Contacts ###############################
#Check for Location Resume
if ($ResumeFound -eq $true -and (Test-Path "MigrationLogs\Contacts.json")) {
    Write-Host "Loading Previous Contacts Migration"
    $MatchedContacts = Get-Content 'MigrationLogs\Contacts.json' -raw | Out-String | ConvertFrom-Json -depth 100
}
else {


    Write-Host "Fetching Contacts from IT Glue" -ForegroundColor Green
    $ContactsSelect = { (Get-ITGlueContacts -page_size 1000 -page_number $i).data }
    $ITGContacts = Import-ITGlueItems -ItemSelect $ContactsSelect

    #($ITGContacts.attributes | sort-object -property name, "organization-name" -Unique)

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
    $MatchedContacts | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\Contacts.json'
    Read-Host "Snapshot Point: Contacts Migrated Continue?"

}

	
############################### Flexible Asset Layouts and Assets ###############################
#Check for Layouts Resume
if ($ResumeFound -eq $true -and (Test-Path "MigrationLogs\AssetLayouts.json")) {
    Write-Host "Loading Previous Asset Layouts Migration"
    $MatchedLayouts = Get-Content 'MigrationLogs\AssetLayouts.json' -raw | Out-String | ConvertFrom-Json -depth 100
    $AllFields = Get-Content 'MigrationLogs\AssetLayoutsFields.json' -raw | Out-String | ConvertFrom-Json -depth 100
}
else {

    $ConfigImportAssetLayoutName = ($MatchedConfigurations.HuduObject | Select-Object name, asset_type | group-object -property asset_type | sort-object count -descending | Select-Object -first 1).name

    Write-Host "Fetching Flexible Asset Layouts from IT Glue" -ForegroundColor Green
    $FlexLayoutSelect = { (Get-ITGlueFlexibleAssetTypes -page_size 1000 -page_number $i).data }
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
                "HuduID"     = $ITGLayout.id
                "Matched"    = $true
                "HuduObject" = $HuduLayout
                "ITGObject"  = $ITGLayout
                "ITGAssets"  = ""
                "Imported"   = "Pre-Existing"
			
            }
        }
        else {
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
                }
            )
		
            if ($($FontAwesomeUpgrade."$($UnmatchedLayout.ITGObject.attributes.icon)")) {
                $NewIcon = $($FontAwesomeUpgrade."$($UnmatchedLayout.ITGObject.attributes.icon)")
            }
            else {
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
            $FlexAssetsSelect = { (Get-ITGlueFlexibleAssets -page_size 1000 -page_number $i -filter_flexible_asset_type_id $UpdateLayout.ITGID).data }
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
                }
                else {
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


    $AllFields | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\AssetLayoutsFields.json'
    $MatchedLayouts | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\AssetLayouts.json'
    Read-Host "Snapshot Point: Layouts Migrated Continue?"

}

############################### Flexible Assets ###############################
#Check for Assets Resume
if ($ResumeFound -eq $true -and (Test-Path "MigrationLogs\Assets.json")) {
    Write-Host "Loading Previous Asset Migration"
    $MatchedAssets = Get-Content 'MigrationLogs\Assets.json' -raw | Out-String | ConvertFrom-Json -depth 100
    $MatchedAssetPasswords = Get-Content 'MigrationLogs\AssetPasswords.json' -raw | Out-String | ConvertFrom-Json -depth 100
    $ManualActions = [System.Collections.ArrayList](Get-Content 'MigrationLogs\ManualActions.json' -raw | Out-String | ConvertFrom-Json -depth 100)
}
else {

    if ($ImportFlexibleAssets -eq $true) {

        $MatchedAssets = [System.Collections.ArrayList]@()
        $MatchedAssetPasswords = [System.Collections.ArrayList]@()

        #We need to do a first pass creating empty assets with just the ITG migrated data. This builds an array we need to use to lookup relations when populating the entire assets

        Foreach ($Layout in $MatchedLayouts) {
            Write-Host "Creating base assets for $($layout.name)"
            foreach ($ITGAsset in $Layout.ITGAssets) {
                # Match Company
                $HuduCompanyID = ($HuduCompanies | where-object -filter { $_.name -eq $ITGAsset.attributes.'organization-name' }).id

                $AssetFields = @{ 
                    'imported_from_itglue' = Get-Date -Format "o"
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
                            "Documents" { Write-Host "Tags to SSL Certificates are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Domains" { Write-Host "Tags to Domains are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Passwords" { Write-Host "Tags to Passwords are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Locations" {
                                $LocationsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $($MatchedLocations | where-object -filter { $_.ITGID -eq $IDMatch.id } | Select-Object @{N = 'id'; E = { $_.HuduID } }, @{N = 'name'; E = { $_.Name } })
                                }
                                $ReturnData = $LocationsLinked | convertto-json -compress -AsArray | Out-String
                                $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))
											
                            }
                            "Organizations" { Write-Host "Tags to Companies are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
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

                    }
                    else {
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
                        }
                        else {

                            if ($field.FieldType -eq "Password") {
                                $ITGPassword = (Get-ITGluePasswords -id $_.value).data
                                try {						
                                    $null = $AssetFields.add("$($field.HuduParsedName)", ($ITGPassword.attributes.password -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]'))
                                }
                                catch {
                                    Write-Host "Error occured adding field, possible duplicate name" -ForegroundColor Red
                                }
                                $MigratedPassword = [PSCustomObject]@{
                                    "Name"      = $ITGPassword.attributes.name
                                    "ITGID"     = $ITGPassword.id
                                    "HuduID"    = $UpdateAsset.HuduID
                                    "Matched"   = $true
                                    "ITGObject" = $ITGPassword
                                    "Imported"  = "Into Asset"
                                }
                                $null = $MatchedAssetPasswords.add($MigratedPassword)
                            }
                            else {
                                $null = $AssetFields.add("$($field.HuduParsedName)", ($_.value -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]'))
                            }
                        }
                    }

                }
                else {
                    Write-Host "Warning $ITGParsed : $ITGValues Could not be added" -ForegroundColor Red
                }
            }

            $UpdatedHuduAsset = (Set-HuduAsset -asset_id $UpdateAsset.HuduID -name $UpdateAsset.name -company_id $($UpdateAsset.HuduObject.company_id) -asset_layout_id $UpdateAsset.HuduObject.asset_layout_id -fields $AssetFields).asset

            $UpdateAsset.HuduObject = $UpdatedHuduAsset
            $UpdateAsset.Imported = "Created-By-Script"
        }


        $MatchedAssets | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\Assets.json'
        $MatchedAssetPasswords | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\AssetPasswords.json'
        $ManualActions | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\ManualActions.json'
        Read-Host "Snapshot Point: Assets Migrated Continue?"
    }
}


############################### Documents / Articles ###############################

#Check for Article Resume
if ($ResumeFound -eq $true -and (Test-Path "MigrationLogs\ArticleBase.json")) {
    Write-Host "Loading Article Migration"
    $MatchedArticles = Get-Content 'MigrationLogs\ArticleBase.json' -raw | Out-String | ConvertFrom-Json -depth 100
}
else {


    $ITGDocuments = Import-CSV -Path "$($ITGLueExportPath)documents.csv"

    $files = Get-ChildItem "$($ITGLueExportPath)Documents" -recurse

    # First lets find each article in the file system and then create blank stubs for them all so we can match relations later
    $MatchedArticles = Foreach ($doc in $ITGDocuments) {
        Write-Host "Starting $($doc.name)" -ForegroundColor Green
        $dir = $files | Where-Object { $_.PSIsContainer -eq $true -and $_.Name -match $doc.locator }
        $RelativePath = ($dir.FullName).Substring("$($ITGLueExportPath)Documents".Length)
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

			
	
	
            $art_folder_id = ''
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
            }
            else {
                if (($folders | Measure-Object).count -gt 2) {
                    # Make / Check Folders
                    $art_folder_id = (Initialize-HuduFolder $folders[1..$($folders.count - 2)]).id
                }
                $ArticleSplat = @{
                    name      = $doc.name
                    content   = "Migration in progress"
                    folder_id = $art_folder_id
                }	
            }
		



        }
        else {
            Write-Host "Company $($doc.organization) Not Found Please migrate $($doc.name) manually"
            continue
        }


        $NewArticle = (New-HuduArticle @ArticleSplat).article
        if ($company.InternalCompany -eq $false) {
            Write-Host "Article created in $($company.CompanyName)"
        }
        else {
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
    $MatchedArticles | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\ArticleBase.json'
    $ManualActions | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\ManualActions.json'
    Read-Host "Snapshot Point: Stub Articles Created Continue?"

}

############################### Documents / Articles Bodies ###############################

#Check for Articles Resume
if ($ResumeFound -eq $true -and (Test-Path "MigrationLogs\Articles.json")) {
    Write-Host "Loading Article Content Migration"
    $MatchedArticles = Get-Content 'MigrationLogs\Articles.json' -raw | Out-String | ConvertFrom-Json -depth 100
}
else {
	

    if ($ImportArticles -eq $true) {
        $Attachfiles = Get-ChildItem "$($ITGLueExportPath)attachments\documents" -recurse

        $URLLength = $ITGURL.length

        # Now do the actual work of populating the content of articles
        $ArticleErrors = foreach ($Article in $MatchedArticles) {
            # Check for attachments
            $attachdir = $Attachfiles | Where-Object { $_.PSIsContainer -eq $true -and $_.Name -match $Article.ITGID }
            if ($Attachdir) {


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
                    $imgPath = ($_.src).substring(6)
                    $basepath = split-path $InFile
                    $imagePath = "$basepath/$imgPath"
                    $imageType = TestImage($imagePath)
                    if ($imageType -ne 'NONIMAGE') {
                        $imgBase64 = ConvertToBase64($imagePath)
                        $_.src = "data:image/$imageType;base64,$imgBase64"
                    }
                    else {
                        [PSCustomObject]@{
                            ErrorType       = "Image Not Detected"
                            Details         = "$imagePath not detected as image"
                            InFile          = "$InFile"
                            MigrationObject = $Article
                        }
                    }
                }


                $links = @($html.Links)			
                foreach ($link in $links) { 
                    $LinkHref = "$($link.href)"
                    try {
                        $parsedurl = $LinkHref.SubString(0, $URLLength)
                    }
                    catch {
                        continue
                    }
                    if ($parsedurl.ToLower() -eq $ITGURL.ToLower()) {
                        $ITGPath = $LinkHref.SubString($URLLength + 1)
                        # Handle Documents Linked with their locator
                        if ($ITGPath.substring(0, 3) -eq 'DOC') {
                            $HuduPath = ($MatchedArticles | Where-Object -filter { $_.ITGLocator -eq $ITGPath }).HuduObject.url
                        }
                        else {
                            if ($ITGPath.substring(0, 11) -eq 'attachments') {
                                $ManualLog = [PSCustomObject]@{
                                    Document_Name = $Article.name
                                    Field_Name    = "N/A"
                                    Asset_Type    = $Article.HuduObject.asset_type
                                    Company_Name  = $Article.HuduObject.company_name
                                    HuduID        = $Article.HuduID
                                    Notes         = "Link to Document attachment."
                                    Action        = "Manually upload document and relink"
                                    Data          = "$LinkHref"
                                    Hudu_URL      = "$($HuduBaseDomain)$($Article.HuduObject.url)"
                                    ITG_URL       = "$ITGURL/$($Article.ITGLocator)"
                                }
                                $null = $ManualActions.add($ManualLog)
                                $HuduPath = ""
                            }
                            else {
                                # Handle Documents linked manually via their edit URL
                                $ITGlueID = (($ITGPath.split('/'))[2]).split('#')[0]
                                $HuduPath = ($MatchedArticles | Where-Object -filter { $_.ITGID -eq $ITGlueID }).HuduObject.url
                            }

                        }
                        $link.href = "$($HuduBaseDomain)$($HuduPath)"
                        Write-Host "Link Rewritten to $($link.href)"

                    }
				
				
				
                }

	
                $page_Source = $html.documentelement.outerhtml
                $page_out = [regex]::replace($page_Source , '\xa0+', ' ')
				
            }

            if ($page_out -eq '') {
                $page_out = "Empty Document in IT Glue Export - Please Check IT Glue"
                [PSCustomObject]@{
                    ErrorType       = "Empty Document"
                    Details         = "An Empty Document Was Detected"
                    InFile          = "$InFile"
                    MigrationObject = $Article
                }
            }
			
				
            if ($_.company.InternalCompany -eq $false) {
                $ArticleSplat = @{
                    article_id = $Article.HuduID
                    name       = $Article.name
                    content    = $page_out
                    company_id = $Article.company.HuduID
                    #folder_id = $Article.HuduObject.folder_id
                }	
            }
            else {
                $ArticleSplat = @{
                    article_id = $Article.HuduID
                    name       = $Article.name
                    content    = $page_out
                    #folder_id = $Article.HuduObject.folder_id
                }	
            }
				
            $null = Set-HuduArticle @ArticleSplat
            Write-Host "$($Article.name) completed"
		
            $Article.Imported = "Created-By-Script"
			
        } 

        $MatchedArticles | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\Articles.json'
        $ArticleErrors | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\ArticleErrors.json'
        $ManualActions | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\ManualActions.json'
        Read-Host "Snapshot Point: Articles Created Continue?"

    }

}


############################### Passwords ###############################

#Check for Passwords Resume
if ($ResumeFound -eq $true -and (Test-Path "MigrationLogs\Passwords.json")) {
    Write-Host "Loading Previous Paswords Migration"
    $MatchedPasswords = Get-Content 'MigrationLogs\Passwords.json' -raw | Out-String | ConvertFrom-Json
}
else {

    #Import Passwords
    Write-Host "Fetching Passwords from IT Glue" -ForegroundColor Green
    $PasswordSelect = { (Get-ITGluePasswords -page_size 1000 -page_number $i).data }
    $ITGPasswordsRaw = Import-ITGlueItems -ItemSelect $PasswordSelect
	
    Write-Host "Fetching each password individually to get the actual password data. This may take a while" -foregroundcolor Green
    $ITGPasswords = foreach ($ITGRawPass in $ITGPasswordsRaw){
        $ITGPassword = (Get-ITGluePasswords -id $ITGRawPass.id).data
        $ITGPassword
    }

    Write-Host "$($ITGPasswords.count) ITG Glue Passwords Found" 

    $MatchedPasswords = foreach ($itgpassword in $ITGPasswords ) {
	
        [PSCustomObject]@{
            "Name"       = $itgpassword.attributes.name
            "ITGID"      = $itgpassword.id
            "HuduID"     = ""
            "Matched"    = $false
            "HuduObject" = ""
            "ITGObject"  = $itgpassword
            "Imported"   = ""
        }
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

                    if ($($unmatchedPassword.ITGObject.attributes."resource-id")) {
						
                        if ($unmatchedPassword.ITGObject.attributes."resource-type" -eq "flexible-asset-traits") {
                            # Check if it has already migrated with Assets
                            $FoundItem = $MatchedAssetPasswords | Where-Object { $_.ITGID -eq $($unmatchedPassword.ITGObject.attributes."resource-id") }
                            if (!$FoundItem) {
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
                            else {
                                Write-Host "Migrated with Asset: $FoundItem.HuduID"
                            }
                        }
                        else {
                            # Check if it needs to link to websites
                            if ($($unmatchedPassword.ITGObject.attributes."resource-type") -eq "domains") {
                                $ParentItemID = ($MatchedWebsites | Where-Object { $_.ITGID -eq $($unmatchedPassword.ITGObject.attributes."resource-id") }).HuduID
                                if ($ParentItemID) {
                                    Write-Host "Matched to $ParentItemID" -ForegroundColor Green
                                }
                                else {
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
                            else {
                                # Deal with all others
                                $ParentItemID = (Find-MigratedItem -ITGID $($unmatchedPassword.ITGObject.attributes."resource-id")).HuduID
                                if ($ParentItemID) {
                                    Write-Host "Matched to $ParentItemID" -ForegroundColor Green
                                }
                                else {
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
					
                    if (!$($unmatchedPassword.ITGObject.attributes."resource-type") -eq "flexible-asset-traits") {
						


                        $PasswordSplat = @{
                            name              = "$($unmatchedPassword.ITGObject.attributes.name)"
                            company_id        = $company.HuduCompanyObject.ID
                            description       = $unmatchedPassword.ITGObject.attributes.notes
                            passwordable_type = $PasswordableType
                            passwordable_id   = $ParentItemID
                            in_portal         = $false
                            password          = $unmatchedPassword.ITGObject.attributes.password
                            url               = $unmatchedPassword.ITGObject.attributes.url
                            username          = $unmatchedPassword.ITGObject.attributes.username

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


    }
    else {
        if ($UnmappedPasswordCount -eq 0) {
            Write-Host "All Passwords matched, no migration required" -foregroundcolor green
        }
        else {
            Write-Host "Warning Import passwords is set to disabled so the above unmatched passwords will not have data migrated" -foregroundcolor red
            Read-Host -Prompt "Press any key to continue or CTRL+C to quit" 
        }
    }

    # Save the results to resume from if needed
    $MatchedPasswords | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\Passwords.json'
    $ManualActions | ConvertTo-Json -depth 100 | Out-File 'MigrationLogs\ManualActions.json'

}


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
Read-Host "Press any key to view the manual actions report or Ctrl+C to end"

Start-Process ManualActions.html
