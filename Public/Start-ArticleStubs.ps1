if (-not (Get-Command -Name Resolve-ArticleFolderPath -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\Resolve-ArticleFolderPath.ps1"
}

function Start-ArticleStubs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)]$Files,
        [Parameter(Mandatory)][string]$ITGDocumentsPath,
        [Parameter(Mandatory)]$MatchedCompanies,
        $GlobalKBFolder,
        [switch]$IncludeIgnoredFirstArticleDirectory,
        [switch]$PlaceInternalDocsInInternalCompany
    )
    $doc = $Document

    Write-Host "Starting $($doc.name)" -ForegroundColor Green

    $escapedLocator = [WildcardPattern]::Escape([string]$doc.locator)
    $dir = $Files | Where-Object {
        $_.PSIsContainer -and $_.Name -like "*$escapedLocator*"
    } | Select-Object -First 1

    if (-not $dir) {
        Write-Host "Not Found $($doc.locator) this article will need to be migrated manually" -ForegroundColor Yellow
        return $null
    }

    # ITGlue sometimes has export oddities like multiple folders for the same article or various names on the articles.
    $documentFiles = @(Get-ChildItem -LiteralPath $dir.FullName -Filter *.htm* -ErrorAction SilentlyContinue)
    if (-not $documentFiles) {
        Write-Host "HTML Files were not found under $($dir.FullName) this article will need to be migrated manually" -ForegroundColor Red
        return $null
    }

    if ($documentFiles.Count -gt 1) {
        Write-Warning "Found more than one HTML file for this article. Using the first match only."
    }
    $DocumentFile = $documentFiles | Sort-Object FullName | Select-Object -First 1

    $folderResolution = Resolve-ArticleFolderPath `
        -BasePath $ITGDocumentsPath `
        -FullPath $DocumentFile.Directory.FullName `
        -IncludeIgnoredFirstArticleDirectory:$IncludeIgnoredFirstArticleDirectory

    $folders = $folderResolution.FolderSegments
    $foldersToInitialize = $folderResolution.FoldersToInitialize
    $Filename = $DocumentFile.Name
    $company = $MatchedCompanies | Where-Object { $_.CompanyName -eq $doc.organization }

    if (($company | Measure-Object).Count -ne 1) {
        Write-Host "Company $($doc.organization) Not Found Please migrate $($doc.name) manually"
        return $null
    }

    $articleUsesGlobalKB = [bool]($company.InternalCompany -and -not $PlaceInternalDocsInInternalCompany)
    $art_folder_id = $null

    if (-not $articleUsesGlobalKB) {
        if ($foldersToInitialize.Count -gt 0) {
            $art_folder_id = (Initialize-HuduFolder $foldersToInitialize -company_id $company.HuduID).id
        }
        $ArticleSplat = @{
            name       = $doc.name
            content    = "Migration in progress"
            company_id = $company.HuduID
            folder_id  = $art_folder_id
        }
    } else {
        if ($foldersToInitialize.Count -gt 0) {
            $targetFolders = @($foldersToInitialize)
            if ($GlobalKBFolder) {
                $targetFolders = @($GlobalKBFolder.name) + $targetFolders
            }
            $art_folder_id = (Initialize-HuduFolder $targetFolders).id
        } elseif ($GlobalKBFolder) {
            $art_folder_id = $GlobalKBFolder.id
        }

        $ArticleSplat = @{
            name      = $doc.name
            content   = "Migration in progress"
            folder_id = $art_folder_id
        }
    }

    $NewArticle = (New-HuduArticle @ArticleSplat).article
    if (-not $NewArticle) {
        Write-Warning "Failed to create article stub for $($doc.name)"
        return $null
    }

    if ($articleUsesGlobalKB) {
        Write-Host "Article created in Global KB"
    } else {
        Write-Host "Article created in $($company.CompanyName)"
    }

    return [PSCustomObject]@{
        "Name"            = $doc.name
        "Filename"        = $Filename
        "Path"            = $DocumentFile.Directory.FullName
        "FullPath"        = $DocumentFile.FullName
        "ITGID"           = $doc.id
        "ITGLocator"      = $doc.locator
        "HuduID"          = $NewArticle.ID
        "HuduObject"      = $NewArticle
        "Folders"         = $folders
        "Imported"        = "Stub-Created"
        "Company"         = $company
        "IsGlobalKBArticle" = $articleUsesGlobalKB
    }
}
