function New-HuduGlobalPasswordFolder {
    <#
    .SYNOPSIS
    Create a new password folder.

    .DESCRIPTION
    Calls the Hudu API to create a password folder for a given company.  
    Supports configuring name, description, security settings, and allowed groups.

    .PARAMETER Name
    Name of the new folder (required).

    .PARAMETER CompanyId
    The company ID that owns the folder (required).

    .PARAMETER Description
    Description of the folder.

    .PARAMETER Security
    Security mode. Accepts "all_users" or "specific".

    .PARAMETER AllowedGroups
    Array of group IDs that should have access (if Security is "specific").

    .EXAMPLE
    New-HuduPasswordFolder -Name "Infrastructure" -CompanyId 2
    Creates a folder named "Infrastructure" for company ID 2.

    .EXAMPLE
    New-HuduPasswordFolder -Name "Finance" -CompanyId 4 -Security specific -AllowedGroups @(10,12)
    Creates a folder for company 4 restricted to groups 10 and 12.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Name,
        [string]$Description,
        [ValidateSet("all_users","specific")][String]$Security,
        [array]$AllowedGroups)

    $password_folder=@{
        name             = $Name
    }
    $password_folder.company_id       = $null


    if ($Description){
        $password_folder["description"] = $Description
    }
    if ($security -and $security -eq "specific"){
        $password_folder["security"] = $security
        $allGroups = $(Get-HuduGroups).id
        
        if ($($AllowedGroups | where-object {$allGroups -contains $_}).count -gt 0) {
            $password_folder["allowed_groups"]= $AllowedGroups | where-object {$allGroups -contains $_}
        } else {
            $password_folder["allowed_groups"]=@("0")
        }
    } else {
        $password_folder["security"] = 'all_users'
        $password_folder["allowed_groups"]= @()
    }
    $payload = @{password_folder = $password_folder} | ConvertTo-Json -Depth 10
    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/password_folders" -Body $payload
        return $res
    } catch {
        Write-Warning "Failed to create new password folder '$Name'"
        return $null
    }
}


function Normalize-Text {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $s = $s.Trim().ToLowerInvariant()
    $s = [regex]::Replace($s, '[\s_-]+', ' ')  # "primary_email" -> "primary email"
    # strip diacritics (prénom -> prenom)
    $formD = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $formD.ToCharArray()){
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne
            [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    ($sb.ToString()).Normalize([System.Text.NormalizationForm]::FormC)
}
function Compare-StringsIgnoring {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$A,
        [Parameter(Mandatory)] [string]$B,
        $ignore = @(
            '\bthe\b','\borg\b','\binc\b','\bpc\b','\band\b','\bltd\b','[\.,/&'']'
        )
    )

    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) {
        return $false
    }

    function _Normalize($s) {
        $t = $s.ToLowerInvariant()
        foreach ($pattern in $ignore) { $t = $t -replace $pattern, '' }
        ($t -replace '\s+', ' ').Trim()
    }

    $normA = _Normalize $A
    $normB = _Normalize $B
    return ($normA -eq $normB)
}
function Test-Equiv {
    param([string]$A, [string]$B)
    $a = Normalize-Text $A; $b = Normalize-Text $B
    if (-not $a -or -not $b) { return $false }
    if ($a -eq $b) { return $true }
    $reA = "(^| )$([regex]::Escape($a))( |$)"
    $reB = "(^| )$([regex]::Escape($b))( |$)"
    if ($b -match $reA -or $a -match $reB) { return $true } 
    if ($a.Replace(' ', '') -eq $b.Replace(' ', '')) { return $true }
    return $false
}
function Get-Similarity {
    param([string]$A, [string]$B)

    $a = [string](Normalize-Text $A)
    $b = [string](Normalize-Text $B)
    if ([string]::IsNullOrEmpty($a) -and [string]::IsNullOrEmpty($b)) { return 1.0 }
    if ([string]::IsNullOrEmpty($a) -or  [string]::IsNullOrEmpty($b))  { return 0.0 }

    $n = [int]$a.Length
    $m = [int]$b.Length
    if ($n -eq 0) { return [double]($m -eq 0) }
    if ($m -eq 0) { return 0.0 }

    $d = New-Object 'int[,]' ($n+1), ($m+1)
    for ($i = 0; $i -le $n; $i++) { $d[$i,0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0,$j] = $j }

    for ($i = 1; $i -le $n; $i++) {
        $im1 = ([int]$i) - 1
        $ai  = $a[$im1]
        for ($j = 1; $j -le $m; $j++) {
            $jm1 = ([int]$j) - 1
            $cost = if ($ai -eq $b[$jm1]) { 0 } else { 1 }

            $del = [int]$d[$i,  $j]   + 1
            $ins = [int]$d[$i,  $jm1] + 1
            $sub = [int]$d[$im1,$jm1] + $cost

            $d[$i,$j] = [Math]::Min($del, [Math]::Min($ins, $sub))
        }
    }

    $dist   = [double]$d[$n,$m]
    $maxLen = [double][Math]::Max($n,$m)
    return 1.0 - ($dist / $maxLen)
}
function Get-SimilaritySafe { param([string]$A,[string]$B)
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return 0.0 }
    $score = Get-Similarity $A $B
    write-host "$a-$b SCORED $score"
    return $score
}

function ChoseBest-ByName {
    param ([string]$Name,[array]$choices)
return $($choices | ForEach-Object {
[pscustomobject]@{Choice = $_; Score  = $(Get-SimilaritySafe -a "$Name" -b $_.name);}} | where-object {$_.Score -ge 0.95} | Sort-Object Score -Descending | select-object -First 1).Choice
}

$ITGlueJWT = $ITGlueJWT ?? (Read-Host "Please enter your ITGlue JWT as retrieved from browser.")
Clear-Host

# while ($true){
#     Write-Host "Testing provided JWT"
#     try {
#         # just test the call; we don't need the result here
#         $null = Get-ITGPasswordFolders -JWTAuthToken $ITGlueJWT -organization_id $PasswordMatchSet[0].ITGObject.attributes."organization-id" -ComputePaths -Separator "-"
#         break
#     } catch {
#         Write-Host "Issue getting password folders. $_; Re-enter a fresh JWT if possible or enter 0 to cancel PasswordFolders"
#         $ITGlueJWT = Read-Host "Please enter your ITGlue JWT as retrieved from browser."
#         Clear-Host
#         if ("$ITGlueJWT".Trim() -eq "0"){break}

#     }
# }

$global_password_folders = @()
$global_password_folders = $(get-hudupasswordfolders | where-object {-not $_.company_id -or $_.company_id -lt 1})

$ITGPasswordFolders =  @{}
$MatchedPasswordFolders = @()
Write-Host "Please Wait, obtaining password folders"
foreach ($itgcompanyID in ($MatchedPasswords.ITGObject.attributes.'organization-id' | Select-Object -Unique)) {

    # 1) Scope matches to this IT Glue org
    $matchesForOrg = $MatchedPasswords | Where-Object {
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
            # globals only

            $existingFolder = ChoseBest-ByName -name "$FolderName" -choices $(get-hudupasswordfolders | where-object {-not $_.company_id -or $_.company_id -lt 1 -or $null -eq $_.company_id})
            if (-not $existingFolder) {
                Write-Host "Creating Hudu password folder '$FolderName' for company $HuduCompanyId"
                $existingFolder = New-HuduGlobalPasswordFolder -Name $FolderName
                # $global_password_folders = $(get-hudupasswordfolders | where-object {-not $_.company_id -or $_.company_id -lt 1 -or $null -eq $_.company_id})
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
                $existingpassfolderPresent = [bool]$($null -ne $existingpass.password_folder_id)
                if (-not $existingpassfolderPresent) {
                    try {$passChanged=$null; $passChanged=Set-HuduPassword `
                            -Id $updatePass.HuduObject.id `
                            -Company_Id $($existingpass.company_id ?? $HuduCompanyId) `
                            -Password_Folder_Id $existingFolder.id
                        $Modified = [bool]$($passChanged -ne $null)
                    } catch {
                        $passwordError = "Error placing password id $($updatePass.HuduObject.id) in '$FolderName' (Company $HuduCompanyId): $_"
                        $Modified = $false
                    }
                }
            } catch {
                $passwordError = "error encountered assigning folder $_"
            }
            $MatchedPasswordFolders+=[PSCustomObject]@{FolderError=$FolderError; companyError=$companyError; ITGCompanyID= $itgcompanyID; HuduCompanyID=$($existingpass.company_id ?? $HuduCompanyId); ITGPasswordFolder= $passwordFolder; HuduPasswordFolder=$existingFolder; HuduPasswords=$passwordsForFolder; FolderName=$FolderName; PasswordError=$passwordError; Modified = $passChanged; existingFolderPresent=$existingFolderPresent}
        }
    }
}
