$ITGlueJWT = $ITGlueJWT ?? (Read-Host "Please enter your ITGlue JWT as retrieved from browser.")
Clear-Host

while ($true){
    Write-Host "Testing provided JWT"
    try {
        # just test the call; we don't need the result here
        $null = Get-ITGPasswordFolders -JWTAuthToken $ITGlueJWT -organization_id $MatchedPasswords[0].ITGObject.attributes."organization-id" -ComputePaths -Separator "-"
        break
    } catch {
        Write-Host "Issue getting password folders. $_; Re-enter a fresh JWT if possible or enter 0 to cancel PasswordFolders"
        $ITGlueJWT = Read-Host "Please enter your ITGlue JWT as retrieved from browser."
        Clear-Host
        if ("$ITGlueJWT".Trim() -eq "0"){break}

    }
}

$ITGPasswordFolders = $ITGPasswordFolders ?? @{}
$MatchedPasswordFolders = $MatchedPasswordFolders ?? @()
Write-Host "Please Wait, obtaining password folders"

foreach ($itgcompanyID in ($matchedpasswords.ITGObject.attributes.'organization-id' | Select-Object -Unique)) {

    # 1) Scope matches to this IT Glue org
    $matchesForOrg = $matchedpasswords | Where-Object {
        [string]$_.ITGObject.attributes.'organization-id' -eq [string]$itgcompanyID
    }
    if (-not $matchesForOrg -or $matchesForOrg.Count -eq 0) {
        Write-Host "No matched passwords for ITG org $itgcompanyID — skipping."
        continue
    }

    # 2) Get folders for this org (paths already computed)
    $passwordFolderArray = Get-ITGPasswordFolders -JWTAuthToken $ITGlueJWT -organization_id $itgcompanyID -ComputePaths -Separator "-"
    if (-not $passwordFolderArray -or $passwordFolderArray.Count -eq 0) {
        Write-Host "No password folders for $itgcompanyID — skipping."
        continue
    }
    Write-Host "Retrieved $($passwordFolderArray.Count) password folders for $itgcompanyID"
    $ITGPasswordFolders["$itgcompanyID"] = $passwordFolderArray

    # 3) Only consider folders that actually have passwords *in this org’s matches*
    $foldersWithPasswords = foreach ($pf in $passwordFolderArray) {
        $has = $matchesForOrg | Where-Object {
            [string]$_.ITGObject.attributes.'password-folder-id' -eq [string]$pf.id
        }
        if ($has) { $pf }
    }

    foreach ($passwordFolder in $foldersWithPasswords) {
        $FolderName = $passwordFolder.path

    # 4) Get the passwords for THIS folder but only from THIS org
        $passwordsForFolder = $matchesForOrg | Where-Object {
            [string]$_.ITGObject.attributes.'password-folder-id' -eq [string]$passwordFolder.id
        }
        if (-not $passwordsForFolder -or $passwordsForFolder.Count -lt 1) {
            Write-Host "Seemingly no passwords for folder: $FolderName"
            continue
        }

    # 5) Derive the Hudu company id from those passwords; ensure they all agree
        $companyGroups = $passwordsForFolder | Group-Object { $_.HuduObject.company_id }
        if ($companyGroups.Count -ne 1) {
            Write-Warning ("Folder '{0}' (ITG org {1}) maps to multiple Hudu company_ids: {2}. " +
                           "Picking the largest group, but you should review.") -f $FolderName, $itgcompanyID, ($companyGroups.Name -join ', ')
            $dominant = $companyGroups | Sort-Object Count -Descending | Select-Object -First 1
            $HuduCompanyId = [int]$dominant.Name
            $passwordsForFolder = $dominant.Group
        } else {
            $HuduCompanyId = [int]$companyGroups[0].Name
        }

        Write-Host "$($passwordsForFolder.Count) passwords for '$FolderName' in Hudu company $HuduCompanyId"

    # 6) Ensure the Hudu password folder exists for company
        try {
            $existingFolder = Get-HuduPasswordFolders -CompanyId $HuduCompanyId -Name $FolderName | Select-Object -First 1
            if (-not $existingFolder) {
                Write-Host "Creating Hudu password folder '$FolderName' for company $HuduCompanyId"
                $existingFolder = New-HuduPasswordFolder -CompanyId $HuduCompanyId -Name $FolderName
            }
        } catch {
            Write-Warning "Error during password folder lookup/create for '$FolderName' (Company $HuduCompanyId): $_"
            continue
        }

    # 7) Move/place each password
        $huduPasswordsChanged=@()
        foreach ($updatePass in $passwordsForFolder) {
            try {
                $passChanged=Set-HuduPassword `
                    -Id $updatePass.HuduObject.id `
                    -Company_Id $HuduCompanyId `
                    -Password_Folder_Id $existingFolder.id
                $huduPasswordsChanged+=$($passChanged.asset_password ?? $passChanged)
            } catch {
                Write-Warning "Error placing password id $($updatePass.HuduObject.id) in '$FolderName' (Company $HuduCompanyId): $_"
            }
        }
        $MatchedPasswordFolders+=[PSCustomObject]@{
            ITGCompanyID            = $itgcompanyID
            HuduCompanyID           = $HuduCompanyId
            ITGPasswordFolder       = $passwordFolder
            HuduPasswordFolder      = $existingFolder
            HuduPasswords           = $passwordsForFolder
            FolderName              = $FolderName
        }    
    }
}
