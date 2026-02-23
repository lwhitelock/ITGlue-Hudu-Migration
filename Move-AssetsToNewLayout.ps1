$RequiredPSversion = [version]'7.5.1'
$currentPSVersion  = $PSVersionTable.PSVersion
if ($currentPSVersion -lt $RequiredPSversion) { throw "Need PowerShell $RequiredPSversion+, you have $currentPSVersion" } else {write-host "PowerShell version $currentPSVersion is compatible." -ForegroundColor Green}

Write-Host "Required PowerShell version: $RequiredPSversion" -ForegroundColor Blue

if ($currentPSVersion -lt $RequiredPSversion) {
    Write-Host "PowerShell $RequiredPSversion or higher is required. You have $currentPSVersion." -ForegroundColor Red
    exit 1
} else {
    Write-Host "PowerShell version $currentPSVersion is compatible." -ForegroundColor Green
}

function Get-CastIfNumeric {
    param([Parameter(Mandatory)][object]$Value)
    if ($Value -is [string]) {
        $Value = $Value.Trim()
    }
    if ($Value -match '^[+-]?\d+(\.\d+)?$') {
        try {
            return [int][double]$Value
        } catch {
            return $null
        }
    }
    return $null
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

function Get-FieldTypeByLabel {
    param(
        [Parameter(Mandatory)][object[]]$LayoutFields
    )
    $typeByLabel = @{}
    foreach ($lf in ($LayoutFields ?? @())) {
        if (-not $lf.label) { continue }
        $typeByLabel[$lf.label] = ($lf.field_type ?? $lf.type ?? 'Text')
    }
    return $typeByLabel
}

function FieldsToLabelValueMap {
    param([object[]]$Fields)

    $map = @{}
    foreach ($f in ($Fields ?? @())) {
        if (-not $f) { continue }
        $label = $f.label
        if ([string]::IsNullOrWhiteSpace($label)) { continue }
        $map[$label] = $f.value
    }
    return $map
}

function LabelValueMapToFields {
    param(
        [Parameter(Mandatory)][hashtable]$Map,
        [object[]]$LayoutFields = $null
    )

    $out = @()

    # Preserve layout ordering if given
    if ($LayoutFields) {
        $layoutLabels = @($LayoutFields | ForEach-Object { $_.label } | Where-Object { $_ })
        foreach ($lab in $layoutLabels) {
            if ($Map.ContainsKey($lab)) {
                $out += @{ $lab = $Map[$lab] }
            }
        }
        # Any extras not in layout
        foreach ($k in $Map.Keys | Where-Object { $_ -notin $layoutLabels }) {
            $out += @{ $k = $Map[$k] }
        }
    } else {
        foreach ($k in $Map.Keys) { $out += @{ $k = $Map[$k] } }
    }

    return $out
}

function Is-BlankValue {
    param([object]$Value)
    if ($null -eq $Value) { return $true }

    # AddressData / objects should count as blank only if no meaningful fields
    if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
        try {
            $pairs = $Value.PSObject.Properties | ForEach-Object { $_.Value }
            return -not ($pairs | Where-Object { -not (Is-BlankValue $_) } | Select-Object -First 1)
        } catch {
            return $false
        }
    }

    return [string]::IsNullOrWhiteSpace([string]$Value)
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
    write-host "$A ... $B SCORED $score"
    return $score
}

function Get-CastIfBoolean {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [array]$trueVals  = @("true","t","yes","y","1","on"),# Accepted truthy keyword mappings
        [array]$falseVals = @("false","f","no","n","0","off"), # Accepted falsey keyword mappings
        [bool]$allowFuzzy=$true
    )
    if ($Value -is [string]) {
        $Value = $Value.Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    }

    # Already a real boolean? return it
    if ($Value -is [bool]) {
        return $Value
    }

    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        if ([int]$Value -eq 1) { return $true }
        if ([int]$Value -eq 0) { return $false }
        return $null
    }
    if ($Value -is [string]) {
        $lower = $Value.ToLowerInvariant()

        if ($trueVals  -contains $lower) { return $true }
        if ($falseVals -contains $lower) { return $false }
        if ($true -eq $allowFuzzy){
            foreach ($t in $truevals){
                if ($value -ilike "*$t" -or $value -ilike "$t*") {return $true}
            }
            foreach ($f in $falseVals){
                if ($value -ilike "*$f" -or $value -ilike "$f*") {return $false}
            }
            foreach ($t in $truevals){
                if ($value -ilike "*$t*") {return $true}
            }
            foreach ($f in $falseVals){
                if ($value -ilike "*$f*") {return $false}
            }            
        }


        return $null
    }
    return $null
}

function Set-SmooshAssetFieldsToField {
    param (
        [PSCustomObject]$sourceAsset,
        [array]$smooshsource,
        [bool]$includeBlanks=$false
    )
    if ($excludeHTMLinSMOOSH -and $true -eq $excludeHTMLinSMOOSH) {
        $lineDelmit = " "
    } else {
        $lineDelmit = "<br><hr>"
    }
    foreach ($sourcefieldsmoosh in $smooshsource) {
        if ($null -eq $($($sourceasset.fields | where-object {$_.label -eq $sourcefieldsmoosh}).value)){
            if ($false -eq $includeBlanks) {continue}
        }
        
        if ($includeLabelInSmooshedValues){
            $header = "$sourcefieldsmoosh -"
        } else {$header = ""}
        $textToUse = ""
        if ("$($($sourceasset.fields | where-object {$_.label -eq $sourcefieldsmoosh}).value)" -ilike '*list_id*'){
            $precastValue="$($($sourceasset.fields | where-object {$_.label -eq $sourcefieldsmoosh}).value)"
            $listItemId = $null; 
            $listItemId = $(SafeDecode "$($($sourceasset.fields | where-object {$_.label -eq $sourcefieldsmoosh}).value)").list_ids[0]
            $textToUse = $($(get-hudulists).list_items | where-object {$_.id -eq $listItemId} | select-object -first 1).name
            Write-Host "non-empty source val [for smoosh] appears to contain listIDs; Raw val '$($precastValue)'... $($textToUse)" -foregroundColor DarkCyan
        } else {
            $textToUse = "$($($sourceasset.fields | where-object {$_.label -ieq $sourcefieldsmoosh}).value)"
        }
        # generate single entry
        $smooshin=@"
$header
$textToUse
"@
        # append to smoosh
        $smoosh=@"
$smoosh
$lineDelmit
$smooshin
"@
}
    if ($excludeHTMLinSMOOSH -and $true -eq $excludeHTMLinSMOOSH) {
        Write-Host "Not using HTML for smoosh; Cleaning values to text-friendly single-line."
        $smoosh = $smoosh -replace "`r?`n", ' '
        $smoosh = $smoosh -replace '\s{2,}', ' '
        $smoosh = Remove-HtmlTags -InputString $smoosh
        $smoosh = $smoosh.Trim()
    }
    write-host "Smooshed: $smoosh"
    write-host "$($($smoosh | ConvertTo-Json -depth 66).ToString())"
    return $smoosh
}

function Get-RelinkableAssetTagLayoutFields {
    param (
        [int]$fromLayoutId
    )
    $linkableLayouts = @()
    $labelLinkMap = @{}
    $relinkables=$($(Get-HuduAssetLayouts -id $fromLayoutId).fields | where-object {$_.field_type -eq "AssetTag" -and $null -ne $_.linkable_id})
    write-host "$($relinkables.count) are likely relinkable."
    $linkableIDX=0
    foreach ($relinkable in $relinkables){
        $linkableIDX=$linkableIDX+1
        $linkablelayout = Get-HuduAssetLayouts -id $relinkable.linkable_id
        if (-not $linkablelayout -or $null -eq $linkablelayout) {continue}
        $labelLinkMap[$relinkable.label]=$linkablelayout
        write-host "linkable $linkableIDX of $($relinkables.count): label $($relinkable.label) is linkable to $($linkablelayout.name)"
        $linkableLayouts+=$linkablelayout
    }    
    return $labelLinkMap
}

function Get-CleansedEmailAddresses {
    <#
    returns a semicolon-delimited series of email addresses (if going to Text field, it's good to do this after stripping HTML, as to remove table row / column names)
    #>
    param (
        [string]$InputString,
        [string]$pattern = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    )
    
    $cleansed  = ( $inputString | Select-String -AllMatches -Pattern $pattern ).Matches.Value -join '; '
    return "$cleansed".Trim()
}

function Get-SmooshedLinkableDescription {
    param (
        [array]$linkableObjects
    )
    $description=""
    if (-not $linkableObjects -or $linkableObjects.count -lt 1) {
        return ""
    }

    foreach ($linkable in $linkableObjects) {
        if ($linkable.linkedasset.url){
        $descriptor=@"
<br><hr>
<a href='$($linkable.linkedasset.url)'>Related $($linkable.LinkedLayout.name) - $($linkable.LinkedAsset.name)</a>
"@
} else {
        $descriptor=@"
Related $($linkable.LinkedLayout.name) - $($linkable.LinkedAsset.name)
"@    
    }
    $description = "$description<br><hr>$descriptor"
    }
    return $description
}
function Get-HuduModule {
    param (
        [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",
        [bool]$use_hudu_fork = $true
        )

    if ($true -eq $use_hudu_fork) {
        if (-not $(Test-Path $HAPImodulePath)) {
            $dst = Split-Path -Path (Split-Path -Path $HAPImodulePath -Parent) -Parent
            Write-Host "Using Lastest Master Branch of Hudu Fork for HuduAPI"
            $zip = "$env:TEMP\huduapi.zip"
            Invoke-WebRequest -Uri "https://github.com/Hudu-Technologies-Inc/HuduAPI/archive/refs/heads/master.zip" -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force 
            $extracted = Join-Path $env:TEMP "HuduAPI-master" 
            if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
            Move-Item -Path $extracted -Destination $dst 
            Remove-Item $zip -Force
        }
    } else {
        Write-Host "Assuming PSGallery Module if not already locally cloned at $HAPImodulePath"
    }

    if (Test-Path $HAPImodulePath) {
        Import-Module $HAPImodulePath -Force
        Write-Host "Module imported from $HAPImodulePath"
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'2.4.4') {
        Import-Module HuduAPI
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 2.4.5 -Scope CurrentUser -Force
        Import-Module HuduAPI
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }
}

function Set-HuduInstance {
    $HuduBaseURL = $HuduBaseURL ?? $((Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g https://myinstance.huducloud.com)') -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://'
    $HuduAPIKey = $HuduAPIKey ?? "$(read-host "Please Enter Hudu API Key")"
    while ($HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API Key from $($settings.HuduBaseDomain)/admin/api_keys").Trim()
        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }
    New-HuduAPIKey $HuduAPIKey
    Clear-Host
    New-HuduBaseURL $HuduBaseURL
}

function Get-RelinkableRelationsForAsset {
    param (
        [PSCustomObject]$sourceAsset,
        [hashtable]$labelLinkMap
    )
    $linkableObjects = @()
    foreach ($linkableField in $sourceAsset.fields | Where-Object {
        $_.label -and $_.label -in $labelLinkMap.Keys
    }) {
        $layoutForLinking = $labelLinkMap[$linkableField.label]

        try {
            $linkedItems = $null
            if ($linkableField.value -is [string] -and $linkableField.value.Trim().StartsWith("[")) {
                $linkedItems = $linkableField.value | ConvertFrom-Json
            }

            foreach ($linkedItem in $linkedItems) {
                $linkedAsset = Get-HuduAssets -Id $linkedItem.id
                if ($false -eq $includeRelationsForArchived -and $true -eq $linkedAsset.archived){
                    write-host "archived link, continuing"
                    continue
                }

                $linkableObjects+=[PSCustomObject]@{
                    SourceAssetId   = $sourceAsset.id
                    SourceField     = $linkableField.label
                    LinkedAsset     = $linkedAsset
                    LinkedLayout    = $layoutForLinking
                }
            }
        }
        catch {
            Write-Warning "Could not parse linked values for field [$($linkableField.label)] in asset [$($sourceAsset.id)]"
        }
    }
    return $linkableObjects
}
$PerJobSettings = @'
# if fields are blank, exclude during smoosh procress?
$includeblanksduringsmoosh = $false

# relate archived objects to new asset / object
$includeRelationsForArchived = $true

# set below to true if smooshing to plaintext field, otherwise leave for richtext field
# (strip html when going to text field)
$excludeHTMLinSMOOSH = $false

# include description of related objects in smoosh
# related objects will have a 1-line description based on related object type and name
$describeRelatedInSmoosh = $false

# include label - above value in smooshed? IE - 
# label -
# value
$includeLabelInSmooshedValues = $true
'@

function Remove-HtmlTags {
    param (
        [string]$InputString
    )
    $tags = @(
'hr','br', 'tr', 'td', 'th', 'table', 'div', 'span',
'p', 'ul', 'ol', 'li', 'h[1-6]', 'strong', 'em', 'b', 'i',
'colgroup', 'col', 'input', 'column', 'section', 'article',
'header', 'footer', 'aside', 'nav', 'main', 'figure', 'figcaption',
'blockquote', 'pre', 'address', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
'thead', 'tbody', 'tfoot','script','noscript','style','template','head','svg','math'
        )
    $cleaned = $InputString
    foreach ($tag in $tags) {
        # Regex matches both opening <tag ...> and closing </tag>
        $pattern = "<\/?$tag\b[^>]*>"
        $cleaned = [regex]::Replace($cleaned, $pattern, " ", "IgnoreCase")
    }
    return $cleaned.Trim()
}

function build-templatemap {
param ([array]$destfields,[string]$mapfile)
# Build entries like: @{from='';to='Some Label'}
$mapEntries = foreach ($f in $destfields) {
    if ($f.field_type -eq "AssetTag") {write-host "Skipping asset tag for $($f.label), those will be relinked as relations"; continue}

    $toEsc = ([string]$f.label) -replace "'", "''"  # double single-quotes inside single-quoted PS strings
    $desttype = ([string]$($f.field_type ?? $f.type)) -replace "'", "''"  # double single-quotes inside single-quoted PS strings
    $req = ([string]$($f.required ?? $false)) -replace "'", "''"  # double single-quotes inside single-quoted PS strings
    if ($desttype -eq "ListSelect") {
        $ListItems = $(Get-HuduLists -id $f.list_id).list_items.name | Foreach-Object {"'$_'=@{whenvalues=@()}"}
"@{to='$toEsc'; from=''; add_listitems='false'; list_id=$($f.list_id); dest_type='ListSelect'; required='$req'; Mapping=@{
$($listitems -join "`n")
}}"
    } elseif ($desttype -eq "AddressData") {
        "@{to='$toEsc'; from='Meta'; dest_type='AddressData'; required='$req'; address=@{
                address_line_1=@{from=''}
                address_line_2=@{from=''}
                city=@{from=''}
                state=@{from=''}
                zip=@{from=''}
                country_name=@{from=''}
        }}"
    } else {
        "@{from='';to='$toEsc'; dest_type='$desttype'; required='$req'; striphtml='False'}"
    }
    }
# Wrap and write
$mappingText = @'
# source 
$CONSTANTS=@(
    ## @{literal="constval";to_label="constfield"}
)
$SMOOSHLABELS=@()
$mapping=@(
'@ + ($mapEntries -join ",`n") + @'
)
'@ + @"
$PerJobSettings
"@
Set-Content -Path $mapfile -Value $mappingText -Encoding UTF8
}

function Select-ObjectFromList($objects, $message, $inspectObjects = $false, $allowNull = $false) {
    $validated = $false
    while (-not $validated) {
        if ($allowNull) {
            Write-Host "0: None/Custom"
        }
        for ($i = 0; $i -lt $objects.Count; $i++) {
            $object = $objects[$i]
            $displayLine = if ($inspectObjects) {
                "$($i+1): $(Write-InspectObject -object $object)"
            } elseif ($null -ne $object.OptionMessage) {
                "$($i+1): $($object.OptionMessage)"
            } elseif ($null -ne $object.name) {
                "$($i+1): $($object.name)"
            } else {
                "$($i+1): $($object)"
            }
            Write-Host $displayLine -ForegroundColor $(if ($i % 2 -eq 0) { 'Cyan' } else { 'Yellow' })
        }
        $choice = Read-Host $message
        if (-not ($choice -as [int])) {
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
            continue
        }
        $choice = [int]$choice
        if ($choice -eq 0 -and $allowNull) {
            return $null
        }
        if ($choice -ge 1 -and $choice -le $objects.Count) {
            return $objects[$choice - 1]
        } else {
            Write-Host "Invalid selection. Please enter a number from the list." -ForegroundColor Red
        }
    }
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
function Get-FieldValueByLabel {
    param([array]$Fields, [string]$Label)
    if (-not $Label) { return $null }
    ($Fields | Where-Object { $_.label -eq $Label } | Select-Object -First 1).value
}
function Normalize-Region {
    param([string]$State)
    if (-not $State) { return $null }
    $s = $State.Trim()

    # Already 2 letters?
    if ($s -match '^[A-Za-z]{2}$') { return $s.ToUpper() }

    $us = @{
        'alabama'='AL'; 'alaska'='AK'; 'arizona'='AZ'; 'arkansas'='AR'; 'california'='CA'
        'colorado'='CO'; 'connecticut'='CT'; 'delaware'='DE'; 'florida'='FL'; 'georgia'='GA'
        'hawaii'='HI'; 'idaho'='ID'; 'illinois'='IL'; 'indiana'='IN'; 'iowa'='IA'
        'kansas'='KS'; 'kentucky'='KY'; 'louisiana'='LA'; 'maine'='ME'; 'maryland'='MD'
        'massachusetts'='MA'; 'michigan'='MI'; 'minnesota'='MN'; 'mississippi'='MS'; 'missouri'='MO'
        'montana'='MT'; 'nebraska'='NE'; 'nevada'='NV'; 'new hampshire'='NH'; 'new jersey'='NJ'
        'new mexico'='NM'; 'new york'='NY'; 'north carolina'='NC'; 'north dakota'='ND'
        'ohio'='OH'; 'oklahoma'='OK'; 'oregon'='OR'; 'pennsylvania'='PA'; 'rhode island'='RI'
        'south carolina'='SC'; 'south dakota'='SD'; 'tennessee'='TN'; 'texas'='TX'; 'utah'='UT'
        'vermont'='VT'; 'virginia'='VA'; 'washington'='WA'; 'west virginia'='WV'; 'wisconsin'='WI'; 'wyoming'='WY'
        'district of columbia'='DC'; 'washington dc'='DC'; 'dc'='DC'
    }
    $key = $s.ToLower()
    if ($us.ContainsKey($key)) { return $us[$key] }
    return $s  # fallback (leave as-is)
}

function Normalize-CountryName {
    param([string]$Country)
    if (-not $Country) { return $null }
    $c = $Country.Trim()
    $map = @{
        'us'='USA'; 'u.s.'='USA'; 'u.s.a'='USA'; 'usa'='USA'; 'united states'='USA'; 'united states of america'='USA'
        'uk'='United Kingdom'; 'u.k.'='United Kingdom'; 'gb'='United Kingdom'; 'gbr'='United Kingdom'
        'uae'='United Arab Emirates'
    }
    $key = $c.ToLower().Replace('.','')
    if ($map.ContainsKey($key)) { return $map[$key] }
    # Title-case fallback
    return -join ($c.ToLower().Split(' ') | ForEach-Object { if ($_){ $_.Substring(0,1).ToUpper()+$_.Substring(1) } })
}

function Normalize-Zip {
    param([string]$Zip)
    if (-not $Zip) { return $null }
    $z = $Zip -replace '\s+', ''  # collapse spaces (e.g., “802 02”)
    return $z.Trim()
}

function Write-InspectObject {
    param (
        [object]$object,
        [int]$Depth = 32,
        [int]$MaxLines = 16
    )
    $stringifiedObject = $null
    if ($null -eq $object) {
        return "Unreadable Object (null input)"
    }
    # Try JSON
    $stringifiedObject = try {
        $json = $object | ConvertTo-Json -Depth $Depth -ErrorAction Stop
        "# Type: $($object.GetType().FullName)`n$json"
    } catch { $null }
    # Try Format-Table
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $object | Format-Table -Force | Out-String
        } catch { $null }
    }
    # Try Format-List
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $object | Format-List -Force | Out-String
        } catch { $null }
    }
    # Fallback to manual property dump
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $props = $object | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
            $lines = foreach ($p in $props) {
                try {
                    "$p = $($object.$p)"
                } catch {
                    "$p = <unreadable>"
                }
            }
            "# Type: $($object.GetType().FullName)`n" + ($lines -join "`n")
        } catch {
            "Unreadable Object"
        }
    }
    if (-not $stringifiedObject) {
        $stringifiedObject =  try {"$($($object).ToString())"} catch {$null}
    }
    # Truncate to max lines if necessary
    $lines = $stringifiedObject -split "`r?`n"
    if ($lines.Count -gt $MaxLines) {
        $lines = $lines[0..($MaxLines - 1)] + "... (truncated)"
    }
    return $lines -join "`n"
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


function Set-LayoutsForTransfer {
    param ($allLayouts)
    $layoutMap = @{}
    foreach ($layout in $allLayouts) {
        $layoutMap[$layout.id] = $layout
    }
    $layoutSummaries = $allLayouts  | ForEach-Object {
        [PSCustomObject]@{
            ID          = $_.id
            OptionMessage = "$($_.name): $( ($_.fields).Count ) fields with $($_.assetsInLayoutCount) assets present"
            Name        = $_.name
    }}
    write-host "$(if ($layoutSummaries.count -ne $allLayouts.count) {
        "$([int]$allLayouts.count - [int]$layoutSummaries.count) layouts were excluded due to not having fields, not having assets, or being otherwise ineligible."
    } else {
        "created user-friendly summaries for $($layoutSummaries.count) asset layouts"
    })" -ForegroundColor darkcyan
    $sourceLayout = $null
    $destLayout = $null
    while ($true) {
        $sourceSummary = Select-ObjectFromList -objects $layoutSummaries -message "Which source / origin asset layout?" -allowNull $false -inspectObjects $inspectlayouts
        $sourceLayout  = $layoutMap[$sourceSummary.ID]

        $destSummaries = $layoutSummaries | Where-Object { $_.ID -ne $sourceLayout.id }
        $destSummary   = Select-ObjectFromList -objects $destSummaries -message "Which dest / target asset layout?" -allowNull $false -inspectObjects $inspectlayouts
        $destLayout    = $layoutMap[$destSummary.ID]
        if ($($null -ne $sourceLayout -and $null -ne $destLayout) -and $(Select-ObjectFromList -objects @("yes","no") -message "You've selected source layout as: $($sourceLayout.name) and dest layout as: $($destLayout.name). Proceed?") -eq "yes") {
            return @{
                SourceLayout = $sourceLayout
                DestLayout   = $destLayout
            }
        } else {
            Write-Host "Opting to re-select."
        }
    }
}

function Get-SourceListItemNameFieldFromID {
    param ([string]$RawValue,[string]$FieldLabel)
    if ([string]::IsNullOrWhiteSpace($RawValue)){return $null}
    $mapped = $null
    if ("$RawValue" -ilike '*list_id*') {
        try {
            $listItemId = ($RawValue | ConvertFrom-Json).list_ids[0]
            if ($FieldLabel) {
                $mapped = (Get-HuduLists -Name $FieldLabel).list_items |
                          Where-Object { $_.id -eq $listItemId } |
                          Select-Object -ExpandProperty name -ErrorAction SilentlyContinue
            }
            if ($mapped) { return $mapped }
        }
        catch {
            Write-Host "Error transforming list_id source value '$RawValue' — $_"
            return $mapped
        }
    } else {
        Write-Host "list item is presumed human-readable"
        return $RawValue
    }
}
function SafeDecode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -isnot [string]) {
        return $InputObject
    }

    $s = $InputObject.Trim()
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }

    try {
        return $s | ConvertFrom-Json -ErrorAction Stop
    } catch {
        # Not valid JSON; just return the original string
        return $InputObject
    }
}


function Set-MappedListSelectItemFromuserMapping {
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        # Hashtable of key → string[] (whenvalues)
        [Parameter(Mandatory)]
        [hashtable]$Mapping,

        # Raw field value (field.value from the source asset)
        [Parameter(Mandatory)]
        $RawValue,

        # Optional: for list_id → label resolution (if needed later)
        [Parameter()]
        [hashtable]$SourceListItemMap,

        [Parameter()]
        [string]$FieldLabel
    )

    $result = @{
        MatchFound   = $false
        Key          = $null        # destination list item label, e.g. 'these options'
        Normalized   = $RawValue    # coerced/clean value used for comparison
        NeedsNewItem = $true
    }

    # --- 1. Normalize / coerce list_id JSON if present ---
    $listItemValue = $RawValue
    if ("$RawValue" -ilike '*list_id*') {
        try {
            $listItemId = ($RawValue | ConvertFrom-Json).list_ids[0]


            $mapped = $null

            if ($FieldLabel) {
                $mapped = (Get-HuduLists -Name $FieldLabel).list_items |
                          Where-Object { $_.id -eq $listItemId } |
                          Select-Object -ExpandProperty name -ErrorAction SilentlyContinue
            }

            if ($mapped) { $listItemValue = $mapped }
        }
        catch {
            Write-Host "Error transforming list_id source value '$RawValue' — $_"
        }
    }

    $result.Normalized = $listItemValue
    $normalizedListItemValue = Remove-HtmlTags -InputString "$listItemValue"

    # --- 2. Filter mappings to only non-empty whenvalues arrays ---
    $nonEmptyMappings = $Mapping.GetEnumerator() | Where-Object {
        $_.Value -and ($_.Value | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ($nonEmptyMappings.Count -eq 0) {
        return $result
    }

    # --- 3. Try to match: find key whose whenvalues contains our value ---
    foreach ($entry in $nonEmptyMappings) {
        $keyName   = $entry.Key          # e.g. 'these options' / 'milk'
        $whenvalues = $entry.Value       # string[] like @('cloud','cloud service')

        foreach ($potentialMatch in $whenvalues) {
            if ($(Test-Equiv -A "$potentialMatch" -B "$listItemValue") -or $(Test-Equiv -A "$potentialMatch" -B "$normalizedListItemValue")) {

                $result.MatchFound   = $true
                $result.Key          = $keyName   # <- THIS is what Hudu wants
                $result.NeedsNewItem = $false
                return $result
            }
        }
    }

    # No match
    return $result
}
function Convert-FieldArrayToMap {
    param([Parameter(Mandatory)][object[]]$FieldArray)

    $map = @{}
    foreach ($ht in $FieldArray) {
        if ($ht -isnot [hashtable] -and $ht -isnot [System.Collections.IDictionary]) { continue }
        foreach ($k in $ht.Keys) {
            $map[$k] = $ht[$k]
        }
    }
    return $map
}

function Merge-HuduFieldMaps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$SourceMap,   # transformed/source
        [Parameter(Mandatory)][hashtable]$DestMap,     # matched/dest existing
        [Parameter(Mandatory)][object[]]$LayoutFields, # dest layout fields
        [ValidateSet('Merge-FillBlanks','Merge-PreferSource','Merge-Concat')]
        [string]$Mode = 'Merge-FillBlanks',

        # For Merge-Concat: which field types should be concatenated?
        [string[]]$ConcatTypes = @('RichText','Text', "Heading", "ConfidentialText","Password"),

        # Separators
        [string]$RichTextSeparator = "<br><hr>",
        [string]$TextSeparator     = "`n`n---`n`n",

        # Provenance stamping
        [switch]$StampProvenance,
        [string]$SourceStamp = "Imported (source)",
        [string]$DestStamp   = "Existing (dest)"
    )

    $typeByLabel = Get-FieldTypeByLabel -LayoutFields $LayoutFields

    $out = @{}

    $labels = @($SourceMap.Keys + $DestMap.Keys) | Select-Object -Unique
    foreach ($label in $labels) {
        $src = $SourceMap[$label]
        $dst = $DestMap[$label]

        $srcBlank = Is-BlankValue $src
        $dstBlank = Is-BlankValue $dst

        $fieldType = $typeByLabel[$label]
        if (-not $fieldType) { $fieldType = 'Text' }

        switch ($Mode) {

            'Merge-FillBlanks' {
                # dest wins unless blank
                if (-not $dstBlank) {
                    $out[$label] = $dst
                } elseif (-not $srcBlank) {
                    $out[$label] = $src
                }
            }

            'Merge-PreferSource' {
                # source wins unless blank
                if (-not $srcBlank) {
                    $out[$label] = $src
                } elseif (-not $dstBlank) {
                    $out[$label] = $dst
                }
            }

            'Merge-Concat' {
                $isConcat = $ConcatTypes -contains $fieldType

                if (-not $isConcat) {
                    # For non-concat field types, default to PreferSource (tweak if you prefer)
                    if (-not $srcBlank) { $out[$label] = $src }
                    elseif (-not $dstBlank) { $out[$label] = $dst }
                    break
                }

                # Concat path (only when both present)
                if (-not $srcBlank -and -not $dstBlank) {

                    $sep = if ($fieldType -eq 'RichText') { $RichTextSeparator } else { $TextSeparator }

                    if ($StampProvenance) {
                        if ($fieldType -eq 'RichText') {
                            $lhs = "<div><strong>$SourceStamp</strong></div>$src"
                            $rhs = "<div><strong>$DestStamp</strong></div>$dst"
                            $out[$label] = "$lhs$sep$rhs"
                        } else {
                            $lhs = "$SourceStamp`n$src"
                            $rhs = "$DestStamp`n$dst"
                            $out[$label] = "$lhs$sep$rhs"
                        }
                    } else {
                        $out[$label] = ([string]$src) + $sep + ([string]$dst)
                    }

                } elseif (-not $srcBlank) {
                    $out[$label] = $src
                } elseif (-not $dstBlank) {
                    $out[$label] = $dst
                }
            }
        }
    }

    return $out
}
function FieldListToMap {
    param([object[]]$FieldList)

    $map = @{}
    foreach ($ht in ($FieldList ?? @())) {
        if ($ht -isnot [System.Collections.IDictionary]) { continue }
        foreach ($k in $ht.Keys) {
            $map[$k] = $ht[$k]   # last wins
        }
    }
    $map
}

function MapToFieldList {
    param(
        [hashtable]$Map,
        [object[]]$LayoutFields = $null  # optional for ordering
    )

    $out = @()

    if ($LayoutFields) {
        foreach ($lf in $LayoutFields) {
            $label = $lf.label
            if ($label -and $Map.ContainsKey($label)) {
                $out += @{ $label = $Map[$label] }
            }
        }
        # include any extras not in layout
        foreach ($k in $Map.Keys | Where-Object { $_ -notin ($LayoutFields.label) }) {
            $out += @{ $k = $Map[$k] }
        }
    } else {
        foreach ($k in $Map.Keys) { $out += @{ $k = $Map[$k] } }
    }

    $out
}


function Ensure-HuduListItemByName {
    param(
        [Parameter(Mandatory)][int]$ListId,
        [Parameter(Mandatory)][string]$Name,
        [hashtable]$listNameExistsByListId
    )

    $nameTrim = $Name.Trim()
    $needle = $nameTrim.ToLowerInvariant()

    if (-not $listNameExistsByListId.ContainsKey($ListId)) {
        Refresh-ListCache
    }

    $map = $listNameExistsByListId[$ListId]
    if ($map -and $map.ContainsKey($needle)) {
        return $map[$needle]  # return canonical name as stored
    }

    # Add item to list
    $list = Get-HuduLists -Id $ListId
    $listName = $list.name

    $items = @()
    foreach ($existing in ($list.list_items ?? @())) {
        $items += @{ id = [int]$existing.id; name = [string]$existing.name }
    }
    $items += @{ name = $nameTrim }

    $null = Set-HuduList -Id $ListId -Name $listName -ListItems $items

    # refresh cache and return
    $listNameExistsByListId = Refresh-ListCache
    $map = $listNameExistsByListId[$ListId]
    if ($map.ContainsKey($needle)) { return $map[$needle] }

    throw "Failed to add/list item '$Name' to list $ListId"
}
function Refresh-ListCache {
    $listNameExistsByListId = @{}
    foreach ($l in Get-HuduLists) {
        $lid = [int]$l.id
        $map = @{}
        foreach ($it in ($l.list_items ?? @())) {
            if ($it.name) {
                $map[$it.name.ToString().Trim().ToLowerInvariant()] = [string]$it.name
            }
        }
        $listNameExistsByListId[$lid] = $map
    }
    return $listNameExistsByListId
}

function Write-ErrorObjectsToFile {
    param (
        [Parameter(Mandatory)]
        [object]$ErrorObject,
        [Parameter()]
        [string]$Name = "unnamed",
        [Parameter()]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color
    )
    $stringOutput = try {
        $ErrorObject | Format-List -Force | Out-String
    } catch {
        "Failed to stringify object: $_"
    }
    $propertyDump = try {
        $props = $ErrorObject | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        $lines = foreach ($p in $props) {
            try {
                "$p = $($ErrorObject.$p)"
            } catch {
                "$p = <unreadable>"
            }
        }
        $lines -join "`n"
    } catch {
        "Failed to enumerate properties: $_"
    }
    $logContent = @"
==== OBJECT STRING ====
$stringOutput
 
==== PROPERTY DUMP ====
$propertyDump
"@
    if ($ErroredItemsFolder -and (Test-Path $ErroredItemsFolder)) {
        $SafeName = ($Name -replace '[\\/:*?"<>|]', '_') -replace '\s+', ''
        if ($SafeName.Length -gt 60) {
            $SafeName = $SafeName.Substring(0, 60)
        }
        $filename = "${SafeName}_error_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $fullPath = Join-Path $ErroredItemsFolder $filename
        Set-Content -Path $fullPath -Value $logContent -Encoding UTF8
        if ($Color) {
            Write-Host "Error written to $fullPath" -ForegroundColor $Color
        } else {
            Write-Host "Error written to $fullPath"
        }
    }
    if ($Color) {
        Write-Host "$logContent" -ForegroundColor $Color
    } else {
        Write-Host "$logContent"
    }
}

# init and vars
Get-HuduModule
Set-HuduInstance
$CONSTANTS=@()
$SMOOSHLABELS=@()
$mapping=@()
$mapfile = "mapping.ps1"
# $CreateAsIPAM=$true
$inspectlayouts = $false
$archivesource = $false


#simpletransfer load datas
write-host "$(if ($allassets -and $null -ne $allassets) {'using existing asset cache'} else {'refreshing asset cache'})"
$allassets = $allassets ?? $(get-huduassets)
write-host "refreshing layouts cache (every time)"
$assetlayouts = get-huduassetlayouts 
$totallayouts = $assetlayouts.count
write-host "$(if ($allrelations -and $null -ne $allrelations) {'using existing relations cache'} else {'refreshing relations cache'})"
$allrelations = $allrelations ?? $(Get-HuduRelations)
write-host "adding/calculating addtitional properties for layouts"

foreach ($layout in $assetlayouts) {$layout | Add-Member -NotePropertyName assetsInLayoutCount -NotePropertyValue $($allAssets | Where-Object {$_.asset_layout_id -eq $layout.id}).count -Force}

$assetlayouts=$assetlayouts # | where-object {$_.assetsInLayoutCount -gt 0}
$assetlayouts = $assetlayouts | Sort-Object Name
$usablelayouts = $assetlayouts.count
write-host "$($totallayouts - $usablelayouts) omitted and marked inactive. $totallayouts available layouts."
$choice=Set-LayoutsForTransfer -allLayouts $assetlayouts
$sourceassetlayout = $choice.SourceLayout
$destassetlayout = $choice.DestLayout
$MergeOnMatch = [bool]$("yes" -eq $(Select-ObjectFromList -message "if an asset in source layout $($sourceassetlayout.name) has a Name that matches a Name in dest layout $($destassetlayout.name), should we merge source into dest (yes) or overwrite dest with source (no)?" -objects @("yes","no")))
$SkipOnMatch = if ($MergeOnMatch -eq $true) {$false} else {[bool]$("yes" -eq $(Select-ObjectFromList -message "if an asset in source layout $($sourceassetlayout.name) has a Name that matches a Name in dest layout $($destassetlayout.name), should we skip adding source asset into dest (yes) or create both (no)?" -objects @("yes","no")))}
$MergeMode = if ($MergeOnMatch -eq $true) {$(Select-Objectfromlist -message "which merge mode / approach for matching assets in destination?" -objects @('Merge-FillBlanks','Merge-PreferSource','Merge-Concat'))} else {$null}



foreach ($layout in @($sourceassetlayout, $destassetlayout)){
    write-host "getting relinkable fields from layout $($layout.name)..."
    $layout | Add-Member -NotePropertyName linkables -NotePropertyValue $(Get-RelinkableAssetTagLayoutFields -fromLayoutId $layout.id) -Force
}

if ($(test-path "$mapfile")) {
    write-host "backed up $mapfile to $mapfile.old"; Move-Item $mapfile "$mapfile.old" -Force
}

# get fields mapped and ready
$srcfields=@()
$sourceListItemMap = @{}
foreach ($field in $sourceassetlayout.fields | Where-Object {$_.field_type -ne "AssetTag"}) { # assettag fields are carried over as relationships
    if ($field.field_type -ieq "ListSelect" -and $null -ne $field.list_id){
        $typicalValues = $(Get-HuduLists -id $field.list_id).list_items ?? @()
        $sourceListItemMap["$($field.label)"]=$typicalValues.name
        $srcfields+=@{label = $field.label; field_type = $field.field_type; list_id=$field.list_id; typicalValues=$typicalValues; required = $($field.required ?? $false)}
    } elseif ($field.field_type -ieq 'DropDown' -and -not ([string]::IsNullOrEmpty($field.options))){
        $typicalValues = $(Get-NormalizedDropdownOptions $field.options) ?? @()
        $srcfields+=@{label = $field.label; field_type = $field.field_type; typicalValues=$typicalValues; required = $($field.required ?? $false)}
    } else {
        $srcfields+=@{label = $field.label; type = $field.field_type; required = $($field.required ?? $false)}
    }
}
$dstfields=@()
foreach ($field in $destassetlayout.fields) {
    if ($field.field_type -eq "ListSelect" -and $null -ne $field.list_id){
        $dstfields+=@{label = $field.label; field_type = $field.field_type; list_id=$field.list_id; required = $($field.required ?? $false)}
    } else {
        $dstfields+=@{label = $field.label; field_type = $field.field_type; required = $($field.required ?? $false)}
    }
}


foreach ($fields in @(@{name="source"; value=$srcfields}, @{name="dest"; value=$dstfields})) {
    $fields.value | convertto-json -depth 66 | out-file "$($fields.name)-fields.json"
}
build-templatemap -destfields $dstfields -mapfile $mapfile


read-host "press enter if you filled in your mapfile, $mapfile"
while ($true) {
    if (-not $(test-path "$mapfile")) {
        read-host "mapfile not found, please ensure it is in working directory, $mapfile, and press enter to continue"
    }    
    try {
        . .\$mapfile
        break
    } catch {
        read-host "your mapfile has error: $_ please update, save, and press enter to try again."
    }
}

$sourcedestlabels       = @{};        $sourcedestrequired      = @{};
$sourcedestStripHTML    = @{};     $sourceDestDataType         = @{};
$addressMapsByDest      = @{};    $ListSelectEquivilencyMaps   = @{};

foreach ($entry in $mapping) {
    if ($entry.dest_type -eq 'ListSelect' -and -not ([string]::IsNullOrWhiteSpace($entry.from))) {
        $parsedMap = @{}
        $entry.Mapping.GetEnumerator().Where({$_.Value.whenvalues?.Count -gt 0}).ForEach({
            $parsedMap[$_.Key] = $_.Value.whenvalues
        })
        $ListSelectEquivilencyMaps[$entry.to]=@{Mapping = $parsedMap; list_options=$($entry.Mapping.Keys); list_id=$entry.list_id; add_listitems=$("$($entry.add_listitems)" -ilike "t*" ?? $false)}
        $sourcedestlabels[$entry.from] = $entry.to
        $sourcedestStripHTML[$entry.from] = [bool]$(@('t','true','y','yes') -contains "$($entry.striphtml ?? "true")".ToLower())
        $sourceDestDataType[$entry.from] = 'ListSelect'
        continue
    } elseif ($entry.dest_type -eq 'AddressData') {
        $addressMapsByDest[$entry.to] = $entry.address
        $sourcedestrequired[$entry.from] = $false
        $sourceDestDataType[$entry.from] = 'AddressData'
        $sourcedestlabels[$entry.from] = 'Meta'
        continue
    }
    $sourcedestStripHTML[$entry.from] = [bool]$(@('t','true','y','yes') -contains "$($entry.striphtml ?? "False")".ToLower())
    write-host "mapping $($entry.from) to $($entry.to) $(if ($true -eq $sourcedestStripHTML[$entry.from]) {"destination field of $($entry.to) will have HTML stripped."} else {'as-is'})"
    $sourcedestlabels[$entry.from] = $entry.to
    $sourcedestrequired[$entry.from] = $((Get-CastIfBoolean ($entry.required ?? $false) -allowFuzzy $false) ?? $false)
    $sourceDestDataType[$entry.from] = $($entry.dest_type ?? 'Text')
}

$mappingtosmooshed = [bool]$($SMOOSHLABELS.count -gt 0)
$sourceAssets = $($allAssets | Where-Object {$_.asset_layout_id -eq $sourceassetlayout.id}) 
$destassets = $($allAssets | Where-Object {$_.asset_layout_id -eq $destassetlayout.id}) 
if ($sourceassets.count -lt 1) { write-host "NO SOURCE ASSETS!"; exit}
read-host "$($($addressMapsByDest.GetEnumerator()).count) Location Types in Target press enter to proceed"


$totalcounts = @{fromablescreated=0; toablescreated=0; assetsarchived=0; assetsmoved=0;
                 assetsskipped=0; assetsmatched=0; errored=0; sourceassetcount=$sourceassets.count;}

# write-out user-defined infos before start
if ($mappingtosmooshed) {write-host "Smooshing $SMOOSHLABELS => $mappingtosmooshed; $(($mapping | Where-Object { $_.from -eq 'SMOOSH' }).to)"}
if ($CONSTANTS) {
    foreach ($c in $CONSTANTS){write-host "Dest Labels containing $($c.to_label) will be given static value from literal $($c.literal) as literal value!"}
} else {write-host "No constants mapped"}
if ($ListSelectEquivilencyMaps.Keys.count -gt 0){Write-host "$($ListSelectEquivilencyMaps.Keys.count) listselect target items mapped for $($ListSelectEquivilencyMaps.Keys -join ",")"}
Write-Host "Smooshing $(if ($excludeHTMLinSMOOSH -and $true -eq $excludeHTMLinSMOOSH) {'using plaintext value-joining'} else {'using traditional HTML value joining'})"
read-host "$($sourceassets.count) source assets and $($destassets.count) dest assets. press enter to proceed"


$sourceassetsIDX=0
foreach ($originalasset in $sourceassets) {
    $sourceassetsIDX=$sourceassetsIDX+1
    $linkableToAssetInfo = $null; $NewAssetName = $originalasset.name; $matchedMap = $null; $match = $null; $newAsset = $null;
    write-host "matching existing assets to asset $sourceassetsIDX of $($sourceassets.count) in destination layout assets ($($destassets.count) total) to determine if overlap"
    $match = $destassets | Where-Object { $_.company_id -eq $originalasset.company_id -and $_.name -ieq $originalasset.name } | Select-Object -First 1
    if (-not $match -and $originalasset.name.length -gt 6) {
        $match = $destassets | where-object {$_.company_id -eq $originalasset.company_id -and ($_.name -ilike "$($originalasset.name)*" -or $_.name -ilike "*$($originalasset.name)")} | Select-Object -First 1
    }
    $match = $match.asset ?? $match
    if ($match -and $null -ne $match -and $null -ne $match.fields) {
        $totalcounts.assetsmatched=$totalcounts.assetsmatched+1
        if ($true -eq $MergeOnMatch){
            write-host "Matched existing asset '$($match.name)' (ID: $($match.id)) in destination layout for source asset '$($originalasset.name)' (ID: $($originalasset.id)) - will compile complete list of fields from both"
            $matchedMap = FieldsToLabelValueMap $match.fields
        } elseif ($true -eq $SkipOnMatch) {
            write-host "match found in dest layout. (#$($totalcounts.assetsmatched)) thus far"
            write-host "original: $($($originalasset | ConvertTo-Json -depth 6).ToString())" -ForegroundColor Yellow
            write-host "match: $($($match | ConvertTo-Json -depth 6).ToString())" -ForegroundColor Blue
            continue
        } else {
            write-host "match found in dest layout. (#$($totalcounts.assetsmatched)) thus far"
            $NewAssetName = "$($originalasset.name) (from layout $($sourceassetlayout.name))"
            write-host "overridding name -> $($NewAssetName) and keeping both per user-preference"
        }
    }


    $transformedFields = @()
    if ($CONSTANTS -and $CONSTANTS.count -gt 0) {
        foreach ($c in $CONSTANTS){
            $transformedFields += @{$c.to_label = $c.literal}
        }
    }

    foreach ($field in $originalasset.fields) {
        # acquire destination information
        $transformedlabel = $sourcedestlabels[$field.label] ?? $null
        $destTranslationFieldRequired = $(Get-CastIfBoolean $($sourcedestrequired[$field.label] ?? $false)) ?? $false
        $stripHTML = $($sourcedestStripHTML["$($field.label)"] ?? $false)
        $destFieldType = $sourceDestDataType["$($field.label)"] ?? 'Text'

        # checking basic validity
        if (-not $transformedlabel -or $null -eq $transformedlabel) {write-host "no destination mapping for source field $($field.label)"; continue;}
        if (-not $field.value -or $null -eq $field.value -or ([string]::IsNullOrWhiteSpace($field.value))) {
                write-host "no source value for $($field.label)";
                if ($true -eq $destTranslationFieldRequired) {
                    write-host "no value for REQUIRED $($field.label) => $transformedlabel"
                    $field.value = $($(read-host "target field $($field.label) => $transformedlabel is required but null, enter value") ?? "None")
                } else {
                    write-host "no value for optional $($field.label) => $transformedlabel"
                    continue
                }
        # pre-process listselect source values as huyman-readable
        } elseif ($field.value -ilike '*list_id*'){
            $precastValue=$field.value;
            $listItemId = $null; 
            $listItemId = $(SafeDecode $field.value).list_ids[0]
            $humanValue = $($(get-hudulists).list_items | where-object {$_.id -eq $listItemId} | select-object -first 1).name

            $field.value = $humanValue
            Write-Host "non-empty source val appears to contain listIDs; Raw val '$($precastValue)' as $destFieldType... $($field.value)" -foregroundColor DarkCyan
        }

        # handle listselect item-level mappings if present
        if ($ListSelectEquivilencyMaps.Keys -contains $transformedlabel) {
            $valueEquivilencies = $ListSelectEquivilencyMaps[$transformedlabel]
            $mapping            = $valueEquivilencies.Mapping
        } else {
            $valueEquivilencies = $null
        }
        if (-not $valueEquivilencies -or -not $mapping) {
        # destination field-type validation and post-processing
            write-host "No list mapping for $($field.label) => $transformedlabel, continuing onto destination-specific ($destFieldType) validation and casting."
            if ($true -eq $stripHTML) {
                $field.value="$(Remove-HtmlTags -InputString "$($field.value)")"
            }

            if ($destFieldType -eq "Number"){
                $precastValue=$field.value; $field.value = $(Get-CastIfNumeric $field.value) ?? $(Get-CastIfNumeric $($field.value -replace '\D+', ''));
                Write-Host "non-empty source val on Number target; Casting '$($precastValue)' as int...$($field.value)"
            } elseif ($destFieldType -eq "CheckBox"){
                $precastValue=$field.value; $field.value = $(Get-CastIfBoolean $field.value -allowFuzzy $true) ?? $null
                Write-Host "non-empty source val on CheckBox/Boolean target; Casting '$($precastValue)' as bool...$($field.value)"
            } elseif ($destFieldType -eq "Date"){
                $precastValue=$field.value; $field.value = $(Get-CoercedDate -InputDate "$($field.value)" -OutputFormat 'MM/DD/YYYY') ?? $null;
                Write-Host "non-empty source val on Date target; Casting '$($precastValue)' as date...$($field.value)"
            }
            $transformedFields += @{$transformedlabel = $field.value}
        } else {
            if ([string]::IsNullOrWhiteSpace($field.value)){continue}
        # mapping for individual listitems
            $result = Set-MappedListSelectItemFromuserMapping `
                -Mapping $mapping `
                -RawValue $field.value `
                -SourceListItemMap $sourceListItemMap `
                -FieldLabel $field.label

            if ($result.MatchFound) {
                Write-Host "$transformedlabel value '$($field.value)' mapped to listselect item '$($result.Key)'"
                $transformedFields += @{ $transformedlabel = $result.Key }
            } elseif (Get-CastIfBoolean $valueEquivilencies.add_listitems) {
                write-host "List item not in range, adding $($field.value) to list id $($valueEquivilencies.list_id)..." -ForegroundColor Yellow
                $listCache = Refresh-ListCache
                Ensure-HuduListItemByName -ListId $valueEquivilencies.list_id -Name "$($field.value)".Trim() -listNameExistsByListId $listCache
                $transformedFields += @{ $transformedlabel = $("$($field.value)".Trim()) }
            } else {Write-Host "No value matches for list id $($valueEquivilencies.list_id) from '$($field.value)' / '$($result.Normalized)'; not configured to add list items, so leaving empty."}
        }
        
        if ($destFieldType -ilike "Password"){
            write-host "$($field.label) => *** [masked password] for value"
        } else {
            write-host "$($field.label) => $transformedlabel for value $($field.value)"
        }
    }

    # seperate section for meta-mapping address source fields to addressdata target
    foreach ($kv in $addressMapsByDest.GetEnumerator()) {
        $destLabel = $kv.Key
        $addrMap   = $kv.Value

        $addr1 = Get-FieldValueByLabel $originalasset.fields $addrMap.address_line_1.from
        $addr2 = Get-FieldValueByLabel $originalasset.fields $addrMap.address_line_2.from
        $city  = Get-FieldValueByLabel $originalasset.fields $addrMap.city.from
        $state = Get-FieldValueByLabel $originalasset.fields $addrMap.state.from
        $zip   = Get-FieldValueByLabel $originalasset.fields $addrMap.zip.from
        $cntry = Get-FieldValueByLabel $originalasset.fields $addrMap.country_name.from

        $state = Normalize-Region $state
        $zip   = Normalize-Zip    $zip
        $cntry = Normalize-CountryName $cntry

        if ($addr1 -or $addr2 -or $city -or $state -or $zip -or $cntry) {
            $NewAddress = [ordered]@{
                address_line_1 = $addr1
                city           = $city
                state          = $state
                zip            = $zip
                country_name   = $cntry
            }
            if ($addr2) { $NewAddress['address_line_2'] = $addr2 }
            $transformedFields += @{ $destLabel = $NewAddress }
        }
    }


    if ($sourceassetlayout.linkables -and $sourceassetlayout.linkables.keys.count -gt 0){
        Write-host "Getting linkable items for asset $($originalasset.name) from $($sourceassetlayout.linkables.keys.count) potentially linkable"
        $linkableToAssetInfo = Get-RelinkableRelationsForAsset -sourceAsset $originalasset -labelLinkMap $sourceassetlayout.linkables
    }
    # map custom smooshed fields ( notes, richtext, whatever we smooshed to in map)
    if ($true -eq $mappingtosmooshed) {
        $valueToAdd="$(Set-SmooshAssetFieldsToField -sourceAsset $originalasset -smooshsource $SMOOSHLABELS -includeBlanks $($includeblanksduringsmoosh ?? $false))"
        # if linkables, smoosh in too.
        if ($describeRelatedInSmoosh -and $true -eq $describeRelatedInSmoosh){
            $describerelated=Get-SmooshedLinkableDescription -linkableObjects $linkableToAssetInfo
            $valueToAdd="$describerelated<br>$valueToAdd"
            if ($true -eq $excludeHTMLinSMOOSH){$valueToAdd = Remove-HtmlTags -InputString $valueToAdd }
        }        
        $transformedFields+=@{"$($sourcedestlabels["SMOOSH"])" = $valueToAdd}
    }

    $newAssetRequest = @{
        Name            = $NewAssetName ?? $originalasset.name
        CompanyId       = $originalasset.company_id
        AssetLayoutId   = $destassetlayout.id
    }

     if ($null -ne $matchedmap -and $matchedmap.count -gt 0){
        write-host "Merging transformed fields with matched existing asset fields..."
        $transformedMap = Convert-FieldArrayToMap $transformedFields 
        $finalMap = Merge-HuduFieldMaps `
            -SourceMap $transformedMap -DestMap $matchedMap -LayoutFields $destassetlayout.fields -Mode $mergeMode `
            -StampProvenance:$true -SourceStamp "From $($sourceassetlayout.name)" -DestStamp   "Existing $($destassetlayout.name)"
        $newAssetRequest["Fields"] = LabelValueMapToFields -Map $finalMap -LayoutFields $destassetlayout.fields
        $newAssetRequest["Id"]     = $match.id
    } elseif ($transformedFields -and $transformedFields.count -gt 0){
        $newAssetRequest["Fields"]=$transformedFields
        write-host $($($transformedFields | convertto-json -depth 5).ToString())
     }


    # prepare any typical asset properties, falling back to a match if a match is present + configured for merge
    $propPairs = @(
        @{ Dest = 'PrimarySerial';       Source = 'primary_serial' }
        @{ Dest = 'PrimaryMail';         Source = 'primary_mail' }
        @{ Dest = 'PrimaryModel';        Source = 'primary_model' }
        @{ Dest = 'PrimaryManufacturer'; Source = 'primary_manufacturer' }
    )
    foreach ($pairing in $propPairs) {
        if ($null -ne $matchedMap -and $matchedMap.count -gt 0){
            write-host "using matched asset for fallback to common property $($pairing.Source) since merging on match is enabled"
            $commonPropValue = $originalAsset.($pairing.Source) ?? $match.($pairing.Source)
        } else {
            $commonPropValue = $originalAsset.($pairing.Source)
        }
        if (-not [string]::IsNullOrEmpty("$commonPropValue")) {
            Write-Host "using value $commonPropValue from source $($pairing.source)->$($pairing.dest)"
            $newAssetRequest[$pairing.Dest] = $commonPropValue
        } else {
            Write-Host "skipping empty value for common-property, $($pairing.source)"             
        }
    }
    # update or create, depending on if we had a match or not
    try {
        if ($null -ne $newAssetRequest.id -and $newAssetRequest.id -gt 0){
            write-host "$($($newAssetRequest | ConvertTo-Json -depth 66).ToString())"
            $newAsset = $(set-huduasset @newAssetRequest)
            $newAsset = $newAsset.asset ?? $newAsset
            write-host "updated asset $($newAsset.id)"
        } else {
            write-host "$($($newAssetRequest | ConvertTo-Json -depth 66).ToString())"
            $newAsset = $(new-huduasset @newAssetRequest)
            $newAsset = $newAsset.asset ?? $newAsset
            write-host "Created asset $($newAsset.id)"
        }
    } catch {
        Write-ErrorObjectsToFile -ErrorObject @{Err=$_; request=$newAssetRequest} -Name "$($newAssetRequest.name)$(if ($null -ne $newAssetRequest.id -and $newAssetRequest.id -gt 0) {"-update-$($newAssetRequest.id)"} else {"-create"})"
        continue
    }

    if (-not $newAsset -or $null -eq $newAsset) {
        Write-ErrorObjectsToFile -ErrorObject $newAssetRequest -Name "NC-$($newAssetRequest.name)"
        $totalcounts.errored=$totalcounts.errored+1
        continue
    }
    if ($null -ne $newAssetRequest.id -and $newAssetRequest.id -gt 0){
        write-host "updated asset $($newasset.id), no need to re-relate or archive items outside of previous asset-tags"
    } else {
        # archive new asset if original was archived
        if ($originalasset.archived -eq $true) {
            Set-HuduAssetArchive -CompanyId $newAsset.company_id -Id $newAsset.id -Archive $true
            $totalcounts.assetsarchived=$totalcounts.assetsarchived+1
        }
        # archive source asset if configured to do so
        if ($archivesource -eq $true) {
            Set-HuduAssetArchive -CompanyId $originalasset.company_id -Id $originalasset.id -Archive $true
            $totalcounts.assetsarchived=$totalcounts.assetsarchived+1
        }        
        $totalcounts.assetsmoved=$totalcounts.assetsmoved+1
        write-host "created asset $($newasset.id), adding relations now."
        # add relations

        $sourceToables  = $($($allrelations | where-object {$_.toable_type -eq 'Asset' -and $originalasset.id -eq $_.toable_id }) ?? @())
        write-host "$($sourceToables.count) toable relations"
        $sourceFromables  = $($($allrelations | where-object {$_.fromable_type -eq 'Asset' -and $originalasset.id -eq $_.fromable_id }) ?? @())
        write-host "$($sourceFromables.count) fromable relations"
        $relationsTo = $sourceToables | Where-Object { $_.toable_id -eq $originalasset.id }
        
        if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
        foreach ($rel in $relationsTo) {
            try {
                $newToable=New-HuduRelation -FromableType $rel.fromable_type -FromableId $rel.fromable_id -ToableType "Asset" -ToableId $newAsset.id
                write-host "created toable rel $($newToable.id)"
                $totalcounts.toablescreated= if ($newToable) {$totalcounts.toablescreated+1} else {$totalcounts.toablescreated}
            } catch {
                Write-ErrorObjectsToFile -ErrorObject @{Err= $_; From = $relationsFrom; To=$relationsTo} -Name "NCREL-TOABLE-$($newasset.name)"
            }
        }
        $relationsFrom = $sourceFromables | Where-Object { $_.fromable_id -eq $originalasset.id }
        foreach ($rel in $relationsFrom) {
            try {
                $newFromable=New-HuduRelation -FromableType "Asset" -FromableId $newAsset.id -ToableType $rel.toable_type -ToableId $rel.toable_id
                write-host "created fromable rel $($newFromable.id)"
                $totalcounts.fromablescreated= if ($newFromable) {$totalcounts.fromablescreated+1} else {$totalcounts.fromablescreated}
            } catch {
                Write-ErrorObjectsToFile -ErrorObject @{Err= $_; From = $relationsFrom; To=$relationsTo} -Name "NCREL-FROMABLE-$($newasset.name)"
            }            
        }
    }
    # add assettag linking regardless of match/merge or made assets
    if ($linkableToAssetInfo -and $linkableToAssetInfo.count -gt 0){
        if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
        write-host "Asset has external asset links, relinking $($linkableToAssetInfo.count) for $($originalasset.name)"
        foreach ($linkableToAsset in $linkableToAssetInfo) {
            $linkedAsset=$linkableToAsset.LinkedAsset
            if (-not $linkableToAsset.LinkedAsset) {continue}
            try {
                $newToable=New-HuduRelation -FromableType 'Asset' -ToableType "Asset" -FromableId $LinkedAsset.id -ToableID $newAsset.id
                $totalcounts.toablescreated= if ($newToable) {$totalcounts.toablescreated+1} else {$totalcounts.toablescreated}
                write-host "created asset-toable rel $($newToable.id)"
            } catch {
                $totalcounts.errored=$totalcounts.errored+1
                Write-ErrorObjectsToFile -ErrorObject @{Err = $_; From = $relationsFrom; To=$relationsTo} -Name "NCREL-AL-$($newasset.name)"
            }
        }
    }
    if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $false} catch {}}
}
Write-host "wrap-up" -ForegroundColor cyan
$newlayoutname = $null
if ("yes" -eq $(Select-ObjectFromList -objects @("yes","no") -message "would you like to rename source layout ($($sourceassetlayout.name))" -allowNull $false)){
    $newlayoutname = read-host "what is the new name for $($sourceassetlayout.name)"
}
if ([string]::IsNullOrWhiteSpace($newlayoutname)) {$newlayoutname = $sourceassetlayout.name}
if ("yes" -eq $(Select-ObjectFromList -objects @("yes","no") -message "would you like to archive source layout's assets? ($($sourceassets.count) total)" -allowNull $false)){
    $setsourceassetsarchived = $true
}
if ($newlayoutname -ne $sourceassetlayout.name){
    Set-HuduAssetLayout -id $sourceassetlayout.id -Name $newlayoutname
}
if ($true -eq $setsourceassetsarchived) {
    foreach ($originalasset in $sourceassets) {
        $result=Set-HuduAssetArchive -id $originalasset.id -CompanyId $originalasset.company_id -archive $true
        $totalcounts.assetsarchived=$(if ($result) {$totalcounts.assetsarchived+1} else {$totalcounts.assetsarchived})
    }
}

foreach ($entry in $totalcounts.GetEnumerator()) {
    Write-Host "$($entry.Key): $($entry.Value)" -ForegroundColor DarkCyan
}
