function Move-HuduCompanyArticlesToGlobal {
    param(
        [int]$CompanyID
    )

    $ArticlesToRedo = $MatchedArticles |? {$_.HuduObject.company_id -eq $CompanyID}

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
        if ($ArticleToMove = Get-HuduArticles -Id $RedoingArticle.HuduObject.id) {
            $ArticleSplat = @{
                name      = $ArticleToMove.name
                content   = $ArticleToMove.content
                folder_id = $art_folder_id
            }

            $MovedArticle = (New-HuduArticle @ArticleSplat).article
            $RedoingArticle.HuduID = $MovedArticle.id
            $RedoingArticle.HuduObject = $MovedArticle
            $RedoingArticle.Imported = "Moved from $CompanyID to Global KB"
        }

    }

}
