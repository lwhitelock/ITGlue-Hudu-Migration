function Resolve-ITGlueAPIEndpoint {
    param(
        [AllowNull()]
        [string]$ITGBaseURI
    )

    $resolvedEndpoint = @(
        $ITGBaseURI
        $ITGAPIEndpoint
        $environmentSettings.ITGAPIEndpoint
        $settings.ITGAPIEndpoint
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($resolvedEndpoint)) {
        $resolvedEndpoint = Select-ObjectFromList -objects @("https://api.itglue.com", "https://api.eu.itglue.com", "https://api.au.itglue.com") -message "Select ITGlue API Endpoint for your instance/region"
    }

    return ($resolvedEndpoint.Trim() -replace '[\\/]+$', '')
}

function Get-ITGlueJWTAuth{
    param ([string]$ITglueJWT, [string]$ITGBaseURI)
    $ITGBaseURI = Resolve-ITGlueAPIEndpoint -ITGBaseURI $ITGBaseURI
    $ITGlueJWT = $ITGlueJWT ?? (Read-Host "Please enter your ITGlue JWT as retrieved from browser.")
    Clear-Host

    while ($true){
        Write-Host "Testing provided JWT"
        try {
            $null = Get-ITGlueCheckLists -JWTAuthToken $ITGlueJWT -page_size 1 -page_number 1 -ITGBaseURI $ITGBaseURI
            Write-host "successful authentication"
            return $ITglueJWT   
        } catch {
            Write-Host "Issue retrieving data with JWT auth. $_; Re-enter a fresh JWT if possible or enter 0 to cancel"
            $ITGlueJWT = Read-Host "Please enter your ITGlue JWT as retrieved from browser."
            Clear-Host
            if ("$ITGlueJWT".Trim() -eq "0"){break}
        }
    }
    return $ITglueJWT
}
