# Check if this is a direct run, and load the logs if so the first time.
if (-not (Get-Command -Name Get-EnsuredPath -ErrorAction SilentlyContinue)) { . $PSScriptRoot\Public\Init-OptionsAndLogs.ps1 }
$ErroredItemsFolder = $(Get-EnsuredPath -path $(join-path $(Resolve-Path .).path "debug"))

if (-not ($FirstTimeLoad -eq 1)) {
    # General Settings Load
    . $PSScriptRoot\..\Initialize-Module.ps1 -InitType 'Lite'
    
    # Add Replace URL functions
    . $PSScriptRoot\..\Private\ConvertTo-HuduURL.ps1

    Write-Host "Checking for Matched Variables"
    if (-not $MatchedPasswords) {$MatchedPasswords = (Get-Content -path "$MigrationLogs\Passwords.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedAssetPasswords) {$MatchedAssetPasswords = (Get-Content -path "$MigrationLogs\AssetPasswords.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedArticleBase) {$MatchedArticleBase = Get-Content "$MigrationLogs\ArticleBase.json" -raw | Out-String | ConvertFrom-Json -depth 100}
    if (-not $MatchedArticles) {$MatchedArticles = (Get-Content -path "$MigrationLogs\Articles.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedCompanies) {$MatchedCompanies = (Get-Content -path "$MigrationLogs\Companies.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedConfigurations) {$MatchedConfigurations = Get-Content "$MigrationLogs\Configurations.json" -raw | Out-String | ConvertFrom-Json -depth 100}
    if (-not $MatchedAssets) {$MatchedAssets = Get-Content "$MigrationLogs\Assets.json" -raw | Out-String | ConvertFrom-Json -depth 100}
    # Set the context so logs don't run again unless the powershell window gets closed.
    $FirstTimeLoad = 1
}

# Load Invoke-ImageTest()
. $PSScriptRoot\Private\Invoke-ImageTest.ps1

# Attachments Path
$AttachmentsPath = (Join-Path -Path $ITGLueExportPath -ChildPath "attachments")
$AttachmentUrlMap = $AttachmentUrlMap ?? @{}
$ITGlueAttachmentCache = @{}

###################### Initial Setup and Confirmations ###############################
Write-Host "##################################################################" -ForegroundColor Yellow
Write-Host "#                                                                #" -ForegroundColor Yellow
Write-Host "#          IT Glue to Hudu Migration Script                      #" -ForegroundColor Yellow
Write-Host "#           - File Attachment Uploads                            #" -ForegroundColor Yellow
Write-Host "#          Version: 3.0                                          #" -ForegroundColor Yellow
Write-Host "#          Date: 06/23/2026                                      #" -ForegroundColor Yellow
Write-Host "#                                                                #" -ForegroundColor Yellow
Write-Host "#                                                                #" -ForegroundColor Yellow
Write-Host "#                                                                #" -ForegroundColor Yellow
Write-Host "#         The script will upload your attachmens                 #" -ForegroundColor Yellow
Write-Host "#         directly to Hudu.                                      #" -ForegroundColor Yellow
Write-Host "##################################################################" -ForegroundColor Yellow
Write-Host "# contact Hudu support if you run into issues.                   #" -ForegroundColor Yellow
Write-Host "# visit the Hudu Sub-Reddit:                                     #" -ForegroundColor Yellow
Write-Host "# https://www.reddit.com/r/hudu/                                 #" -ForegroundColor Yellow
Write-Host "# The #v-hudu channel on the MSPGeek Slack/Discord:              #" -ForegroundColor Yellow
Write-Host "# https://join.mspgeek.com/                                      #" -ForegroundColor Yellow
Write-Host "# Or log an issue in the Github Respository:                     #" -ForegroundColor Yellow
Write-Host "# https://github.com/Hudu-Technologies-Inc/ITGlue-Hudu-Migration #" -ForegroundColor Yellow
Write-Host "##################################################################" -ForegroundColor Yellow

################### Supporting Functions ###############################

function Resolve-HuduUploadUrl {
param(
    $Upload
)
    $UploadObject = $Upload.upload ?? $Upload
    $UploadUrl = $UploadObject.url ?? $UploadObject.file_url ?? $UploadObject.download_url

    if ([string]::IsNullOrWhiteSpace($UploadUrl)) { return $null }
    if ($UploadUrl -match '^https?://') { return [string]$UploadUrl }
    if ([string]::IsNullOrWhiteSpace($HuduBaseDomain)) { return [string]$UploadUrl }

    return "$($HuduBaseDomain.TrimEnd('/'))/$($UploadUrl.TrimStart('/'))"
}

function Add-AttachmentUrlMapEntry {
param(
    [string[]]$OriginalUrl,
    [string]$HuduUrl
)
    if (-not $OriginalUrl -or [string]::IsNullOrWhiteSpace($HuduUrl)) { return }

    foreach ($Url in @($OriginalUrl | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        $script:AttachmentUrlMap[$Url] = $HuduUrl
    }
}

function Get-AttachmentPathInfo {
param(
    [System.IO.FileInfo]$FoundFile
)
    $AttachmentsRoot = (Resolve-Path $AttachmentsPath).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $RelativePath = $FoundFile.FullName.Substring($AttachmentsRoot.Length).TrimStart([char[]]@('\', '/'))
    $PathParts = @($RelativePath -split '[\\/]')
    if ($PathParts.Count -lt 3) { return $null }

    $AttachmentType = $PathParts[0]
    $ITGID = $PathParts[1]
    $ITGEntityType = switch ($AttachmentType) {
        'documents' { 'docs' }
        'passwords' { 'passwords' }
        'configurations' { 'configurations' }
        default { 'assets' }
    }

    [pscustomobject]@{
        AttachmentType = $AttachmentType
        ITGID          = $ITGID
        ITGEntityType  = $ITGEntityType
        RelativePath   = $RelativePath
    }
}

function Get-OriginalAttachmentUrl {
param(
    [System.IO.FileInfo]$FoundFile,
    $FoundAsset
)
    $PathInfo = Get-AttachmentPathInfo -FoundFile $FoundFile
    if (-not $PathInfo -or [string]::IsNullOrWhiteSpace($ITGURL)) { return $null }

    $CompanyId = $FoundAsset.Company.ITGID ??
        $FoundAsset.Company.id ??
        $FoundAsset.ITGObject.attributes.'organization-id' ??
        $FoundAsset.ITGObject.attributes.organization_id ??
        $FoundAsset.ITGObject.relationships.organization.data.id

    $FileUrlSegment = if ($FoundFile.Name -match '^(?<FileId>\d{1,20})[-_\s]') {
        $Matches.FileId
    } else {
        [Uri]::EscapeDataString($FoundFile.Name)
    }

    if ($CompanyId) {
        return "$($ITGURL.TrimEnd('/'))/$CompanyId/$($PathInfo.ITGEntityType)/$($PathInfo.ITGID)/files/$FileUrlSegment"
    }

    return "$($ITGURL.TrimEnd('/'))/$($PathInfo.ITGEntityType)/$($PathInfo.ITGID)/files/$FileUrlSegment"
}

function Get-ITGlueAttachmentResourceType {
param(
    [string]$AttachmentType,
    [string]$UploadType
)
    switch ($AttachmentType) {
        'documents' { 'documents' }
        'configurations' { 'configurations' }
        'contacts' { 'contacts' }
        'locations' { 'locations' }
        'passwords' { 'passwords' }
        'websites' { 'domains' }
        default {
            if ($UploadType -eq 'AssetPassword') { 'passwords' }
            elseif ($UploadType -eq 'Website') { 'domains' }
            else { 'flexible_assets' }
        }
    }
}

function Normalize-ITGlueAttachmentFilename {
param(
    [string]$Name
)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }

    $Text = [IO.Path]::GetFileName($Name).Normalize([Text.NormalizationForm]::FormD)
    $Chars = $Text.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark
    }

    $Text = (-join $Chars).ToLowerInvariant()
    $Text = $Text -replace '&', ' and '
    $Text = $Text -replace '[^a-z0-9.]+', ' '
    $Text = $Text.Trim()
    $Text = $Text -replace '\s+', ' '

    return $Text
}

function Get-ITGlueAttachmentName {
param(
    $Attachment
)
    @(
        $Attachment.attributes.'file-name'
        $Attachment.attributes.file_name
        $Attachment.attributes.name
        $Attachment.attributes.attachment.file_name
        $Attachment.attributes.attachment.'file-name'
        $Attachment.attributes.'attachment-file-name'
        $Attachment.attributes.'attachment-file_name'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
}

function Get-ITGlueAttachmentsForResource {
param(
    [string]$ResourceType,
    [string]$ResourceId
)
    if ([string]::IsNullOrWhiteSpace($ResourceType) -or [string]::IsNullOrWhiteSpace($ResourceId)) { return @() }
    if ([string]::IsNullOrWhiteSpace($ITGKey)) { return @() }

    $CacheKey = "$ResourceType/$ResourceId"
    if ($script:ITGlueAttachmentCache.ContainsKey($CacheKey)) { return $script:ITGlueAttachmentCache[$CacheKey] }

    $ApiBase = @($ITGAPIEndpoint, $settings.ITGAPIEndpoint, $environmentSettings.ITGAPIEndpoint) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($ApiBase)) { return @() }

    $ApiBase = $ApiBase.TrimEnd('/')
    $Uri = "$ApiBase/$ResourceType/$ResourceId/relationships/attachments?page%5Bsize%5D=1000"

    try {
        $Response = Invoke-RestMethod -Method GET -Uri $Uri -Headers @{ 'x-api-key' = $ITGKey } -ErrorAction Stop
        $Attachments = @($Response.data)
    }
    catch {
        Write-Warning "Unable to retrieve IT Glue attachments for $ResourceType/$ResourceId. Attachment URL aliases may be incomplete. $($_.Exception.Message)"
        $Attachments = @()
    }

    $script:ITGlueAttachmentCache[$CacheKey] = $Attachments
    return $Attachments
}

function Find-ITGlueAttachmentForFile {
param(
    [System.IO.FileInfo]$FoundFile,
    $FoundAsset,
    [string]$UploadType
)
    $PathInfo = Get-AttachmentPathInfo -FoundFile $FoundFile
    if (-not $PathInfo) { return $null }

    $ResourceType = Get-ITGlueAttachmentResourceType -AttachmentType $PathInfo.AttachmentType -UploadType $UploadType
    $Attachments = Get-ITGlueAttachmentsForResource -ResourceType $ResourceType -ResourceId $PathInfo.ITGID
    if (-not $Attachments -or $Attachments.Count -lt 1) { return $null }

    $ExpectedName = Normalize-ITGlueAttachmentFilename -Name $FoundFile.Name
    $ExpectedStem = Normalize-ITGlueAttachmentFilename -Name ([IO.Path]::GetFileNameWithoutExtension($FoundFile.Name))

    foreach ($Attachment in $Attachments) {
        $AttachmentName = Get-ITGlueAttachmentName -Attachment $Attachment
        $NormalizedName = Normalize-ITGlueAttachmentFilename -Name $AttachmentName
        $NormalizedStem = Normalize-ITGlueAttachmentFilename -Name ([IO.Path]::GetFileNameWithoutExtension($AttachmentName))

        if ($ExpectedName -and $ExpectedName -eq $NormalizedName) { return $Attachment }
        if ($ExpectedStem -and $ExpectedStem -eq $NormalizedStem) { return $Attachment }
    }

    return $null
}

function Get-ITGlueAttachmentUrlAliases {
param(
    $Attachment
)
    if (-not $Attachment -or [string]::IsNullOrWhiteSpace($Attachment.id) -or [string]::IsNullOrWhiteSpace($ITGURL)) { return @() }

    $AttachmentId = $Attachment.id
    $BaseUrl = $ITGURL.TrimEnd('/')

    @(
        "$BaseUrl/attachments/$AttachmentId"
        "$BaseUrl/attachments/$AttachmentId`?preview=1"
        "$BaseUrl/attachments/$AttachmentId`?preview=true"
        "/attachments/$AttachmentId"
        "/attachments/$AttachmentId`?preview=1"
        "/attachments/$AttachmentId`?preview=true"
    )
}

function Save-AttachmentUrlMap {
    $script:AttachmentUrlMap | ConvertTo-Json -Depth 10 | Out-File "$MigrationLogs\AttachmentUrlMap.json"
}

# Function for looping over found assets and attachments. Requires PSQL Connection
function Add-HuduAttachment {
param(
    $FoundAssetsToAttach,
    $UploadType,
    [string]$FileSuffix=""
)
    $HuduUpload = @()

    # Grab existing attachments.
    ##### Commenting out, no database access
    # $Query = "select uploadable_id, file_data from uploads where uploadable_type = '$UploadType'"
    # $ExistingAttachments = $ExistingAttachments = Get-PSQLData -Query $Query -Connection $Conn
    # $UploadedAttachments = $ExistingAttachments | Select-Object @{n='id'; e={ $_.uploadable_id}},@{n='file';e={($_.file_data|Convertfrom-json).metadata.filename}},@{n='url';e={($_.file_data|Convertfrom-json).id}}
    ##### Replace above lines with new method that doesn't require database. Also commenting lines 149 and 150, 155-158
    
    $Results = foreach ($FoundAsset in $FoundAssetsToAttach) {
        Write-Host "Finding attachments for $($FoundAsset.name) with ITGlueID $($FoundAsset.itgid) to Hudu $($UploadType) $($FoundAsset.HuduID)" -ForegroundColor Cyan
        # Write-Host "Checking existing attachments from database"
        # $CurrentAssetAttachments = $UploadedAttachments | Where-Object {$_.id -eq $FoundAsset.HuduID}
        
        $FilesToUpload = Get-ChildItem -path "$AttachmentsPath\*\$($FoundAsset.ITGID)\*" -Recurse
        foreach ($FoundFile in $FilesToUpload) {
            if ($FoundFile.PSIsContainer -ne $True) {
                <# if ($FoundFile.name -in $CurrentAssetAttachments.file) {
                    Write-Host "Skipping $($FoundFile.name) because its already uploaded as an attachment" -ForegroundColor Yellow
                    continue
                } #>
                Write-Host "Pushing $($FoundFile.name) to Hudu $($UploadType) $($FoundAsset.name) - $($FoundAsset.HuduID)" -ForegroundColor Blue
                try {
                    $HuduUpload = New-HuduUpload -FilePath $FoundFile.fullname -uploadable_id $FoundAsset.HuduID -uploadable_type $UploadType
                    $FullHuduUploadUrl = Resolve-HuduUploadUrl -Upload $HuduUpload
                    $OriginalAttachmentUrl = Get-OriginalAttachmentUrl -FoundFile $FoundFile -FoundAsset $FoundAsset
                    $ITGlueAttachment = Find-ITGlueAttachmentForFile -FoundFile $FoundFile -FoundAsset $FoundAsset -UploadType $UploadType
                    $OriginalAttachmentUrls = @($OriginalAttachmentUrl) + @(Get-ITGlueAttachmentUrlAliases -Attachment $ITGlueAttachment)
                    $OriginalAttachmentUrls = @($OriginalAttachmentUrls | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
                    Add-AttachmentUrlMapEntry -OriginalUrl $OriginalAttachmentUrls -HuduUrl $FullHuduUploadUrl
                    [PSCustomObject]@{
                        URL  = $FullHuduUploadUrl
                        OriginalAttachmentUrl = $OriginalAttachmentUrl
                        OriginalAttachmentUrls = $OriginalAttachmentUrls
                        ITGAttachmentID = $ITGlueAttachment.id
                        Uploadable_ID = $FoundAsset.HuduID
                        Uploadable_Type = $UploadType
                        FilePath  = $FoundFile.fullname
                        status  = "Uploaded Successfully"
                    }
                }
                catch {
                Write-Error ('Insert exception: {0}' -f $_.Exception.Message)
                [PSCustomObject]@{
                    FileHref  = "/file/$UploadIndex"
                    ArticleId = $ArticleId
                    FileData  = $UploadData
                    status  = "FAILED: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
    
    $SuffixSegment = if ([string]::IsNullOrWhiteSpace($FileSuffix)) { "" } else { "-$FileSuffix" }
    $Results |ConvertTo-Json -Compress -Depth 10 |Out-File "$($MigrationLogs)\$($UploadType)$SuffixSegment-attachments-upload.json"
    return $results
}

# Used for Creating the CSV Mapping for FA Custom Upload fields
function Build-CSVMapping {
    $Folders = Get-ChildItem -Attributes Directory -Filter *-* -Path $ITGlueExportPath

    $CSVMapping = foreach ($folder in $Folders) {
        Write-Host "We need to map the embedded attachments to the right CSV file. Please enter the name of the csv file for $($folder.name)";
        $FileName = Read-Host "CSV Name";
        
        Write-Host "We need to specify the header where the file path is located for this folder. Please specify the header name for $($folder.name)";
        $HeaderName = Read-Host "Header"; 
        
        [pscustomobject]@{
            foldername=$Folder.name;
            csv_file=$FileName;
            csv_header=$HeaderName
        }
    }
    $CSVMapping | ConvertTo-Json -Depth 50 -Compress |Out-File "$MigrationLogs\AttachmentFields-CSVMap.json"
    return $CSVMapping
}
################ END FUNCTIONS REGION #################

if ((get-host).version.major -ne 7) {
    Write-Host "Powershell 7 Required" -foregroundcolor Red
    exit 1
}


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
$RequiredHuduVersion = "2.1.5.9"
$HuduAppInfo = Get-HuduAppInfo
If ([version]$HuduAppInfo.version -lt [version]$RequiredHuduVersion) {
    Write-Host "This script requires at least version $RequiredHuduVersion. Please update your version of Hudu and run the script again. Your version is $($HuduAppInfo.version)"
    exit 1
}

# Check if we have a logs folder. Logs are required to match attachments to entity
if (Test-Path -Path "$MigrationLogs") {
        Write-Host "Migration Logs successfully found" -ForegroundColor Green
    }
else {
    Write-Host "No previous runs found creating log directory. Unable to proceed"
    exit 1
}

## Starting main script
Write-Host "Starting script in 10 seconds. Press CTRL+C to cancel" -ForegroundColor Yellow
start-sleep 10

if (-not $MatchedAssets) {$MatchedAssets = (Get-Content -path "$MigrationLogs\Assets.json" | ConvertFrom-json -depth 100) }
if (-not $matchedConfigurations) {$matchedConfigurations = (Get-Content -path "$MigrationLogs\Configurations.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedPasswords) {$MatchedPasswords = (Get-Content -path "$MigrationLogs\Passwords.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedContacts) {$MatchedContacts = (Get-Content -path "$MigrationLogs\Contacts.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedArticles) {$MatchedArticles = (Get-Content -path "$MigrationLogs\Articles.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedLocations) {$MatchedLocations = (Get-Content -path "$MigrationLogs\Locations.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedPasswords) {$MatchedPasswords = (Get-Content -path "$MigrationLogs\Passwords.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedWebsites) {$MatchedWebsites = (Get-Content -path "$MigrationLogs\websites.json" | ConvertFrom-json -depth 100) }

$AttachmentsToUpload = Get-ChildItem -Path $AttachmentsPath -Recurse -File
$filesById = $AttachmentsToUpload | Group-Object { $_.Directory.Name } -AsHashTable -AsString

$foundContactsToAttach = $MatchedContacts | Where-Object {$filesById.ContainsKey([string]$_.ITGID) -and [int]$($_.HuduID) -gt 0}
if ($foundContactsToAttach -and $foundContactsToAttach.count -gt 0) {Add-HuduAttachment -FoundAssetsToAttach $foundContactsToAttach -UploadType "Asset" -FileSuffix "Contacts"}

$FoundConfigurationsToAttach = $MatchedConfigurations | Where-Object {$filesById.ContainsKey([string]$_.ITGID) -and [int]$($_.HuduID) -gt 0}
if ($FoundConfigurationsToAttach -and $FoundConfigurationsToAttach.count -gt 0) {Add-HuduAttachment -FoundAssetsToAttach $FoundConfigurationsToAttach -UploadType "Asset" -FileSuffix "Configurations"}

$FoundDocumentsToAttach = $MatchedArticles | Where-Object {$filesById.ContainsKey([string]$_.ITGID) -and [int]$($_.HuduID) -gt 0}
if ($FoundDocumentsToAttach -and $FoundDocumentsToAttach.count -gt 0) {Add-HuduAttachment -FoundAssetsToAttach $FoundDocumentsToAttach -UploadType "Article"}

$FoundLocationsToAttach = $MatchedLocations | Where-Object {$filesById.ContainsKey([string]$_.ITGID) -and [int]$($_.HuduID) -gt 0}
if ($FoundLocationsToAttach -and $FoundLocationsToAttach.count -gt 0) {Add-HuduAttachment -FoundAssetsToAttach $FoundLocationsToAttach -UploadType "Asset" -FileSuffix "Locations"}

$FoundPasswordsToAttach = $MatchedPasswords| Where-Object {$filesById.ContainsKey([string]$_.ITGID) -and [int]$($_.HuduID) -gt 0}
if ($FoundPasswordsToAttach -and $FoundPasswordsToAttach.count -gt 0) {Add-HuduAttachment -FoundAssetsToAttach $FoundPasswordsToAttach -UploadType "AssetPassword"}

$MatchedAssetsToAttach = $MatchedAssets | Where-Object {$filesById.ContainsKey([string]$_.ITGID) -and [int]$($_.HuduID) -gt 0}
if ($MatchedAssetsToAttach -and $MatchedAssetsToAttach.count -gt 0) {Add-HuduAttachment -FoundAssetsToAttach $MatchedAssetsToAttach -UploadType "Asset" -FileSuffix "FlexibleAssets"}

$FoundWebsitesToAttach = $MatchedWebsites | Where-Object {$filesById.ContainsKey([string]$_.ITGID) -and [int]$($_.HuduID) -gt 0}
if ($FoundWebsitesToAttach -and $FoundWebsitesToAttach.count -gt 0) {Add-HuduAttachment -FoundAssetsToAttach $FoundWebsitesToAttach -UploadType "Website"}


$UploadFieldsArePresent = $UploadFieldsArePresent ?? $true
if ($true -eq $UploadFieldsArePresent){
    Write-Host "One or more Upload fields were present on the assets or we couldnt determine their presence. These will be uploaded now." -ForegroundColor Yellow
    . "$($(get-childitem -path "." -Recurse -file "Add-UploadFieldAttachments.ps1" | Select-Object -first 1).fullname)"

    if ($MatchedUploadFields) {
        foreach ($UploadField in $MatchedUploadFields.Values) {
            Add-AttachmentUrlMapEntry -OriginalUrl $UploadField.ITGFileUrl -HuduUrl (Resolve-HuduUploadUrl -Upload $UploadField.Upload)
        }
    }
}


$CSVMapPath = "$MigrationLogs\AttachmentFields-CSVMap.json"
if (-not (Test-Path $CSVMapPath)) {
    Save-AttachmentUrlMap
    write-host "no optional CSV map found at $CSVMapPath. Attachments complete!"
    exit
}

if (!($CSVMapping = Get-Content $CSVMapPath|ConvertFrom-Json -Depth 10)) {
    $CSVMapping = Build-CSVMapping
}

if ($CSVMapping) {
    foreach ($n in $CSVMapping) { 
        try {
            $CSVPath = Join-Path -Path $ITGLueExportPath -ChildPath $n.csv_file
            $CSV = Import-Csv -Path $CSVPath
            $CSVHeader = $n.csv_header 
        
            $CSVAttachmentsToUpload = $CSV | Where-Object {$_.$CSVHeader}
            foreach ($record in $CSVAttachmentsToUpload) {
                $FileReferences = $record.$CSVHeader.split(',').trim()
                foreach ($fr in $FileReferences) {
                    $FileToUpload = Get-Item -path (Join-Path -Path $ITGlueExportPath -ChildPath "$($n.foldername)\$($fr)")
                    $HuduAssetID = $ITGlueAssets |Where-Object {$_.itgid -eq $record.id}  |Select-Object -ExpandProperty HuduID
                    $HuduAssetName = $ITGlueAssets |Where-Object {$_.itgid -eq $record.id}  |Select-Object -ExpandProperty Name
                    Write-Host "Uploading $($FileToUpload.fullname) to Hudu Asset $($HuduAssetName) - $($HuduAssetID)" -ForegroundColor Blue
                    $HuduUpload = New-HuduUpload -FilePath $FileToUpload.fullname -uploadable_id $HuduAssetID -uploadable_type 'Asset'
                    if ($fr -match '^https?://') {
                        Add-AttachmentUrlMapEntry -OriginalUrl $fr -HuduUrl (Resolve-HuduUploadUrl -Upload $HuduUpload)
                    }

                }
            }
    } catch {
        try {
            Write-ErrorObjectsToFile -ErrorObject @{
                CSVMapping = $CSVMapping    
                CSV = $CSV
                N   = $n
                Error = $_
                record = $record
                file_ref = $fr
            } -Name "Upload_$CSVHeader"
            } catch {
                write-host "upload err - $($record ?? 'record') - $($CSVHeader ?? 'header')"
            }
        }  
    }
}
Save-AttachmentUrlMap
Write-Host "All attachments have been processed."
    
