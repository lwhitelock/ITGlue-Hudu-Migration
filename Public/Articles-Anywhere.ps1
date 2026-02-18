# --- helpers kept local to avoid cross-runspace nulls ---
using namespace System.Text.RegularExpressions
try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}
$Script:PDFToHTMLTempBinLocation=$null
# Regex objects used by the rewriter (local; no $Script: scope needed)
$rxTag       = [Regex]::new('<(img|embed|a|iframe|source|video|audio)\b(?<attrs>[^>]*)>', [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline)
$rxAttr      = [Regex]::new('\b(?<name>src|href|data|poster)\s*=\s*(?<q>["''])(?<val>.*?)\k<q>', [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline)
$rxStyleAttr = [Regex]::new('\bstyle\s*=\s*(["''])(?<style>.*?)\1', [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline)
$rxCssUrl    = [Regex]::new('url\(\s*(["'']?)(?<u>[^)"'']+)\1\s*\)', [RegexOptions]::IgnoreCase -bor [RegexOptions]::Singleline)

$huduapikey = $huduapikey ?? $(read-host "Please enter hudu api key")
$hudubaseurl = $hudubaseurl ?? $(read-host "please enter hudu instance url")
function Set-HuduInstance {
    $HuduBaseURL = $HuduBaseURL ?? 
        $((Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g https://myinstance.huducloud.com)') -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://'
    $HuduAPIKey = $HuduAPIKey ?? "$(read-host "Please Enter Hudu API Key")"
    while ($HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API Key from $($settings.HuduBaseDomain)/admin/api_keys").Trim()
        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }
    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}

function Get-EnsureModule {
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Install-Module -Name $Name -Scope CurrentUser -Repository PSGallery -Force -AllowClobber `
            -ErrorAction SilentlyContinue *> $null
    }
    try {
        Import-Module -Name $Name -Force -ErrorAction Stop *> $null
    } catch {
        Write-Warning "Failed to import module '$Name': $($_.Exception.Message)"
    }
}
function Unset-Vars {
    param (
        [string]$varname,
        [string[]]$scopes = @('Local', 'Script', 'Global', 'Private')
    )

    foreach ($scope in $scopes) {
        if (Get-Variable -Name $varname -Scope $scope -ErrorAction SilentlyContinue) {
            Remove-Variable -Name $varname -Scope $scope -Force -ErrorAction SilentlyContinue
            Write-Host "Unset `$${varname} from scope: $scope"
        }
    }
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
function Get-HuduVersionCompatible {
    param (
        [version]$RequiredHuduVersion = [version]"2.37.1",
        $DisallowedVersions = @([version]"2.37.0")
    )
    Write-Host "Required Hudu version: $requiredversion" -ForegroundColor Blue
    try {
        $HuduAppInfo = Get-HuduAppInfo
        $CurrentHuduVersion = $HuduAppInfo.version

        if ([version]$CurrentHuduVersion -lt [version]$RequiredHuduVersion) {
            Write-Host "This script requires at least version $RequiredHuduVersion and cannot run with version $CurrentHuduVersion. Please update your version of Hudu." -ForegroundColor Red
            exit 1
        }
    } catch {
        write-host "error encountered when checking hudu version for $(Get-HuduBaseURL) - $_"
    }
    Write-Host "Hudu Version $CurrentHuduVersion is compatible"  -ForegroundColor Green
}

function Get-PSVersionCompatible {
    param (
        [version]$RequiredPSversion = [version]"7.5.1"
    )

    $currentPSVersion = (Get-Host).Version
    Write-Host "Required PowerShell version: $RequiredPSversion" -ForegroundColor Blue

    if ($currentPSVersion -lt $RequiredPSversion) {
        Write-Host "PowerShell $RequiredPSversion or higher is required. You have $currentPSVersion." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "PowerShell version $currentPSVersion is compatible." -ForegroundColor Green
    }
}


function Get-NormalizedTitle([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  ([System.Web.HttpUtility]::HtmlDecode($s) -replace '\s+', ' ').Trim().ToLowerInvariant()
}
function Get-TitleSlug([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  ($s -replace '[^\p{L}\p{Nd}]+','-').Trim('-').ToLowerInvariant()
}
function New-DocImageMap([object[]]$HuduImages) {
  $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($h in $HuduImages) {
    $orig = [string]$h.OriginalFilename
    $url  = $h.UsingImage.url ?? $h.UsingImage.public_url ?? $h.UsingImage.file_url ?? $h.UsingImage.cdn_url
    if (-not $orig -or -not $url) { continue }
    $leaf = Split-Path -Leaf $orig
    $base = [IO.Path]::GetFileNameWithoutExtension($leaf)
    foreach ($k in @(
        $leaf,
        $base,
        [uri]::EscapeDataString($leaf),
        [uri]::EscapeDataString($base)
    )) {
        if ($k -and -not $map.ContainsKey($k)) { $map[$k] = $url }
    }
  }
  $map
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
function Rewrite-DocLinks {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Html,
    [Parameter(Mandatory)][scriptblock]$ImageResolver, # param([string]$src,[hashtable]$ctx)->string/$null
    [Parameter(Mandatory)][scriptblock]$LinkResolver,  # param([string]$href,[hashtable]$ctx)->string/$null
    [hashtable]$Context = @{}
  )
  if ([string]::IsNullOrEmpty($Html)) {
    return [pscustomobject]@{ Html=''; Rewrites=@(); Unresolved=@() }
  }
  $rewrites  = New-Object System.Collections.Generic.List[object]
  $unresolved = New-Object System.Collections.Generic.List[object]

  $html1 = $rxTag.Replace($Html, {
    param([Match]$m)
    $tagName = $m.Groups[1].Value.ToLowerInvariant()
    $attrs   = $m.Groups['attrs'].Value
    $newAttrs = $rxAttr.Replace($attrs, {
      param([Match]$ma)
      $name = $ma.Groups['name'].Value.ToLowerInvariant()
      $q    = $ma.Groups['q'].Value
      $val  = $ma.Groups['val'].Value
      $newVal = if ($name -eq 'href') { & $LinkResolver  $val $Context } else { & $ImageResolver $val $Context }
      if ($newVal -and $newVal -ne $val) {
        $rewrites.Add([pscustomobject]@{ Tag=$tagName; Attr=$name; From=$val; To=$newVal }) | Out-Null
        return "$name=$q$newVal$q"
      } else {
        if (-not $newVal) { $unresolved.Add([pscustomobject]@{ Tag=$tagName; Attr=$name; Value=$val }) | Out-Null }
        return $ma.Value
      }
    })
    "<$tagName$newAttrs>"
  })

  $html2 = $rxStyleAttr.Replace($html1, {
    param([Match]$m)
    $q     = $m.Groups[1].Value
    $style = $m.Groups['style'].Value
    $newStyle = $rxCssUrl.Replace($style, {
      param([Match]$mu)
      $u = $mu.Groups['u'].Value
      $newU = & $ImageResolver $u $Context
      if ($newU -and $newU -ne $u) {
        $rewrites.Add([pscustomobject]@{ Tag='style'; Attr='url'; From=$u; To=$newU }) | Out-Null
        return "url($newU)"
      } else {
        if (-not $newU) { $unresolved.Add([pscustomobject]@{ Tag='style'; Attr='url'; Value=$u }) | Out-Null }
        return $mu.Value
      }
    })
    " style=$q$newStyle$q"
  })

  [pscustomobject]@{ Html=$html2; Rewrites=$rewrites; Unresolved=$unresolved }
}

# --- the single entry point you asked for ---
function Set-HuduArticleFromHtml {
  [CmdletBinding()]
  param(
    [string[]]$ImagesArray = @(),   # flat list of absolute image paths
    [string]$CompanyName = "",                     # optional → global KB if ''
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$HtmlContents,
    [switch]$CreateCompanyIfMissing = $false,
    [string]$HuduBaseUrl
  )

  # 1) Resolve company (optional)
  $matchedCompany = $null
  if ($CompanyName) {
    $huduCompanies = Get-HuduCompanies
    $matchedCompany = $huduCompanies | Where-Object { $_.name -eq $CompanyName } | Select-Object -First 1
    if (-not $matchedCompany) {
      $matchedCompany = $huduCompanies | Where-Object {
        (Test-Equiv -A $_.name -B $CompanyName) -or (Test-Equiv -A $_.nickname -B $CompanyName)
      } | Select-Object -First 1
    }
    if (-not $matchedCompany -and $CreateCompanyIfMissing) {
      $created = New-HuduCompany -Name $CompanyName
      $matchedCompany = ($created.company ?? $created)
    }
  }
  # 2. resolve or create article
  $allHududocuments = Get-HuduArticles
  $matchedDocument = if ($matchedCompany) {
    $allHududocuments | Where-Object { $_.company_id -eq $matchedCompany.id -and (Test-Equiv -A $_.name -B $Title) } | Select-Object -First 1
  } else {
    $allHududocuments | Where-Object { Test-Equiv -A $_.name -B $Title } | Select-Object -First 1
  }
  if (-not $matchedDocument) {
    $matchedDocument = if ($matchedCompany) {
      (Get-HuduArticles -CompanyId $matchedCompany.id -Name $Title | Select-Object -First 1)
    } else {
      (Get-HuduArticles -Name $Title | Select-Object -First 1)
    }
  }
  $newDocument = $null
  if (-not $matchedDocument) {
    $newDocument = if ($matchedCompany) {
      New-HuduArticle -Name $Title -Content '[transfer in-progress]' -CompanyId $matchedCompany.id
    } else {
      New-HuduArticle -Name $Title -Content '[transfer in-progress]'
    }
    $newDocument = $newDocument.article ?? $newDocument
  }
  $articleUsed = $matchedDocument ?? $newDocument
  if (-not $articleUsed -or -not $articleUsed.id) {
    throw "Could not match or create article: '$Title' (Company: '$CompanyName')"
  }

  # 2) Idempotent uploads (company-scoped if company present; else global KB)
  $existingRelatedImages = Get-HuduUploads | Where-Object { $_.uploadable_type -eq 'Article' -and $_.uploadable_id -eq $articleUsed.Id }

  $ImagesArray = @($ImagesArray) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

  $HuduImages = @()
  foreach ($ImageFile in $ImagesArray) {
    if (-not (Test-Path -LiteralPath $ImageFile -PathType Leaf)) { continue }
    $existingUpload = $null
    $uploaded = $null
    $imageFileName = ([IO.Path]::GetFileName($ImageFile)).Trim()

    $existingUpload = $existingRelatedImages | Where-Object { $_.name -eq $imageFileName } | Select-Object -First 1
    if (-not $existingUpload) {
      $existingUpload = $existingRelatedImages | Where-Object { Test-Equiv -A $_.name -B $imageFileName } | Select-Object -First 1
    }
    $existingUpload = $existingUpload.upload ?? $existingUpload

    if (-not $existingUpload) {
        $uploaded = New-HuduUpload -FilePath $ImageFile -Uploadable_Type 'Article' -Uploadable_Id $articleUsed.Id
        $uploaded = $uploaded.upload ?? $uploaded
    }

    $usingImage = $existingUpload ?? $uploaded
    if ($usingImage) {
      $HuduImages += @{ OriginalFilename = $ImageFile; UsingImage = $usingImage }
    }
  }

  # 3) Match or create article (company or global)


  # 4) Build maps for rewriting
  $imageMap   = New-DocImageMap -HuduImages $HuduImages

  $thisUrl = $articleUsed.article.url ?? $articleUsed.url
  $articleMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
  if ($thisUrl) {
    $norm = Get-NormalizedTitle $Title; $slug = Get-TitleSlug $Title
    foreach ($k in @($Title,$norm,$slug,"$Title.html","$Title.htm","$slug.html","$slug.htm", ($Title -replace '\s+','_') + '.html')) {
      if ($k -and -not $articleMap.ContainsKey($k)) { $articleMap[$k] = $thisUrl }
    }
  }

  # 5) Resolvers
  $ImageResolver = {
    param([string]$src, [hashtable]$ctx)
    if ([string]::IsNullOrWhiteSpace($src)) { return $null }
    if ($src -match '^(?i)(https?:|data:)') { return $src }
    $raw = ($src -split '#')[0].Split('?')[0]
    $dec = [System.Web.HttpUtility]::UrlDecode($raw)
    if ($dec -match '^(?i)file:///') { $dec = $dec -replace '^file:///', '' -replace '/', '\' }
    $leaf = Split-Path -Leaf $dec
    $base = [IO.Path]::GetFileNameWithoutExtension($leaf)
    foreach ($k in @($leaf,$base)) { if ($k -and $ctx.ImageMap.ContainsKey($k)) { return $ctx.ImageMap[$k] } }
    # last try with undecoded leaf
    $leaf2 = Split-Path -Leaf $raw; $base2 = [IO.Path]::GetFileNameWithoutExtension($leaf2)
    foreach ($k in @($leaf2,$base2)) { if ($k -and $ctx.ImageMap.ContainsKey($k)) { return $ctx.ImageMap[$k] } }
    return $null
  }
  $LinkResolver = {
    param([string]$href, [hashtable]$ctx)
    if ([string]::IsNullOrWhiteSpace($href)) { return $null }
    if ($href -match '^(?i)https?:') { return $href }
    if ($href.StartsWith('#')) { return $null }
    $raw  = $href.Split('#')[0].Split('?')[0]
    $leaf = Split-Path -Leaf ([System.Web.HttpUtility]::UrlDecode($raw))
    $leafNoEx = [IO.Path]::GetFileNameWithoutExtension($leaf)
    $norm = Get-NormalizedTitle $leafNoEx; $slug = Get-TitleSlug $leafNoEx
    foreach ($k in @($leaf,$leafNoEx,$norm,$slug,"$leafNoEx.html","$leafNoEx.htm","$slug.html","$slug.htm")) {
      if ($k -and $ctx.ArticleMap.ContainsKey($k)) { return $ctx.ArticleMap[$k] }
    }
    return $null
  }

  $ctx = @{ ImageMap = $imageMap; ArticleMap = $articleMap }
  $r = Rewrite-DocLinks -Html $HtmlContents -ImageResolver $ImageResolver -LinkResolver $LinkResolver -Context $ctx
  Set-HuduArticle -Id $articleUsed.Id -CompanyId $articleUsed.company_id -Content $r.Html | Out-Null

  [pscustomobject]@{
    Title       = $Title
    Article     = $r.Html
    HuduArticle = $articleUsed
    HuduImages  = $HuduImages
    HuduCompany = $matchedCompany
    Rewrites    = $r.Rewrites
    Unresolved  = $r.Unresolved
  }
}

function Invoke-WebRequestThrottled {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Uri,
    [int]$TimeoutSec = 60,
    [hashtable]$Headers,
    [ValidateSet('GET','POST','HEAD','PUT','DELETE','PATCH','OPTIONS','TRACE')][string]$Method = 'GET',
    [int]$DelayMs = 250,
    [int]$Retry = 2,
    [int]$RetryDelayMs = 750,
    [string]$Referer,
    [string]$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell/7 PlainFetcher/1.0',
    [switch]$AddDefaultHeaders
  )

  # --- Normalize URI ---
  $u = $Uri.Trim()
  if ($u -notmatch '^(?i)(https?|file)://') {
    Write-Warning "No protocol was specified, adding https:// to the beginning of the specified hostname"
    $u = "https://$u"
  }
  try {
    $uriObj = [Uri]$u
    if (-not $uriObj.IsAbsoluteUri) { throw "URI is not absolute" }
  } catch {
    throw "Invalid Uri '$u' : $($_.Exception.Message)"
  }

  # --- Clean headers: drop null/empty; stringify arrays ---
  $cleanHeaders = @{}
  if ($Headers) {
    foreach ($k in $Headers.Keys) {
      $v = $Headers[$k]
      if ($null -eq $v) { continue }
      if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
        $v = ($v | ForEach-Object { "$_" }) -join ', '
      }
      $vs = "$v".Trim()
      if ($vs -ne '') { $cleanHeaders[$k] = $vs }
    }
  }
  # Ensure non-empty UA even if caller passed null/empty
  if ([string]::IsNullOrWhiteSpace($UserAgent)) {
    $UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell/7 PlainFetcher/1.0'
  }
  # Optional: add plain defaults if caller didn’t provide them
  if ($AddDefaultHeaders) {
    if (-not $cleanHeaders.ContainsKey('Accept')) {
      $cleanHeaders['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    }
    if (-not $cleanHeaders.ContainsKey('Accept-Language')) {
      $cleanHeaders['Accept-Language'] = 'en-US,en;q=0.9'
    }
  }

  # --- Build param splat ---

  $params = @{
    Uri                = $uriObj.AbsoluteUri
    Method             = $Method
    TimeoutSec         = $TimeoutSec
    MaximumRedirection = 5
    ErrorAction        = 'Stop'
    UseBasicParsing    = $true
  }
  if ($cleanHeaders.Count -gt 0) { $params.Headers = $cleanHeaders }
  if (-not [string]::IsNullOrWhiteSpace($UserAgent)) { $params.UserAgent = $UserAgent }

  # Referer: only if valid absolute URL
  if ($Referer) {
    try {
      $refObj = [Uri]$Referer
      if ($refObj.IsAbsoluteUri) {
        if (-not $params.ContainsKey('Headers')) { $params.Headers = @{} }
        $params.Headers['Referer'] = $refObj.AbsoluteUri
      }
    } catch { } # ignore bad referer
  }

  # --- Retry loop ---
  for ($i = 0; $i -le $Retry; $i++) {
    try {
      $resp = Invoke-WebRequest @params
      if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
      return $resp
    } catch {
      $msg = $_.Exception.Message
      # Only blame headers if we actually sent some
      $hadHeaders = ($params.ContainsKey('Headers') -and $params.Headers.Count -gt 0)
      if ($hadHeaders -and $msg -match "format of value '' is invalid") {
        $hdrList = ($params.Headers.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key,$_.Value }) -join '; '
        throw "Invalid header value detected. Headers: $hdrList"
      }
      if ($i -lt $Retry) {
        Start-Sleep -Milliseconds $RetryDelayMs
      } else {
        throw
      }
    }
  }
}

function Resolve-Url([string]$BaseUrl, [string]$MaybeRelative) {
  if ([string]::IsNullOrWhiteSpace($MaybeRelative)) { return $null }
  if ($MaybeRelative -match '^(?i)(https?|file|data):') { return $MaybeRelative }
  if (-not $BaseUrl) { return $MaybeRelative }
  try { return (New-Object Uri([Uri]$BaseUrl, $MaybeRelative)).AbsoluteUri } catch { return $MaybeRelative }
}

function Get-PlainHtml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Html,
    [string]$BaseUrl
  )
  $rxComments = [Regex]::new('<!--.*?-->', 'Singleline')
  $rxScript   = [Regex]::new('<script\b[^>]*>.*?</script>', 'IgnoreCase, Singleline')
  $rxStyleTag = [Regex]::new('<style\b[^>]*>.*?</style>', 'IgnoreCase, Singleline')
  $rxLinkCss  = [Regex]::new('<link\b[^>]*rel=["'']?stylesheet["'']?[^>]*>', 'IgnoreCase, Singleline')
  $rxNoscript = [Regex]::new('<noscript\b[^>]*>.*?</noscript>', 'IgnoreCase, Singleline')

  $rxHref = [Regex]::new('(<a\b[^>]*\bhref\s*=\s*)(["''])(?<u>[^"''#>]+)\2', 'IgnoreCase')
  $rxSrc  = [Regex]::new('(<(?:img|source|video|audio|iframe)\b[^>]*\bsrc\s*=\s*)(["''])(?<u>[^"''>]+)\2', 'IgnoreCase')
  $rxCssUrl = [Regex]::new('url\(\s*(["'']?)(?<u>[^)"'']+)\1\s*\)', 'IgnoreCase')

  $h = $Html
  $h = $rxComments.Replace($h,'')
  $h = $rxScript.Replace($h,'')
  $h = $rxStyleTag.Replace($h,'')
  $h = $rxLinkCss.Replace($h,'')
  $h = $rxNoscript.Replace($h,'')

  # absolutize href/src and CSS url(...)
  $h = $rxHref.Replace($h, { param($m) $pre=$m.Groups[1].Value; $q=$m.Groups[2].Value; $u=$m.Groups['u'].Value; "$pre$q$(Resolve-Url $BaseUrl $u)$q" })
  $h = $rxSrc.Replace($h,  { param($m) $pre=$m.Groups[1].Value; $q=$m.Groups[2].Value; $u=$m.Groups['u'].Value; "$pre$q$(Resolve-Url $BaseUrl $u)$q" })
  $h = $rxCssUrl.Replace($h, { param($m) "url($(Resolve-Url $BaseUrl $m.Groups['u'].Value))" })

  # minimal skeleton if needed
  if (-not ($h -match '<html')) {
    $h = "<!doctype html><html><head><meta charset=""utf-8""></head><body>$h</body></html>"
  }
  $h
}

function Get-HtmlImageUrls {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Html
  )
  $rxImgSrc = [Regex]::new('<img\b[^>]*?\bsrc\s*=\s*(["''])(?<u>.*?)\1', 'IgnoreCase, Singleline')
  $rxSrcset = [Regex]::new('\bsrcset\s*=\s*(["''])(?<s>.*?)\1', 'IgnoreCase, Singleline')
  $rxCssUrl = [Regex]::new('url\(\s*(["'']?)(?<u>[^)"'']+)\1\s*\)', 'IgnoreCase, Singleline')

  $urls = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($m in $rxImgSrc.Matches($Html)) { [void]$urls.Add($m.Groups['u'].Value) }
  foreach ($m in $rxSrcset.Matches($Html)) {
    foreach ($part in ($m.Groups['s'].Value -split ',')) {
      $u = ($part -split '\s+')[0].Trim(); if ($u) { [void]$urls.Add($u) }
    }
  }
  foreach ($m in $rxCssUrl.Matches($Html)) { [void]$urls.Add($m.Groups['u'].Value) }
  $urls
}

function Save-DataUriImage {
  param([string]$DataUri, [string]$OutputDir, [string]$FileBase = 'inline')
  if ($DataUri -notmatch '^data:(?<mime>[^;]+);base64,(?<b64>.+)$') { return $null }
  $mime = $Matches['mime']; $b64 = $Matches['b64']
  $ext  = switch -regex ($mime) {
    '^image/png'  { '.png'  ; break }
    '^image/jpeg' { '.jpg'  ; break }
    '^image/gif'  { '.gif'  ; break }
    '^image/webp' { '.webp' ; break }
    '^image/svg'  { '.svg'  ; break }
    default       { '.bin'  }
  }
  $bytes = [Convert]::FromBase64String($b64)
  [IO.Directory]::CreateDirectory($OutputDir) | Out-Null
  $path = Join-Path $OutputDir ($FileBase + $ext)
  $i=1; while (Test-Path $path) { $path = Join-Path $OutputDir ("{0}_{1}{2}" -f $FileBase,$i,$ext); $i++ }
  [IO.File]::WriteAllBytes($path, $bytes)
  return $path
}


function Get-PlainPageAndImages {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$OutputDir,
    [hashtable]$Headers,        # e.g. @{ Authorization = "Bearer xxx"; Cookie = "..." }
    [int]$DelayMs = 250,        # throttle
    [int]$TimeoutSec = 60,
    [string]$UserAgent
  )

  [IO.Directory]::CreateDirectory($OutputDir) | Out-Null

  # 1) fetch
  if ($Headers -and $Headers.Keys.count -gt 0){
    $resp = Invoke-WebRequestThrottled -Uri $Url -Headers $Headers -DelayMs $DelayMs -TimeoutSec $TimeoutSec -UserAgent $UserAgent
  } else {
    $resp = Invoke-WebRequestThrottled -Uri $Url -AddDefaultHeaders -DelayMs $DelayMs -TimeoutSec $TimeoutSec -UserAgent $UserAgent
  }
  $origHtml = $resp.Content
  $baseUrl  = $resp.BaseResponse.ResponseUri.AbsoluteUri

  # 2) normalize to plain-jane html
  $plainHtml = Get-PlainHtml -Html $origHtml -BaseUrl $baseUrl

  # 3) collect & download images (respect same headers & throttle)
  $urls = Get-HtmlImageUrls -Html $plainHtml
  $downloads = New-Object System.Collections.Generic.List[object]

  foreach ($raw in $urls) {
    $u = Resolve-Url $baseUrl $raw
    $saved = $null; $ok=$false; $err=$null
    try {
      if ($u -match '^(?i)data:image/') {
        $saved = Save-DataUriImage -DataUri $u -OutputDir $OutputDir -FileBase 'inline'
        $ok = [bool]$saved
      }
      elseif ($u -match '^(?i)file://') {
        $src = ($u -replace '^file:///?','') -replace '/','\'
        $leaf = Split-Path -Leaf $src; $dest = Join-Path $OutputDir $leaf
        $i=1; while (Test-Path $dest) { $dest = Join-Path $OutputDir ("{0}_{1}{2}" -f ([IO.Path]::GetFileNameWithoutExtension($leaf)),$i,[IO.Path]::GetExtension($leaf)); $i++ }
        Copy-Item -LiteralPath $src -Destination $dest -Force
        $saved = $dest; $ok = $true
      }
      else {
        $leaf = ($u -as [uri]).Segments[-1]; if (-not $leaf) { $leaf = 'image' }
        $tmp = Join-Path $OutputDir ([IO.Path]::GetRandomFileName())
        $respImg = Invoke-WebRequestThrottled -Uri $u -Headers $Headers -DelayMs $DelayMs -TimeoutSec $TimeoutSec -Referer $baseUrl
        [IO.File]::WriteAllBytes($tmp, $respImg.Content)

        $ext = [IO.Path]::GetExtension($leaf)
        if (-not $ext -and $respImg.Headers.'Content-Type') {
          $ext = switch -regex ($respImg.Headers.'Content-Type') {
            'image/png'  { '.png' } 'image/jpeg' { '.jpg' } 'image/gif' { '.gif' }
            'image/webp' { '.webp'} 'image/svg'  { '.svg' } default { '.img' }
          }
        }
        if (-not $ext) { $ext = '.img' }
        $name = ([IO.Path]::GetFileNameWithoutExtension($leaf)); if (-not $name) { $name = 'image' }
        $dest = Join-Path $OutputDir ($name + $ext)
        $i=1; while (Test-Path $dest) { $dest = Join-Path $OutputDir ("{0}_{1}{2}" -f $name,$i,$ext); $i++ }
        Move-Item -LiteralPath $tmp -Destination $dest -Force
        $saved = $dest; $ok=$true
      }
    } catch { $err = $_.Exception.Message }
    $downloads.Add([pscustomobject]@{ Url=$u; SavedPath=$saved; Success=$ok; Error=$err }) | Out-Null
  }

  # 4) save the normalized HTML too (optional)
  $htmlPath = Join-Path $OutputDir 'page.plain.html'
  Set-Content -LiteralPath $htmlPath -Encoding UTF8 -Value $plainHtml
  $images = Get-ChildItem -LiteralPath $OutputDir -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|bmp|tif|tiff)$' } |
            Select-Object -ExpandProperty FullName

  [pscustomobject]@{
    Url        = $baseUrl
    HtmlPath   = $htmlPath
    Html       = $plainHtml
    Images     = $images
    ImagesDir  = $OutputDir
    Downloads  = $downloads
  }
}

function Get-BasicTextFromPDF {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$InputPdfPath,
    [string]$PdfToHtmlPath
  )

  if (-not (Test-Path -LiteralPath $InputPdfPath -PathType Leaf)) {
    throw "PDF not found: $InputPdfPath"
  }

  # Make a unique temp dir for output
  $OutputDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
  [IO.Directory]::CreateDirectory($OutputDir) | Out-Null

  # Ensure pdftohtml exists; if not, fetch Poppler and point to Library\bin\pdftohtml.exe
  if (-not $PdfToHtmlPath -or -not (Test-Path -LiteralPath $PdfToHtmlPath)) {
    if (-not $Script:PDFToHTMLTempBinLocation -or -not (Test-Path -LiteralPath $Script:PDFToHTMLTempBinLocation)) {

    $url  = 'https://github.com/oschwartz10612/poppler-windows/releases/download/v25.07.0-0/Release-25.07.0-0.zip'
    $root = Join-Path $env:TEMP ("poppler-" + [guid]::NewGuid())
    $zip  = Join-Path $root 'poppler.zip'
    [IO.Directory]::CreateDirectory($root) | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $root -Force
    $bin = Get-ChildItem -Recurse -Directory $root -Filter bin |
           Where-Object { $_.FullName -match '\\Library\\bin$' } |
           Select-Object -First 1 -ExpandProperty FullName
    if (-not $bin) { throw "Could not find Library\bin in downloaded Poppler zip." }
    $PdfToHtmlPath = Join-Path $bin 'pdftohtml.exe'
    } else {
      Write-Host "Reusing Script-Temp PDFtoHTML location $($Script:PDFToHTMLTempBinLocation)"
      $PdfToHtmlPath = $Script:PDFToHTMLTempBinLocation
    }
  }

  if (-not (Test-Path -LiteralPath $PdfToHtmlPath)) {
    throw "pdftohtml not found at: $PdfToHtmlPath"
  } else {
    $Script:PDFToHTMLTempBinLocation = $PdfToHtmlPath ?? $Script:PDFToHTMLTempBinLocation 
  }
  $pdfToTxtPath = join-path -path (split-path $PDFToHTMLTempBinLocation) -ChildPath 'pdftotext.exe'

  $base       = [IO.Path]::GetFileNameWithoutExtension($InputPdfPath)
  $txtOutput = Join-Path $OutputDir ($base + '.txt')

  $argumentsArray = @(
    '-enc','UTF-8'
    '-nopgbrk'
    $InputPdfPath
    $txtOutput
  )


  $proc = Start-Process -FilePath $pdfToTxtPath -ArgumentList $argumentsArray -NoNewWindow -PassThru -Wait -WorkingDirectory $OutputDir
  if ($proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $txtOutput)) {
    throw "pdftohtml failed (exit $($proc.ExitCode)) or output missing: $txtOutput"
  }

  # Collect images that pdftohtml emitted next to the HTML
  $images = @()

  # Read HTML as a single string
  
  $html = Get-Content -LiteralPath $txtOutput -Raw -Encoding UTF8
  $parsedForHTML = "$("$($html -replace ":",":<br><br>")" -replace "-----BEGIN CERTIFICATE-----","<br>-----BEGIN CERTIFICATE-----<br>")" -replace "-----END CERTIFICATE-----","<br>-----END CERTIFICATE-----<br>"

  [pscustomobject]@{
    HtmlPath  = $htmlOutput
    Html      = $parsedForHTML
    Images    = $images
    OutputDir = $OutputDir
    ToolPath  = $PdfToHtmlPath
  }
}


function Get-HTMLAndImagesArrayFromPDF {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$InputPdfPath,
    [string]$PdfToHtmlPath
  )

  if (-not (Test-Path -LiteralPath $InputPdfPath -PathType Leaf)) {
    throw "PDF not found: $InputPdfPath"
  }

  # Make a unique temp dir for output
  $OutputDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
  [IO.Directory]::CreateDirectory($OutputDir) | Out-Null

  # Ensure pdftohtml exists; if not, fetch Poppler and point to Library\bin\pdftohtml.exe
  if (-not $PdfToHtmlPath -or -not (Test-Path -LiteralPath $PdfToHtmlPath)) {
    if (-not $Script:PDFToHTMLTempBinLocation -or -not (Test-Path -LiteralPath $Script:PDFToHTMLTempBinLocation)) {

    $url  = 'https://github.com/oschwartz10612/poppler-windows/releases/download/v25.07.0-0/Release-25.07.0-0.zip'
    $root = Join-Path $env:TEMP ("poppler-" + [guid]::NewGuid())
    $zip  = Join-Path $root 'poppler.zip'
    [IO.Directory]::CreateDirectory($root) | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $root -Force
    $bin = Get-ChildItem -Recurse -Directory $root -Filter bin |
           Where-Object { $_.FullName -match '\\Library\\bin$' } |
           Select-Object -First 1 -ExpandProperty FullName
    if (-not $bin) { throw "Could not find Library\bin in downloaded Poppler zip." }
    $PdfToHtmlPath = Join-Path $bin 'pdftohtml.exe'
    } else {
      Write-Host "Reusing Script-Temp PDFtoHTML location $($Script:PDFToHTMLTempBinLocation)"
      $PdfToHtmlPath = $Script:PDFToHTMLTempBinLocation
    }
  }

  if (-not (Test-Path -LiteralPath $PdfToHtmlPath)) {
    throw "pdftohtml not found at: $PdfToHtmlPath"
  } else {
    $Script:PDFToHTMLTempBinLocation = $PdfToHtmlPath ?? $Script:PDFToHTMLTempBinLocation 
  }

  $base       = [IO.Path]::GetFileNameWithoutExtension($InputPdfPath)
  $htmlOutput = Join-Path $OutputDir ($base + '.html')

  # Build args (no embedded quotes)
  $argumentsArray = @(
    '-s',
    '-noframes',
    '-enc','UTF-8',
    '-fmt','png',
    $InputPdfPath,
    $htmlOutput
  )

  $proc = Start-Process -FilePath $PdfToHtmlPath -ArgumentList $argumentsArray -NoNewWindow -PassThru -Wait -WorkingDirectory $OutputDir
  if ($proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $htmlOutput)) {
    throw "pdftohtml failed (exit $($proc.ExitCode)) or output missing: $htmlOutput"
  }

  # Collect images that pdftohtml emitted next to the HTML
  $images = Get-ChildItem -LiteralPath $OutputDir -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|bmp|tif|tiff)$' } |
            Select-Object -ExpandProperty FullName

  # Read HTML as a single string
  
  $html = Get-Content -LiteralPath $htmlOutput -Raw -Encoding UTF8

  [pscustomobject]@{
    HtmlPath  = $htmlOutput
    Html      = $html
    Images    = $images
    OutputDir = $OutputDir
    ToolPath  = $PdfToHtmlPath
  }
}

function Set-HuduArticleFromPDF {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$PdfPath,
    [string]$CompanyName,
    [string]$Title,
    [bool]$includeOriginal=$true, # include original pdf attached to converted article
    [bool]$useTextOnly = $false     # if true, skip HTML+images and just extract text from PDF for article content
  )

  if (-not (Test-Path -LiteralPath $PdfPath -PathType Leaf)) { write-warning "NO PDF, $($PdfPath)"; return $null }

  $pdfBaseName = [IO.Path]::GetFileNameWithoutExtension($PdfPath)

  if ($true -eq $useTextOnly){
    $pdfData = Get-BasicTextFromPDF -InputPdfPath $PdfPath
  } else {
    $pdfData = Get-HTMLAndImagesArrayFromPDF -InputPdfPath $PdfPath
  }


  $displayTitle = if ($Title) { $Title } else { $pdfBaseName }

  $newDoc = Set-HuduArticleFromHtml `
              -ImagesArray  ($pdfData.Images ?? @()) `
              -CompanyName  $CompanyName `
              -Title        $displayTitle `
              -HtmlContents $pdfData.Html `
              -HuduBaseUrl  (Get-HuduBaseURL)

  if ($true -eq $includeOriginal){
    New-HuduUpload -FilePath $PdfPath -Uploadable_Type 'Article' -Uploadable_Id $newDoc.HuduArticle.Id | Out-Null
  }

  return $newDoc
}

function Set-HuduArticleFromWebPage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Uri,
    [hashtable]$AddtlHeaders = @{},
    [string]$CompanyName,
    [string]$Title
  )

  $uuid = [guid]::NewGuid().ToString()
  $dest = Join-Path $env:TEMP ("grab-" + $uuid)

  $web = Get-PlainPageAndImages -Url $Uri -OutputDir $dest -Headers $AddtlHeaders -DelayMs 300

  # flat list of saved image paths
  $imagePaths = @()
  if ($web -and $web.Downloads) {
    $imagePaths = $web.Downloads | Where-Object Success | Select-Object -ExpandProperty SavedPath
  }
  $displayTitle = if ($Title) { $Title } else { "Captured page ($uuid)" }

  $newDoc = Set-HuduArticleFromHtml `
              -ImagesArray  ($imagePaths ?? @()) `
              -CompanyName  $CompanyName `
              -Title        $displayTitle `
              -HtmlContents $web.Html `
              -HuduBaseUrl  (Get-HuduBaseURL)

  return $newDoc
}

function Set-HuduArticleFromResourceFolder {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ResourcesFolder,
    [string]$CompanyName,
    [string]$Title
  )

  if (-not (Test-Path -LiteralPath $ResourcesFolder -PathType Container)) {
    Write-Warning "NO FOLDER, $ResourcesFolder"; return $null
  }

  try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}

  $uuid    = [guid]::NewGuid().ToString()
  $htmlDoc = Get-ChildItem -LiteralPath $ResourcesFolder -File -Filter '*.html' | Select-Object -First 1

  $images = Get-ChildItem -LiteralPath $ResourcesFolder -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|gif|bmp|tif|tiff|webp|svg)$' } |
            Select-Object -ExpandProperty FullName

  $other  = Get-ChildItem -LiteralPath $ResourcesFolder -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(pdf|docx?|xlsx?|pptx?|txt|csv|md|zip)$' } |
            Select-Object -ExpandProperty FullName

  $html = ''

  if ($htmlDoc) {
    Write-Verbose "Using existing HTML file: $($htmlDoc.FullName)"
    $html = Get-Content -LiteralPath $htmlDoc.FullName -Raw -Encoding UTF8
  }

  # If no HTML file, or it was empty/whitespace, scaffold a simple gallery/list page
  if ([string]::IsNullOrWhiteSpace($html)) {
    if (-not $htmlDoc) {
      Write-Verbose ("No .html found in {0}{1}. Generating basic HTML from resources." -f $ResourcesFolder, $(if ($CompanyName) { " for $CompanyName" } else { "" }))
    } else {
      Write-Verbose "Existing HTML was empty; generating scaffold."
    }

    if ((-not $images -or $images.Count -lt 1) -and (-not $other -or $other.Count -lt 1)) {
      throw "No .html and no supported resources present in '$ResourcesFolder'."
    }

    $parentFolder = [IO.Path]::GetFileName($ResourcesFolder.TrimEnd('\','/'))
    $dispTitle    = if ($Title) { $Title } else { "Directory Listing from $parentFolder" }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!doctype html>')
    [void]$sb.AppendLine('<html><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<style>body{font-family:sans-serif} .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px} figure{margin:0;border:1px solid #ddd;padding:8px;border-radius:8px} figcaption{font-size:12px;color:#555;margin-top:6px;word-break:break-word}</style>')
    [void]$sb.AppendLine('</head><body>')
    [void]$sb.AppendLine(('<h1>{0}</h1>' -f ([System.Web.HttpUtility]::HtmlEncode($dispTitle))))

    if ($images -and $images.Count -gt 0) {
      [void]$sb.AppendLine('<h2>Images</h2><div class="grid">')
      foreach ($p in $images) {
        $leaf = [IO.Path]::GetFileName($p)
        $alt  = [System.Web.HttpUtility]::HtmlEncode($leaf)
        [void]$sb.AppendLine(('<figure><img src="{0}" alt="{1}" loading="lazy" style="max-width:100%;height:auto"><figcaption>{1}</figcaption></figure>' -f $leaf,$alt))
      }
      [void]$sb.AppendLine('</div>')
    }

    if ($other -and $other.Count -gt 0) {
      [void]$sb.AppendLine('<h2>Other Files</h2><ul>')
      foreach ($p in $other) {
        $leaf = [IO.Path]::GetFileName($p)
        $txt  = [System.Web.HttpUtility]::HtmlEncode($leaf)
        [void]$sb.AppendLine(('<li><a href="{0}">{1}</a></li>' -f $leaf,$txt))
      }
      [void]$sb.AppendLine('</ul>')
    }

    [void]$sb.AppendLine('</body></html>')
    $html = $sb.ToString()
  }

  if ([string]::IsNullOrWhiteSpace($html)) {
    Write-Verbose "HTML still empty after scaffold; inserting minimal stub."
    $safeTitle = [System.Web.HttpUtility]::HtmlEncode($(if ($Title) { $Title } else { $uuid }))
    $html = "<!doctype html><html><head><meta charset=""utf-8""></head><body><h1>$safeTitle</h1></body></html>"
  }

  $displayTitle = if ($Title) {
    $Title
  } elseif ($dispTitle){
    $dispTitle
  } elseif ($htmlDoc) {
    [IO.Path]::GetFileNameWithoutExtension($htmlDoc.Name)
  } else {
    $uuid
  }

  Write-Verbose ("Scaffold complete: htmlLen={0}, images={1}, other={2}" -f ($html.Length), ($images?.Count ?? 0), ($other?.Count ?? 0))

  $newDoc = Set-HuduArticleFromHtml `
              -ImagesArray  ($images ?? @()) `
              -CompanyName  $CompanyName `
              -Title        $displayTitle `
              -HtmlContents $html `
              -HuduBaseUrl  (Get-HuduBaseURL)

  return $newDoc
}


Get-PSVersionCompatible; Get-HuduModule; Set-HuduInstance; Get-HuduVersionCompatible;

Write-Host @"
You're all ready to go and create any articles you'd like, from
- webpages
- pdfs
- local directory resources

Examples:
# from a web page
Set-HuduArticleFromWebPage -uri "https://en.wikipedia.org/wiki/Special:Random" -companyname "$($env:USERNAME)'s company" -title "website synced from $($env:COMPUTERNAME)"

# from a PDF file
Set-HuduArticleFromPDF -pdfPath "$($(Get-ChildItem $(join-path -Path $HOME -ChildPath "Downloads") -File -Filter "*.pdf" | select-object -First 1) ?? "c:\tmp\somepdf.pdf")" -companyname "$($env:USERNAME)'s company" -title "new article from pdf"

# From a folder containing any type of files
Set-HuduArticleFromResourceFolder -resourcesFolder "$(join-path -Path $HOME -ChildPath "Desktop") " -companyname "$($env:USERNAME)'s company" -title "$($env:USERNAME)'s Desktop Contents"

# From a local folder containing a webpage and images
Set-HuduArticleFromResourceFolder -resourcesFolder "$(join-path -Path $HOME -ChildPath "Pictures")" -companyname "$($env:USERNAME)'s company" -title "local pictures in $(join-path -Path $HOME -ChildPath "Pictures")"

"@

