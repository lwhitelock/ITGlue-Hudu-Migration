<#
.SYNOPSIS
Export Hudu KB articles for a single company to HTML files, preserving folder structure.

.REQUIREMENTS
- PowerShell 5.1+ (for Out-GridView) or PowerShell 7 with Microsoft.PowerShell.GraphicalTools
- HuduAPI module

.FLOW
1) Prompt for Hudu URL and API Key
2) Choose company by: ID / exact Name / pick from list (Out-GridView)
3) Prompt for export base path
4) Build folder tree via Get-HuduFolders
5) Export all articles for the company to CompanyName\...\<ArticleName>.html
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Ensure-Module {
  param([string]$Name)
  if (-not (Get-Module -ListAvailable -Name $Name)) {
    Install-Module $Name -Scope CurrentUser -Force -AllowClobber | Out-Null
  }
  Import-Module $Name -Force
}

function Use-Hudu {
  param([Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$ApiKey)
  New-HuduBaseURL $BaseUrl  | Out-Null
  New-HuduAPIKey  $ApiKey   | Out-Null
}

function Sanitize-Name {
  param([string]$Name)
  if ([string]::IsNullOrWhiteSpace($Name)) { return "_blank" }
  $bad = [IO.Path]::GetInvalidFileNameChars() + [char]':' + [char]'|'
  $safe = ($Name.ToCharArray() | ForEach-Object { if ($bad -contains $_) { '_' } else { $_ } }) -join ''
  # trim and collapse spaces/underscores
  ($safe -replace '\s+',' ') -replace '_{2,}','_'
}

function Choose-Company {
  param($Companies)

  Write-Host "`nSelect company input method:"
  Write-Host "[1] Company ID"
  Write-Host "[2] Exact Company Name"
  Write-Host "[3] Pick from list (Out-GridView)"
  $choice = Read-Host "Enter 1 / 2 / 3"
  switch ($choice) {
    '1' {
      $id = [int](Read-Host "Enter Company ID")
      return $Companies | Where-Object { $_.id -eq $id } | Select-Object -First 1
    }
    '2' {
      $name = Read-Host "Enter exact Company Name"
      return $Companies | Where-Object { $_.name -eq $name } | Select-Object -First 1
    }
    '3' {
      if (-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
        throw "Out-GridView not available. Install Microsoft.PowerShell.GraphicalTools or use option 1/2."
      }
      return ($Companies | Sort-Object name | Select-Object name,id | Out-GridView -Title "Pick a Company" -PassThru) | ForEach-Object {
        $Companies | Where-Object { $_.id -eq $_.id } | Select-Object -First 1
      }
    }
    default { throw "Invalid selection." }
  }
}

function Build-FolderPathMap {
  <#
    Returns: Hashtable: FolderId => RelativePath (e.g., "How-To\Networking")
    Builds full path by walking parent_id chain.
  #>
  param($Folders)

  $byId = @{}
  foreach ($f in $Folders) { $byId[$f.id] = $f }

  $cache = @{}

  function ResolvePath([int]$id) {
    if ($cache.ContainsKey($id)) { return $cache[$id] }
    $node = $byId[$id]
    if (-not $node) { return $null }
    $name = Sanitize-Name $node.name
    $path = if ($node.parent_id) {
      $parentPath = ResolvePath([int]$node.parent_id)
      if ($parentPath) { Join-Path $parentPath $name } else { $name }
    } else { $name }
    $cache[$id] = $path
    return $path
  }

  foreach ($f in $Folders) { [void](ResolvePath([int]$f.id)) }
  return $cache
}

function Ensure-Dir {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

# --- 1) Collect connection info ---
$baseUrl = Read-Host "Hudu Base URL (e.g., https://hudu.example.com)"
if ([string]::IsNullOrWhiteSpace($baseUrl)) { throw "Hudu URL is required." }
$apiKey  = Read-Host "Hudu API Key"
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw "API Key is required." }

Ensure-Module HuduAPI
Use-Hudu -BaseUrl $baseUrl -ApiKey $apiKey

# --- 2) Choose company ---
$companies = Get-HuduCompanies
if (-not $companies) { throw "No companies returned from Hudu." }

$company = Choose-Company -Companies $companies
if (-not $company) { throw "Company not found/selected." }
$companyName = $company.name
$companyId   = $company.id

Write-Host "Selected company: $companyName (ID: $companyId)"

# --- 3) Export path ---
$exportBase = Read-Host "Export base path (folder will be created under this path)"
if ([string]::IsNullOrWhiteSpace($exportBase)) { throw "Export base path is required." }
$exportRoot = Join-Path $exportBase (Sanitize-Name $companyName)
Ensure-Dir $exportRoot

# --- 4) Gather folders and articles ---
$allFolders = Get-HuduFolders
$companyFolders = $allFolders | Where-Object { $_.company_id -eq $companyId -or $_.company_id -eq $null } # include global folders just in case
$folderPathMap = Build-FolderPathMap -Folders $companyFolders

$allArticles = Get-HuduArticles
$articles = $allArticles | Where-Object { $_.company_id -eq $companyId }

if (-not $articles) {
  Write-Host "No articles found for company '$companyName'."
  return
}

# --- 5) Export ---
$i = 0
$total = $articles.Count
foreach ($a in $articles) {
  $i++
  Write-Progress -Activity "Exporting articles" -Status "[$i/$total] $($a.name)" -PercentComplete (($i/$total)*100)

  $relFolder = $null
  if ($a.folder_id) {
    $relFolder = $folderPathMap[[int]$a.folder_id]
  }

  $targetDir = if ($relFolder) { Join-Path $exportRoot $relFolder } else { $exportRoot }
  Ensure-Dir $targetDir

  # build file name; keep unique with id/slug suffix
  $fileBase = Sanitize-Name $a.name
  if (-not $fileBase) { $fileBase = "_document" }
  $suffix = if ($a.slug) { $a.slug } else { $a.id }
  $file    = Join-Path $targetDir ("{0}__{1}.html" -f $fileBase, $suffix)

  # write content as UTF8 (no BOM)
  [IO.File]::WriteAllText($file, [string]$a.content, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host "Done. Exported $total article(s) to: $exportRoot"
