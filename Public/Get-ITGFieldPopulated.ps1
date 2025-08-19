function Test-ValuePresent {
    param([object]$Value)

    if ($null -eq $Value) { return $false }

    # Tag/Upload pattern: @{ type='...'; values=@(...) }
    if ($Value -is [pscustomobject] -or $Value -is [hashtable]) {
        $props = $Value.PSObject.Properties
        $hasValuesProp = $props['values'] -ne $null
        if ($hasValuesProp) {
            $vals = $props['values'].Value
            return @($vals).Count -gt 0
        }
        # If it's some other object (e.g., single linked object), treat as present if non-null
        return $true
    }

    if ($Value -is [string]) {
        return -not [string]::IsNullOrWhiteSpace($Value)
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return (@($Value).Count -gt 0)
    }

    # numbers, booleans, DateTime, etc.
    return $true
}

function Get-ITGFieldPopulated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$FlexLayoutFields,
        [Parameter(Mandatory)] [array]$FlexAssets,
        [string[]] $ExcludeKinds = @('Header')
    )
    foreach ($requiredForCalc in @($FlexLayoutFields, $FlexAssets)){
        if (-not $requiredForCalc -or $null -eq $requiredForCalc -or $requiredForCalc.count -lt 1){
            return @{}
        }
    }
    $dataFieldKeys = @{}
    foreach ($f in $FlexLayoutFields) {
        $kind = $f.Attributes.kind
        if ($ExcludeKinds -notcontains $kind) {
            $key = $f.Attributes.'name-key'
            if ($key) { $dataFieldKeys[$key] = $true }
        }
    }

    # Init counts
    $keyFilledCounts = @{}
    foreach ($k in $dataFieldKeys.Keys) { $keyFilledCounts[$k] = 0 }

    $totalAssets = [int]$FlexAssets.Count
    if ($totalAssets -eq 0) {
        $none = @{}
        foreach ($k in $dataFieldKeys.Keys) { $none[$k] = $false }
        return $none
    }

    # Single pass over assets for counts of each field
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

    # build map for later refrerence [required/not]
    $fullyPopulated = @{}
    foreach ($k in $dataFieldKeys.Keys) {
        $fullyPopulated[$k] = ($keyFilledCounts[$k] -eq $totalAssets)
    }

    return $fullyPopulated
}
