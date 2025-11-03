


$ITGlueJWT = $ITGlueJWT ?? $(read-host "Please enter your ITGlue JWT as retrieved from browser.")
while ($true){
    Write-Host "Testing provided JWT"
    try {
        Get-ITGPasswordFolders -JWTAuthToken $ITGlueJWT -organization_id $MatchedPasswords[0].ITGObject.attributes."organization-id" -ComputePaths -Separator "-"
        break
    } catch {
        Write-Host "Issue getting password folders. $_; Re-enter a fresh JWT if possible"
        $ITGlueJWT = $(read-host "Please enter your ITGlue JWT as retrieved from browser.")
        Clear-Host
    }
}

$ITGPasswordFolders = @{}
#ITGPasswordFolders[companyid] = @( @{name=''; ancestry=''})
Write-Host "Please Wait, obtaining password folders"
foreach ($itgcompanyID in $($matchedpasswords.ITGObject.attributes."organization-id" | Select-Object -Unique)){
    $passwordFolderArray = $(Get-ITGPasswordFolders -JWTAuthToken $ITGlueJWT -organization_id $itgcompanyID -ComputePaths -Separator "-").data ?? @()
    if ($passwordFolderArray -and $passwordFolderArray.count -gt 0){
        Write-Host "retrieved $($passwordFolderArray.count) password folders for $($itgcompany.companyName)"
        $ITGPasswordFolders["$itgcompanyID"]=$passwordFolderArray
    } else {Write-Host "No password folders for $($itgcompany.companyName), skipping-"; continue;}
    # since we need to flatten these, iterate through these folders and name them by parents [if they have passwords]
    
    foreach ($passwordFolder in $ITGPasswordFolders["$itgcompanyID"] | where-object {[int]$_.attributes.'passwords-count' -gt 0}){
        $FolderName = $passwordFolder.path
        $passwordsForFolder = $matchedpasswords | where-object {[string]$_.ITGObject.attributes.'password-folder-id' -eq "$($passwordFolder.id)"}
        if (-not $passwordsForFolder -or $passwordsForFolder.count -lt 1){
            Write-Host "Seemingly no passwords for password folder: $FolderName"
            continue
        }
        $HuduCompanyId = $matchedpasswords[0].HuduObject.company_id
        Write-Host "$($passwordsForFolder.count) passwords for $FolderName in company $($HuduCompanyId)"
        
        $existingFolder = Get-HuduPasswordFolders -CompanyId $HuduCompanyId -name $FolderName
        if (-not $existingFolder){
            Write-Host "creating new password folder $folderName for company ID $HuduCompanyId"
            $existingFolder = New-HuduPasswordFolder -Name $FolderName -companyid $HuduCompanyId
        }
        foreach ($updatePass in $passwordsForFolder){
            Set-HuduPassword -id $updatePass.id -password_folder_id $existingFolder.id
        }
    }
}

