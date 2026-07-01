function Import-HuduMigrationLogs {
param($FirstTimeLoad)
  
  # Check if this is a direct run, and load the logs if so the first time.
  if (-not ($FirstTimeLoad -eq 1)) {
      if ($FirstTimeLoad -eq 2) { Write-Host "Force reloading all Migration Logs into console variables" -ForegroundColor Yellow }
      # General Settings Load
      . $PSScriptRoot\..\Initialize-Module.ps1 -InitType 'Lite'
      
      # Add Replace URL functions
      . $PSScriptRoot\..\Private\ConvertTo-HuduURL.ps1
  
      Write-Host "Checking for Matched Variables"
  
      Write-Host "Loading Passwords Log"
      if (-not $MatchedPasswords) {$MatchedPasswords = (Get-Content -path "$MigrationLogs\Passwords.json" | ConvertFrom-json -depth 100) }
      if (-not $MatchedAssetPasswords) {$MatchedAssetPasswords = (Get-Content -path "$MigrationLogs\AssetPasswords.json" | ConvertFrom-json -depth 100) }
  
      Write-Host "Loading Locations Log"
      if (-not $MatchedLocations) {$MatchedLocations = (Get-Content -path "$MigrationLogs\Locations.json" | ConvertFrom-json -depth 100) }
      
      Write-host "Loading Articles Log"
      if (-not $MatchedArticles) {$MatchedArticles = (Get-Content -path "$MigrationLogs\Articles.json" | ConvertFrom-json -depth 100) }
      
      if (-not $MatchedCompanies) {$MatchedCompanies = (Get-Content -path "$MigrationLogs\Companies.json" | ConvertFrom-json -depth 100) }
  
      Write-host "Loading Configuration Log"
      if (-not $MatchedConfigurations) {$MatchedConfigurations = Get-Content "$MigrationLogs\Configurations.json" -raw | Out-String | ConvertFrom-Json -depth 100}
      
      Write-host "Loading Asset Log"
      if (-not $MatchedAssets) {$MatchedAssets = Get-Content "$MigrationLogs\Assets.json" -raw | Out-String | ConvertFrom-Json -depth 100}
      
      # Set the context so logs don't run again unless the powershell window gets closed.
      $FirstTimeLoad = 1
  }
}
