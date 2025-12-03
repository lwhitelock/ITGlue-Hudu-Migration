# Check if this is a direct run, and load the logs if so the first time.
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


    if ($Articles) {
        Write-host "Loading Articles Log"
        if (-not ($ITGlueDocuments = (Get-Content "$MigrationLogs\Articles.json" | ConvertFrom-json -Depth 50))) {
            Write-Warning "Article log is missing, using ArticleBase file"
            $ITGlueBaseDocuments = Get-Content "$MigrationLogs\ArticleBase.json" | ConvertFrom-json -Depth 50
        }

        # This is specifically for the article content, skipping stubs for right now.
        # Get Attachment directories so we can match on the name per article, this needs to be outside the loop so we don't constantly re-run it
		$AttchmentsPath = Join-Path -Path $ITGLueExportPath -ChildPath "attachments\documents"
		$AttchmentsPath = "\\?\$AttchmentsPath"
        $Attachfiles = Get-ChildItem -LiteralPath $AttchmentsPath -Recurse -Force
        
                    # Now do the actual work of populating the content of articles
            $ArticleErrors = foreach ($Article in $UnmatchedArticles) {

                $page_out = ''
                
            
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
                        Data          = "$($attachdir.fullname)"
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
                            if ($fullImgUrl -and ($foundFile = Get-Item -LiteralPath "$fullImgPath*" -ErrorAction SilentlyContinue)) {
                                $imagePath = $foundFile.FullName
                            } elseif ($tnImgUrl -and ($foundFile = Get-Item -LiteralPath "$tnImgPath*" -ErrorAction SilentlyContinue)) {
                                $imagePath = $foundFile.FullName
                            } else { 
                                Remove-Variable -Name imagePath -ErrorAction SilentlyContinue
                                Remove-Variable -Name foundFile -ErrorAction SilentlyContinue
                                Write-Warning "Unable to validate image file."
                                [PSCustomObject]@{
                                ErrorType = 'Image missing found'
                                Details = "Neither $fullImgPath or $tnImgPath were found"
                                InFile = "$InFile"
                                MigrationObject = $Article
                            }
                        }

                            # Test the path to ensure that a file extension exists, if no file extension we get problems later on. We rename it if there's no ext.
                            if ($imagePath -and (Test-Path $imagePath -ErrorAction SilentlyContinue)) {
                                if ((Get-Item -LiteralPath $imagePath).extension -eq '') {
                                    Write-Warning "$imagePath is undetermined image. Testing..."
                                    if ($Magick = New-Object ImageMagick.MagickImage($imagePath)) {
                                        $OriginalFullImagePath = $imagePath
                                        $imagePath = "$($imagePath).$($Magick.format)"
                                        $MovedItem = Move-Item -Path "$OriginalFullImagePath" -Destination "$imagePath"
                                    }
                                }                        
                                $imageType = Invoke-ImageTest($imagePath)
                                if ($imageType) {
                                    Write-Host "Uploading new image"
                                    try {
                                        $UploadImage = New-HuduPublicPhoto -FilePath "$imagePath" -record_id $Article.HuduID -record_type 'Article'
                                        $NewImageURL = $UploadImage.public_photo.url.replace($HuduBaseDomain, '')
                                        $ImgLink = $html.Links | Where-Object {$_.innerHTML -eq $imgHTML}
                                        Write-Host "Setting image to: '$NewImageURL'"
                                        $_.src = [string]"$NewImageURL"
                                        
                                        # Update Links for this image
                                        $ImgLink.href = [string]"$NewImageUrl"

                                    }
                                    catch {
                                        [PSCustomObject]@{
                                            ErrorType = 'Failed to Upload to Backend Storage'
                                            Details = "$imagePath failed to upload to Hudu backend. $_"
                                            InFile = "$InFile"
                                            MigrationObject = $Article
                                        }
                                    }
                                    if ($Magick -and $MovedItem) {
                                        Move-Item -Path "$imagePath" -Destination "$OriginalFullImagePath"
                                    }
            
                                }
                                else {
                                    [PSCustomObject]@{
                                        ErrorType       = 'Image Not Detected'
                                        Details         = "$imagePath not detected as image"
                                        InFile          = "$InFile"
                                        MigrationObject = $Article
                                    }
                                }
                            }
                            else {
                                Write-Warning "Image $tnImgUrl file is missing"
                                [PSCustomObject]@{
                                    ErrorType       = 'Image File Missing'
                                    Details         = "$tnImgUrl is not present in export"
                                    InFile          = "$InFile"
                                    MigrationObject = $Article
                                }
                            }
                        }
                    }
                    
                
                    $page_Source = $html.documentelement.outerhtml
                    $page_out = [regex]::replace($page_Source , '\xa0+', ' ')
                            
                }
            
                if ($page_out.Length -lt 1) { 

                }else {
                    $page_out = 'Empty Document in IT Glue Export - Please Check IT Glue'
                    [PSCustomObject]@{
                        ErrorType       = 'Empty Document'
                        Details         = 'An Empty Document Was Detected'
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


    }

