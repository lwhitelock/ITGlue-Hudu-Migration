function Move-HuduCompanyArticlesToGlobal {
    param(
        [int]$CompanyID
    )

    $ArticlesToRedo = ($MatchedArticles |? {$_.HuduObject.company_id -eq $CompanyID})
    Write-Host "Moving $($ArticlesToRedo.count) Articles"

    foreach ($RedoingArticle in $ArticlesToRedo) {
        $RedoingFolders = $RedoingArticle.folders

        $art_folder_id = $null
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

        Write-Host "Looking for original article"
        if ($ArticleToMove = (Get-HuduArticles -Id $RedoingArticle.HuduObject.id).article) {
            Write-Host "Article found, creating new version"
            $ArticleSplat = @{
                name      = $ArticleToMove.name
                content   = $ArticleToMove.content
                folder_id = $art_folder_id
            }

            if ($MovedArticle = (New-HuduArticle @ArticleSplat).article) {
                $RedoingArticle.HuduID = $MovedArticle.id
                $RedoingArticle.HuduObject = $MovedArticle
                $RedoingArticle.Imported = "Moved from $CompanyID to Global KB"
                Write-Host "Article recreated. Safe to delete original."                
            }
            else {
                Write-Host "Failed to create article."
            }

        }

    }

}
