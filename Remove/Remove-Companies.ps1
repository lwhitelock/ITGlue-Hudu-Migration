$Companies = Get-HuduCompanies

foreach ($Company in $Companies) {
    $CompanyId = $Company.id
    $CompanyName = $Company.name

    # Remove the Company
    Remove-HuduCompany -Id $CompanyId -Confirm:$false

    # Log the removal
    Write-Host "Removed Company: $CompanyName (ID: $CompanyId)"
}