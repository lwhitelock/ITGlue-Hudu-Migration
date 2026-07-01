# $ImageMap["x:\files\thisfile\that article\...\images\99349394"] = "https://new/public/photo/url"

# Build lookup by filename / image id
$ImageMapByLeaf = @{}

foreach ($kvp in $ImageMap.GetEnumerator()) {
    $leaf = Split-Path $kvp.Key -Leaf

    if (-not $ImageMapByLeaf.ContainsKey($leaf)) {
        $ImageMapByLeaf[$leaf] = $kvp.Value
    }
    else {
        Write-Warning "Duplicate image leaf '$leaf' found in ImageMap. Keeping first value."
    }
}

$HardcodedImagesPattern =
    [regex]::Escape($settings.ITGURL) + '/documents/[^"''\s]*/images/(?<leaf>[^"''\s<>]+)'

$HardcodedImagesArticles = Get-HuduArticles | Where-Object {
    $_.content -imatch $HardcodedImagesPattern
}

foreach ($Article in $HardcodedImagesArticles) {
    $OriginalContent = $Article.content

    $NewContent = [regex]::Replace(
        $OriginalContent,
        $HardcodedImagesPattern,
        {
            param($match)

            $leaf = $match.Groups['leaf'].Value

            if ($ImageMapByLeaf.ContainsKey($leaf)) {
                return $ImageMapByLeaf[$leaf]
            }

            Write-Warning "No image map match for leaf '$leaf' in article '$($Article.name)'"
            return $match.Value
        },
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($NewContent -ne $OriginalContent) {
        Write-Host "Updating article: $($Article.name)"

        Set-HuduArticle `
            -Id $Article.id `
            -CompanyId $Article.company_id `
            -Content $NewContent
    }
}