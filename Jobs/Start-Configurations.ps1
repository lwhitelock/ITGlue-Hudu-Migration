
$ConfigMigrationName = "Configurations"
$ConfigImportAssetLayoutName = "Configurations"
	
#Check for Configuration Resume
if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Configurations.json")) {
    Write-Host "Loading Previous Configurations Migration"
    $MatchedConfigurations = Get-Content "$MigrationLogs\Configurations.json" -raw | Out-String | ConvertFrom-Json -depth 100
} else {

    #Get Configurations from IT Glue
    Write-Host "Fetching Configurations from IT Glue" -ForegroundColor Green
    $ConfigurationsSelect = { (Get-ITGlueConfigurations -page_size 1000 -page_number $i -include related_items).data }
    $ITGConfigurations = Import-ITGlueItems -ItemSelect $ConfigurationsSelect
    $ITGConfigurations = $ITGConfigurations |select @{n='HuduCompanyId';e={ $ITGCompaniesHashTable["$($_.attributes.'organization-id')"].huduid}},*
    if ($ScopedMigration) {
        $OriginalConfigurationCount = $($ITGConfigurations.count)
        Write-Host "Setting configurations to those in scope..." -foregroundcolor Yellow        
        $ITGConfigurations    = $ITGConfigurations | Where-Object { $ScopedCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "configurations scoped... $OriginalConfigurationCount => $($ITGConfigurations.count)"
    }

    $ConfigAssetLayoutFields = @(
        @{
            label        = 'Hostname'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 1
        },
        @{
            label        = 'Primary IP'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 2
        },
        @{
            label        = 'MAC Address'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 3
        },
        @{
            label        = 'Default Gateway'
            field_type   = 'Text'
            show_in_list = 'true'
            position     = 4
        },
        @{
            label        = 'Serial Number'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 5
        },
        @{
            label        = 'Asset Tag'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 6
        },
        @{
            label        = 'Position'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 7
        },
        @{
            label        = 'Installed By'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 8
        },
        @{
            label        = 'Purchased By'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 9
        },
        @{
            label        = 'Notes'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 10
        },
        @{
            label        = 'Operating System Notes'
            field_type   = 'RichText'
            show_in_list = 'false'
            position     = 11
        },
        @{
            label        = 'Warranty Expires At'
            field_type   = 'Date'
            expiration   = 'true'
            show_in_list = 'false'
            position     = 12
        },
        @{
            label        = 'Installed At'
            field_type   = 'Date'
            show_in_list = 'false'
            position     = 13
        },
        @{
            label        = 'Purchased At'
            field_type   = 'Date'
            show_in_list = 'false'
            position     = 14
        },
        @{
            label        = 'Configuration Type Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 15
        },
        @{
            label        = 'Configuration Type Kind'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 16
        },
        @{
            label        = 'Configuration Status Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 17
        },
        @{
            label        = 'Manufacturer Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 18
        },
        @{
            label        = 'Model ID'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 19
        },
        @{
            label        = 'Operating System Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 20
        },
        @{
            label        = 'Location Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 21
        },
        @{
            label        = 'Model Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 22
        },
        @{
            label        = 'Contact Name'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 23
        }
    )
    $ConfigHuduItemFilter = { ($_.name -eq $itgimport.attributes.name -and $_.company_id -eq $itgimport.HuduCompanyId) }
	
    $ConfigImportEnabled = $ImportConfigurations
    if ($settings.IncludeITGlueID -and $true -eq $settings.IncludeITGlueID){
        $ConfigAssetLayoutFields+=@{
            label        = 'ITGlue ID'
            field_type   = 'Text'
            show_in_list = 'false'
            position     = 502}
        $ConfigAssetFieldsMap = { @{ 
            'hostname'                  = $unmatchedImport."ITGObject".attributes."hostname"
            'primary ip'                = $unmatchedImport."ITGObject".attributes."primary-ip"
            'mac address'               = $unmatchedImport."ITGObject".attributes."mac-address"
            'default gateway'           = $unmatchedImport."ITGObject".attributes."default-gateway"
            'serial number'             = $unmatchedImport."ITGObject".attributes."serial-number"
            'asset tag'                 = $unmatchedImport."ITGObject".attributes."asset-tag"
            'position'                  = $unmatchedImport."ITGObject".attributes."position"
            'installed by'              = $unmatchedImport."ITGObject".attributes."installed-by"
            'purchased by'              = $unmatchedImport."ITGObject".attributes."purchased-by"
            'notes'                     = $unmatchedImport."ITGObject".attributes."notes"
            'operating system notes'    = $unmatchedImport."ITGObject".attributes."operating-system-notes"
            'warranty expires at'       = $unmatchedImport."ITGObject".attributes."warranty-expires-at"
            'installed at'              = $unmatchedImport."ITGObject".attributes."installed-at"
            'purchased at'              = $unmatchedImport."ITGObject".attributes."purchased-at"
            'configuration type name'   = $unmatchedImport."ITGObject".attributes."configuration-type-name"
            'configuration type kind'   = $unmatchedImport."ITGObject".attributes."configuration-type-kind"
            'manufacturer name'  		= $unmatchedImport."ITGObject".attributes."manufacturer-name"			
            'configuration status_name' = $unmatchedImport."ITGObject".attributes."configuration-status-name"
            'operating system name'     = $unmatchedImport."ITGObject".attributes."operating-system-name"
            'location name'             = $unmatchedImport."ITGObject".attributes."location-name"
            'model name'                = $unmatchedImport."ITGObject".attributes."model-name"
            'contact name'              = $unmatchedImport."ITGObject".attributes."contact-name"	
            'ITGlue ID'                 = $unmatchedImport."ITGObject".id
        } }    
    } else {
        $ConfigAssetFieldsMap = { @{ 
            'hostname'                  = $unmatchedImport."ITGObject".attributes."hostname"
            'primary ip'                = $unmatchedImport."ITGObject".attributes."primary-ip"
            'mac address'               = $unmatchedImport."ITGObject".attributes."mac-address"
            'default gateway'           = $unmatchedImport."ITGObject".attributes."default-gateway"
            'serial number'             = $unmatchedImport."ITGObject".attributes."serial-number"
            'asset tag'                 = $unmatchedImport."ITGObject".attributes."asset-tag"
            'position'                  = $unmatchedImport."ITGObject".attributes."position"
            'installed by'              = $unmatchedImport."ITGObject".attributes."installed-by"
            'purchased by'              = $unmatchedImport."ITGObject".attributes."purchased-by"
            'notes'                     = $unmatchedImport."ITGObject".attributes."notes"
            'operating system notes'    = $unmatchedImport."ITGObject".attributes."operating-system-notes"
            'warranty expires at'       = $unmatchedImport."ITGObject".attributes."warranty-expires-at"
            'installed at'              = $unmatchedImport."ITGObject".attributes."installed-at"
            'purchased at'              = $unmatchedImport."ITGObject".attributes."purchased-at"
            'configuration type name'   = $unmatchedImport."ITGObject".attributes."configuration-type-name"
            'configuration type kind'   = $unmatchedImport."ITGObject".attributes."configuration-type-kind"
            'manufacturer name'  		= $unmatchedImport."ITGObject".attributes."manufacturer-name"			
            'configuration status_name' = $unmatchedImport."ITGObject".attributes."configuration-status-name"
            'operating system name'     = $unmatchedImport."ITGObject".attributes."operating-system-name"
            'location name'             = $unmatchedImport."ITGObject".attributes."location-name"
            'model name'                = $unmatchedImport."ITGObject".attributes."model-name"
            'contact name'              = $unmatchedImport."ITGObject".attributes."contact-name"	
        } }
    }

    # First we need to decide on if we are going to do one Asset type or many
    Write-Host "Hudu does not have the same standard configuration type as IT Glue."
    Write-Host "With the migration there are a few options of how to approach this"
    Write-Host "1) The script can create a new Hudu Asset Layout for all configurations to go into, like how IT Glue works"
    Write-Host "2) The script can create an Asset layout for each in use Configuration Type you have in IT Glue and then split up configurations into them"
    Write-Host "3) The script can prompt for each Configuration type you have, asking you for the new Hudu Asset Layout to map to, this will allow you to have a mix of 1 and 2"

    $ConfigurationOption = Get-ConfigurationsImportMode

    # All Configurations to 1 Layout
    if ($ConfigurationOption -eq 1) {
	
	

        $ConfigImportSplat = @{
            AssetFieldsMap        = $ConfigAssetFieldsMap
            AssetLayoutFields     = $ConfigAssetLayoutFields
            ImportIcon            = $ConfigImportIcon
            ImportEnabled         = $ConfigImportEnabled
            HuduItemFilter        = $ConfigHuduItemFilter
            ImportAssetLayoutName = $ConfigImportAssetLayoutName
            ItemSelect            = $ConfigItemSelect
            MigrationName         = $ConfigMigrationName
            ITGImports            = $ITGConfigurations
        }

        $MatchedConfigurations = Import-Items @ConfigImportSplat


    } elseif ($ConfigurationOption -eq 2) {
        $ITGConfigTypes = $ITGConfigurations.attributes."configuration-type-name" | Select-Object -unique
        $MatchedConfigurations = New-Object System.Collections.ArrayList
        foreach ($ConfigType in $ITGConfigTypes) {

            Write-Host "Processing $ConfigType"

            $ParsedITGConfigs = $ITGConfigurations | Where-Object { $_.attributes."configuration-type-name" -eq $ConfigType }

            $ConfigMigrationName = "$($ConfigurationPrefix)$($ConfigType)"
            $ConfigImportAssetLayoutName = "$($ConfigurationPrefix)$($ConfigType)"
	
            $ConfigImportSplat = @{
                AssetFieldsMap        = $ConfigAssetFieldsMap
                AssetLayoutFields     = $ConfigAssetLayoutFields
                ImportIcon            = $ConfigImportIcon
                ImportEnabled         = $ConfigImportEnabled
                HuduItemFilter        = $ConfigHuduItemFilter
                ImportAssetLayoutName = $ConfigImportAssetLayoutName
                ItemSelect            = $ConfigItemSelect
                MigrationName         = $ConfigMigrationName
                ITGImports            = $ParsedITGConfigs
            }
	
            $ReturnedConfigurations = Import-Items @ConfigImportSplat

            if (($ReturnedConfigurations | measure-object).count -gt 1) {
                $MatchedConfigurations.addrange($ReturnedConfigurations)
            } else {
                $MatchedConfigurations.add($ReturnedConfigurations)
            }

        }

	
	
    } elseif ($ConfigurationOption -eq 3) {
        $ITGConfigTypes = $ITGConfigurations.attributes."configuration-type-name" | Select-Object -unique
        $MatchedConfigurations = New-Object System.Collections.ArrayList

        foreach ($ConfigType in $ITGConfigTypes) {
            Write-Host ""
            Write-Host "Processing $ConfigType"
            Write-Host "Please provide the Asset Layout name for $ConfigType in Hudu." -foregroundcolor green
            $ConfigImportAssetLayoutName = $(Write-TimedMessage -Timeout 12 -Message "Please enter layout name" -DefaultResponse $ConfigType)
		

            $ParsedITGConfigs = $ITGConfigurations | Where-Object { $_.attributes."configuration-type-name" -eq $ConfigType }

            $ConfigMigrationName = $ConfigImportAssetLayoutName
			
            $ConfigImportSplat = @{
                AssetFieldsMap        = $ConfigAssetFieldsMap
                AssetLayoutFields     = $ConfigAssetLayoutFields
                ImportIcon            = $ConfigImportIcon
                ImportEnabled         = $ConfigImportEnabled
                HuduItemFilter        = $ConfigHuduItemFilter
                ImportAssetLayoutName = $ConfigImportAssetLayoutName
                ItemSelect            = $ConfigItemSelect
                MigrationName         = $ConfigMigrationName
                ITGImports            = $ParsedITGConfigs
            }
	
            $ReturnedConfigurations = Import-Items @ConfigImportSplat
            if (($ReturnedConfigurations | measure-object).count -gt 1) {
                $MatchedConfigurations.addrange($ReturnedConfigurations)
            } else {
                $MatchedConfigurations.add($ReturnedConfigurations)
            }
        }



    } else {
        Write-Error "This should never have happened some how you selected something other than 1, 2 or 3 :/"
        exit 1
    }

    # Save the results to resume from if needed
    $MatchedConfigurations | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Configurations.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Configurations Migrated Continue?"  -DefaultResponse "continue to Contacts, please."

}
