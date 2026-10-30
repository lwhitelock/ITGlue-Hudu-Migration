$Articles = Get-HuduArticles

foreach ($Article in $Articles) {
    $ArticleId = $Article.id
    $ArticleName = $Article.name

    # Remove the article
    Remove-HuduArticle -Id $ArticleId -Confirm:$false

    # Log the removal
    Write-Host "Removed article: $ArticleName (ID: $ArticleId)"
}