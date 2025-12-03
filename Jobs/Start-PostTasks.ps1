
############################### Wrap-Up ###############################
write-host "wrapup 1/8... setting asset layouts as active, enabling advanced website monitoring features"
foreach ($layout in Get-HuduAssetLayouts) {write-host "setting $($(Set-HuduAssetLayout -id $layout.id -Active $true).asset_layout.name) as active" }
$MatchedWebsites.HuduObject | Where-Object {$_.id -and $_.id -gt 0} | Foreach-Object {write-host "Enabling advanced monitoring features for $($(Set-HuduWebsite -id $_.id -EnableDMARC 'true' -EnableDKIM 'true' -EnableSPF 'true' -DisableDNS 'false' -DisableSSL 'false' -DisableWhois 'false' -Paused 'false').name)" -ForegroundColor DarkCyan}
write-host "wrapup 2/8... adding attachments (this can take a while)"
. .\Add-HuduAttachmentsViaAPI.ps1

write-host "wrapup 3/8... adding missing relations (this can take a long while). Some errors may appear but can be safely ignored."
# set retry to off/false in HuduAPI module, this will save time during adding potentially existent relations.
if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
. .\Get-MissingRelations.ps1

@($AssetRelationsToCreate) + @($ConfigurationRelationsToCreate) | ForEach-Object {try {New-HuduRelation -FromableType  $_.FromableType -FromableID    $_.FromableID -ToableType    $_.ToableType -ToableID      $_.ToableID} catch {Write-Host "Skipped or errored: $_" -ForegroundColor Yellow}}

write-host "wrapup 4/8... archiving passwords, assets, configurations as they had been in ITGlue (this can take a while)"
$DocsCsv = import-csv "$ITGLueExportPath\documents.csv"
$ArchivedPasswords = $MatchedPasswords |? {$_.itgobject.attributes.archived -eq $true}
$ArchivedConfigurations = $MatchedConfigurations |? {$_.ITGObject.attributes.archived -eq $true}    
$ArchivedAssets = $MatchedAssets |? {$_.ITGObject.attributes.archived -eq $true}
$ArchivedDocs = $DocsCsv |? {$_.archived -eq 'yes'}

write-host "wrapup 5/8... archiving items..."
$ptaresults = $ArchivedPasswords | % {if ($_.huduid -and $_.huduid -gt 0) {Set-HuduPasswordArchive -id $_.huduid -Archive $true}}
$ctaresults = $ArchivedConfigurations |% {if ($_.huduid -and $_.huduid -gt 0) {Set-HuduAssetArchive -Id $_.huduid -CompanyId $_.huduobject.company_id -Archive $true}}
$ataresults = $ArchivedAssets |% {if ($_.huduid -and $_.huduid -gt 0) {Set-HuduAssetArchive -Id $_.huduid -CompanyId $_.huduobject.company_id -Archive $true}}
$dtaresults = $ArchivedDocs |% {$i = $_; $A2D = $MatchedArticles |? {$A2D.itgid -eq $i.id}; if ($A2D.huduid -and $A2D.huduid -gt 0) {Set-HuduArticleArchive -Id $A2D.HuduId -Archive $true}} 
foreach ($obj in @(
    @{Name = "passwords";       Archived = $ptaresults ?? @() },
    @{Name = "configs";         Archived = $ctaresults ?? @() },
    @{Name = "assets";          Archived = $ataresults ?? @() },
    @{Name = "docs";            Archived = $dtaresults ?? @() })) {
    $obj.Archived | ConvertTo-Json -depth 75 | Out-File $(join-path $settings.MigrationLogs "archived-$($obj.Name).json")
}
write-host "wrapup 6/8... Setting Standalone articles with attachments to filename..."
foreach ($a in $(Get-HuduArticles | where-object {$_.content -eq "Empty Document in IT Glue Export - Please Check IT Glue" -and $_.name -ilike "*.*"})){Set-HuduArticle -id $a.id -content "Please see attached file, $($a.name)"}
if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $false} catch {}}

write-host "wrapup 7/8... Placing password folders if user-configured to do so... $($importPasswordFolders)"
if ($true -eq $importPasswordFolders){
    . .\public\Process-PasswordFolders.ps1
}
write-host "wrapup 8/8... Placing checklists / checklist templates if user-configured to do so... $($importChecklists)"
if ($true -eq $importChecklists){
    . .\public\Process-Checklists.ps1
}
foreach ($auxilliaryObj in @(@{Name = "passwordfolders"; Created = $MatchedPasswordFolders ?? @() }, @{Name = "checklists"; Created = $MatchedChecklists ?? @() })) {
    $auxilliaryObj.Created | ConvertTo-Json -depth 75 | Out-File $(join-path $settings.MigrationLogs "created-$($auxilliaryObj.Name).json")
}