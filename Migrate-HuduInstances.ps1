<# 
.SYNOPSIS
  Hudu-to-Hudu migrator: Companies, Asset Layouts, Assets, KB Folders/Articles, Passwords.
  Company matching is by Name. Optional image host rewrite in article HTML.
  WRITTEN BY CHATGPT RUN WITH CARE

.PARAMETERS
  -SourceBaseUrl    https://hudu-src.example.com
  -SourceApiKey     <string>
  -TargetBaseUrl    https://hudu-dst.example.com
  -TargetApiKey     <string>
  -CompanyInclude   Names to include (default: all)
  -PageSize         Page size when fetching lists (best-effort; module may auto-paginate)
  -RewriteImageHost Switch; with -OldImageHost and -NewImageHost replaces <img src> hosts in article HTML
  -UpdateExisting   Update existing objects when found (assets/articles/passwords)
  -DryRun           Log only; no writes

.NOTES
  Requires HuduAPI module (auto-installed). HuduAPI command refs: New/Get/Set-* for Companies, Assets, Articles, Passwords, Folders. 
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)][string]$SourceBaseUrl,
  [Parameter(Mandatory)][string]$SourceApiKey,
  [Parameter(Mandatory)][string]$TargetBaseUrl,
  [Parameter(Mandatory)][string]$TargetApiKey,
  [string[]]$CompanyInclude = @(),
  [int]$PageSize = 500,
  [switch]$RewriteImageHost,
  [string]$OldImageHost,
  [string]$NewImageHost,
  [switch]$UpdateExisting,
  [switch]$DryRun
)

# ---------- Prep ----------
$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable -Name HuduAPI)) {
  Install-Module HuduAPI -Scope CurrentUser -Force -AllowClobber | Out-Null
}
Import-Module HuduAPI -Force

function Use-Hudu {
  param([string]$BaseUrl,[string]$ApiKey)
  New-HuduBaseURL $BaseUrl | Out-Null
  New-HuduAPIKey  $ApiKey  | Out-Null
}

function Log { param($msg) Write-Host "[$(Get-Date -Format s)] $msg" }

# ---------- Helpers ----------
function Get-CompanyMap {
  # Returns @{ 'Company Name' = @{ SrcId = <id>; DstId = <id> } }
  param($SrcCompanies,$DstCompanies)
  $map = @{}
  foreach ($c in $SrcCompanies) {
    if ($CompanyInclude.Count -gt 0 -and $CompanyInclude -notcontains $c.name) { continue }
    $dst = $DstCompanies | Where-Object { $_.name -eq $c.name } | Select-Object -First 1
    if (-not $dst -and -not $DryRun) {
      if ($PSCmdlet.ShouldProcess("Target: Company '$($c.name)'","Create")) {
        $dst = New-HuduCompany -name $c.name
        Log "Created company: $($c.name) -> id $($dst.id)"
      }
    }
    $map[$c.name] = [ordered]@{ SrcId = $c.id; DstId = $dst?.id }
  }
  $map
}

function Ensure-Layouts {
  # Copy asset layouts (fields, icon/colors, include_* flags) by name; returns @{ Name = @{ SrcId; DstId } }
  param($SrcLayouts)
  $layoutMap = @{}
  Use-Hudu -BaseUrl $TargetBaseUrl -ApiKey $TargetApiKey
  $dstLayouts = Get-HuduAssetLayouts
  foreach ($l in $SrcLayouts) {
    $dst = $dstLayouts | Where-Object { $_.name -eq $l.name } | Select-Object -First 1
    if (-not $dst -and -not $DryRun) {
      $fields = @()
      foreach ($f in ($l.fields | Sort-Object position)) {
        $fields += @{
          label      = $f.label
          field_type = $f.field_type
          position   = $f.position
        }
      }
      $args = @{
        name              = $l.name
        icon              = $l.icon
        color             = $l.color
        icon_color        = $l.icon_color
        include_passwords = [bool]$l.include_passwords
        include_photos    = [bool]$l.include_photos
        include_comments  = [bool]$l.include_comments
        include_files     = [bool]$l.include_files
        fields            = $fields
      }
      if ($PSCmdlet.ShouldProcess("Target: AssetLayout '$($l.name)'","Create")) {
        $dst = New-HuduAssetLayout @args
        Log "Created asset layout: $($l.name) -> id $($dst.id)"
      }
    }
    $layoutMap[$l.name] = [ordered]@{ SrcId = $l.id; DstId = $dst?.id }
  }
  $layoutMap
}

function Build-CustomFieldsForWrite {
  # Convert source asset.fields -> array of @{ <internal_name_or_label_snake> = value }
  param($Asset)
  $out = @()
  foreach ($f in $Asset.fields) {
    $key =
      if ($f.PSObject.Properties.Name -contains 'name' -and $f.name) { $f.name }
      elseif ($f.PSObject.Properties.Name -contains 'label' -and $f.label) { ($f.label -replace '[^A-Za-z0-9]+','_').ToLower() }
      else { continue }
    $out += @{ $key = $f.value }
  }
  $out
}

function Ensure-FolderPath {
  # Ensure full folder path exists in target for a given company; returns folder_id (or $null for global/no folder)
  param($SrcFolderId,$SrcAllFolders,$DstCompanyId)
  if (-not $SrcFolderId) { return $null }

  $path = New-Object System.Collections.Generic.List[object]
  $cur  = $SrcAllFolders | Where-Object { $_.id -eq $SrcFolderId }
  while ($cur) {
    $path.Insert(0, $cur)
    $cur = if ($cur.parent_id) { $SrcAllFolders | Where-Object { $_.id -eq $cur.parent_id } } else { $null }
  }

  # Walk/create on target
  Use-Hudu -BaseUrl $TargetBaseUrl -ApiKey $TargetApiKey
  $parentId = $null
  foreach ($node in $path) {
    $existing = Get-HuduFolders | Where-Object {
      $_.name -eq $node.name -and
      (($_.parent_id) -as [int]) -eq ($parentId -as [int]) -and
      (($_.company_id) -as [int]) -eq ($DstCompanyId -as [int])
    } | Select-Object -First 1

    if ($existing) { $parentId = $existing.id; continue }

    if ($DryRun) { continue }
    $newArgs = @{ name = $node.name }
    if ($DstCompanyId) { $newArgs.company_id = $DstCompanyId }
    if ($parentId)     { $newArgs.parent_id  = $parentId     }

    if ($PSCmdlet.ShouldProcess("Target: Folder '$($node.name)'","Create")) {
      $created = New-HuduFolder @newArgs
      $parentId = $created.id
      Log "Created folder: $($node.name) -> id $parentId (company_id=$DstCompanyId parent=$($node.parent_id))"
    }
  }
  $parentId
}

# ---------- Fetch source universe ----------
Use-Hudu -BaseUrl $SourceBaseUrl -ApiKey $SourceApiKey
$srcCompanies = Get-HuduCompanies
if ($CompanyInclude.Count -gt 0) {
  $srcCompanies = $srcCompanies | Where-Object { $CompanyInclude -contains $_.name }
}
$srcLayouts   = Get-HuduAssetLayouts
$srcFolders   = Get-HuduFolders
$srcArticles  = Get-HuduArticles
$srcAssets    = Get-HuduAssets
$srcPwds      = Get-HuduPasswords

# ---------- Build maps / ensure targets ----------
Use-Hudu -BaseUrl $TargetBaseUrl -ApiKey $TargetApiKey
$dstCompanies = Get-HuduCompanies

$CompanyMap = Get-CompanyMap -SrcCompanies $srcCompanies -DstCompanies $dstCompanies
$LayoutMap  = Ensure-Layouts   -SrcLayouts   $srcLayouts

# ---------- Assets ----------
foreach ($c in $srcCompanies) {
  $map = $CompanyMap[$c.name]; if (-not $map?.DstId) { Log "SKIP assets: target company missing for '$($c.name)'"; continue }
  $companyAssets = $srcAssets | Where-Object { $_.company_id -eq $c.id }
  foreach ($a in $companyAssets) {
    $layoutName = ($srcLayouts | Where-Object { $_.id -eq $a.asset_layout_id }).name
    $dstLayoutId = $LayoutMap[$layoutName]?.DstId
    if (-not $dstLayoutId) { Log "SKIP asset '$($a.name)': missing target layout '$layoutName'"; continue }

    # check if exists by name in dst
    Use-Hudu -BaseUrl $TargetBaseUrl -ApiKey $TargetApiKey
    $existing = Get-HuduAssets -companyid $map.DstId -assetlayoutid $dstLayoutId | Where-Object { $_.name -eq $a.name } | Select-Object -First 1
    $fields = Build-CustomFieldsForWrite -Asset $a

    if ($existing) {
      if ($UpdateExisting -and -not $DryRun) {
        if ($PSCmdlet.ShouldProcess("Asset '$($a.name)' (company=$($c.name))","Update")) {
          Set-HuduAsset -name $a.name -company_id $map.DstId -asset_layout_id $dstLayoutId -fields $fields -asset_id $existing.id | Out-Null
          Log "Updated asset: $($a.name)"
        }
      } else {
        Log "SKIP existing asset: $($a.name)"
      }
      continue
    }

    if (-not $DryRun) {
      if ($PSCmdlet.ShouldProcess("Asset '$($a.name)' (company=$($c.name))","Create")) {
        New-HuduAsset -name $a.name -company_id $map.DstId -asset_layout_id $dstLayoutId -fields $fields -PrimarySerial $a.primary_serial -PrimaryMail $a.primary_mail -PrimaryModel $a.primary_model -PrimaryManufacturer $a.primary_manufacturer | Out-Null
        Log "Created asset: $($a.name)"
      }
    }
  }
}

# ---------- KB Folders + Articles ----------
foreach ($art in $srcArticles) {
  $srcCompanyName = if ($art.company_id) { ($srcCompanies | Where-Object { $_.id -eq $art.company_id }).name } else { $null }
  $dstCompanyId   = if ($srcCompanyName) { $CompanyMap[$srcCompanyName]?.DstId } else { $null }

  if ($srcCompanyName -and -not $dstCompanyId) { Log "SKIP article '$($art.name)': target company missing for '$srcCompanyName'"; continue }

  $dstFolderId = Ensure-FolderPath -SrcFolderId $art.folder_id -SrcAllFolders $srcFolders -DstCompanyId $dstCompanyId

  Use-Hudu -BaseUrl $TargetBaseUrl -ApiKey $TargetApiKey
  $existing = Get-HuduArticles | Where-Object {
    $_.name -eq $art.name -and
    (($_.company_id) -as [int]) -eq ($dstCompanyId -as [int]) -and
    (($_.folder_id) -as [int])  -eq ($dstFolderId  -as [int])
  } | Select-Object -First 1

  $content = $art.content
  if ($RewriteImageHost) {
    if (-not $OldImageHost -or -not $NewImageHost) { throw "RewriteImageHost requires -OldImageHost and -NewImageHost" }
    $content = $content -replace ("(src\s*=\s*[""'])(https?://)"+[regex]::Escape($OldImageHost)), "`$1`$2$NewImageHost"
  }

  if ($existing) {
    if ($UpdateExisting -and -not $DryRun) {
      if ($PSCmdlet.ShouldProcess("Article '$($art.name)'","Update")) {
        Set-HuduArticle -name $art.name -content $content -folder_id $dstFolderId -company_id $dstCompanyId -article_id $existing.id | Out-Null
        Log "Updated article: $($art.name)"
      }
    } else {
      Log "SKIP existing article: $($art.name)"
    }
    continue
  }

  if (-not $DryRun) {
    if ($PSCmdlet.ShouldProcess("Article '$($art.name)'","Create")) {
      New-HuduArticle -name $art.name -content $content -folder_id $dstFolderId -company_id $dstCompanyId | Out-Null
      Log "Created article: $($art.name)"
    }
  }
}

# ---------- Passwords ----------
foreach ($c in $srcCompanies) {
  $map = $CompanyMap[$c.name]; if (-not $map?.DstId) { Log "SKIP passwords: target company missing for '$($c.name)'"; continue }
  $pwds = $srcPwds | Where-Object { $_.company_id -eq $c.id }
  foreach ($p in $pwds) {
    Use-Hudu -BaseUrl $TargetBaseUrl -ApiKey $TargetApiKey
    # Try to preserve association if passwordable is Asset; map by asset name in same layout/company.
    $pwdType = $p.passwordable_type
    $pwdTargetId = $null
    if ($pwdType -eq 'Asset' -and $p.passwordable_id) {
      $srcAsset = $srcAssets | Where-Object { $_.id -eq $p.passwordable_id } | Select-Object -First 1
      if ($srcAsset) {
        $layoutName = ($srcLayouts | Where-Object { $_.id -eq $srcAsset.asset_layout_id }).name
        $dstLayoutId = $LayoutMap[$layoutName]?.DstId
        $dstAsset = if ($dstLayoutId) { Get-HuduAssets -companyid $map.DstId -assetlayoutid $dstLayoutId | Where-Object { $_.name -eq $srcAsset.name } | Select-Object -First 1 }
        if ($dstAsset) { $pwdTargetId = $dstAsset.id } else { $pwdType = 'Company' }
      } else {
        $pwdType = 'Company'
      }
    } else {
      $pwdType = 'Company'
    }

    # Exists?
    $existingPwd = Get-HuduPasswords -companyid $map.DstId | Where-Object { $_.name -eq $p.name -and $_.username -eq $p.username } | Select-Object -First 1

    if ($existingPwd) {
      if ($UpdateExisting -and -not $DryRun) {
        if ($PSCmdlet.ShouldProcess("Password '$($p.name)' (company=$($c.name))","Update")) {
          Set-HuduPassword -Id $existingPwd.id -Name $p.name -CompanyId $map.DstId -PasswordableType $pwdType -PasswordableId $pwdTargetId -InPortal ([bool]$p.in_portal) -Password $p.password -OTPSecret $p.otp_secret -URL $p.url -Username $p.username -Description $p.description | Out-Null
          Log "Updated password: $($p.name)"
        }
      } else {
        Log "SKIP existing password: $($p.name)"
      }
      continue
    }

    if (-not $DryRun) {
      if ($PSCmdlet.ShouldProcess("Password '$($p.name)' (company=$($c.name))","Create")) {
        New-HuduPassword -Name $p.name -CompanyId $map.DstId -PasswordableType $pwdType -PasswordableId $pwdTargetId -InPortal ([bool]$p.in_portal) -Password $p.password -OTPSecret $p.otp_secret -URL $p.url -Username $p.username -Description $p.description | Out-Null
        Log "Created password: $($p.name)"
      }
    }
  }
}

Log "DONE."
