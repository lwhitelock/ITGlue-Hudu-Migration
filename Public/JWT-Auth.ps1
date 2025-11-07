function Get-ITGlueJWTAuth{
    param ([string]$ITglueJWT)
    $ITGlueJWT = $ITGlueJWT ?? (Read-Host "Please enter your ITGlue JWT as retrieved from browser.")
    Clear-Host

    while ($true){
        Write-Host "Testing provided JWT"
        try {
            Get-ITGlueCheckLists -JWTAuthToken $ITGlueJWT -page_size $PageSize -page_number $PageNum
            break
        } catch {
            Write-Host "Issue retrieving data with JWT auth. $_; Re-enter a fresh JWT if possible or enter 0 to cancel"
            $ITGlueJWT = Read-Host "Please enter your ITGlue JWT as retrieved from browser."
            Clear-Host
            if ("$ITGlueJWT".Trim() -eq "0"){break}
        }
    }
    return $ITglueJWT
}