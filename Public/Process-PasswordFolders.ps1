
$global_password_folders = @()
$ITGPasswordFolders =  @{}
$MatchedPasswordFolders = @()
$GlobalPasswordFolderMode = $GlobalPasswordFolderMode ?? $([bool]$("global" -eq $(Select-ObjectFromList -message "Password folder import mode-" -objects @("global","per-company"))))

if (-not (Get-Command -Name Get-ITGPasswordFolders -ErrorAction SilentlyContinue)) { . $PSScriptRoot\Public\Get-PasswordFolders.ps1 }
if (-not (Get-Command -Name Get-ITGlueJWTAuth -ErrorAction SilentlyContinue)) { . $PSScriptRoot\Public\JWT-Auth.ps1 }
$ITGlueJWT = Get-ITGlueJWTAuth -ITglueJWT $ITglueJWT

$PFMappings = $PFMappings ?? @{}
# $PFMappings["Software &"]="Software & Applications"
# $PFMappings["Software and"]="Software & Applications"

function ChoseBest-ByName {
    param ([string]$Name,[array]$choices)
return $($choices | ForEach-Object {
[pscustomobject]@{Choice = $_; Score  = $(Get-SimilaritySafe -a "$Name" -b $_.name);}} | where-object {$_.Score -ge 0.98} | Sort-Object Score -Descending | select-object -First 1).Choice
}

function remove-hudupasswordfromfolder {
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id
    )
    $AssetPassword = [ordered]@{asset_password = $(Get-HuduPasswords -Id $Id) }
    $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name password_folder_id -Force -Value $null
    Invoke-HuduRequest -Method put -Resource "/api/v1/asset_passwords/$Id" -Body $($AssetPassword | ConvertTo-Json -Depth 10)
}

function New-HuduGlobalPasswordFolder {
    param ([Parameter(Mandatory)] [string]$Name)
    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/password_folders" -Body $(@{password_folder = @{name = $Name; security = "all_users"; allowed_groups  = @()}} | ConvertTo-Json -Depth 10)
        return $res
    } catch {
        Write-Warning "Failed to create new password folder '$Name'- $_"; return $null;
    }
}

$global_password_folders = $(get-hudupasswordfolders | where-object {-not $_.company_id -or $_.company_id -lt 1})

Write-Host "Please Wait, obtaining password folders from ITGlue"
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
    $passwordFolderArray = Get-ITGPasswordFolders -JWTAuthToken $ITGlueJWT -organization_id $itgcompanyID -ComputePaths -Separator "<FDELIM>"
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
        $companyError = $null; $folderError = $null; $passwordError = $null; $Modified = $false; $existingpass = $null;
        
        $FolderName = ($passwordFolder.path -split "<FDELIM>")[0]
        $match = $null
        $match = $PFMappings.Keys | Sort-Object { $_.Length } -Descending | Where-Object { $FolderName.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if ($match) {
            Write-Host "Matched map term $match"
            $FolderName = $PFMappings[$match]
        }


        write-host "folder name $foldername from path $($passwordFolder.path)" -ForegroundColor DarkCyan


    # 4) Get the passwords for THIS folder but only from THIS org
        $passwordsForFolder = $matchesForOrg | Where-Object {
            [string]$_.ITGObject.attributes.'password-folder-id' -eq [string]$passwordFolder.id
        }
        if (-not $passwordsForFolder -or $passwordsForFolder.Count -lt 1) {
            $folderError= "Seemingly no MATCHED passwords for folder: $FolderName"
            $MatchedPasswordFolders+=[PSCustomObject]@{FolderError=$FolderError; companyError=$companyError; ITGCompanyID= $itgcompanyID; HuduCompanyID=$($existingpass.company_id ?? $HuduCompanyId); ITGPasswordFolder= $passwordFolder; HuduPasswordFolder=$existingFolder; HuduPasswords=$passwordsForFolder; FolderName=$FolderName; PasswordError=$passwordError; Modified = $passChanged; existingFolderPresent=$existingFolderPresent}
            continue
        }

    # 5) Derive the Hudu company id from those passwords; ensure they all agree
        $companyGroups = $passwordsForFolder | where-object {$_.HuduObject.company_id -and $_.HuduObject.company_id -ge 1} | Group-Object { $_.HuduObject.company_id }
        if ($companyGroups.Count -ne 1) {
            $dominant = $companyGroups | Sort-Object Count -Descending | Select-Object -First 1
            $HuduCompanyId = [int]$dominant.Name
            $passwordsForFolder = $dominant.Group
        } else {
            $HuduCompanyId = [int]$companyGroups[0].Name
            if ($HuduCompanyId -lt 1) {
                $HuduCompanyId = [int]$companyGroups[1].Name
            }
        }
        Write-Host "$($passwordsForFolder.Count) passwords for '$FolderName' in Hudu company $HuduCompanyId"
        if (-not $HuduCompanyId -or $HuduCompanyId -lt 1){
            $companyError= "Company doesnt seem to exist?"
            $MatchedPasswordFolders+=[PSCustomObject]@{FolderError=$FolderError; companyError=$companyError; ITGCompanyID= $itgcompanyID; HuduCompanyID=$($existingpass.company_id ?? $HuduCompanyId); ITGPasswordFolder= $passwordFolder; HuduPasswordFolder=$existingFolder; HuduPasswords=$passwordsForFolder; FolderName=$FolderName; PasswordError=$passwordError; Modified = $passChanged; existingFolderPresent=$existingFolderPresent}
            continue
        }

        # 6) Ensure the Hudu password folder exists for company
        try {
            if ($true -ne $GlobalPasswordFolderMode){
            # company-specific 
                $existingFolder = Get-HuduPasswordFolders -CompanyId $HuduCompanyId -Name $FolderName | Select-Object -First 1
                if (-not $existingFolder) {
                    Write-Host "Creating Hudu password folder '$FolderName' for company $HuduCompanyId"
                    $existingFolder = New-HuduPasswordFolder -CompanyId $HuduCompanyId -Name $FolderName
                }
            } else {
            # globals only - fuzzy-match for naming differences ohn source
                $existingFolder = ChoseBest-ByName -name "$FolderName" -choices $(get-hudupasswordfolders | where-object {-not $_.company_id -or $_.company_id -lt 1 -or $null -eq $_.company_id})
                if (-not $existingFolder) {
                    Write-Host "Creating Hudu password folder '$FolderName' for company $HuduCompanyId"
                    $existingFolder = New-HuduGlobalPasswordFolder -Name $FolderName
                    # $global_password_folders = $(get-hudupasswordfolders | where-object {-not $_.company_id -or $_.company_id -lt 1 -or $null -eq $_.company_id})
                }
            }
            if (-not $existingFolder) {
                $folderError = "No folder $FolderName for company $HuduCompanyId"
            } else {write-host "$folderName -> $($existingFolder.name)"}
        } catch {
                $folderError = "folder error during fetch / create for folder $FolderName for company $HuduCompanyId $_"
        }
        if ($null -ne $folderError){
            $MatchedPasswordFolders+=[PSCustomObject]@{FolderError=$FolderError; companyError=$companyError; ITGCompanyID= $itgcompanyID; HuduCompanyID=$($existingpass.company_id ?? $HuduCompanyId); ITGPasswordFolder= $passwordFolder; HuduPasswordFolder=$existingFolder; HuduPasswords=$passwordsForFolder; FolderName=$FolderName; PasswordError=$passwordError; Modified = $passChanged; existingFolderPresent=$existingFolderPresent}
            continue
        } 
            

    # 7) Move/place each password
        foreach ($updatePass in $passwordsForFolder) {
            $modified=$false
            try {
                $existingpass = get-hudupasswords -id $updatePass.HuduObject.id; $existingpass = $existingpass.asset_password ?? $existingpass
                if (-not $existingpass) {$passwordError =  "no pass can be retrieved"
                    $passwordError =  "no pass can be retrieved without error $_"
                }
            } catch {
                $passwordError = "Error encounted validating password $_"
            }
            try {
                if ($null -ne $passwordError){
                    $MatchedPasswordFolders+=[PSCustomObject]@{FolderError=$FolderError; companyError=$companyError; ITGCompanyID= $itgcompanyID; HuduCompanyID=$($existingpass.company_id ?? $HuduCompanyId); ITGPasswordFolder= $passwordFolder; HuduPasswordFolder=$existingFolder; HuduPasswords=$passwordsForFolder; FolderName=$FolderName; PasswordError=$passwordError; Modified = $passChanged; existingFolderPresent=$existingFolderPresent}
                    continue
                }
                try {
                    $passChanged=$null; $passChanged=Set-HuduPassword `
                        -Id $updatePass.HuduObject.id `
                        -Company_Id $($existingpass.company_id ?? $HuduCompanyId) `
                        -Password_Folder_Id $existingFolder.id
                    $Modified = [bool]$($passChanged -ne $null)
                } catch {
                    $passwordError = "Error placing password id $($updatePass.HuduObject.id) in '$FolderName' (Company $HuduCompanyId): $_"
                    $Modified = $false
                }
            } catch {
                $passwordError = "error encountered assigning folder $_"
            }
            $MatchedPasswordFolders+=[PSCustomObject]@{FolderError=$FolderError; companyError=$companyError; ITGCompanyID= $itgcompanyID; HuduCompanyID=$($existingpass.company_id ?? $HuduCompanyId); ITGPasswordFolder= $passwordFolder; HuduPasswordFolder=$existingFolder; HuduPasswords=$passwordsForFolder; FolderName=$FolderName; PasswordError=$passwordError; Modified = $passChanged; existingFolderPresent=$existingFolderPresent}
        }
    }
}

$companyPasswordFolderAttributionMove = $companyPasswordFolderAttributionMove ?? $true
$minCompanyPctForGlobalFolder = $minCompanyPctForGlobalFolder ?? 0.125 # defaults to 1/8th of companies with passwords as threshold for moving to global folder if using global password folder mode but allowing company attribution move

if ($true -eq $companyPasswordFolderAttributionMove) {
    $allPasswordFolders = Get-HuduPasswordFolders | Where-Object { -not $_.company_id -or $_.company_id -lt 1 }
    $allPasswords = Get-HuduPasswords
    $companyIdsWithAnyPasswords = $allPasswords.company_id | Where-Object { $_ -ge 1 } | Sort-Object -Unique
    $denom = [math]::Max(1, $companyIdsWithAnyPasswords.Count)

    foreach ($folder in $allPasswordFolders) {
        $passwordsInFolder = $allPasswords | Where-Object { $_.password_folder_id -eq $folder.id }
        $companyGroups = $passwordsInFolder.company_id | Where-Object { $_ -ge 1 } | Sort-Object -Unique

        $representedPct = $companyGroups.Count / $denom
        Write-Host ("Folder '{0}' has passwords from {1} company(ies) ({2:P1} of companies-with-passwords)" -f $folder.name, $companyGroups.Count, $representedPct)

        if ($companyGroups -gt 1 -and $representedPct -lt $minCompanyPctForGlobalFolder) {
            Write-Host ("Moving folder '{0}' because {1:P1} < threshold {2:P1}" -f $folder.name, $representedPct, $minCompanyPctForGlobalFolder)
            foreach ($companyId in $companyGroups) {
                Write-Host "Company $companyId has password(s) in folder '$($folder.name)'"

                $companyPasswords = $passwordsInFolder | Where-Object { $_.company_id -eq $companyId }
                $companyScopedFolder = Get-HuduPasswordFolders -CompanyId $companyId -Name $folder.name | Select-Object -First 1

                if ($null -eq $companyScopedFolder) {
                    Write-Host "Creating company-scoped folder for company $companyId for folder '$($folder.name)'"
                    $companyScopedFolder = New-HuduPasswordFolder -CompanyId $companyId -Name $folder.name
                    $companyScopedFolder = $companyScopedFolder.password_folder ?? $companyScopedFolder
                } else {
                    Write-Host "Company-scoped folder already exists for company $companyId for folder '$($folder.name)'"
                }

                Write-Host "Moving $($companyPasswords.Count) password(s) to company-scoped folder '$($companyScopedFolder.name)' for company $companyId"

                foreach ($pass in $companyPasswords) {
                    try {
                        Set-HuduPassword -Id $pass.id -Company_Id $companyId -Password_Folder_Id $companyScopedFolder.id
                    } catch {
                        Write-Warning "Failed to move password id $($pass.id) to company-scoped folder '$($companyScopedFolder.name)' for company $companyId $_"
                    }
                }
            }
            write-host "Deleting global folder '$($folder.name)' since it now should have no passwords in it"
            Remove-HuduPasswordFolder -Id $folder.id
        } else {
            Write-Host ("Keeping folder '{0}' because {1:P1} >= threshold {2:P1}" -f $folder.name, $representedPct, $minCompanyPctForGlobalFolder)
        }
    }
}