# Check if this is a direct run, and load the logs if so the first time.
if (-not ($FirstTimeLoad -eq 1)) {
    if (-not $MatchedPasswords) {$MatchedPasswords = (Get-Content -path "$MigrationLogs\Passwords.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedAssetPasswords) {$MatchedAssetPasswords = (Get-Content -path "$MigrationLogs\AssetPasswords.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedArticles) {$MatchedArticles = (Get-Content -path "$MigrationLogs\Articles.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedCompanies) {$MatchedCompanies = (Get-Content -path "$MigrationLogs\Companies.json" | ConvertFrom-json -depth 100) }
    # Set the context so logs don't run again unless the powershell window gets closed.
    $FirstTimeLoad = 1
}

function Add-HuduRelation {
    param(
        $relation
    )

    switch ($relation.relation_type) {
        "AssetPassword" {
            if (!($HuduLinkedObject = $MatchedPasswords | Where-Object {$_.ITGID -eq $relation.itg_to_id})) {
                $HuduLinkedObject = $MatchedAssetPasswords | Where-Object {$_.ITGID -eq $relation.itg_to_id}
            }
        }
        "Article" {
            $HuduLinkedObject = $MatchedArticles | Where-Object {$_.ITGID -eq $relation.itg_to_id}
        }
        "Company" {
            $HuduLinkedObject = $MatchedCompanies | Where-Object {$_.ITGID -eq $relation.itg_to_id}
        }
        default {Write-Warning "No matching relationship type found"}
    }

    if ($HuduLinkedObject) {
        return (New-HuduRelation -FromableType 'Asset' -FromableID $relation.hudu_from_id -ToableType $relation.relation_type -ToableID $HuduLinkedObject.HuduID).relation
    }
}
