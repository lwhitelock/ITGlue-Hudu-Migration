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

function Get-CoercedDate {
    param(
        [Parameter(Mandatory)][string]$InputDate,
        [datetime]$Cutoff = [datetime]'1000-01-01',
        [ValidateSet('DD.MM.YYYY','YYYY.MM.DD','MM/DD/YYYY')]
        [string]$OutputFormat = 'MM/DD/YYYY'
    )

    $Inv    = [System.Globalization.CultureInfo]::InvariantCulture
    $Styles = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces -bor `
              [System.Globalization.DateTimeStyles]::AssumeLocal
    $Accepted = [string[]]@('MM/dd/yyyy HH:mm:ss','MM/dd/yyyy hh:mm:ss tt')

    $dt = $null
    try {
        if (-not [datetime]::TryParseExact($InputDate, $Accepted, $Inv, $Styles, [ref]$dt)) {
            return $null
        }
    } catch { return $null }
    if ($dt -lt $Cutoff) { return $null }

    switch ($OutputFormat) {
        'DD.MM.YYYY' { $dt.ToString('dd.MM.yyyy', $Inv) }
        'YYYY.MM.DD' { $dt.ToString('yyyy.MM.dd', $Inv) }
        'MM/DD/YYYY' { $dt.ToString('MM/dd/yyyy', $Inv) }
    }
}
