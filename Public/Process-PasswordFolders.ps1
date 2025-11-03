


$ITGlueJWT = $ITGlueJWT ?? $(read-host "Please enter your ITGlue JWT as retrieved from browser.")
$ITGPasswordFolders = @{}
$unsortedPasswordFolders = @()
#ITGPasswordFolders[passfolderid] = @{name=''; ancestry=''}
foreach ($itgcompany in $MatchedCompanies){
    Write-Host "retrieving password folders for $($itgcompany.companyName)"
    $passwordFolderArray = Get-ITGPasswordFolders -JWTAuthToken $ITGlueJWT -organization_id $itgcompany.itgid
    $ITGcompanyPWF["$($itgcompany.itgid)"]=
    
}