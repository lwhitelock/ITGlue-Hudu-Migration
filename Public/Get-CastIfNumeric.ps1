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
        [Parameter(Mandatory)]
        [object]$InputDate,  # allow string or [datetime]

        [datetime]$Cutoff = [datetime]'1000-01-01',

        [ValidateSet('DD.MM.YYYY','YYYY.MM.DD','MM/DD/YYYY')]
        [string]$OutputFormat = 'MM/DD/YYYY'
    )

    $Inv = [System.Globalization.CultureInfo]::InvariantCulture

    # 1) If it's already a DateTime, trust it
    if ($InputDate -is [datetime]) {
        $dt = [datetime]$InputDate
    }
    else {
        $text = "$InputDate".Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }

        # 2) Try strict formats first via ParseExact
        $formats = @(
            'MM/dd/yyyy HH:mm:ss'
            'MM/dd/yyyy hh:mm:ss tt'
            'MM/dd/yyyy'
        )

        $dt   = $null
        $ok   = $false

        foreach ($fmt in $formats) {
            try {
                $dt = [System.DateTime]::ParseExact($text, $fmt, $Inv)
                $ok = $true
                break
            } catch {
                # ignore and try next format
            }
        }

        # 3) Fallback: general Parse (handles lots of “normal” date strings)
        if (-not $ok) {
            try {
                $dt = [System.DateTime]::Parse($text, $Inv)
            } catch {
                return $null
            }
        }
    }

    if ($dt -lt $Cutoff) { return $null }

    switch ($OutputFormat) {
        'DD.MM.YYYY' { $dt.ToString('dd.MM.yyyy', $Inv) }
        'YYYY.MM.DD' { $dt.ToString('yyyy.MM.dd', $Inv) }
        'MM/DD/YYYY' { $dt.ToString('MM/dd/yyyy', $Inv) }
    }
}

function Get-NormalizedDropdownOptions {
  param([Parameter(Mandatory)]$OptionsRaw)
  $lines =
    if ($null -eq $OptionsRaw) { @() }
    elseif ($OptionsRaw -is [string]) { $OptionsRaw -split "`r?`n" }
    elseif ($OptionsRaw -is [System.Collections.IEnumerable]) { @($OptionsRaw) }
    else { @("$OptionsRaw") }

  $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($l in $lines) {
    $x = "$l".Trim()
    if ($x -ne "" -and $seen.Add($x)) { $out.Add($x) }
  }
  if ($out.Count -eq 0) { @('None','N/A') } elseif ($out.Count -eq 1) { @('None',$out[0] ?? "N/A") } else { $out.ToArray() }
}
function Get-UniqueListName {
  param([Parameter(Mandatory)][string]$BaseName,[bool]$allowReuse=$false)

  $name = $BaseName.Trim()
  $i = 0
  while ($true) {
    $existing = Get-HuduLists -name $name
    if (-not $existing) { return $name }
    if ($existing -and $true -eq $allowReuse) {return $existing}
    $i++
    $name = "{0}-{1}" -f $BaseName.Trim(), $i
  }
}
