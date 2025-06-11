function Get-ConfigurationsImportMode {
    $ImportOption = Write-TimedMessage -Message "[1] [2] [3]" -Timeout 10 -DefaultResponse 1
    if (!($ImportOption -in @(1, 2, 3))) {
        Write-Host "Please select 1, 2 or 3"
        $ImportOption = Get-ConfigurationsImportMode -ImportName $ImportName
    }
		
    return $ImportOption
}