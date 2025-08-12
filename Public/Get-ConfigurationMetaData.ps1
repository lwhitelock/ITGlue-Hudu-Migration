###### Configuration Meta Data #########

# Types
$ConfigurationTypesSelect = { (Get-ITGlueConfigurationTypes -page_size 1000 -page_number $i).data }
$ITGConfigurationTypes = Import-ITGlueItems -ItemSelect $ConfigurationTypesSelect

# Statuses
$ConfigurationStatusesSelect = { (Get-ITGlueConfigurationStatuses -page_size 1000 -page_number $i).data }
$ITGConfigurationStatuses = Import-ITGlueItems -ItemSelect $ConfigurationStatusesSelect

# Manufacturers
$ConfigurationManufacturersSelect = { (Get-ITGlueManufacturers -page_size 1000 -page_number $i).data }
$ITGConfigurationManufacturers = Import-ITGlueItems -ItemSelect $ConfigurationManufacturersSelect

# Models
$ConfigurationModelsSelect = { (Get-ITGlueModels -page_size 1000 -page_number $i).data }
$ITGConfigurationModels = Import-ITGlueItems -ItemSelect $ConfigurationModelsSelect

# Operating Systems
$ConfigurationOsSelect = { (Get-ITGlueOperatingSystems -page_size 1000 -page_number $i).data } 
$ITGConfigurationOSes = Import-ITGlueItems -ItemSelect $ConfigurationOsSelect

# Platforms
$ConfigurationPlatformSelect = { (Get-ITGluePlatforms -page_size 1000 -page_number $i).data }
$ITGConfigurationPlatforms = Import-ITGlueItems -ItemSelect $ConfigurationPlatformSelect
