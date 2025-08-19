function Get-TraitValue {
    param($Traits, [string]$Key)
    if (-not $Traits) { return $null }
    $p = $Traits.PSObject.Properties[$Key]
    if ($p) { return $p.Value } else { return $null }
}

function Test-ITGValuePresent {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) { return -not [string]::IsNullOrWhiteSpace($Value) }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return (@($Value).Count -gt 0)
    }
    return $true
}

function Get-ITGFieldPopulated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $FlexLayoutFields,
        [Parameter(Mandatory)] $FlexAssets,
        [string[]] $ExcludeKinds = @('Header')
    )

    $dataFieldKeys = @{}
        $kind = $f.Attributes.kind
        if ($ExcludeKinds -notcontains $kind) {
            $key = $f.Attributes.name
            if ($key) { $dataFieldKeys[$key] = $true }
        }
    
    $keyFilledCounts = @{}
    foreach ($k in $dataFieldKeys.Keys) { $keyFilledCounts[$k] = 0 }

    $totalAssets = [int]$FlexAssets.Count
    if ($totalAssets -eq 0) {
        $none = @{}
        foreach ($k in $dataFieldKeys.Keys) { $none[$k] = $false }
        return $none
    }

    foreach ($asset in $FlexAssets) {
        $traits = $asset.Attributes.traits
        foreach ($k in $dataFieldKeys.Keys) {
            $v = $null
            if ($traits) {
                $p = $traits.PSObject.Properties[$k]
                if ($p) { $v = $p.Value }
            }
            if (Test-ValuePresent $v) { $keyFilledCounts[$k]++ }
        }
    }

    $fullyPopulated = @{}
    foreach ($k in $dataFieldKeys.Keys) {
        $fullyPopulated[$k] = ($keyFilledCounts[$k] -eq $totalAssets)
    }
    write-host "$($($fullyPopulated | ConvertTo-Json -depth 66).ToString())"
    read-host

    return $fullyPopulated
}