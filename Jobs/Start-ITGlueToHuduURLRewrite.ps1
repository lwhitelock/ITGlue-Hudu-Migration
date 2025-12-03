# Articles
$articlesUpdated = @()
foreach ($articleFound in $UpdateArticles) {
    if ($NewContent = Update-StringWithCaptureGroups -inputString $articleFound.content -pattern $RichRegexPatternToMatchSansAssets -type "rich") {
        $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichRegexPatternToMatchWithAssets -type "rich"
	$NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichDocLocatorUrlPatternToMatch -type "rich"
 	$NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichDocLocatorRelativeURLPatternToMatch -type "rich"
        Write-Host "Updating Article $($articleFound.name) with replaced Content" -ForegroundColor 'Green'
	try {
        $ArticlePost = Set-HuduArticle -Name $articleFound.name -id $articleFound.id -Content $NewContent -ErrorAction Stop
        $articlesUpdated = $articlesUpdated + @{"status" = "replaced"; "original_article" = $articleFound; "updated_article" = $ArticlePost}
	} catch { $articlesUpdated = $articlesUpdated + @{"status" = "failed"; "original_article" = $articleFound; "attempted_changes" = $newContent} }
        }
    else {
        Write-Warning "Article $articleFound.id found ITGlue URL but didn't match"
        $articlesUpdated = $articlesUpdated + @{"status" = "clean"; "original_article" = $articleFound}
    }
}

$articlesUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedArticlesURL.json"
Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Article URLs Replaced. Continue?"  -DefaultResponse "continue to Assets, please."

# Assets
$assetsUpdated = @()
foreach ($assetFound in $UpdateAssets.HuduObject) {
    $originalAsset = $assetFound
    $replacedStatus = 'clean'
    $customFields = @()

    foreach ($field in $assetFound.fields) {
        # Convert the caption to snake_case to match API expectations for 2.37.1
        $label = ($field.caption -replace '[^\w\s]', '') -replace '\s+', '_' | ForEach-Object { $_.ToLower() }

        if ($label -in @('itglue_url', 'itglue_id', 'imported_from_itglue') -and $field.value -like "*$ITGURL*") {
            $NewContent = Update-StringWithCaptureGroups -inputString $field.value -pattern $RichRegexPatternToMatchSansAssets -type "rich"
            $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichRegexPatternToMatchWithAssets -type "rich"

            if ($NewContent -and $NewContent -ne $field.value) {
                Write-Host "Replacing Asset $($assetFound.name) field $($field.caption) with updated content" -ForegroundColor 'Red'
                $customFields += @{ $label = $NewContent }
                $replacedStatus = 'replaced'
            } else {
                $customFields += @{ $label = $field.value }
            }
        } else {
            # For other fields, preserve existing value (optional)
            $customFields += @{ $label = $field.value }
        }
    }

    if ($replacedStatus -eq 'replaced') {
        Write-Host "Updating Asset $($assetFound.name) with new custom_fields array" -ForegroundColor 'Green'
        $AssetPost = Invoke-HuduRequest -Method PUT -Resource "api/v1/companies/$($assetFound.company_id)/assets/$($assetFound.id)" -Body @{
            name              = $assetFound.name
            asset_layout_id   = $assetFound.asset_layout_id
            custom_fields     = $customFields
        }
    }

    $assetsUpdated += @{
        status         = $replacedStatus
        original_asset = $originalAsset
        updated_asset  = $AssetPost.asset
    }
}

$assetsUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedAssetsURL.json"
Write-TimedMessage -Timeout 3 -Message  "Snapshot Point: Assets URLs Replaced. Continue?" -DefaultResponse "continue to Passwords Matching, please."

# Passwords
$passwordsUpdated = @()
foreach ($passwordFound in $UpdatePasswords.HuduObject) {
    $NewContent = Update-StringWithCaptureGroups -inputString $passwordFound.description -pattern $TextRegexPatternToMatchSansAssets -type "plain"
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $TextRegexPatternToMatchWithAssets -type "plain"
    if ($NewContent) {
        Write-Host "Updating Password $($passwordFound.name) with updated description" -ForegroundColor 'Green'
        $passwordsUpdated = $passwordsUpdated + @{"original_password" = $passwordFound; "updated_password" = (Set-HuduPassword -id $passwordFound.id -Description $NewContent).asset_password}
    }
}
$passwordsUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedPasswordsURL.json"
Write-TimedMessage -Timeout 3 -Message  "Snapshot Point: Password URLs Replaced. Continue?"  -DefaultResponse "continue to Asset Passwords Matching, please."

# Asset Passwords
$assetPasswordsUpdated = @()
foreach ($passwordFound in $UpdateAssetPasswords) {
    $passwordFound = Get-HuduPasswords -id $passwordFound.HuduID
    $NewContent = Update-StringWithCaptureGroups -inputString $passwordFound.description -pattern $TextRegexPatternToMatchSansAssets -type "plain"
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $TextRegexPatternToMatchWithAssets -type "plain"
    if ($NewContent)   {
        Write-Host "Updating Asset Password $($passwordFound.name) with updated description" -ForegroundColor 'Green'
        $assetPasswordsUpdated = $assetPasswordsUpdated + @{"original_password" = $passwordFound; "updated_password" = (Set-HuduPassword -Id $passwordFound.id -Description $NewContent).asset_password}
    }
    
}
$assetPasswordsUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedAssetPasswordsURL.json"
Write-TimedMessage -Timeout 3 -Message  "Snapshot Point: Asset Passwords URLs Replaced. Continue?"  -DefaultResponse "continue to Company Notes, please."

# Company Notes
$companyNotesUpdated = @()
foreach ($companyFound in $UpdateCompanyNotes.HuduCompanyObject) {
    $NewContent = Update-StringWithCaptureGroups -inputString $companyFound.notes -pattern $RichRegexPatternToMatchSansAssets -type "rich"
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichRegexPatternToMatchWithAssets -type "rich"
    if ($NewContent) {
        Write-Host "Updating Company $($companyFound.name) with updated notes" -ForegroundColor 'Green'
        $companyNotesUpdated = $companyNotesUpdated + @{"original_company" = $companyFound; "updated_company" = (Set-HuduCompany -id $companyFound.id -Notes $NewContent).company}
    }

}
$companyNotesUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedCompaniesURL.json"
Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Company Notes URLs Replaced. Continue?"  -DefaultResponse "continue to Manual Actions, please."
