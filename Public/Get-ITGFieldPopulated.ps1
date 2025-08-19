function Get-ITGFieldPopulated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $FlexLayoutFields,
        [Parameter(Mandatory)] $FlexAssets,
        [string[]] $ExcludeKinds = @('Header')
    )

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

    # 1) Collect the data field keys we care about (by name-key)
    $dataFieldKeys = @{}
    foreach ($f in $FlexLayoutFields) {
        $kind = $f.Attributes.kind
        if ($ExcludeKinds -notcontains $kind) {
            $key = $f.Attributes.'name-key'
            if ($key) { $dataFieldKeys[$key] = $true }
        }
    }

    # Early out: nothing to check
    if ($dataFieldKeys.Count -eq 0) {
        return @{}
    }

    # 2) Init counts
    $keyFilledCounts = @{}
    foreach ($k in $dataFieldKeys.Keys) { $keyFilledCounts[$k] = 0 }

    $totalAssets = [int]$FlexAssets.Count
    if ($totalAssets -eq 0) {
        $none = @{}
        foreach ($k in $dataFieldKeys.Keys) { $none[$k] = $false }
        return $none
    }

    # 3) Single pass over assets
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

    # 4) Build boolean map
    $fullyPopulated = @{}
    foreach ($k in $dataFieldKeys.Keys) {
        $fullyPopulated[$k] = ($keyFilledCounts[$k] -eq $totalAssets)
    }

    return $fullyPopulated
}
