## Temporary Functions until HuduAPI is Updated, will be removed

function New-HuduList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ListObject
    )

    $response = Invoke-WebRequest -Method POST -Uri "$HuduBaseDomain/api/v1/lists" -Headers @{'x-api-key' = $HuduAPIKey} -Body ($ListObject |ConvertTo-Json -Depth 10 -Compress) -ContentType "application/json; charset=utf-8"
    return $response
}

##
########################################
###### Configuration Meta Data #########
# Types
$ConfigurationTypesSelect = { (Get-ITGlueConfigurationTypes -page_size 1000 -page_number $i).data }
$ITGConfigurationTypes = Import-ITGlueItems -ItemSelect $ConfigurationTypesSelect
$NewHuduConfigurationTypeList = [pscustomobject]@{list = $ITGConfigurationTypes | Group-Object type | Select @{n='name';e={$_.name}}, @{n='list_items_attributes'; e={ $_.Group.attributes | Group-Object -Property name | select @{n='name'; e={ $_.name}} } }}
$HuduListConfigurationTypes = New-HuduList $NewHuduConfigurationTypeList

# Statuses
$ConfigurationStatusesSelect = { (Get-ITGlueConfigurationStatuses -page_size 1000 -page_number $i).data }
$ITGConfigurationStatuses = Import-ITGlueItems -ItemSelect $ConfigurationStatusesSelect
$NewHuduConfigurationStatusList = [pscustomobject]@{list = $ITGConfigurationStatuses | Group-Object type | Select @{n='name';e={$_.name}}, @{n='list_items_attributes'; e={ $_.Group.attributes | Group-Object -Property Name | select @{n='name'; e={$_.name}} } }}
$HuduListConfigurationStatuses = New-HuduList $NewHuduConfigurationStatusList

# Manufacturers
$ConfigurationManufacturersSelect = { (Get-ITGlueManufacturers -page_size 1000 -page_number $i).data }
$ITGConfigurationManufacturers = Import-ITGlueItems -ItemSelect $ConfigurationManufacturersSelect
$NewHuduConfigurationManufacturerList = [pscustomobject]@{list = $ITGConfigurationManufacturers | Group-Object type | Select @{n='name';e={$_.name}}, @{n='list_items_attributes'; e={ $_.Group.attributes |Group-Object -Property Name | select @{n='name'; e={$_.name}} } }}
$HuduListConfigurationManufacturerList = New-HuduList $NewHuduConfigurationManufacturerList

# Models
$ConfigurationModelsSelect = { (Get-ITGlueModels -page_size 1000 -page_number $i).data }
$ITGConfigurationModels = Import-ITGlueItems -ItemSelect $ConfigurationModelsSelect
$NewHuduConfigurationModelsList = [pscustomobject]@{list = $ITGConfigurationModels | Group-Object type | Select @{n='name';e={$_.name}}, @{n='list_items_attributes'; e={ $_.Group.attributes |Group-Object -Property Name | select @{n='name'; e={$_.name}} } }}
$HuduListConfigurationModelList = New-HuduList $NewHuduConfigurationModelsList

# Operating Systems
$ConfigurationOsSelect = { (Get-ITGlueOperatingSystems -page_size 1000 -page_number $i).data } 
$ITGConfigurationOSes = Import-ITGlueItems -ItemSelect $ConfigurationOsSelect
$NewHuduConfigurationOSesList = [pscustomobject]@{list = $ITGConfigurationOSes | Group-Object type | Select @{n='name';e={$_.name}}, @{n='list_items_attributes'; e={ $_.Group.attributes |Group-Object -Property Name | select @{n='name'; e={$_.name}} } }}
$HuduListConfigurationOsList = New-HuduList $NewHuduConfigurationOSesList

# Platforms
$ConfigurationPlatformSelect = { (Get-ITGluePlatforms -page_size 1000 -page_number $i).data }
$ITGConfigurationPlatforms = Import-ITGlueItems -ItemSelect $ConfigurationPlatformSelect
$NewHuduConfigurationPlatformList = [pscustomobject]@{list = $ITGConfigurationPlatforms | Group-Object type | Select @{n='name';e={$_.name}}, @{n='list_items_attributes'; e={ $_.Group.attributes |Group-Object -Property Name | select @{n='name'; e={$_.name}} } }}
$HuduListConfigurationPlatformList = New-HuduList $NewHuduConfigurationPlatformList
