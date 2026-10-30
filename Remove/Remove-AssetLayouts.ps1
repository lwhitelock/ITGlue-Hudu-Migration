$AssetLayouts = Get-HuduAssetLayouts

foreach ($AssetLayout in $AssetLayouts) {
    $AssetLayoutId = $AssetLayout.id
    $AssetLayoutName = $AssetLayout.name

    # Remove the AssetLayout
    Remove-HuduAssetLayout -Id $AssetLayoutId -Confirm:$false

    # Log the removal
    Write-Host "Removed AssetLayout: $AssetLayoutName (ID: $AssetLayoutId)"
}