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

############################### Settings ###############################
# Define the path to the settings.json file in the user's AppData folder
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

    # Convert the hash table to JSON
    $json = $settings | ConvertTo-Json

    # Save the JSON to the settings file
    if (!(Test-Path -Path "$env:APPDATA\HuduMigration")) { New-Item -Path "$env:APPDATA" -Name "HuduMigration" -ItemType Directory}
    $json | Out-File -FilePath $defaultSettingsPath
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
            $environmentSettings = Get-Content -Path $defaultSettingsPath | ConvertFrom-Json -Depth 50
        }
    }
    'N' {
        Write-Host "Starting with a new settings file" -ForegroundColor Cyan
        CollectAndSaveSettings
        $environmentSettings = Get-Content -Path $defaultSettingsPath | ConvertFrom-Json -Depth 50
    }
    default {
        Write-Host 'Invalid choice. Please choose (I)mport or (N)ew.' -ForegroundColor Red
    }
}

############################### API Settings ###############################
# Hudu
# Get a Hudu API Key from https://yourhududomain.com/admin/api_keys
$HuduAPIKey = ConvertSecureStringToPlainText -SecureString ($environmentSettings.HuduAPIKey|ConvertTo-SecureString)
# Set the base domain of your Hudu instance without a trailing /
$HuduBaseDomain = $environmentSettings.HuduBaseDomain

# IT Glue - MAKE SURE TO USE AN API KEY WITH PASSWORD ACCESS
$ITGAPIEndpoint = $environmentSettings.ITGAPIEndpoint
$ITGKey = ConvertSecureStringToPlainText -SecureString ($environmentSettings.ITGKey|ConvertTo-SecureString)

#Enter your primary IT Glue internal URL
$ITGURL = $environmentSettings.ITGURL

# IT Glue Internal Company Name (The documents from this company will be migrated to the Global KB)
$InternalCompany = $environmentSettings.InternalCompany

$ITGLueExportPath = $environmentSettings.ITGLueExportPath


# Choose if you want to resume previous attempts from the last successful section
$resumeQuestion = Read-Host "Would you like to resume a previous migration? (yes/no)"
$ResumePrevious = if ($resumeQuestion -eq 'yes') {$true} else {$false}

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
$DisableWebsiteMonitoring = "false"

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
