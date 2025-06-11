function Get-CastIfNumeric {
    param([Parameter(Mandatory = $true)][object]$Value)

    if ($Value -is [string]) {
        $Value = $Value.Trim()

        try {
            $asDouble = [double]$Value

            # Round if equivalent to int (e.g. 1.0, 2.000)
            if ($asDouble % 1 -eq 0 -and $asDouble -le [int]::MaxValue) {
                return [int]$asDouble
            }

            # Otherwise return as double if it’s still valid
            if ($asDouble -le [double]::MaxValue) {
                return $asDouble
            }
        } catch {
            return $Value
        }
    }

    return $Value
}