# Main settings load
. $PSScriptRoot\Initialize-Module.ps1 -InitType 'Lite'

# Replace TestImage() with Invoke-ImageTest()
. $PSScriptRoot\Private\Invoke-ImageTest.ps1

############################### Settings ###############################
# S3 settings
$S3Endpoint = ''
$S3Bucket = ''

# Postgres settings
$MyPort = 5432
$Connection = @{
    dbhost = ''
    dbname = 'hudu2'
    dbuser = 'postgres'
    dbpass = ''
}

################### Supporting Functions ###############################
# PSQL Functions
function Connect-PSQL {
    param (
        [Parameter(Mandatory = $true)]
        [string]$dbhost,
        [Parameter(Mandatory = $true)]
        [string]$dbname,
        [Parameter(Mandatory = $true)]
        [string]$dbuser,
        [string]$dbpass = ''
    )
    try {
        $conn = New-Object System.Data.Odbc.OdbcConnection
        $conn.ConnectionString = "Driver={PostgreSQL UNICODE(x64)};Server=$dbhost;Port=$MyPort;Database=$dbname;Uid=$dbuser;Pwd=$dbpass;"
        $conn.open()
        $conn
    }
    catch {
        Write-Error "Unable to connect to database: $($_.Exception.Message)"
    }
}

function Disconnect-PSQL {
    Param(
        [Parameter(Mandatory = $true)]
        [psobject]$Connection
    )
    if ($Connection.state -eq 'Open') {
        $Connection.close()
    }
}

function Get-PSQLData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [Parameter(Mandatory = $true)]
        [psobject]$Connection
    )
    try {
        Write-Verbose $Query
        $cmd = New-Object System.Data.Odbc.OdbcCommand($Query, $Connection)
        $cmd.CommandTimeout = 300
        $ds = New-Object system.Data.DataSet
        (New-Object system.Data.odbc.odbcDataAdapter($cmd)).fill($ds) | Out-Null
        $ds.Tables[0]
    }
    catch {
        Write-Error "Error getting query result: $($_.Exception.Message)"
    }
}
 
function Set-PSQLData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [Parameter(Mandatory = $true)]
        [psobject]$Connection
    )
    try {
        Write-Verbose $Query
        $cmd = New-Object System.Data.Odbc.OdbcCommand($Query, $Connection)
        $cmd.ExecuteNonQuery()
    }
    catch {
        Write-Error "Error executing query: $($_.Exception.Message)"
    } 
}

# Uses migration computer to determine file types (not required, but improved QOL)
function Get-MimeType {
    param($Extension = $null)
    $mimeType = $null
    if ( $null -ne $Extension ) {
        $drive = Get-PSDrive HKCR -ErrorAction SilentlyContinue
        if ( $null -eq $drive ) {
            $drive = New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT
        }
        $mimeType = (Get-ItemProperty HKCR:$extension).'Content Type'
    }
    $mimeType
}

# Upload to Hudu with S3 Storage
function New-HuduUpload {
    Param(
        $Connection,
        $FilePath,
        $BucketName,
        $EndpointUri,
        $ArticleId,
        $UploadType = 'Article'
    )

    if (! (Test-Path $FilePath)) {
        Write-Error "$FilePath does not exist"
        return
    }

    $File = Get-Item $FilePath
    try {
        $Magick = New-Object ImageMagick.MagickImage($FilePath)
        $Width = $Magick.Width
        $Height = $Magick.Height
    }
    catch {
        $Width = $null
        $Height = $null        
    }
    $MimeType = Get-MimeType -extension $File.Extension
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.ffffff'

    $UploadIndex = (Get-PSQLData -Connection $Connection -Query "INSERT INTO public.uploads (file_data,uploadable_type,uploadable_id,account_id,created_at,updated_at) VALUES ('{}','$UploadType',$ArticleId,1,'$Timestamp','$Timestamp') RETURNING id").id

    $S3Path = "upload/$UploadIndex/file/"

    $OriginalMetadata = [PSCustomObject]@{
        filename  = $File.Name
        size      = $File.Length
        width     = $Width
        height    = $Height
        mime_type = $MimeType
    }

    $OrigGuid = [guid]::newguid() -replace '-'
    $OriginalName = '{0}{1}' -f $OrigGuid, $File.Extension
    $OrigKey = ('{0}{1}' -f $S3Path, $OriginalName)

    $WriteS3Orig = @{
        BucketName  = $BucketName
        EndpointUrl = $EndpointUri
        File        = $FilePath
        Key         = "uploads/$OrigKey"
    }
    Write-S3Object @WriteS3Orig | Out-Null

    $UploadData = [PSCustomObject]@{
        id       = $OrigKey
        storage  = 'store'
        metadata = $OriginalMetadata 
    } 
    $Upload = $UploadData | ConvertTo-Json -Depth 10 -Compress
    $Query = "UPDATE public.uploads SET file_data = '$Upload' where id = $UploadIndex"
    
    try {
        Set-PSQLData -Connection $Connection -Query $Query | Out-Null

        [PSCustomObject]@{
            FileHref  = "/file/$UploadIndex"
            ArticleId = $ArticleId
            FileData  = $UploadData
        }
    }
    catch {
        Write-Error ('Insert exception: {0}' -f $_.Exception.Message)
    }
}

# Function for looping over found assets and attachments. Requires PSQL Connection
function Add-HuduAttachment {
param(
    $FoundAssetsToAttach,
    $UploadType
)
    $HuduUpload = @()

    # Grab existing attachments.
    $Query = "select uploadable_id, file_data from uploads where uploadable_type = '$UploadType'"
    $ExistingAttachments = $ExistingAttachments = Get-PSQLData -Query $Query -Connection $Conn
    $UploadedAttachments = $ExistingAttachments | Select-Object @{n='id'; e={ $_.uploadable_id}},@{n='file';e={($_.file_data|Convertfrom-json).metadata.filename}},@{n='url';e={($_.file_data|Convertfrom-json).id}}

    $Results = foreach ($FoundAsset in $FoundAssetsToAttach) {
        Write-Host "Finding attachments for $($FoundAsset.name) with ITGlueID $($FoundAsset.itgid) to Hudu $($UploadType) $($FoundAsset.HuduID)" -ForegroundColor Cyan
        Write-Host "Checking existing attachments from database"
        $CurrentAssetAttachments = $UploadedAttachments | Where-Object {$_.id -eq $FoundAsset.HuduID}
        $FilesToUpload = Get-ChildItem -path "$($ITGlueExportPath)attachments\*\$($FoundAsset.ITGID)\*" -Recurse
        foreach ($FoundFile in $FilesToUpload) {
            if ($FoundFile.PSIsContainer -ne $True) {
                if ($FoundFile.name -in $CurrentAssetAttachments.file) {
                    Write-Host "Skipping $($FoundFile.name) because its already uploaded as an attachment" -ForegroundColor Yellow
                    continue
                }
                Write-Host "Uploading $($FoundFile.name) to Hudu $($UploadType) $($FoundAsset.name) - $($FoundAsset.HuduID)" -ForegroundColor Blue
                $HuduUpload = New-HuduUpload -Connection $Conn -FilePath $FoundFile.fullname -BucketName $S3Bucket -EndpointUri $S3Endpoint -ArticleId $FoundAsset.HuduID -UploadType $UploadType
                $HuduUpload
            }
        }

    }

    $Results |ConvertTo-Json -Compress -Depth 10 |Out-File ".\$($UploadType)-attachments-upload.json"

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
    $CSVMapping | ConvertTo-Json -Depth 50 -Compress |Out-File ".\MigrationLogs\AttachmentFields-CSVMap.json"
}
################ END FUNCTIONS REGION #################

# Connect to the Database
$Conn = Connect-PSQL @Connection

# Import AWS Tools, and confirm credentials are saved as your default profile
Write-Host "Checking for AWS Tools" -ForegroundColor Cyan
try {
    Remove-Module AWS.Tools.Common
    Import-Module AWSPowerShell.NetCore
    while ($ConfirmAWsCredential -notin 'Y','N') {
        $ConfirmAWsCredential = Read-Host "Did you add your S3 API Access Keys as your default profile? (Y/n)"
    }

    if ($ConfirmAWsCredential -eq 'N') {
        Set-AWSCredential -StoreAs default -AccessKey (Read-Host "Please enter your access key") -SecretKey (Read-Host "Please enter your secret key")
    }
    
}
catch {
    Install-Module AWSPowerShell.NetCore -Scope CurrentUser -ErrorAction Stop
    Set-AWSCredential -StoreAs default -AccessKey (Read-Host "Please enter your access key") -SecretKey (Read-Host "Please enter your secret key")
}

# Check if we have a logs folder. Logs are required to match attachments to entity
if (Test-Path -Path "$MigrationLogs") {
        Write-Host "A previous attempt has been found job will be used to match asset attachments" -ForegroundColor Green
    }
else {
    Write-Host "No previous runs found creating log directory. Unable to proceed"
    exit 1
}

## Starting main script
Write-Host "Starting script. Press CTRL+C to cancel" -ForegroundColor Yellow
Pause

$ITGlueAssets = Get-Content "$MigrationLogs\Assets.json" | ConvertFrom-json
#$ITGlueDocuments = Get-Content "$MigrationLogs\Articles.json" | ConvertFrom-json
$ITGlueConfigurations = Get-Content "$MigrationLogs\Configurations.json" | ConvertFrom-json

$AttachmentsToUpload = Get-ChildItem "$($ITGLueExportPath)attachments\" -Recurse
$FoundAssetsToAttach = $ITGlueAssets |Where-Object {$_.itgid -in $AttachmentsToUpload.name -and $_.HuduID -eq $null}
#$FoundDocumentsToAttach = $ITGlueDocuments |Where-Object {$_.itgid -in $AttachmentsToUpload.name}
$FoundConfigurationsToAttach = $ITGlueConfigurations | Where-Object {$_.itgid -in $AttachmentsToUpload.name}
if ($FoundAssetsToAttach) {Add-HuduAttachment -FoundAssetsToAttach $FoundAssetsToAttach -UploadType "Asset"}
if ($FoundConfigurationsToAttach) {Add-HuduAttachment -FoundAssetsToAttach $FoundConfigurationsToAttach -UploadType "Asset"}
#if ($FoundDocumentsToAttach) {Add-HuduAttachment -FoundAssetsToAttach $FoundDocumentsToAttach -UploadType "Article"}

$CSVMapping = Get-Content ".\MigrationLogs\AttachmentFields-CSVMap.json"

if ($CSVMapping) {
    foreach ($n in $CSVMapping) { 
        $CSV = Import-Csv -Path "$($ITGLueExportPath)$($n.csv_file)" 
        $CSVHeader = $n.csv_header 
    
        $CSVAttachmentsToUpload = $CSV | Where-Object {$_.$CSVHeader}
        foreach ($record in $CSVAttachmentsToUpload) {
            $FileReferences = $record.$CSVHeader.split(',').trim()
            foreach ($fr in $FileReferences) {
                $FileToUpload = Get-Item -path "$($ITGlueExportPath)$($n.foldername)\$($fr)"
                $HuduAssetID = $ITGlueAssets |Where-Object {$_.itgid -eq $record.id}  |Select-Object -ExpandProperty HuduID
                $HuduAssetName = $ITGlueAssets |Where-Object {$_.itgid -eq $record.id}  |Select-Object -ExpandProperty Name
                Write-Host "Uploading $($FileToUpload.fullname) to Hudu Asset $($HuduAssetName) - $($HuduAssetID)" -ForegroundColor Blue
                $HuduUpload = New-HuduUpload -Connection $Conn -FilePath $FileToUpload.fullname -BucketName $S3Bucket -EndpointUri $S3Endpoint -ArticleId $HuduAssetID -UploadType 'Asset'
            }
        }
    }
}
