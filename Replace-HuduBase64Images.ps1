# This script is mostly credited to John Duprey from MSPGeek
# This script runs against the Hudu Database which is not-supported
# This script will pull any documents that have base64 encoded images in it, extract the base64 image into a binary stream, upload it to s3 storage
## then update the article to use the newly uploaded image files. This uses the same process that Hudu natively uses.

#  Postgres Database Functions. This requires the ODBC Driver to be installed
## FTP MSI Download from this link, scroll to the last zip (latest version), download, extract and install. No reboot required
## https://www.postgresql.org/ftp/odbc/versions/msi/

param(
    [parameter(ParameterSetName='RunAll')][switch]$ProcessAllArticles,
    [parameter(ParameterSetName='RunOne')]$AritcleIdsToProcess,
    [parameter(ParameterSetName='RunSome')][int]$NumberofArticlesToLoop
)

# Postgres settings, modify your port to the port number you tunneled via SSH
# You need to expose the PSQL Port in Docker first. Refer to mspbooks.mspgeek.org doc for more details.
$MyPort = 5432
$ConnectionDetails = @{
    dbhost = 'localhost'
    dbname = 'hudu_production'
    dbuser = 'postgres'
    dbpass = ''
}

# PostgreSQL functions
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

    if ($Connection.state -ne 'Open') {
        $Connection = Connect-PSQL @ConnectionDetails 
    }
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

    if ($Connection.state -ne 'Open') {
        $Connection = Connect-PSQL @ConnectionDetails  
    }
    try {
        Write-Verbose $Query
        $cmd = New-Object System.Data.Odbc.OdbcCommand($Query, $Connection)
        $cmd.ExecuteNonQuery()
    }
    catch {
        Write-Error "Error executing query: $($_.Exception.Message)"
    } 
}

# Detect MimeType for uploading to Hudu
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

# Upload to Hudu with S3 AWS Powershell Module
function New-HuduImage {
    Param(
        $Connection,
        $FilePath,
        $OutputPath,
        $BucketName,
        $EndpointUri,
        $ArticleId
    )

    if (! (Test-Path $FilePath)) {
        Write-Error "$FilePath does not exist"
        return
    }

    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath | Out-Null
    }

    $OutputPath = (Get-Item $OutputPath).FullName

    $File = Get-Item $FilePath
    $Magick = New-Object ImageMagick.MagickImage($FilePath)
    $MimeType = Get-MimeType -extension ".$($Magick.format)"

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.ffffff'
    $PublicImageIndex = (Get-PSQLData -Connection $Connection -Query "INSERT INTO public.public_photos (image_data,record_type,record_id,created_at,updated_at) VALUES ('{}','Article',$ArticleId,'$Timestamp','$Timestamp') RETURNING id").id

    $S3Path = "publicphoto/$PublicImageIndex/image/"

    $OriginalMetadata = [PSCustomObject]@{
        filename  = $File.Name
        size      = $File.Length
        width     = $Magick.Width
        height    = $Magick.Height
        mime_type = $MimeType
    }
    $OrigKey = ('{0}{1}' -f $S3Path, $OriginalName)
    $WriteS3Orig = @{
        BucketName  = $BucketName
        EndpointUrl = $EndpointUri
        File        = $FilePath
        Key         = "uploads/$OrigKey"
    }
    Write-S3Object @WriteS3Orig | Out-Null

    if ($Magick.Width -gt 1200) {
        $Magick.Resize(1200, 0)
    }
    $Magick.Quality = 75

    $OrigGuid = [guid]::newguid() -replace '-'
    $ResizedGuid = [guid]::newguid() -replace '-'

    $OriginalName = 'original-{0}{1}' -f $OrigGuid, $File.Extension
    $ResizedName = 'resized-{0}{1}' -f $ResizedGuid, $File.Extension

    try {
        $Magick.Write("$OutputPath\$ResizedName")
    }
    catch { Write-Verbose "Error resizing image" }

    if (Test-Path "$OutputPath\$ResizedName") {
        $ResizedMagick = New-Object ImageMagick.MagickImage("$OutputPath\$ResizedName")
        $ResizedFile = Get-Item "$OutputPath\$ResizedName"

        $ResizedMetadata = [PSCustomObject]@{
            filename  = $File.Name
            size      = $ResizedFile.Length
            width     = $ResizedMagick.Width
            height    = $ResizedMagick.Height
            mime_type = $MimeType
        }
        $ResizedKey = ('{0}{1}' -f $S3Path, $ResizedName)
        $WriteS3Resized = @{
            BucketName  = $BucketName
            EndpointUrl = $EndpointUri
            File        = $ResizedFile.FullName
            Key         = "uploads/$ResizedKey"
        }
        Write-S3Object @WriteS3Resized | Out-Null
        Remove-Item $ResizedFile.FullName
    }
    else {
        $ResizedMetadata = $OriginalMetadata
        $ResizedKey = $OrigKey
    }

    $ImageData = [PSCustomObject]@{
        original = [PSCustomObject]@{
            id       = $OrigKey
            storage  = 'store'
            metadata = $OriginalMetadata
        }
        resized  = [PSCustomObject]@{
            id       = $ResizedKey
            storage  = 'store'
            metadata = $ResizedMetadata
        }
    } 
    $Image = $ImageData | ConvertTo-Json -Depth 10 -Compress

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.ffffff'

    $Query = "UPDATE public.public_photos SET image_data = '$Image' WHERE id = $PublicImageIndex"
    
    try {
        Set-PSQLData -Connection $Connection -Query $Query | Out-Null

        [PSCustomObject]@{
            ImgSrc = '/public_photo/{0}' -f $PublicImageIndex
            ArticleId = $ArticleId
            ImageData = $ImageData
            FileName = $File.Name
        }
    }
    catch {
        Write-Error ('Insert exception: {0}' -f $_.Exception.Message)
    }
}

# Pull an article, strip content apart searching for base64, use New-HuduImage to upload, and return a built string of HTML with the updated image sources
function Repair-Base64ImagesFromArticle {
    param(
        $ArticleID
    )

    $Query = "Select content from articles where id=$ArticleID"
    Write-Host "Retrieving Content for Article $ArticleID"
    $OriginalKBContent = (Get-PSQLData -Connection $Conn -Query $Query).content
    
    Write-Host "Splitting by IMG tag to extract base64"
    $ImageTags = $OriginalKBContent -split "<IMG "
    # Make sure to skip the first index 0 as it will be before the image tags.
    Write-Host "$($ImageTags.count -1) images found. Looping through each one"
    $imgCnt = 1
    $b64imgCnt = 1

    foreach ($Img in $ImageTags[1..$ImageTags.length]) {
        if ($Img -like '*data:image/*;base64*') {
            #$ImgMetadata = (($Img -split ' ')[1] -split '"')[1]
            $base64string = (($img -split 'base64,')[1] -split '"')[0].trim()
            $fileName = $TemporaryFolderPath.fullname + "\Article$ArticleID-image$imgCnt.b64"

            Write-Host "Base64 image found. Saving to file $fileName"
            $bytes = [Convert]::FromBase64String($base64string)
            [IO.file]::WriteAllBytes($filename, $bytes)
            $b64imgCnt++

        }
        $imgCnt++
    }

    if ($b64imgCnt -eq $ImageTags.count) { Write-Host "All images were accounted for as Base64."}

    $UploadedArticleImages = foreach ($Filename in (Get-ChildItem -Path $TemporaryFolderPath -Filter "Article$ArticleID-image*.b64")) {
        Write-Host "Uploading $Filename.fullname to S3 Storage" -ForegroundColor Green
        New-HuduImage -Connection $Conn -FilePath $Filename.fullname -OutputPath $TemporaryFolderPath  -BucketName kbsfiles -EndpointUri https://nyc3.digitaloceanspaces.com -ArticleId $ArticleID
    }
    
    if ($UploadedArticleImages) {

        Write-Host "Uploading to S3 finished, building new HTML content" -ForegroundColor DarkYellow

        while ($imgCnt -gt 1) {
            $b64imgCnt--
            $imgCnt--
            $s3Image = $UploadedArticleImages | Where-Object {(($_.filename -split '-')[1] -replace 'image','' -replace '.b64','') -eq $imgCnt }
            if ($s3Image) {Write-Host "Found corresponding S3 image....updating" -ForegroundColor Red}
            $Img = $ImageTags[$imgCnt]
            if ($Img -like '*data:image/*;base64*') {
                Write-Host "Replacing Base64 Image index array of $imgCnt" -ForegroundColor Red
                $base64string = (($img -split 'base64,')[1] -split '"')[0].trim()
                $ImageTags[$imgCnt] = ($Img.replace("$base64string","REPLACEDSTRING:$($s3Image.ImgSrc)") -replace 'data:image/.*;base64,REPLACEDSTRING:','')
            }

            else {$img; Write-Host "WARNING: $imgcnt is not a base64 image" -ForegroundColor Yellow}

        }

        Write-Host "Finished replacing base64, stringing HTML together" -ForegroundColor DarkYellow



        $fixedHuduContent = $ImageTags -join '<IMG '
        return $fixedHuduContent

    }

}

# Import AWS Tools, and confirm credentials are saved as your default profile
try {
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

# Import ImageMagic Modules, prompt for path if the module is missing
try {
    if (!('ImageMagick.MagickImage' -as [type])) {
        Add-Type -Path '.\Magick.NET-Q16-AnyCPU.dll'
    }
}
catch {
    $ImageMagickPath = (Read-Host "Failed to load ImageMagick. Please provide path for the three DLLs.") + "\Magick.NET-Q16-AnyCPU.dll"
    if (Test-Path "$ImageMagickPath") {
        Add-Type -Path $ImageMagickPath
    }
    else {
        throw "ImageMagick wasn't found at the location specified"

    }
}

# Setup Temporary location for workspace
$TemporaryFolderPath = try {New-Item -Path "$($ENV:APPDATA)\HuduFix" -ItemType Directory -ErrorAction Stop} catch { Get-Item -Path "$($ENV:APPDATA)\HuduFix" }

# Initiate DB Connection
try {
    $Conn = Connect-PSQL @ConnectionDetails -ErrorAction Stop
}
catch {
    Throw "Failed to connect to database. Please make sure you've installed the ODBC Driver, and that you've tunneled the port."
}

# Main script running from here, will validate parameters and process the above functions based on values.

Write-Host 'Running Script'
pause
if ($AritcleIdsToProcess) {

    # Pulling specific document with base64 images from the database. This can take several minutes.
    Write-Host "Pulling document $($AritcleIdsToProcess -join ',') with base64 images from the database. This can take several minutes." -ForegroundColor Cyan
    $InlineImageArticles = Get-PSQLData -Connection $Conn -Query "Select id,name,slug from articles where content like '%data:image%' and id in ($($AritcleIdsToProcess -join ','))"

}

if ($NumberofArticlesToLoop) {

    # Pulling documents with base64 images from the database. This can take several minutes.
    Write-Host "Pulling documents with base64 images from the database. This can take several minutes." -ForegroundColor Cyan
    $InlineImageArticles = Get-PSQLData -Connection $Conn -Query "Select id,name,slug from articles where content like '%data:image%' limit $($NumberofArticlesToLoop)"

}

if ($ProcessAllArticles) {

    # Pulling documents with base64 images from the database. This can take several minutes.
    Write-Host "Pulling documents with base64 images from the database. This can take several minutes." -ForegroundColor Cyan
    $InlineImageArticles = Get-PSQLData -Connection $Conn -Query "Select id,name,slug from articles where content like '%data:image%'"


}

if ($InlineImageArticles) {

    Write-Host "Found articles. Processing"
    # Hudu Api Details needed for fixing documents, only load this into memory if necessary.
    ## SENSITIVE KEYS STORED HERE DO NOT SAVE OR SHARE
    Import-Module HuduAPI
    #New-HuduAPIKey -ApiKey <APIKEY>
    New-HuduAPIKey -ApiKey (Read-Host "Enter your Hudu API Key")
    #New-HuduBaseURL -BaseURL <URL>
    New-HuduBaseURL -BaseURL (Read-Host "Enter your Hudu URL")


    $Results = foreach ($articleToFix in $InlineImageArticles) {
        $newContent = Repair-Base64ImagesFromArticle -ArticleID $articleToFix.id
        Write-Host "Posting new HTML Content to document $articleToFix" -ForegroundColor Cyan
        $updatedDoc = Set-HuduArticle -name $articleToFix.name -content $newContent -id $articleToFix.id

        @{
            articleid = $articleToFix.ID
            articlename = $articleToFix.name
            data = $updatedDoc
            success = if ($updatedDoc) {$TRUE} else {$FALSE}
        }

    }

    $Results |ConvertTo-Json -Depth 10 |Out-File "$TemporaryFolderPath\$((Get-Date).ToString().Replace('/','_').Replace(':','').replace(' ',''))-run.json"

} else {
    Write-Host "No articles found to process - exiting script" -ForegroundColor Green
}
