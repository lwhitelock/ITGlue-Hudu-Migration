if (-not (Get-Command -Name Get-HuduFlagTypes -ErrorAction SilentlyContinue)) { 
    Write-Host "Flags and Flag Types aren't available in your HuduAPI module version. Skipping."
    $allowSettingFlagsAndTypes = $false
} elseif ($currentVersion -lt [version]("2.40.0")){
    Write-Host "Flags and Flag Types aren't available in your hudu version. Upgrade your hudu instance and try again if it's a dealbreaker."
    $allowSettingFlagsAndTypes = $false
} else {
    $flagsResult = Get-UserFlagSetup; $ObjectFlagMap = $flagsResult.ObjectFlagMap ?? @{}; $allowSettingFlagsAndTypes = $flagsResult.AllowSettingFlags ?? $false; $flagPasswordsByType = $flagsResult.passwordFlagCategories ?? $false;
}