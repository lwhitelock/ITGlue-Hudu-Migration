function Get-CastIfNumeric {
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($Value -is [string]) {
        $Value = $Value.Trim()
    }

    if ($Value -match '^[+-]?\d+(\.\d+)?$') {
        try {
            return [int][double]$Value
        } catch {
            return 0
        }
    }
    return $Value
}
