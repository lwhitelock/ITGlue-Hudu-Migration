function Get-ConfigurationsImportMode {
    $ImportOption = Read-Host "[1] [2] [3]"
    if (!($ImportOption -in @(1, 2, 3))) {
        Write-Host "Please select 1, 2 or 3"
        $ImportOption = Get-ConfigurationsImportMode -ImportName $ImportName
    }
		
    return $ImportOption
}