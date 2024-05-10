param(
    [parameter(ParameterSetName='RunAll')][switch]$ProcessAllArticles,
    [parameter(ParameterSetName='RunOne')]$ArticleIdsToProcess,
    [parameter(ParameterSetName='RunSome')][int]$NumberofArticlesToLoop
)

# Main settings load
. $PSScriptRoot\Initialize-Module.ps1 -InitType 'Lite'

# Pull an article, strip content apart searching for base64, use New-HuduImage to upload, and return a built string of HTML with the updated image sources
function Repair-Base64ImagesFromArticle {
    param(
        $ArticleID
    )

    Write-Host "Retrieving Content for Article $ArticleID"
    $OriginalKBContent = (Get-HuduArticles -id $ArticleID).content
    
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
            $Magick = New-Object ImageMagick.MagickImage($fileName)
            $NewExtension = "-b64.$($Magick.format)"
            Move-Item -Path $filename -Destination $filename.replace('.b64', $NewExtension)
            $b64imgCnt++

        }
        $imgCnt++
    }

    if ($b64imgCnt -eq $ImageTags.count) { Write-Host "All images were accounted for as Base64."}

    $UploadedArticleImages = foreach ($Filename in (Get-ChildItem -Path $TemporaryFolderPath -Filter "Article$ArticleID-image*-b64.*")) {
        Write-Host "Uploading $Filename.fullname to Hudu API" -ForegroundColor Green
        $UploadedImage = New-HuduPublicPhoto -FilePath $Filename.fullname -RecordId $ArticleID -RecordType 'Article'
        [pscustomobject]@{filename=$filename.name; imgsrc = $UploadedImage.public_photo.url }
    }
    
    if ($UploadedArticleImages) {

        Write-Host "Uploading to S3 finished, building new HTML content" -ForegroundColor DarkYellow

        while ($imgCnt -gt 1) {
            $b64imgCnt--
            $imgCnt--
            $HuduImage = $UploadedArticleImages | Where-Object {(($_.filename -split '-')[1] -replace 'image','' -replace '.b64','') -eq $imgCnt }
            if ($HuduImage) {Write-Host "Found corresponding Hudu image....updating" -ForegroundColor Red}
            $Img = $ImageTags[$imgCnt]
            if ($Img -like '*data:image/*;base64*') {
                Write-Host "Replacing Base64 Image index array of $imgCnt" -ForegroundColor Red
                $base64string = (($img -split 'base64,')[1] -split '"')[0].trim()
                $ImageTags[$imgCnt] = ($Img.replace("$base64string","REPLACEDSTRING:$($HuduImage.ImgSrc)") -replace 'data:image/.*;base64,REPLACEDSTRING:','')
            }

            else {$img; Write-Host "WARNING: $imgcnt is not a base64 image" -ForegroundColor Yellow}

        }

        Write-Host "Finished replacing base64, stringing HTML together" -ForegroundColor DarkYellow



        $fixedHuduContent = $ImageTags -join '<IMG '
        return $fixedHuduContent

    }

}

# Setup Temporary location for workspace
$TemporaryFolderPath = try {New-Item -Path "$($ENV:APPDATA)\HuduFix" -ItemType Directory -ErrorAction Stop} catch { Get-Item -Path "$($ENV:APPDATA)\HuduFix" }

# Main script running from here, will validate parameters and process the above functions based on values.

Write-Host 'Running Script'
pause
if ($ArticleIdsToProcess) {

    # Pulling specific document with base64 images from the database. This can take several minutes.
    Write-Host "Pulling document $($ArticleIdsToProcess -join ',') with base64 images from the database. This can take several minutes." -ForegroundColor Cyan
    $InlineImageArticles = Get-PSQLData -Connection $Conn -Query "Select id,name,slug from articles where content like '%data:image%' and id in ($($ArticleIdsToProcess -join ','))"

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
        Write-Host "Posting new HTML Content to document $($articleToFix.name)" -ForegroundColor Cyan
        if (($newContent.count -gt 1) -and ($newContent.getType().name -ne 'String')) {
            $updatedDoc = Set-HuduArticle -name $articleToFix.name -content $newContent[$newContent.length-1] -id $articleToFix.id
        } else {
            $updatedDoc = Set-HuduArticle -name $articleToFix.name -content $newContent -id $articleToFix.id
         }

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
