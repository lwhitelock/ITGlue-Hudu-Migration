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

function Get-ITGFieldUniqueValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$FlexAssets,
        [Parameter(Mandatory)] [string]$FieldKey,
        [bool]$ExcludeEmpty = $true,
        [scriptblock]$Normalize = {
            param($s)
            if ($null -eq $s) { return $null }
            return ($s.ToString().Trim().ToLowerInvariant())
        }
    )

    $set = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($asset in $FlexAssets) {
        $traits = $asset.Attributes.traits
        if (-not $traits) { continue }

        $prop = $traits.PSObject.Properties[$FieldKey]
        if (-not $prop) { continue }

        $raw = $prop.Value
        if ($ExcludeEmpty -and -not (Test-ValuePresent $raw)) { continue }

        # Helper to add a single atomic value
        $add = {
            param($value)

            if ($null -eq $value) { return }

            # If PSCustomObject / hashtable → use common fields or JSON
            if ($value -is [pscustomobject] -or $value -is [hashtable]) {
                $props = $value.PSObject.Properties
                if ($props['name']) { $value = $props['name'].Value }
                elseif ($props['value']) { $value = $props['value'].Value }
                elseif ($props['id']) { $value = $props['id'].Value }
                else { $value = ($value | ConvertTo-Json -Compress -Depth 6) }
            }

            $s = & $Normalize ([string]$value)
            if (-not [string]::IsNullOrWhiteSpace($s)) {
                [void]$set.Add($s)
            }
        }

        if ($raw -is [pscustomobject] -or $raw -is [hashtable]) {
            if ($raw.PSObject.Properties['values']) {
                foreach ($v in $raw.values) {
                    & $add $v
                }
                continue
            }
        }

        # Collections (but not strings)
        if ($raw -is [System.Collections.IEnumerable] -and -not ($raw -is [string])) {
            foreach ($v in $raw) {
                & $add $v
            }
            continue
        }
        & $add $raw
    }

    return @($set) | Sort-Object { $_.ToLowerInvariant() }
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
