param(
    [switch]$Direct
)
if ($Direct) {
    # General Settings Load
    . $PSScriptRoot\..\Initialize-Module.ps1 -InitType 'Lite'
    
    # Add Replace URL functions
    . $PSScriptRoot\..\Private\ConvertTo-HuduURL.ps1
}

Write-Host "Checking for Matched Variables"

 if (!$MatchedCompanies) {$MatchedCompanies = Get-Content "$MigrationLogs\Companies.json" -raw | Out-String | ConvertFrom-Json}
 if (!$MatchedArticleBase) {$MatchedArticleBase = Get-Content "$MigrationLogs\ArticleBase.json" -raw | Out-String | ConvertFrom-Json}
 if (!$MatchedPasswords) {$MatchedPasswords = Get-Content "$MigrationLogs\Passwords.json" -raw | Out-String | ConvertFrom-Json}
 if (!$MatchedConfigurations) {$MatchedConfigurations = Get-Content "$MigrationLogs\Configurations.json" -raw | Out-String | ConvertFrom-Json}
 if (!$MatchedAssets) {$MatchedAssets = Get-Content "$MigrationLogs\Assets.json" -raw | Out-String | ConvertFrom-Json}


Write-Host "Loading Organizations from CSV"
$ITGCompaniesFromCSV = Import-CSV (Join-Path -Path $ITGlueExportPath -ChildPath "organizations.csv")

# Filter for companies that have some kind of note or null sent
$CompanyNotesToAdd = $ITGCompaniesFromCSV | Where-Object {$_.quick_notes -ne '' -or $_.alert -ne ''}

Write-Host "Found $($CompanyNotesToAdd.count) Companies to update."
Pause
$UpdatedCompanies = foreach ($companyNotes in $CompanyNotesToAdd) {
    $CompanyToUpdate = $MatchedCompanies | Where-Object {$_.ITGID -eq $companyNotes.id}
    
    #Check for alerts in ITGlue on the organization
    if ($ITGlueAlert = $companyNotes.alert) {
        $CompanyNotes = "<div class='callout callout-warning'>$ITGlueAlert</div>" + $companyNotes.quick_notes
    } 
    else {
        $CompanyNotes = $companyNotes.quick_notes
    }
    Write-Host "Updating Company $($companyToUpdate.CompanyName) with Quick Notes and Alerts from CSV" -ForegroundColor Blue
    (Set-HuduCompany -id $CompanyToUpdate.huduid -Notes $companyNotes).company
}

Write-Host "Updated $($UpdatedCompanies.count) Companies total. Starting URL rewrite from ITGlue to Hudu"
# Rewrite URLs
$companyNotesUpdated = @()
foreach ($companyFound in $UpdatedCompanies) {
    $NewContent = Update-StringWithCaptureGroups -inputString $companyFound.notes -pattern $RichRegexPatternToMatchSansAssets -type "rich"
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RichRegexPatternToMatchWithAssets -type "rich"
    if ($NewContent) {
        Write-Host "Updating Company $($companyFound.name) with updated notes" -ForegroundColor 'Green'
        $companyNotesUpdated = $companyNotesUpdated + @{"original_company" = $companyFound; "updated_company" = (Set-HuduCompany -id $companyFound.id -Notes $NewContent).company}
    }

}
$companyNotesUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedCompaniesURL.json"