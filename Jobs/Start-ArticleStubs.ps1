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


            $company = $MatchedCompanies | Where-Object { $_.CompanyName -eq $doc.organization }
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
                                    Asset_Type    = "Article"
                                    Company_Name  = $Article.Company.CompanyName
                                    HuduID        = $Article.HuduID
                                    Notes         = 'Missing image, file not found'
                                    Actions       = "Neither $fullImgPath or $tnImgPath were found, validate the images exist in the export, or retrieve them from ITGlue directly"
                                    Data          = "$InFile"
                                    Hudu_URL      = $Article.HuduObject.url
                                    ITG_URL       = "$ITGURL/$($Article.ITGLocator)"
                            }
                            $null = $ManualActions.add($ManualLog)
                            continue
                    }
                    # Test the path to ensure that a file extension exists, if no file extension we get problems later on. We rename it if there's no ext.
                    if ($imagePath -and (Test-Path $imagePath -ErrorAction SilentlyContinue)) {
                        Write-Host "File present at purported image path: $imagePath... checking for image..." -ForegroundColor DarkRed

                            $imageType = Invoke-ImageTest $imagePath
                            if ($imageType) {
                                Write-Host "$imagePath appears to contain image... normalizing..." -ForegroundColor DarkRed
                                $imageInfo = Normalize-And-ConvertImage -InputPath $imagePath
                                Write-Host "$imagePath => $($imageInfo.FinalPath)" -ForegroundColor DarkRed

                                $imagePath = $imageInfo.FinalPath ?? $imagePath
                                $OriginalFullImagePath = $imageInfo.Original

                                Write-Host "Uploading new/copied ITGlue image $OriginalFullImagePath => $imagePath"
                                try {
                                    $UploadImage = New-HuduPublicPhoto -FilePath $imagePath.ToLower() -record_id $Article.HuduID -record_type 'Article'
                                } catch {
                    # issue during Upload
                                    Write-ErrorObjectsToFile -ErrorObject @{
                                        Err = $_
                                        ImageObject = $imageObject
                                        ImageLink=$ImgLink
                                        UploadImage=$UploadImage
                                        ImageInfo=$imageInfo
                                        Article=$Article
                                        Problem="image error during upload"
                                    } -name "image-upload-err-$($imageInfo.basename)"
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
                                        Write-Host "Image link object was not found for innerHTML: $imgHTML"
                                    }
                                } catch {
                    # issue during HTML replace / parse
                                    Write-ErrorObjectsToFile -ErrorObject @{
                                        LogEntry        = $ManualLog
                                        Err             = $_
                                        ImageObject     = $imageObject
                                        Problem         = "issue encountered during html image replace."
                                        ImageLink       = $ImgLink
                                        ImageInfo       = $imageInfo
                                        NewImageURL     = $NewImageURL
                                        Article         = $Article
                                    } -name "image-err-$($imageInfo.basename)"

                                    $null = $ManualActions.add($ManualLog)
                                }
                            } else {
                    # image not detected by imagemagick
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
                                Write-ErrorObjectsToFile -ErrorObject @{
                                    LogEntry        = $ManualLog
                                    Article         = $Article
                                    ImageObject     = $imageObject
                                    FileName        = $imagePath
                                    Problem         = "image not detected at '$(Resolve-Path $imagePath)'"
                                } -name "image-nd-$($imagePath)"
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

