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
    }

    if ($HuduLinkedObject) {
        return (New-HuduRelation -FromableType 'Asset' -FromableID $relation.hudu_from_id -ToableType $relation.relation_type -ToableID $HuduLinkedObject.HuduID).relation
    }
}