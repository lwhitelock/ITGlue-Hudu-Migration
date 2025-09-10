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
function Test-DateAfter {
    param(
        [Parameter(Mandatory)][string]$DateString,
        [datetime]$Cutoff = [datetime]'1000-01-01'
    )
    $dt = $null
    $ok = [datetime]::TryParseExact(
        $DateString,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal,
        [ref]$dt
    )
    if (-not $ok) { return $false }   # invalid format → fail
    return ($dt -ge $Cutoff)
}
