Import-Module ImportExcel
Import-Module HuduAPI
$Path = Read-Host "Provide spreadsheet mapping of ITGlue (configuration type names) to Hudu (asset layout names)"
$APIKey = Read-Host "Enter your Hudu API Key"
$APIBaseUrl = Read-Host "Enter your Hudu Base URL"
$ALS = Import-Excel $Path

New-HuduAPIKey $APIKey
New-HuduBaseUrl = $APIBaseUrl
$AssetLayouts = Get-HuduAssetLayouts
$Configurations = Get-HuduAssets -AssetLayoutId ($AssetLayouts |? {$_.name -eq 'Configurations'}).id
$ReformedConfigurations = $Configurations |select @{n='type'; e={ ($_.fields |? {$_.label -eq 'Configuration Type Name'}).value}},*
$GroupedReformedConfigurations  = $ReformedConfigurations| Group-Object -Property type

# Add ID to each layout
foreach ($AL in $ALS) {$AL|Add-Member -MemberType NoteProperty -Name assetlayout_id -Value ($AssetLayouts|?{$_.name -eq $AL.hudu}).id -Force}

# Move asset layouts
$Results = foreach ($AL in $ALS[0]) {
  # Pull Configurations by name
  $AssetsToMove = ($GroupedReformedConfigurations |? {$_.name -eq $AL.'IT Glue'}).group
  Write-Host "Moving $($AssetsToMove.count) configurations of $($AL.'IT Glue') type to asset layout $($AL.Hudu)" -ForegroundColor Cyan
  Move-HuduAssetsToNewLayout -AssetsToMove $AssetsToMove -NewAssetLayoutID $al.assetlayout_id
}
