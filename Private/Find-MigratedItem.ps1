function Find-MigratedItem {
    param (
        $ITGID,
        [bool]$assetsOnly=$true
    )

    $FoundItem = $MatchedAssets | Where-Object { [string]($_.ITGID) -eq [string]"$ITGID" }
	
    if (!$FoundItem) {
        $FoundItem = $MatchedContacts | Where-Object { [string]($_.ITGID) -eq [string]"$ITGID" }
    }
 	
    if (!$FoundItem) {
        $FoundItem = $MatchedConfigurations | Where-Object { [string]($_.ITGID) -eq [string]"$ITGID" }
    }
 	
    if (!$FoundItem) {
        $FoundItem = $MatchedLocations | Where-Object { [string]($_.ITGID) -eq [string]"$ITGID" }
    }
    if ($false -eq $assetsOnly -and !$FoundItem) {
        $FoundItem = $MatchedCompanies | Where-Object { [string]($_.ITGID) -eq [string]"$ITGID" }
    }
    if ($false -eq $assetsOnly -and !$FoundItem) {
        $FoundItem = $MatchedWebsites | Where-Object { [string]($_.ITGID) -eq [string]"$ITGID" }
    }    
    if ($false -eq $assetsOnly -and !$FoundItem) {
        $FoundItem = $MatchedPasswords | Where-Object { [string]($_.ITGID) -eq [string]"$ITGID" }
    }
    if ($false -eq $assetsOnly -and !$FoundItem) {
        $FoundItem = $MatchedArticles | Where-Object { [string]($_.ITGID) -eq [string]"$ITGID" }
    }        
    return $FoundItem

}