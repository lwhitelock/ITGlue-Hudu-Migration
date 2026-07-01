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

function Set-ReleaseArtifact {
    Remove-Item -Path "$($(get-childitem -path "." -Recurse -Directory "artifacts" | Select-Object -first 1).fullname)\*.txt" -Force -ErrorAction SilentlyContinue
    Get-GitCheckoutInfo | Out-File "$($(get-childitem -path "." -Recurse -Directory "artifacts" | Select-Object -first 1).fullname)\$($(Get-Date -Format o | ForEach-Object { $_ -replace ":", "." })).txt" -Encoding utf8
}
function Get-ReleaseArtifact {
    $artifact = (Get-ChildItem -Path "." -Recurse -Directory "artifacts" | Select-Object -First 1 | Get-ChildItem -Filter "*.txt" | Select-Object -First 1)
    if (-not $(test-path $artifact.FullName)) {
        return $null
    }
    return "$(Get-Content -Path $artifact.FullName)"
}


function Get-GitCheckoutInfo {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location).Path
    )
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return ($(Get-ReleaseArtifact) ?? "No Git installation found, cannot discern checkout info")
    }
    Push-Location -LiteralPath $Path
    try {
        $insideRepo = git rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -ne 0 -or $insideRepo -ne 'true') {
            return "Not inside a Git repository"
        }
        $commit = git rev-parse HEAD 2>$null
        $branch = git branch --show-current 2>$null
        if ([string]::IsNullOrWhiteSpace($branch)) {
            $branch = '(detached HEAD)'
        }
        $remoteUrl = git remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0) {
            $remoteUrl = $null
        }
        return "using commit $commit from branch $branch of repo $remoteUrl"
    }
    finally {
        Pop-Location
    }
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
function Test-Equiv {
    param([string]$A, [string]$B)
    $a = Normalize-Text $A; $b = Normalize-Text $B
    if (-not $a -or -not $b) { return $false }
    if ($a -eq $b) { return $true }
    $reA = "(^| )$([regex]::Escape($a))( |$)"
    $reB = "(^| )$([regex]::Escape($b))( |$)"
    if ($b -match $reA -or $a -match $reB) { return $true } 
    if ($a.Replace(' ', '') -eq $b.Replace(' ', '')) { return $true }
    return $false
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

function Format-ManualActionsReport {
    param(
        [System.Collections.ArrayList]$ManualActions,
        [string]$OutputPath = "ManualActions.html",
        [string]$Summary
    )

    function ConvertTo-ReportHtml {
        param([AllowNull()]$Value)

        if ($null -eq $Value) { return "" }

        $text = if ($Value -is [string]) {
            $Value
        } elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            @($Value) -join ", "
        } else {
            try {
                $Value | ConvertTo-Json -Depth 8 -Compress -ErrorAction Stop
            } catch {
                [string]$Value
            }
        }

        return [System.Net.WebUtility]::HtmlEncode([string]$text)
    }

    function ConvertTo-AbsoluteReportUrl {
        param([AllowNull()][string]$Url)

        if ([string]::IsNullOrWhiteSpace($Url)) { return "" }
        if ($Url -match '^https?://') { return $Url }
        if ([string]::IsNullOrWhiteSpace($HuduBaseDomain)) { return $Url }

        return "$($HuduBaseDomain.TrimEnd('/'))/$($Url.TrimStart('/'))"
    }

    function New-ReportLink {
        param(
            [AllowNull()][string]$Url,
            [string]$Label = "Open"
        )

        if ([string]::IsNullOrWhiteSpace($Url)) {
            return '<span class="muted">Not available</span>'
        }

        $safeUrl = ConvertTo-ReportHtml $Url
        $safeLabel = ConvertTo-ReportHtml $Label
        return "<a href=""$safeUrl"" target=""_blank"" rel=""noopener noreferrer"">$safeLabel</a>"
    }

    function Get-ManualActionType {
        param([AllowNull()]$ManualAction)

        if ($ManualAction -and -not [string]::IsNullOrWhiteSpace($ManualAction.Type)) {
            return $ManualAction.Type
        }

        if ($ManualAction -and -not [string]::IsNullOrWhiteSpace($ManualAction.Asset_Type)) {
            return $ManualAction.Asset_Type
        }

        return "Unknown"
    }

    $manualActionItems = @($ManualActions | Where-Object { $null -ne $_ })

    foreach ($item in $manualActionItems) {
        $absoluteHuduUrl = ConvertTo-AbsoluteReportUrl $item.Hudu_URL
        $huduUrlProperty = $item.PSObject.Properties["Hudu_URL"]

        if ($huduUrlProperty) {
            $huduUrlProperty.Value = $absoluteHuduUrl
        } else {
            $item | Add-Member -MemberType NoteProperty -Name Hudu_URL -Value $absoluteHuduUrl
        }
    }

    $totalActions = $manualActionItems.Count
    $groupedItems = @(
        $manualActionItems |
            Group-Object {
                $huduId = if ($_.huduid) { $_.huduid } else { "no-id" }
                $huduUrl = if ($_.Hudu_URL) { $_.Hudu_URL } else { "no-url" }
                "$huduId|$huduUrl|$($_.Document_Name)"
            } |
            Sort-Object {
                $first = $_.Group | Select-Object -First 1
                "$($first.Company_name)|$(Get-ManualActionType $first)|$($first.Document_Name)"
            }
    )
    $recordCount = $groupedItems.Count
    $companyCount = @($manualActionItems | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Company_name) } | Select-Object -ExpandProperty Company_name -Unique).Count
    $typeCount = @($manualActionItems | ForEach-Object { Get-ManualActionType $_ } | Where-Object { $_ -ne "Unknown" } | Select-Object -Unique).Count
    $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $summaryHtml = ConvertTo-ReportHtml $Summary

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('<!doctype html>')
    [void]$builder.AppendLine('<html lang="en">')
    [void]$builder.AppendLine('<head>')
    [void]$builder.AppendLine('  <meta charset="utf-8">')
    [void]$builder.AppendLine('  <meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$builder.AppendLine('  <title>Manual Actions Required Report</title>')
    [void]$builder.AppendLine(@'
  <style>
    :root {
      color-scheme: light;
      --page: #f6f8fb;
      --surface: #ffffff;
      --surface-alt: #f0f4f8;
      --border: #d8e0ea;
      --text: #1e2a35;
      --muted: #5d6b7a;
      --heading: #102232;
      --accent: #0f766e;
      --accent-strong: #134e4a;
      --warning: #b45309;
      --link: #1d4ed8;
      --shadow: 0 8px 24px rgba(15, 23, 42, 0.08);
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      background: var(--page);
      color: var(--text);
      font-family: "Segoe UI", Roboto, Arial, sans-serif;
      line-height: 1.45;
    }

    .shell {
      width: min(1180px, calc(100% - 32px));
      margin: 0 auto;
      padding: 32px 0 48px;
    }

    header {
      margin-bottom: 24px;
      border-bottom: 1px solid var(--border);
      padding-bottom: 18px;
    }

    h1, h2, h3 { color: var(--heading); margin: 0; }

    h1 {
      font-size: 28px;
      font-weight: 700;
    }

    .subtitle {
      margin-top: 8px;
      color: var(--muted);
      font-size: 14px;
    }

    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
      gap: 12px;
      margin: 20px 0 24px;
    }

    .stat {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 14px 16px;
      box-shadow: var(--shadow);
    }

    .stat-label {
      display: block;
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: .06em;
    }

    .stat-value {
      display: block;
      margin-top: 4px;
      font-size: 24px;
      font-weight: 700;
      color: var(--accent-strong);
    }

    .summary {
      background: #172033;
      color: #ecf2f8;
      border-radius: 8px;
      padding: 18px;
      overflow-x: auto;
      margin-bottom: 24px;
      box-shadow: var(--shadow);
    }

    .summary h2 {
      color: #ffffff;
      font-size: 17px;
      margin-bottom: 10px;
    }

    pre {
      margin: 0;
      white-space: pre-wrap;
      font: 13px/1.5 Consolas, "Liberation Mono", monospace;
    }

    .section-title {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 16px;
      margin: 28px 0 12px;
    }

    .section-title h2 { font-size: 20px; }

    .muted { color: var(--muted); }

    .empty-state {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 24px;
      color: var(--muted);
      box-shadow: var(--shadow);
    }

    .action-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      margin-bottom: 16px;
      box-shadow: var(--shadow);
      overflow: hidden;
    }

    .action-header {
      padding: 16px 18px;
      border-left: 5px solid var(--accent);
      background: var(--surface);
    }

    .action-header h3 {
      font-size: 17px;
      margin-bottom: 10px;
    }

    .meta-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 8px 18px;
      color: var(--muted);
      font-size: 13px;
    }

    .meta-grid strong {
      color: var(--text);
      font-weight: 600;
    }

    a {
      color: var(--link);
      text-decoration: none;
      overflow-wrap: anywhere;
    }

    a:hover { text-decoration: underline; }

    .table-wrap { overflow-x: auto; }

    table {
      width: 100%;
      border-collapse: collapse;
      table-layout: fixed;
      font-size: 13px;
    }

    th {
      background: var(--surface-alt);
      color: var(--heading);
      text-align: left;
      font-weight: 700;
      border-top: 1px solid var(--border);
      border-bottom: 1px solid var(--border);
      padding: 10px 12px;
    }

    td {
      vertical-align: top;
      border-bottom: 1px solid var(--border);
      padding: 10px 12px;
      overflow-wrap: anywhere;
    }

    tr:last-child td { border-bottom: 0; }

    .field-col { width: 18%; }
    .notes-col { width: 26%; }
    .action-col { width: 26%; }
    .data-col { width: 30%; }

    .badge {
      display: inline-block;
      border: 1px solid rgba(180, 83, 9, .28);
      background: #fff7ed;
      color: var(--warning);
      border-radius: 999px;
      padding: 2px 8px;
      font-size: 12px;
      font-weight: 600;
    }

    @media (max-width: 760px) {
      .shell { width: min(100% - 20px, 1180px); padding-top: 20px; }
      h1 { font-size: 23px; }
      .summary { padding: 14px; }
      .action-header { padding: 14px; }
      table { min-width: 760px; }
    }
  </style>
'@)
    [void]$builder.AppendLine('</head>')
    [void]$builder.AppendLine('<body>')
    [void]$builder.AppendLine('  <main class="shell">')
    [void]$builder.AppendLine('    <header>')
    [void]$builder.AppendLine('      <h1>Manual Actions Required Report</h1>')
    [void]$builder.AppendLine("      <div class=""subtitle"">Generated $generatedAt. Review these items after the migration completes.</div>")
    [void]$builder.AppendLine('    </header>')
    [void]$builder.AppendLine('    <section class="stats" aria-label="Manual action totals">')
    [void]$builder.AppendLine("      <div class=""stat""><span class=""stat-label"">Manual Actions</span><span class=""stat-value"">$totalActions</span></div>")
    [void]$builder.AppendLine("      <div class=""stat""><span class=""stat-label"">Impacted Records</span><span class=""stat-value"">$recordCount</span></div>")
    [void]$builder.AppendLine("      <div class=""stat""><span class=""stat-label"">Companies</span><span class=""stat-value"">$companyCount</span></div>")
    [void]$builder.AppendLine("      <div class=""stat""><span class=""stat-label"">Item Types</span><span class=""stat-value"">$typeCount</span></div>")
    [void]$builder.AppendLine('    </section>')
    [void]$builder.AppendLine('    <section class="summary">')
    [void]$builder.AppendLine('      <h2>Migration Summary</h2>')
    [void]$builder.AppendLine("      <pre>$summaryHtml</pre>")
    [void]$builder.AppendLine('    </section>')
    [void]$builder.AppendLine('    <section>')
    [void]$builder.AppendLine('      <div class="section-title">')
    [void]$builder.AppendLine('        <h2>Manual Actions</h2>')
    [void]$builder.AppendLine("        <span class=""muted"">$recordCount record groups</span>")
    [void]$builder.AppendLine('      </div>')

    if ($totalActions -eq 0) {
        [void]$builder.AppendLine('      <div class="empty-state">No manual actions were recorded for this migration.</div>')
    } else {
        foreach ($group in $groupedItems) {
            $items = @($group.Group)
            $coreItem = $items | Select-Object -First 1
            $documentName = ConvertTo-ReportHtml ($coreItem.Document_Name ?? "Unnamed item")
            $itemType = ConvertTo-ReportHtml (Get-ManualActionType $coreItem)
            $companyName = ConvertTo-ReportHtml ($coreItem.Company_name ?? "No company")
            $huduLink = New-ReportLink -Url $coreItem.Hudu_URL -Label "Open in Hudu"
            $itgLink = New-ReportLink -Url $coreItem.ITG_URL -Label "Open in IT Glue"

            [void]$builder.AppendLine('      <article class="action-card">')
            [void]$builder.AppendLine('        <div class="action-header">')
            [void]$builder.AppendLine("          <h3>$documentName <span class=""badge"">$($items.Count) action$(if ($items.Count -eq 1) { '' } else { 's' })</span></h3>")
            [void]$builder.AppendLine('          <div class="meta-grid">')
            [void]$builder.AppendLine("            <div><strong>Type:</strong> $itemType</div>")
            [void]$builder.AppendLine("            <div><strong>Company:</strong> $companyName</div>")
            [void]$builder.AppendLine("            <div><strong>Hudu:</strong> $huduLink</div>")
            [void]$builder.AppendLine("            <div><strong>IT Glue:</strong> $itgLink</div>")
            [void]$builder.AppendLine('          </div>')
            [void]$builder.AppendLine('        </div>')
            [void]$builder.AppendLine('        <div class="table-wrap">')
            [void]$builder.AppendLine('          <table>')
            [void]$builder.AppendLine('            <thead><tr><th class="field-col">Field</th><th class="notes-col">Notes</th><th class="action-col">Action</th><th class="data-col">Data</th></tr></thead>')
            [void]$builder.AppendLine('            <tbody>')

            foreach ($manualAction in $items) {
                $field = ConvertTo-ReportHtml ($manualAction.Field_Name ?? "N/A")
                $notes = ConvertTo-ReportHtml ($manualAction.Notes ?? $manualAction.Problem ?? "")
                $action = ConvertTo-ReportHtml ($manualAction.Action ?? $manualAction.Actions ?? "")
                $data = ConvertTo-ReportHtml $manualAction.Data

                [void]$builder.AppendLine("              <tr><td>$field</td><td>$notes</td><td>$action</td><td>$data</td></tr>")
            }

            [void]$builder.AppendLine('            </tbody>')
            [void]$builder.AppendLine('          </table>')
            [void]$builder.AppendLine('        </div>')
            [void]$builder.AppendLine('      </article>')
        }
    }

    [void]$builder.AppendLine('    </section>')
    [void]$builder.AppendLine('  </main>')
    [void]$builder.AppendLine('</body>')
    [void]$builder.AppendLine('</html>')

    $builder.ToString() | Out-File $OutputPath -Encoding utf8

}

function ChoseBest-ByName {
    param ([string]$Name,[array]$choices,[string]$prop='name')
return $($choices | ForEach-Object {
[pscustomobject]@{Choice = $_; Score  = $(Get-SimilaritySafe -a "$Name" -b $(if ([string]::IsNullOrEmpty($prop)){$_} else {$_.$prop}))}} | where-object {$_.Score -ge 0.97} | Sort-Object Score -Descending | select-object -First 1).Choice

}

function Get-SafeCount {
    param(
        [AllowNull()]
        $InputObject
    )

    @($InputObject).Count
}

function Format-MigrationSummary {
    param(
        [datetime]$ScriptStartTime,
        [datetime]$CompletedAt = (Get-Date),
        [timespan]$Duration,

        [string]$DebugFolder = "$PSScriptRoot\debug",
        [string]$MigrationLogs = "$PSScriptRoot\debug\logs",
        $migratedItems,
        $archivedItems
    )



    $debugPath = (Resolve-Path -LiteralPath $DebugFolder -ErrorAction SilentlyContinue).Path
    $logsPath  = (Resolve-Path -LiteralPath $MigrationLogs -ErrorAction SilentlyContinue).Path
    $manualActionsPath = Join-Path (Resolve-Path .).Path 'ManualActions.html'

    if (-not $debugPath) { $debugPath = $DebugFolder }
    if (-not $logsPath)  { $logsPath  = $MigrationLogs }

    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add('#######################################################')
    $lines.Add('          IT Glue to Hudu Migration Complete')
    $lines.Add('#######################################################')
    $lines.Add("Started At:   $ScriptStartTime")
    $lines.Add("Completed At: $CompletedAt")
    $lines.Add("Duration:     $($Duration.ToString('hh\:mm\:ss'))")
    $lines.Add("Git Info:     $(Get-GitCheckoutInfo)")
    $lines.Add("Hudu Host:    $(Get-HuduBaseurl)")
    $lines.Add("Hudu Version: $($CurrentVersion ?? ([version]$(Get-HuduAppInfo).version))")
    $lines.Add('-------------------------------------------------------')

    foreach ($item in $migratedItems.GetEnumerator()) {
        $lines.Add(('{0,6} : {1}' -f $item.Value, $item.Key))
    }

    $lines.Add('-------------------------------------------------------')

    foreach ($item in $archivedItems.GetEnumerator()) {
        $lines.Add(('{0,6} : {1}' -f $item.Value, $item.Key))
    }
    $lines.Add('#######################################################')
    $lines.Add("Manual Actions report can be found in $manualActionsPath")
    $lines.Add("Logs of what was migrated can be found in the $debugPath and $logsPath folders, including snapshots of matched items with and without data that was migrated, and the results of any attempted URL replacements in descriptions and content.")

    $lines -join [Environment]::NewLine
}


$InvocationWelcomeText = @'
#######################################################"
#
#          IT Glue to Hudu Migration Script           
#
#          Version: 3.14.159
#          Date: 02/02/2026
#
#          Original Author: Luke Whitelock
#                  https://mspp.io
#          Contributors: John Duprey
#                        Mendy Green
#                        Mason Stelter
#                  https://MSPGeek.org                
#                  https://mendyonline.com            
#                                                     
######################################################
This is the Hudu Technologies Fork of an amazing open-source project.

The original project was started by Luke Whitelock and often being maintained by Mendy Green and community contributors. 
This fork is tested for and intended to be used with the very newest Hudu versions.

If you encounter any issues while using this version/fork, feel free to contact hudu support
or reach out to the community for assistance.

Email: support@usehudu.com
Chat: support@hudumagic.com
https://community.hudu.com/

# The #v-hudu channel on the MSPGeek Slack/Discord:   
# https://join.mspgeek.com/                           
# Or log an issue here:
# https://github.com/Hudu-Technologies-Inc/ITGlue-Hudu-Migration/issues

 Instructions:                                       
 Please view Luke's blog post:                       
 https://mspp.io/automated-it-glue-to-hudu-migration-script/
 for instructions specific to this fork, please see README.md and/or SwitchingLayouts.md [if applicable]
   .-.-.   .-.-.   .-.-.   .-.-.   .-.-.   .-.-.   .-.-.   .-.-
 / / \ \ / / \ \ / / \ \ / / \ \ / / \ \ / / \ \ / / \ \ / / \
`-'   `-`-'   `-`-'   `-`-'   `-`-'   `-`-'   `-`-'   `-`-'
'@

$BackupSafetyText = @'
<*><*><*><*><*><*><*><*><*><*><*><*><*><*><*><*><*><*><*><*>- !!!
Please keep ALL COPIES of the Migration Logs folder. This can save you.
Please DO NOT CHANGE ANYTHING in the Migration Logs folder. This can save you.
<*><*><*><*><*><*><*><*><*><*><*><*><*><*><*><*><*><*><*><*>- !!!
'@

$LiabilityWarning = @"
######################################################
Have you taken a full backup of your Hudu Environment?
Things could go wrong and you need to be able to 
recover to the state from before the script was run
######################################################
This Script has the potential to ruin your Hudu environment
You run it entirely at your own risk
You accept full responsibility for any problems caused by running it
######################################################
"@