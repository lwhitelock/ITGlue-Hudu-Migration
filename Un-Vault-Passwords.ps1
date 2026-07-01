

$resolvedITGlueExportPath = $ITGLueExportPath ?? $environmentSettings.ITGLueExportPath ?? $settings.ITGLueExportPath
if ([string]::IsNullOrWhiteSpace($resolvedITGlueExportPath)) {
    throw "ITGlue export path is blank. Please set ITGLueExportPath before running the vaulted password update."
}

$sourceCSVpath = $vaultedCSVPath ?? $(Join-Path -Path $resolvedITGlueExportPath -ChildPath "vaulted")
$combinedCSVPath = $(join-path -path $environmentSettings.MigrationLogs -childpath "combined.csv")
Get-ChildItem -path $sourceCSVpath -Recurse -Filter *.csv | Import-Csv | Export-Csv $combinedCSVPath -NoTypeInformation
$unvaultedpasswords = Import-Csv -Path $combinedCSVPath
$MigrationLogs = $MigrationLogs ?? $environmentSettings.MigrationLogs
$MatchedPasswordsJson =  "$MigrationLogs\Passwords.json"

while ([string]::IsNullOrWhiteSpace($combinedCSVPath) -or -not (Test-Path -Path $combinedCSVPath -PathType Leaf)) {
    $combinedCSVPath = Read-Host "Please enter the path to the CSV file containing the unvaulted passwords (or type 'exit' to quit)"
    if ($combinedCSVPath -eq 'exit') {
        Write-Host "Exiting script."
        return
    }
    if (-not (Test-Path -Path $combinedCSVPath -PathType Leaf)) {
        Write-Warning "The file path you entered does not exist or is not a file. Please try again."
        $combinedCSVPath = $null
    }
}

if (Test-Path -LiteralPath $MatchedPasswordsJson -PathType Leaf) {
    $MatchedPasswords = $MatchedPasswords ?? $(Get-Content -LiteralPath $MatchedPasswordsJson -Raw | ConvertFrom-Json -Depth 100)
} elseif (-not $MatchedPasswords) {
    Write-Warning "No Passwords.json found at '$MatchedPasswordsJson' and no in-memory matched passwords were available."
    return
} else {
    Write-Warning "No Passwords.json found at '$MatchedPasswordsJson'. Using the in-memory matched passwords from this PowerShell session."
}

$allHuduPasswords = @(Get-HuduPasswords)
$hudupasswords = @($allHuduPasswords | Where-Object {
    $_.password -ilike "AES256GCM*" -or # typical format
    $_.password -ilike "AES-256-GCM*"  # format sometimes used when blank
})
Write-Host "Loaded $($allHuduPasswords.Count) Hudu passwords, $($hudupasswords.Count) vaulted placeholder passwords, and $($unvaultedpasswords.Count) CSV rows."
if ($hudupasswords.Count -eq 0 -or ($unvaultedpasswords.Count -eq 0)) {
    Write-Warning "No Hudu passwords with AES256GCM/AES-256-GCM placeholder format found or no unvaulted passwords found. Please ensure you have the correct JSON file and CSV file and that they contain the expected data."
    return
}
function Get-PropertyValueSafe {
    param(
        [AllowNull()]
        $Object,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties |
        Where-Object { $_.Name -ieq $PropertyName } |
        Select-Object -First 1
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-NestedPropertyValueSafe {
    param(
        [AllowNull()]
        $Object,

        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    $current = $Object
    foreach ($segment in $Path) {
        if ($null -eq $current) {
            return $null
        }

        $current = Get-PropertyValueSafe -Object $current -PropertyName $segment
    }

    return $current
}

function Get-PasswordIdFromItGlueUrl {
    param(
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $null
    }

    $match = [regex]::Match($Url, '/passwords/(\d+)(?:$|[/?#])', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value
}

function Get-FirstNonEmptyString {
    param(
        [AllowNull()]
        [object[]]$Values
    )

    if ($null -eq $Values) {
        return $null
    }

    foreach ($value in $Values) {
        if ($null -eq $value) {
            continue
        }

        $stringValue = [string]$value
        if (-not [string]::IsNullOrWhiteSpace($stringValue)) {
            return $stringValue
        }
    }

    return $null
}

function Normalize-PasswordMatchValue {
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value).Trim().ToLowerInvariant() -replace '\s+', ' '
}

function Get-PasswordIdentityKey {
    param(
        [AllowNull()]
        $Object,

        [switch]$IncludeUrl
    )

    $name = Normalize-PasswordMatchValue (Get-PropertyValueSafe -Object $Object -PropertyName 'name')
    $username = Normalize-PasswordMatchValue (Get-PropertyValueSafe -Object $Object -PropertyName 'username')
    $url = Normalize-PasswordMatchValue (Get-PropertyValueSafe -Object $Object -PropertyName 'url')

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($username)) {
        return $null
    }

    if ($IncludeUrl) {
        if ([string]::IsNullOrWhiteSpace($url)) {
            return $null
        }

        return "$name`t$username`t$url"
    }

    return "$name`t$username"
}

function Get-PasswordCompanyIdentityKey {
    param(
        [AllowNull()]
        $Object,

        [switch]$IncludeUrl
    )

    $companyId = Normalize-PasswordMatchValue (Get-PropertyValueSafe -Object $Object -PropertyName 'company_id')
    $identityKey = Get-PasswordIdentityKey -Object $Object -IncludeUrl:$IncludeUrl

    if ([string]::IsNullOrWhiteSpace($companyId) -or [string]::IsNullOrWhiteSpace($identityKey)) {
        return $null
    }

    return "$companyId`t$identityKey"
}

function Add-UniqueCsvLookup {
    param(
        [hashtable]$Lookup,
        [hashtable]$Duplicates,
        [AllowNull()]
        [string]$Key,
        [AllowNull()]
        $CsvPassword
    )

    if ([string]::IsNullOrWhiteSpace($Key) -or $Duplicates.ContainsKey($Key)) {
        return
    }

    if ($Lookup.ContainsKey($Key)) {
        $Lookup.Remove($Key)
        $Duplicates[$Key] = $true
        return
    }

    $Lookup[$Key] = $CsvPassword
}

function Add-UniqueObjectLookup {
    param(
        [hashtable]$Lookup,
        [hashtable]$Duplicates,
        [AllowNull()]
        [string]$Key,
        [AllowNull()]
        $Value
    )

    if ([string]::IsNullOrWhiteSpace($Key) -or $Duplicates.ContainsKey($Key)) {
        return
    }

    if ($Lookup.ContainsKey($Key)) {
        $Lookup.Remove($Key)
        $Duplicates[$Key] = $true
        return
    }

    $Lookup[$Key] = $Value
}

$matchedByHuduId = @{}
$matchedByCompanyFullIdentity = @{}
$matchedByCompanyNameUsername = @{}
$duplicateCompanyFullIdentity = @{}
$duplicateCompanyNameUsername = @{}
foreach ($matchedPassword in @($MatchedPasswords)) {
    $possibleHuduIds = @(
        (Get-PropertyValueSafe -Object $matchedPassword -PropertyName 'HuduID'),
        (Get-NestedPropertyValueSafe -Object $matchedPassword -Path @('HuduObject', 'id')),
        (Get-NestedPropertyValueSafe -Object $matchedPassword -Path @('HuduObject', 'asset_password', 'id')),
        (Get-NestedPropertyValueSafe -Object $matchedPassword -Path @('HuduObject', 'asset_passwords', 'id'))
    )

    foreach ($possibleHuduId in $possibleHuduIds) {
        $key = Get-FirstNonEmptyString -Values @($possibleHuduId)
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }

        if (-not $matchedByHuduId.ContainsKey($key)) {
            $matchedByHuduId[$key] = $matchedPassword
        }
    }

    $matchedHuduObject = Get-PropertyValueSafe -Object $matchedPassword -PropertyName 'HuduObject'
    Add-UniqueObjectLookup -Lookup $matchedByCompanyFullIdentity -Duplicates $duplicateCompanyFullIdentity -Key (Get-PasswordCompanyIdentityKey -Object $matchedHuduObject -IncludeUrl) -Value $matchedPassword
    Add-UniqueObjectLookup -Lookup $matchedByCompanyNameUsername -Duplicates $duplicateCompanyNameUsername -Key (Get-PasswordCompanyIdentityKey -Object $matchedHuduObject) -Value $matchedPassword
}

$csvByItgId = @{}
$csvByFullIdentity = @{}
$csvByNameUsername = @{}
$duplicateFullIdentity = @{}
$duplicateNameUsername = @{}
foreach ($csvPassword in @($unvaultedpasswords)) {
    $csvId = Get-FirstNonEmptyString -Values @(
        (Get-PropertyValueSafe -Object $csvPassword -PropertyName 'id'),
        (Get-PropertyValueSafe -Object $csvPassword -PropertyName 'ID')
    )

    if ([string]::IsNullOrWhiteSpace($csvId)) {
        continue
    }

    if (-not $csvByItgId.ContainsKey($csvId)) {
        $csvByItgId[$csvId] = $csvPassword
    }

    Add-UniqueCsvLookup -Lookup $csvByFullIdentity -Duplicates $duplicateFullIdentity -Key (Get-PasswordIdentityKey -Object $csvPassword -IncludeUrl) -CsvPassword $csvPassword
    Add-UniqueCsvLookup -Lookup $csvByNameUsername -Duplicates $duplicateNameUsername -Key (Get-PasswordIdentityKey -Object $csvPassword) -CsvPassword $csvPassword
}

$MatchedFromJson = foreach ($pass in @($hudupasswords)) {
    $huduId = [string]$pass.id
    $match = $matchedByHuduId[$huduId]
    $jsonMatchSource = if ($match) { "MatchedPasswords.json HuduID" } else { $null }

    if (-not $match) {
        $companyFullIdentityKey = Get-PasswordCompanyIdentityKey -Object $pass -IncludeUrl
        if ($companyFullIdentityKey -and $matchedByCompanyFullIdentity.ContainsKey($companyFullIdentityKey)) {
            $match = $matchedByCompanyFullIdentity[$companyFullIdentityKey]
            $jsonMatchSource = "MatchedPasswords.json company/name/username/url"
        }
    }

    if (-not $match) {
        $companyNameUsernameKey = Get-PasswordCompanyIdentityKey -Object $pass
        if ($companyNameUsernameKey -and $matchedByCompanyNameUsername.ContainsKey($companyNameUsernameKey)) {
            $match = $matchedByCompanyNameUsername[$companyNameUsernameKey]
            $jsonMatchSource = "MatchedPasswords.json company/name/username"
        }
    }

    $itgIdFromJsonId = Get-PropertyValueSafe -Object $match -PropertyName 'ITGID'
    $itgIdFromJsonObject = Get-NestedPropertyValueSafe -Object $match -Path @('ITGObject', 'id')
    $itgIdFromJsonUrl = Get-PasswordIdFromItGlueUrl -Url (Get-NestedPropertyValueSafe -Object $match -Path @('HuduObject', 'login_url'))
    $itgIdFromHuduUrl = Get-PasswordIdFromItGlueUrl -Url (Get-PropertyValueSafe -Object $pass -PropertyName 'login_url')

    $itgId = Get-FirstNonEmptyString -Values @(
        $itgIdFromJsonId,
        $itgIdFromJsonObject,
        $itgIdFromJsonUrl,
        $itgIdFromHuduUrl
    )

    $csvUnvault = if ($itgId) { $csvByItgId[[string]$itgId] } else { $null }
    $identityMatchSource = $null
    if (-not $csvUnvault) {
        $fullIdentityKey = Get-PasswordIdentityKey -Object $pass -IncludeUrl
        if ($fullIdentityKey -and $csvByFullIdentity.ContainsKey($fullIdentityKey)) {
            $csvUnvault = $csvByFullIdentity[$fullIdentityKey]
            $identityMatchSource = "Unique name/username/url"
            $itgId = Get-FirstNonEmptyString -Values @(
                (Get-PropertyValueSafe -Object $csvUnvault -PropertyName 'id'),
                (Get-PropertyValueSafe -Object $csvUnvault -PropertyName 'ID')
            )
        }
    }
    if (-not $csvUnvault) {
        $nameUsernameKey = Get-PasswordIdentityKey -Object $pass
        if ($nameUsernameKey -and $csvByNameUsername.ContainsKey($nameUsernameKey)) {
            $csvUnvault = $csvByNameUsername[$nameUsernameKey]
            $identityMatchSource = "Unique name/username"
            $itgId = Get-FirstNonEmptyString -Values @(
                (Get-PropertyValueSafe -Object $csvUnvault -PropertyName 'id'),
                (Get-PropertyValueSafe -Object $csvUnvault -PropertyName 'ID')
            )
        }
    }
    $passwordUnvaulted = if ($csvUnvault) { $csvUnvault.password } else { "Not Found in CSV" }
    $matchSource = if ($match) {
        $jsonMatchSource
    } elseif ($itgIdFromHuduUrl) {
        "Hudu login_url"
    } elseif ($identityMatchSource) {
        $identityMatchSource
    } else {
        "NotFound"
    }

    if ($match) {
        Write-Host "Matched Hudu ID $huduId to ITG ID $itgId from $jsonMatchSource"
    } elseif ($itgIdFromHuduUrl) {
        Write-Host "Matched Hudu ID $huduId to ITG ID $itgId from Hudu login_url"
    } elseif ($identityMatchSource) {
        Write-Host "Matched Hudu ID $huduId to ITG ID $itgId from $identityMatchSource"
    } else {
        Write-Host "No matched JSON row found for Hudu ID $huduId"
    }

    [PSCustomObject]@{
        HuduID            = $huduId
        ITGID             = $itgId
        Name              = $pass.name
        HuduPassword      = $pass.password
        UnvaultedPassword = $passwordUnvaulted
        MatchedInJson     = if ($match) { "Yes" } else { "No" }
        FoundInCsv        = if ($csvUnvault) { "Yes" } else { "No" }
        MatchSource       = $matchSource
        MatchedJson       = $match
        CsvRow            = $csvUnvault
    }
}
Write-Host "Please review the matched results below. When you're ready, press Enter to continue with updating Hudu passwords based on the unvaulted passwords from the CSV. If you want to exit without making changes, perform a CTRL+C to stop the script."
$MatchedFromJson
$unvaultedMatches = $MatchedFromJson | Where-Object {$_.FoundInCsv -eq "Yes" -and $_.MatchSource -in @("MatchedPasswords.json HuduID", "MatchedPasswords.json company/name/username/url", "MatchedPasswords.json company/name/username", "Hudu login_url", "Unique name/username/url", "Unique name/username")}
$unvaultedMatches | ForEach-Object {Set-HuduPassword -id $_.HuduID -Password $_.UnvaultedPassword}

write-host "All set- you can repeat for other companies with vaulted passwords." -ForegroundColor Green
