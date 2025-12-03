
############################### Locations ###############################
#Check for Location Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Locations.json")) {
    Write-Host "Loading Previous Locations Migration"
    $MatchedLocations = Get-Content "$MigrationLogs\Locations.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {
    $ITGLocations = $ITGLocations |select @{n='HuduCompanyId';e={ $ITGCompaniesHashTable["$($_.attributes.'organization-id')"].huduid}},*

    $LocHuduItemFilter = { ($_.name -eq $itgimport.attributes.name -and $_.company_id -eq $itgimport.HuduCompanyId)`
            -or ($ITGPrimaryLocationNames -contains $itgimport.attributes.name -and $HuduPrimaryLocationNames -contains $_.name -and $_.company_id -eq $itgimport.HuduCompanyId)`
            -or ($itgimport.attributes.primary -eq $true -and $HuduPrimaryLocationNames -contains $_.name -and $_.company_id -eq $itgimport.HuduCompanyId) }

    $LocImportEnabled = $ImportLocations

    $LocMigrationName = "Locations"


    $LocAssetLayoutFields = @(
        @{
            label        = 'Address 1'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 1
        },
        @{
            label        = 'Address 2'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 2
        },
        @{
            label        = 'City'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 3
        },
        @{
            label        = 'Postal Code'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 4
        },
        @{
            label        = 'Region'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 5
        },
        @{
            label        = 'Country'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 6
        },
        @{
            label        = 'Phone'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 7
        },
        @{
            label        = 'Fax'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 8
        },
        @{
            label        = 'Notes'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 9
        }
    )
    if ($settings.IncludeITGlueID -and $true -eq $settings.IncludeITGlueID){
        $LocAssetLayoutFields+=@{
            label        = 'ITGlue ID'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 502}
        $LocAssetFieldsMap = { @{ 
            'address 1'   = $unmatchedImport."ITGObject".attributes."address-1"
            'address 2'   = $unmatchedImport."ITGObject".attributes."address-2"
            'city'        = $unmatchedImport."ITGObject".attributes."city"
            'postal code' = $unmatchedImport."ITGObject".attributes."postal-code"
            'region'      = $unmatchedImport."ITGObject".attributes."region-name"
            'country'     = $unmatchedImport."ITGObject".attributes."country-name"
            'phone'       = $unmatchedImport."ITGObject".attributes."phone"
            'fax'         = $unmatchedImport."ITGObject".attributes."fax"
            'notes'       = $unmatchedImport."ITGObject".attributes."notes"		
            'ITGlue ID'   = $unmatchedImport."ITGObject".id
        } }            
    } else {
        $LocAssetFieldsMap = { @{ 
            'address 1'   = $unmatchedImport."ITGObject".attributes."address-1"
            'address 2'   = $unmatchedImport."ITGObject".attributes."address-2"
            'city'        = $unmatchedImport."ITGObject".attributes."city"
            'postal code' = $unmatchedImport."ITGObject".attributes."postal-code"
            'region'      = $unmatchedImport."ITGObject".attributes."region-name"
            'country'     = $unmatchedImport."ITGObject".attributes."country-name"
            'phone'       = $unmatchedImport."ITGObject".attributes."phone"
            'fax'         = $unmatchedImport."ITGObject".attributes."fax"
            'notes'       = $unmatchedImport."ITGObject".attributes."notes"		
        } }
    }


    $LocImportSplat = @{
        AssetFieldsMap        = $LocAssetFieldsMap
        AssetLayoutFields     = $LocAssetLayoutFields
        ImportIcon            = $LocImportIcon
        ImportEnabled         = $LocImportEnabled
        HuduItemFilter        = $LocHuduItemFilter
        ImportAssetLayoutName = $LocImportAssetLayoutName
        ItemSelect            = $LocItemSelect
        MigrationName         = $LocMigrationName
        ITGImports            = $ITGLocations

    }

    #Import Locations
    $MatchedLocations = Import-Items @LocImportSplat
    $ITGLocationsHashTable = @{}
    foreach ($ITGL in $MatchedLocations) {
        $ITGLocationsHashTable[$ITGL.itgid] = $ITGL
    }
    # Save the results to resume from if needed
    $MatchedLocations | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Locations.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Locations Migrated Continue?"  -DefaultResponse "continue to Websites, please."

}
