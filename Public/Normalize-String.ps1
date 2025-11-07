function Normalize-String {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputString,
        [switch]$PreserveWhitespace,
        [switch]$PreserveExtension
    )
    $extension = ""
    $basename = $InputString
    if ($PreserveExtension) {
        $extension = [IO.Path]::GetExtension($InputString)
        $basename = [IO.Path]::GetFileNameWithoutExtension($InputString)
    }

    # Normalize Unicode (decompose accents), then remove non-ASCII
    $normalized = $basename.Normalize([Text.NormalizationForm]::FormD)
    $chars = $normalized.ToCharArray() | Where-Object {
        ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark')
    }
    $ascii = -join $chars
    if ($PreserveWhitespace) {
        $ascii = $ascii -replace '[^a-zA-Z0-9 _-]', ''
    } else {
        $ascii = $ascii -replace '[^a-zA-Z0-9]', ''
    }
    return "$ascii$extension"
}


function Limit-FilenameLength {
    param (
        [string]$FullFilename,
        [int]$MaxLength = 100,
        [switch]$PreserveExtension
    )

    if ($PreserveExtension) {
        $extension = [IO.Path]::GetExtension($FullFilename)
        $basename = [IO.Path]::GetFileNameWithoutExtension($FullFilename)

        $maxBaseLength = $MaxLength - $extension.Length
        if ($basename.Length -gt $maxBaseLength) {
            $basename = $basename.Substring(0, $maxBaseLength)
        }

        return "$basename$extension"
    } else {
        # Trim the entire string to max length regardless of extension
        return if ($FullFilename.Length -gt $MaxLength) {
            $FullFilename.Substring(0, $MaxLength)
        } else {
            $FullFilename
        }
    }
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
    write-host "$a ... $b SCORED $score"
    return $score
}

function ChoseBest-ByName {
    param ([string]$Name,[array]$choices)
return $($choices | ForEach-Object {
[pscustomobject]@{Choice = $_; Score  = $(Get-SimilaritySafe -a "$Name" -b $_.name);}} | where-object {$_.Score -ge 0.97} | Sort-Object Score -Descending | select-object -First 1).Choice
}

