#Check for Location Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Contacts.json")) {
    Write-Host "Loading Previous Contacts Migration"
    $MatchedContacts = Get-Content "$MigrationLogs\Contacts.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {


    Write-Host "Fetching Contacts from IT Glue" -ForegroundColor Green
    $ContactsSelect = { (Get-ITGlueContacts -page_size 1000 -page_number $i -include related_items).data }
    $ITGContacts = Import-ITGlueItems -ItemSelect $ContactsSelect
    $ITGContacts = $ITGContacts |select @{n='HuduCompanyId';e={ $ITGCompaniesHashTable["$($_.attributes.'organization-id')"].huduid}},*

    #($ITGContacts.attributes | sort-object -property name, "organization-name" -Unique)


    if ($ScopedMigration) {
        $OriginalContactsCount = $($ITGContacts.count)
        Write-Host "Setting contacts to those in scope..." -foregroundcolor Yellow               
        $ITGContacts          = $ITGContacts | Where-Object { $ScopedCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "Contacts scoped... $OriginalContactsCount => $($ITGContacts.count)"
    }

    $ConHuduItemFilter = { ($_.name -eq $itgimport.attributes.name -and $_.company_id -eq $itgimport.HuduCompanyId) }

    $ConImportEnabled = $ImportContacts

    $ConMigrationName = "Contacts"

    $LocationLayout = Get-HuduAssetLayouts -name $LocImportAssetLayoutName

    $ConAssetLayoutFields = @(
        @{
            label        = 'First Name'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 1
        },
        @{
            label        = 'Last Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 2
        },
        @{
            label        = 'Title'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 3
        },
        @{
            label        = 'Contact Type'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 4
        },
        @{
            label        = 'Location'
            field_type   = 'AssetTag'
            show_in_list = 'false'
            linkable_id  = $LocationLayout.ID
            position     = 5
        },
        @{
            label        = 'Important'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 6
        },
        @{
            label        = 'Notes'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 7
        },
        @{
            label        = 'Emails'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 8
        },
        @{
            label        = 'Phones'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 9
        }
    )
    if ($settings.IncludeITGlueID -and $true -eq $settings.IncludeITGlueID){
        $ConAssetLayoutFields+=@{
            label        = 'ITGlue ID'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 502}
        $ConAssetFieldsMap = { @{ 
            'first name'   = $unmatchedImport."ITGObject".attributes."first-name"
            'last name'    = $unmatchedImport."ITGObject".attributes."last-name"
            'title'        = $unmatchedImport."ITGObject".attributes."title"
            'contact type' = $unmatchedImport."ITGObject".attributes."contact-type-name"
            'location'     = $ITGLocationsHashTable["$($unmatchedImport."ITGObject".attributes.'location-id')"] | Select-Object @{N='id';E={$_.HuduID}}, @{N='name';E={$_.Name}} | convertto-json -AsArray -Compress | out-string
            'important'    = $unmatchedImport."ITGObject".attributes."important"
            'notes'        = $unmatchedImport."ITGObject".attributes."notes"
            'emails'       = $unmatchedImport."ITGObject".attributes."contact-emails" | convertto-html -fragment | out-string
            'phones'       = $unmatchedImport."ITGObject".attributes."contact-phones"	| convertto-html -fragment | out-string
            'ITGlue ID'    = $unmatchedImport."ITGObject".id
        } } 
    } else {
        $ConAssetFieldsMap = { @{ 
            'first name'   = $unmatchedImport."ITGObject".attributes."first-name"
            'last name'    = $unmatchedImport."ITGObject".attributes."last-name"
            'title'        = $unmatchedImport."ITGObject".attributes."title"
            'contact type' = $unmatchedImport."ITGObject".attributes."contact-type-name"
            'location'     = $ITGLocationsHashTable["$($unmatchedImport."ITGObject".attributes.'location-id')"] | Select-Object @{N='id';E={$_.HuduID}}, @{N='name';E={$_.Name}} | convertto-json -AsArray -Compress | out-string
            'important'    = $unmatchedImport."ITGObject".attributes."important"
            'notes'        = $unmatchedImport."ITGObject".attributes."notes"
            'emails'       = $unmatchedImport."ITGObject".attributes."contact-emails" | convertto-html -fragment | out-string
            'phones'       = $unmatchedImport."ITGObject".attributes."contact-phones"	| convertto-html -fragment | out-string
        } }
    }

    $ConImportSplat = @{
        AssetFieldsMap        = $ConAssetFieldsMap
        AssetLayoutFields     = $ConAssetLayoutFields
        ImportIcon            = $ConImportIcon
        ImportEnabled         = $ConImportEnabled
        HuduItemFilter        = $ConHuduItemFilter
        ImportAssetLayoutName = $ConImportAssetLayoutName
        ItemSelect            = $ConItemSelect
        MigrationName         = $ConMigrationName
        ITGImports            = $ITGContacts

    }

    #Import Locations
    $MatchedContacts = Import-Items @ConImportSplat

    Write-Host "Contacts Complete"

    # Save the results to resume from if needed
    $MatchedContacts | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Contacts.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Contacts Migrated Continue?"  -DefaultResponse "continue to Flexible Asset Layouts, please."

}
