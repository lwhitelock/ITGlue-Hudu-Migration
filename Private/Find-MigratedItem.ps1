function Find-MigratedItem {
    param (
        $ITGID
    )

    $FoundItem = $MatchedAssets | Where-Object { $_.ITGID -eq $ITGID }
	
    if (!$FoundItem) {
        $FoundItem = $MatchedContacts | Where-Object { $_.ITGID -eq $ITGID }
    }
 	
    if (!$FoundItem) {
        $FoundItem = $MatchedConfigurations | Where-Object { $_.ITGID -eq $ITGID }
    }
 	
    if (!$FoundItem) {
        $FoundItem = $MatchedLocations | Where-Object { $_.ITGID -eq $ITGID }
    }

		
    return $FoundItem

}