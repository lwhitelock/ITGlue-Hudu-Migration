# This file is used for setting the migration settings.
#
# Please Read the blog post at https://mspp.io/automated-it-glue-to-hudu-migration-script/ before running this script
# Version 2.0.0-beta
# Updated 07/04/2023
# If you found this script useful please consider sponsoring me at https://github.com/sponsors/lwhitelock?frequency=one-time
#
# References
# Determine image type https://devblogs.microsoft.com/scripting/psimaging-part-1-test-image/
# Parsing HTML https://stackoverflow.com/questions/28497902/finding-img-tags-in-html-files-in-powershell
# Nice Base64 conversion https://www.aaron-powell.com/posts/2010-11-07-base64-encoding-images-with-powershell/
# 
# Thank you!
# Luke Whitelock - Primary creator of the ITGlue Migration script and HuduAPI Powershell Module
# John Duprey - Adding file and image uploads to the Migration script, and heavy contributor to the HuduAPI Powershell Module
# Mendy Green - Adding URL rewrite, TOTP Seed imports, improved resilency in the migration, and contributor to the HuduAPI Powershell module
#
# Upcoming Changes
# Convert to a full blown module, prompts for interactive migration experience, save settings to an outside file for secure sharing
# Add/enhance the migration areas to use the new API features of Hudu

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Full", "Lite")]
    [string] $InitType
)

############################### Settings ###############################
# Define the path to the settings.json file in the user's AppData folder
  # Something awesome will be here soon.
$settingsFiles = Get-Item "$env:APPDATA\HuduMigration\*\settings.json"
$defaultSettingsPath = "$env:APPDATA\HuduMigration\settings.json"

# Function to read back securely stored keys used in the settings.json file
function ConvertSecureStringToPlainText {
    param (
        [Parameter(Mandatory=$true)]
        [System.Security.SecureString] $SecureString
    )

    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    return $plainText
}


# Prompt the user for various settings and save the responses
function CollectAndSaveSettings {
    # Create a hash table to store the settings
    $settings = @{}

    # Ask the user for Hudu settings
    $settings.HuduBaseDomain = Read-Host -Prompt 'Set the base domain of your Hudu instance including https:// without a trailing /'
    $HuduAPIKey = Read-Host -Prompt "Get a Hudu API Key from $($settings.HuduBaseDomain)/admin/api_keys"
    $settings.HuduAPIKey = ConvertTo-SecureString -String $HuduAPIKey -AsPlainText -Force | ConvertFrom-SecureString

    # Ask the user for ITGlue Settings
    $ITGKey = Read-Host 'Enter your ITGlue API Key. MAKE SURE TO USE AN API KEY WITH PASSWORD ACCESS'
    $settings.ITGKey = ConvertTo-SecureString -String $ITGKey -AsPlainText -Force | ConvertFrom-SecureString
    $settings.ITGAPIEndpoint = Read-Host 'Enter the ITGlue API Endpoint for your instance/region. (e.g https://api.itglue.com)'

    $settings.InternalCompany = Read-Host 'Enter the exact name of the ITGlue Organization that represents your Internal Company'
    Write-Host "The documents from the company $($settings.InternalCompany) will be migrated to Hudu's Global KB section" -ForegroundColor Cyan
    $settings.ITGLueExportPath = Read-Host 'Enter the path of the ITGLue Export. (e.g. C:\Temp\ITGlue\Export)'
    $settings.ITGURL = Read-Host -Prompt 'Set the domain of your ITGlue instance including https:// without a trailing /'
    $instance = $settings.ITGURL.replace('https://','')
    $settings.GlobalKBFolder = Read-Host -Prompt 'Do you want all documents in Global KB to be placed into a subfolder? (y/n)'
    $customBrandedDomain = Read-Host -Prompt "Do you have additional hostnames you'd like to include in the URL Replacement? For example custom branded ITGlue Domain Name. (y/n)"
    if ($customBrandedDomain -eq 'y') {
    	$settings.ITGCustomDomains = Read-Host -Prompt "Please enter comma separated list of URLs to check for, following the same format of the main domain URL. If only one, don't include the comma."
     }

    # Migration Log Settings
    $settings.MigrationLogs = Read-Host "Enter the path for the migration logs, or press enter to accept the Default path (%appdata%\HuduMigration\$instance\MigrationLogs)"
    if (!($settings.MigrationLogs)) {
        $settings.MigrationLogs = "$ENV:appdata\HuduMigration\$instance\MigrationLogs"
    }

    $settings.ConPromptPrefix = Read-Host "Would you like a Prefix in front of Configuration names created in Hudu? This can make it easy to review and you can rename them later. Enter the prefix here, otherwise leave it blank. (e.g. ITGlue-)"
    $settings.FAPromptPrefix = Read-Host "Would you like a Prefix in front of Asset Layout names created in Hudu? This can make it easy to review and you can rename them later. Enter the prefix here, otherwise leave it blank. (e.g. ITGlue-)"

    # Convert the hash table to JSON
    $json = $settings | ConvertTo-Json

    # Save the JSON to the settings file
    if (!(Test-Path -Path "$env:APPDATA\HuduMigration\$instance")) { New-Item "$env:APPDATA\HuduMigration\$instance" -ItemType Directory }
    $json | Out-File -FilePath $defaultSettingsPath
}

function UpdateSavedSettings {
    param(
        $newSettings
    )
    if ($settingsPath) {
        if (Test-Path $settingsPath) {
            # Convert the hash table to JSON
            Write-Host "Overwriting existing settings file with updated settings." -ForegroundColor Cyan
            $json = $newSettings | ConvertTo-Json
            $json | Out-File -FilePath $settingsPath
        }
        else {
            Write-Host "Creating new settings file in $settingsPath" -ForegroundColor Yellow
            $json = $newSettings | ConvertTo-Json
            $json | Out-File -FilePath $settingsPath
        }
    }
    else {
        if (Test-Path $defaultSettingsPath) {
            # Convert the hash table to JSON
            Write-Host "Overwriting existing settings file with updated settings." -ForegroundColor Cyan
            $json = $newSettings | ConvertTo-Json
            $json | Out-File -FilePath $defaultSettingsPath
        }
        else {
            Write-Host "Creating new settings file in $defaultSettingsPath" -ForegroundColor Yellow
            $json = $newSettings | ConvertTo-Json
            $json | Out-File -FilePath $defaultSettingsPath
        }
    }
}


# Prompt the user for a settings file
# Prompt the user for a settings file
function PromptForSettingsPath {
    param(
        [switch]$Default
    )
    if ($Default) {
        $userPath = Read-Host -Prompt 'Enter the full path to the settings.json file, or press Enter to use the default settings file'
    } else {
        $userPath = Read-Host -Prompt 'Enter the full path to the settings.json file.'
    }
    
    
    if ($userPath -eq '') { 
        $userPath = $defaultSettingsPath
        $fileNotExistMessage = 'The default settings file does not exist. Please specify a path.'
    } else {
        $fileNotExistMessage = 'The specified path does not exist or is not accessible. Please try again.'
    }
    
    if (Test-Path -Path $userPath) {
        return $userPath
    } else {
        Write-Warning $fileNotExistMessage
        return PromptForSettingsPath
    }
}

# Ask the user what they want to do
if ($environmentSettings -and $InitType -eq 'Lite') {
    Write-Host "Lite init and settings detected."
 }
 else {
    $choice = Read-Host -Prompt 'Do you want to (I)mport settings or start from (N)ew?'

    switch ($choice) {
        'I' { 
            if (Test-Path -Path $defaultSettingsPath) {
                Write-Host "Default settings file found at $defaultSettingsPath" -ForegroundColor Cyan
                $importChoice = Read-Host -Prompt 'Do you want to use the (D)efault settings file or (S)pecify a different path?'
                
                switch ($importChoice) {
                    'D' {
                        Write-Host "Importing settings from $defaultSettingsPath" -ForegroundColor Yellow
                        $environmentSettings = Get-Content -Path $defaultSettingsPath | ConvertFrom-Json -Depth 50
                    }
                    'S' {
                        $settingsPath = PromptForSettingsPath -Default
                        Write-Host "Importing settings from $settingsPath" -ForegroundColor Yellow
                        $environmentSettings = Get-Content -Path $settingsPath | ConvertFrom-Json -Depth 50
                    }
                    default {
                        Write-Host 'Invalid choice. Please choose (D)efault or (S)pecify.'
                    }
                }
            } else {
                $settingsPath = PromptForSettingsPath
                Write-Host "Importing settings from $settingsPath" -ForegroundColor Yellow
                $environmentSettings = Get-Content -Path $settingsPath | ConvertFrom-Json -Depth 50
            }
        }
        'N' {
            Write-Host "Starting with a new settings file" -ForegroundColor Cyan
            CollectAndSaveSettings
            $environmentSettings = Get-Content -Path $defaultSettingsPath | ConvertFrom-Json -Depth 50
        }
        default {
            throw 'Invalid choice. Please choose (I)mport or (N)ew.'
        }
    }
}
############################### API Settings ###############################
# Hudu
# Get a Hudu API Key from https://yourhududomain.com/admin/api_keys
try {
    $HuduAPIKey = ConvertSecureStringToPlainText -SecureString ($environmentSettings.HuduAPIKey|ConvertTo-SecureString)
}
catch {
    Write-Host "Your Hudu API Key is not readable!!!" -ForegroundColor Yellow
    $HuduAPIKey = Read-Host -Prompt "Enter the Hudu API Key from $($environmentSettings.HuduBaseDomain)/admin/api_keys"
    $environmentSettings.HuduAPIKey = ConvertTo-SecureString -String $HuduAPIKey -AsPlainText -Force | ConvertFrom-SecureString
    UpdateSavedSettings -newSettings $environmentSettings
}

# Set the base domain of your Hudu instance without a trailing /
$HuduBaseDomain = $environmentSettings.HuduBaseDomain

# IT Glue - MAKE SURE TO USE AN API KEY WITH PASSWORD ACCESS
$ITGAPIEndpoint = $environmentSettings.ITGAPIEndpoint

try {
    $ITGKey = ConvertSecureStringToPlainText -SecureString ($environmentSettings.ITGKey|ConvertTo-SecureString)
}
catch {
    Write-Host "Your ITG API Key is not readable!!!" -ForegroundColor Yellow
    $ITGKey = Read-Host 'Enter your ITGlue API Key. MAKE SURE TO USE AN API KEY WITH PASSWORD ACCESS'
    $environmentSettings.ITGKey = ConvertTo-SecureString -String $ITGKey -AsPlainText -Force | ConvertFrom-SecureString
    UpdateSavedSettings -newSettings $environmentSettings
}

#Enter your primary IT Glue internal URL
$ITGURL = $environmentSettings.ITGURL

# IT Glue Internal Company Name (The documents from this company will be migrated to the Global KB)
$InternalCompany = $environmentSettings.InternalCompany

$ITGLueExportPath = $environmentSettings.ITGLueExportPath


# Choose if you want to resume previous attempts from the last successful section
while ($resumeQuestion -notin ('yes','no')) {
	$resumeQuestion = Read-Host "Would you like to resume a previous migration? (yes/no)"
}
$ResumePrevious = if ($resumeQuestion -eq 'yes') {$true} else {$false}
$GlobalKBFolder = $environmentSettings.GlobalKBFolder

# These settings should only run when doing a full settings initialization.
if ($InitType -eq 'Full') {
    ############################### Company Settings ###############################
    while ($ImportCompanies -notin (1,2)) {$ImportCompanies = Read-Host "1) Import Companies `n2) Skip Companies`n(1/2)"}
    switch ($ImportCompanies) {
        "1" {$ImportCompanies = $true}
        "2" {$ImportCompanies = $false}
    }

    ############################### Location Settings ###############################
    while ($ImportLocations -notin (1,2)) {$ImportLocations = Read-Host "1) Import Locations `n2) Skip Locations`n(1/2)"}
    switch ($ImportLocations) {
        "1" {$ImportLocations = $true}
        "2" {$ImportLocations = $false}
    }

    # The asset layout name how locations will appear in Hudu
    $LocImportAssetLayoutName = "Locations"

    # The font awesome name for the locations icon in Hudu
    $LocImportIcon = "fas fa-building"

    # Here set two arrays of the different names you have used to identify the primary location in both ITGlue And Hudu
    $ITGPrimaryLocationNames = @("Primary Address", "Main", "Head Office", "Main Office")
    $HuduPrimaryLocationNames = @("Primary Address")

    ############################### Domain / Website Settings ###############################
    while ($ImportDomains -notin (1,2)) {$ImportDomains = Read-Host "Domains are used for Website, DNS and SSL Monitoring.`n 1) Import Domains`n 2) Skip Domains`n(1/2)"}
    switch ($ImportDomains) {
        "1" {$ImportDomains = $true}
        "2" {$ImportDomains = $false}
    }

    # Choose if you would like to enable monitoring for the imported websites.
    while ($DisableWebsiteMonitoring -notin (1,2)) {$DisableWebsiteMonitoring = Read-Host "1) Disable Website Monitoring `n2) Leave Website Monitoring enabled`n(1/2)"}
    switch ($DisableWebsiteMonitoring) {
        "1" {$DisableWebsiteMonitoring = "true"}
        "2" {$DisableWebsiteMonitoring = "false"}
    }


    ############################### Configuration Settings ###############################
    while ($ImportConfigurations -notin (1,2)) {$ImportConfigurations = Read-Host "1) Import Configurations `n2) Skip Configurations`n(1/2)"}
    switch ($ImportConfigurations) {
        "1" {$ImportConfigurations = $true}
        "2" {$ImportConfigurations = $false}
    }


    # The font awesome name for the locations icon in Hudu
    $ConfigImportIcon = "fas fa-sitemap"

    # Set if you would like a Prefix in front of configuration names created in Hudu. This can make it easy to review and you can rename them later set to "" if you dont want one
    $ConfigurationPrefix = $environmentSettings.ConPromptPrefix


    ############################### Contact Settings ###############################
    while ($ImportContacts -notin (1,2)) {$ImportContacts = Read-Host "1) Import Contacts `n2) Skip Contacts`n(1/2)"}
    switch ($ImportContacts) {
        "1" {$ImportContacts = $true}
        "2" {$ImportContacts = $false}
    }

    # The asset layout name how locations will appear in Hudu
    $ConImportAssetLayoutName = "People"

    # The font awesome name for the locations icon in Hudu
    $ConImportIcon = "fas fa-users"

    ############################### Flexible Asset Layouts ###############################
    while ($ImportFlexibleAssetLayouts -notin (1,2)) {$ImportFlexibleAssetLayouts = Read-Host "1) Import Asset Layouts `n2) Skip Asset Layouts`n(1/2)"}
    switch ($ImportFlexibleAssetLayouts) {
        "1" {$ImportFlexibleAssetLayouts = $true}
        "2" {$ImportFlexibleAssetLayouts = $false}
    }

    # Set if you would like a Prefix in front of Layout names created in Hudu. This can make it easy to review and you can rename them later set to "" if you don't want one

    $FlexibleLayoutPrefix = $environmentSettings.FAPromptPrefix

    ############################### Flexible Assets ###############################
    while ($ImportFlexibleAssets -notin (1,2)) {$ImportFlexibleAssets = Read-Host "1) Import Assets `n2) Skip Assets`n(1/2)"}
    switch ($ImportFlexibleAssets) {
        "1" {$ImportFlexibleAssets = $true}
        "2" {$ImportFlexibleAssets = $false}
    }


    ############################### Articles ###############################
    while ($ImportArticles -notin (1,2)) {$ImportArticles = Read-Host "1) Import Articles `n2) Skip Articles`n(1/2)"}
    switch ($ImportArticles) {
        "1" {$ImportArticles = $true}
        "2" {$ImportArticles = $false}
    }

    ############################### Passwords ###############################
    while ($ImportPasswords -notin (1,2)) {$ImportPasswords = Read-Host "1) Import Passwords `n2) Skip Passwords`n(1/2)"}
    switch ($ImportPasswords) {
        "1" {$ImportPasswords = $true}
        "2" {$ImportPasswords = $false}
    }
}
############################ Migration Logs Path ##############################
$MigrationLogs = $environmentSettings.MigrationLogs

############################### End of Settings ###############################

############################## Load ImageMagick ###############################
# Import ImageMagick Modules, prompt for path if the module is missing
Write-Host "Adding Imagemagick commands from dot NET assemblies" -ForegroundColor Cyan
$ImageMagickPath = "$PSScriptRoot\Magick.NET-Q16-AnyCPU.dll"
while (!('ImageMagick.MagickImage' -as [type])) {
    if (Test-Path "$ImageMagickPath") {
        try {
            Add-Type -Path $ImageMagickPath -ErrorAction Stop
        }
        catch { 
            throw "Failed to load ImageMagick, please check the files and try again. `n $_"
        }
    }
    else {
        $ImageMagickPath = (Read-Host "Failed to load ImageMagick. Please provide path for the three DLLs.") + "\Magick.NET-Q16-AnyCPU.dll"
    }
}
################### Initialization Complete #############################
