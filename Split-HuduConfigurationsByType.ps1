Import-Module ImportExcel
$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1"
if (Test-Path $HAPImodulePath) {
    Import-Module $HAPImodulePath -Force
    Write-Host "Module imported from $HAPImodulePath"
} elseif ((Get-Module -ListAvailable -Name HuduAPI).version -ge '2.4.4') {
    Write-Host "Module imported from $HAPImodulePath"
    Import-Module HuduAPI
} else {
    Install-Module HuduAPI -MinimumVersion 2.4.5 -Scope CurrentUser
    Import-Module HuduAPI
}
  
$Path = Read-Host "Provide spreadsheet mapping of ITGlue (configuration type names) to Hudu (asset layout names)"
$APIKey = Read-Host "Enter your Hudu API Key"
$APIBaseUrl = Read-Host "Enter your Hudu Base URL"
$ALS = Import-Excel $Path

New-HuduAPIKey $APIKey
New-HuduBaseUrl $APIBaseUrl
$AssetLayouts = Get-HuduAssetLayouts
$Configurations = Get-HuduAssets -AssetLayoutId ($AssetLayouts |? {$_.name -eq 'Configurations'}).id
$ReformedConfigurations = $Configurations | Select @{n='new_assetlayout_id'; e={ $c=$_; ($als |? {$_.'IT Glue' -eq ($c.fields |? {$_.label -eq 'Configuration type name'}).value}).assetlayout_id },*
$AssetsToProcess = $ReformedConfigurations |? {$_.new_assetlayout_id -ne $null}

# Move asset layouts
$Results = foreach ($Asset in $AssetsToProcess) {
  # Pull Configurations by name
  Write-Host "Moving $($Asset.name) configuration of $(($Asset.fields |? {$_.label -eq 'Configuration type name'}).value) type to asset layout $($Asset.new_assetlayout_id)" -ForegroundColor Cyan
  Move-HuduAssetsToNewLayout -Id $Asset.id -CompanyId $Asset.company_id -AssetLayoutId $Asset.new_assetlayout_id 
}
