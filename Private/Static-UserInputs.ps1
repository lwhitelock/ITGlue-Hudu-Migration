function Get-FlexLayoutImportMode {
    $ImportOption = Write-TimedMessage -Message "[1] [2]" -Timeout 10 -DefaultResponse 1
    if (!($ImportOption -in @(1, 2))) {
        Write-Host "Please select 1 or 2"
        $ImportOption = Get-FlexLayoutImportMode -ImportName $ImportName
    }
		
    return $ImportOption
}
function Get-ConfigurationsImportMode {
    $ImportOption = Write-TimedMessage -Message "[1] [2] [3]" -Timeout 10 -DefaultResponse $(if ($true -eq $settings.SplitConfigurations) {2} else {1})
    if (!($ImportOption -in @(1, 2, 3))) {
        Write-Host "Please select 1, 2 or 3"
        $ImportOption = Get-ConfigurationsImportMode -ImportName $ImportName
    }
		
    return $ImportOption
}
function Confirm-Import {
    param(
        [string]$ImportObjectName,
        [PSCustomObject]$ImportObject,
        [String]$ImportSetting
    )
    if ($ImportSetting -eq "S") {
        $ImportConfirm = Read-Host "Would you like to migrate: $ImportObjectName Y/n"
        if ($ImportConfirm -ne "Y" -or $ImportConfirm -ne "y") {
            Write-Host "$ImportObjectName has been skipped"
            $ImportObject.imported = "Not-Migrated"
            continue
        }	
    }
}