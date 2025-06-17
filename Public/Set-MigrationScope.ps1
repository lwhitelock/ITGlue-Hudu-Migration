function Set-MigrationScope {
    param(
        [Parameter(Mandatory)]
        [array]$AllITGCompanies,

        [Parameter(Mandatory)]
        [string]$InternalCompany
    )

    Write-Host "Scoped Migration Mode. Select companies to migrate from IT Glue."

    $ScopedForCompanies = [System.Collections.ArrayList]@()
    while ($true) {
        $selection = Select-ObjectFromList -allowNull $true `
            -message "Select a number corresponding to a company to add to migration list. Press Enter to finish." `
            -objects $AllITGCompanies

        if ($null -eq $selection) { break }

        [void]$ScopedForCompanies.Add($selection)
    }

    if ($ScopedForCompanies.Count -eq 0) {
        Write-Error "No companies selected for scoped migration. Exiting."
        exit 1
    }

    # Deduplicate based on ID
    $ScopedForCompanies = $ScopedForCompanies | Sort-Object { $_.id } -Unique

    $companyNames = $ScopedForCompanies | ForEach-Object { $_.attributes.name }
    $confirmationMessage = "You've elected to migrate these companies:`n$($companyNames -join ', ')`nContinue?"
    $userChoice = Select-ObjectFromList -objects @("yes", "no") -message $confirmationMessage

    if ($userChoice -eq "no") {
        Write-Host "Migration cancelled by user."
        exit 1
    }

    Write-Host "Limiting migration to selected companies..."

    # Return filtered list (with internal company added if not already present)
    $ScopedIds = $ScopedForCompanies.id
    $ScopedList = $AllITGCompanies | Where-Object {
        $ScopedIds -contains $_.id -or $_.attributes.name -eq $InternalCompany
    } | Sort-Object id -Unique

    return $ScopedList
}

function Filter-ScopedAssets {
    param (
        [array]$Layouts,
        [array]$ScopedCompanyIds
    )

    foreach ($Layout in $Layouts) {
        $Layout.ITGAssets = $Layout.ITGAssets | Where-Object {
            $ScopedCompanyIds -contains $_.attributes.'organization-id'
        }
    }

    return $Layouts
}
