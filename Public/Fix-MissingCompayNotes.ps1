$CompanyNotesToAdd = $ITGCompaniesFromCSV | Where-Object {$_.quick_notes -ne $null -or $_.alert -ne $null}

$UpdatedCompanies = foreach ($companyNotes in $CompanyNotesToAdd[0]) {
    $CompanyToUpdate = $MatchedCompanies | Where-Object {$_.ITGID -eq $companyNotes.id}

#Check for alerts in ITGlue on the organization
if ($ITGlueAlert = $companyNotes.alert) {
    $CompanyNotes = "<div class='callout callout-warning'>$ITGlueAlert</div>" + $companyNotes.quick_notes
} else {
    $CompanyNotes = $companyNotes.quick_notes
}

(Set-HuduCompany -id $CompanyToUpdate.huduid -Notes $companyNotes).company

}