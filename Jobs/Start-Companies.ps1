#Check for Company Resume
$HuduCompanies = Get-HuduCompanies

if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Companies.json")) {
    Write-Host "Loading Previous Companies Migration"
    $MatchedCompanies = Get-Content "$MigrationLogs\Companies.json" -raw | Out-String | ConvertFrom-Json
} else {

    #Import Companies
    Write-Host "Fetching Companies from IT Glue" -ForegroundColor Green
    $CompanySelect = { (Get-ITGlueOrganizations -page_size 1000 -page_number $i).data }
    $ITGCompanies = Import-ITGlueItems -ItemSelect $CompanySelect
    $ITGCompaniesFromCSV = Import-CSV (Join-Path -Path $ITGlueExportPath -ChildPath "organizations.csv")
    Write-Host "$($ITGCompanies.count) ITG Glue Companies Found" 

    if ($ScopedMigration) {
        $OriginalCompanyCount = $($ITGcompanies.count)
        Write-Host "Setting companies to those in scope..." -foregroundcolor Yellow 
        if ($null -ne $Prescoped) {
            $ITGCompanies = Set-PredefinedScope -AllITGCompanies $ITGCompanies -Prescoped $Prescoped -InternalCompany $InternalCompany
        } else {
            $ITGCompanies = Set-MigrationScope -AllITGCompanies $ITGCompanies -InternalCompany $InternalCompany
        }
        $ScopedCompanyIds = $ITGCompanies.id
        Write-Host "Companies scoped... $OriginalCompanyCount => $($Itgcompanies.count)"
    }
    $uniqueOrgTypes = $($ITGCompanies.attributes.'organization-type-name' | Select-Object -unique)
    if ($true -eq $MergedOrganizationTypes){
        $MergedOrganizationSettings.Types+=$(select-objectfromlist -objects $uniqueOrgTypes -message "Select a type to include in type-scoping (from ITGlue). These company types will be attributed to a single company.")
        $MergedOrganizationSettings.TargetCompany = $(Get-HuduCompanies -id $(read-host "To which company will you be scoping $($MergedOrganizationSettings.types) to? [enter company id]"))
        Write-Host "$($($MergedOrganizationSettings.Types | ForEach-Object { $_ }) -join ', ') org types in ITGlue will be attributed to $($MergedOrganizationSettings.TargetCompany.name) in Hudu."
        if ($null -ne $MergedOrganizationSettings.TargetCompany){
            foreach ($kind in $uniqueOrgTypes){
                if ($MergedOrganizationSettings.Types -contains $kind){
                    Write-Host "$($($ITGCompanies | where-object {"$($_.attributes.'organization-type-name')" -eq $kind}).count) of $kind will be migrated to $($MergedOrganizationSettings.TargetCompany.name)" -ForegroundColor Yellow 
                } else {
                    Write-Host "$($($ITGCompanies | where-object {"$($_.attributes.'organization-type-name')" -eq $kind}).count) of $kind will be migrated in the typical fashion" -ForegroundColor Green
                }
            }
    }}
    if ($MergedOrganizationSettings.Types.Count -gt 0 -and -not $MergedOrganizationSettings.TargetCompany){
        Write-Host "Youve designated $($MergedOrganizationSettings.Types.Count) company types to be merged into hudu, but don't have a valid company. Verify that a hudu company exists with the ID that you elected to merge into"
        exit 1
    }
    $ITGCompaniesHashTable = @{}


    $nameTracker = @{}
    $MatchedCompanies = foreach ($itgcompany in $ITGCompanies) {
        $originalName = $itgcompany.attributes.name

        # Create a unique name if it's already been seen
        if ($nameTracker.ContainsKey($originalName)) {
            $nameTracker[$originalName]++
            $uniqueName = "$originalName-$($nameTracker[$originalName])"
        } else {
            $nameTracker[$originalName] = 0
            $uniqueName = $originalName
        }

        $HuduCompany = $HuduCompanies | where-object { $_.name -eq $itgcompany.attributes.name }

        if ($MergedOrganizationSettings.Types -contains "$($itgcompany.attributes.'organization-type-name')"){
            $HuduCompany = $MergedOrganizationSettings.TargetCompany
        }

        $intCompany = $InternalCompany -eq $originalName

        if ($HuduCompany) {
            [PSCustomObject]@{
                "CompanyName"       = $uniqueName
                "ITGID"             = $itgcompany.id
                "HuduID"            = $HuduCompany.id
                "Matched"           = $true
                "InternalCompany"   = $intCompany
                "HuduCompanyObject" = $HuduCompany
                "ITGCompanyObject"  = $itgcompany
                "Imported"          = "Pre-Existing"
            }
        } else {
            [PSCustomObject]@{
                "CompanyName"       = $uniqueName
                "ITGID"             = $itgcompany.id
                "HuduID"            = ""
                "Matched"           = $false
                "InternalCompany"   = $intCompany
                "HuduCompanyObject" = ""
                "ITGCompanyObject"  = $itgcompany
                "Imported"          = ""
            }
        }
    }
    foreach ($ITGC in $MatchedCompanies) {
        $ITGCompaniesHashTable[$ITGC.itgid] = $ITGC
    }
    # Check if the internal company was found and that there was only 1 of them
    $PrimaryCompany = $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.InternalCompany -eq $true } | Select-Object CompanyName

    if (($PrimaryCompany | measure-object).count -ne 1) {
        Write-Host "A single Internal Company was not found please run the script again and check the company name entered exactly matches what is in ITGlue" -foregroundcolor red
        exit 1
    }

    # Lets confirm it is the correct one
    Write-Host ""
    Write-Host "Your Internal Company has been matched to: $(($MatchedCompanies | Sort-Object CompanyName | Where-Object {$_.InternalCompany -eq $true} | Select-Object CompanyName).companyname) in IT Glue"
    Write-Host "The documents under this customer will be migrated to the Global KB in Hudu"
    Write-Host ""
    Write-TimedMessage -Message "Internal Company Correct? Press Return to continue or CTRL+C to quit if this is not correct" -Timeout 12 -DefaultResponse "Assuming found match on '$(($MatchedCompanies | Sort-Object CompanyName | Where-Object {$_.InternalCompany -eq $true} | Select-Object CompanyName).companyname)' is correct."

    Write-Host "Matched Companies (Already exist so will not be migrated)"
    $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.Matched -eq $true } | Select-Object CompanyName | Format-Table

    Write-Host "Unmatched Companies"
    $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.Matched -eq $false } | Select-Object CompanyName | Format-Table



    #Import Locations
    Write-Host "Fetching Locations from IT Glue" -ForegroundColor Green
    $LocationsSelect = { (Get-ITGlueLocations -page_size 1000 -page_number $i -include related_items).data }
    $ITGLocations = Import-ITGlueItems -ItemSelect $LocationsSelect
    if ($ScopedMigration) {
        $OriginalLocationsCount = $($ITGLocations.count)
        Write-Host "Setting locations to those in scope..." -foregroundcolor Yellow
        $ITGLocations         = $ITGLocations | Where-Object { $ScopedCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "locations scoped... $OriginalLocationsCount => $($ITGLocations.count)"
    }

    # Import Companies
    $UnmappedCompanyCount = ($MatchedCompanies | Where-Object { $_.Matched -eq $false } | measure-object).count
    if ($ImportCompanies -eq $true -and $UnmappedCompanyCount -gt 0) {
	
        $importCOption = Get-ImportMode -ImportName "Companies"
	
        if (($importCOption -eq "A") -or ($importCOption -eq "S") ) {		
            foreach ($unmatchedcompany in ($MatchedCompanies | Where-Object { $_.Matched -eq $false })) {
                $unmatchedcompany.ITGCompanyObject.attributes.'quick-notes' = ($ITGCompaniesFromCSV | Where-Object {$_.id -eq $unmatchedcompany.ITGID}).quick_notes
                $unmatchedcompany.ITGCompanyObject.attributes.alert = ($ITGCompaniesFromCSV | Where-Object {$_.id -eq $unmatchedcompany.ITGID}).alert
                Confirm-Import -ImportObjectName $($unmatchedcompany.CompanyName) -ImportObject $unmatchedcompany -ImportSetting $importCOption
						
                Write-Host "Starting $($unmatchedcompany.CompanyName)"
                $PrimaryLocation = $ITGLocations | Where-Object { $unmatchedcompany.ITGID -eq $_.attributes."organization-id" -and $_.attributes.primary -eq $true }
                
                #Check for alerts in ITGlue on the organization
                if ($ITGlueAlert = $unmatchedcompany.ITGCompanyObject.attributes.alert) {
                    $CompanyNotes = "<div class='callout callout-warning'>$ITGlueAlert</div>" + $unmatchedcompany.ITGCompanyObject.attributes."quick-notes"
                } else {
                    $CompanyNotes = $unmatchedcompany.ITGCompanyObject.attributes."quick-notes"
                }

                if ($PrimaryLocation -and $PrimaryLocation.count -eq 1) {
                    $CompanySplat = @{
                        "name"           = $($unmatchedcompany.CompanyName)
                        "nickname"       = $unmatchedcompany.ITGCompanyObject.attributes."short-name"
                        "address_line_1" = $PrimaryLocation.attributes."address-1"
                        "address_line_2" = $PrimaryLocation.attributes."address-2"
                        "city"           = $PrimaryLocation.attributes.city
                        "state"          = $PrimaryLocation.attributes."region-name"
                        "zip"            = $PrimaryLocation.attributes."postal-code"
                        "country_name"   = $PrimaryLocation.attributes."country-name"
                        "phone_number"   = $PrimaryLocation.attributes.phone
                        "fax_number"     = $PrimaryLocation.attributes.fax
                        "notes"          = $CompanyNotes
                        "CompanyType"    = $unmatchedcompany.ITGCompanyObject.attributes.'organization-type-name'
                    }
                    $HuduNewCompany = (New-HuduCompany @CompanySplat).company
                    $CompaniesMigrated = $CompaniesMigrated + 1
                } else {
                    Write-Host "No Location Found, creating company without address details"
                    $HuduNewCompany = (New-HuduCompany -name $($unmatchedcompany.CompanyName) -nickname $unmatchedcompany.ITGCompanyObject.attributes."short-name" -notes $CompanyNotes -CompanyType $unmatchedcompany.attributes.'organization-type-name').company
                    $CompaniesMigrated = $CompaniesMigrated + 1
                }
			
                $unmatchedcompany.matched = $true
                $unmatchedcompany.HuduID = $HuduNewCompany.id
                $unmatchedcompany.HuduCompanyObject = $HuduNewCompany
                $unmatchedcompany.Imported = "Created-By-Script"
			
                Write-host "$($unmatchedcompany.CompanyName) Has been created in Hudu"
                Write-Host ""
            }
		
        }
		

    } else {
        if ($UnmappedCompanyCount -eq 0) {
            Write-Host "All Companies matched, no migration required" -foregroundcolor green
        } else {
            Write-Host "Warning Import Companies is set to disabled so the above unmatched companies will not have data migrated" -foregroundcolor red
            Write-TimedMessage -Message "Press any key to continue or CTRL+C to quit" -DefaultResponse "continue and wrap-up companies, please." -Timeout 6
        }
    }

    # Save the results to resume from if needed
    $MatchedCompanies | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Companies.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Companies Migrated Continue?"  -DefaultResponse "continue to Locations, please."


}
$CompaniesToMigrate = $MatchedCompanies | Sort-Object CompanyName | Where-Object { $_.Matched -eq $true }
$HuduCompanies = Get-HuduCompanies
