function Get-FlexLayoutImportMode {
    $ImportOption = Write-TimedMessage -Message "[1] [2]" -Timeout 10 -DefaultResponse 1
    if (!($ImportOption -in @(1, 2))) {
        Write-Host "Please select 1 or 2"
        $ImportOption = Get-FlexLayoutImportMode -ImportName $ImportName
    }
		
    return $ImportOption
}