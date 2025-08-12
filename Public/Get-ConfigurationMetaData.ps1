###### Configuration Meta Data #########

# Types
$ConfigurationTypesSelect = { (Get-ITGlueConfigurationTypes -page_size 1000 -page_number $i).data }
$ITGConfigurationTypes = Import-ITGlueItems -ItemSelect $ConfigurationTypesSelect
$NewHuduConfigurationTypeList = $ITGConfigurationTypes | Group-Object type | Select name, @{n='list_item_attributes'; e={ $_.Group.attributes | select name } }

# Statuses
$ConfigurationStatusesSelect = { (Get-ITGlueConfigurationStatuses -page_size 1000 -page_number $i).data }
$ITGConfigurationStatuses = Import-ITGlueItems -ItemSelect $ConfigurationStatusesSelect
$NewHuduConfigurationStatusList = $ITGConfigurationStatuses | Group-Object type | Select name, @{n='list_item_attributes'; e={ $_.Group.attributes | select name } }


# Manufacturers
$ConfigurationManufacturersSelect = { (Get-ITGlueManufacturers -page_size 1000 -page_number $i).data }
$ITGConfigurationManufacturers = Import-ITGlueItems -ItemSelect $ConfigurationManufacturersSelect
$NewHuduConfigurationManufacturerList = $ITGConfigurationManufacturers | Group-Object type | Select name, @{n='list_item_attributes'; e={ $_.Group.attributes | select name } }


# Models
$ConfigurationModelsSelect = { (Get-ITGlueModels -page_size 1000 -page_number $i).data }
$ITGConfigurationModels = Import-ITGlueItems -ItemSelect $ConfigurationModelsSelect
$NewHuduConfigurationModelsList = $ITGConfigurationModels | Group-Object type | Select name, @{n='list_item_attributes'; e={ $_.Group.attributes | select name } }


# Operating Systems
$ConfigurationOsSelect = { (Get-ITGlueOperatingSystems -page_size 1000 -page_number $i).data } 
$ITGConfigurationOSes = Import-ITGlueItems -ItemSelect $ConfigurationOsSelect
$NewHuduConfigurationOSesList = $ITGConfigurationOSes | Group-Object type | Select name, @{n='list_item_attributes'; e={ $_.Group.attributes | select name } }


# Platforms
$ConfigurationPlatformSelect = { (Get-ITGluePlatforms -page_size 1000 -page_number $i).data }
$ITGConfigurationPlatforms = Import-ITGlueItems -ItemSelect $ConfigurationPlatformSelect
$NewHuduConfigurationPlatformList = $ITGConfigurationPlatforms | Group-Object type | Select name, @{n='list_item_attributes'; e={ $_.Group.attributes | select name } }

