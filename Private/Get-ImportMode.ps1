function Get-ImportMode {
    param(
        [string]$ImportName
    )
    Write-Host "Importing $ImportName"
    $ImportOption = $(Write-TimedMessage -Timout 8 -DefaultResponse "A" -Message "[A] Import All unmapped $ImportName. [N] Import None of the unmapped $ImportName. [S] Select for each individual $ImportName (A/N/S)")
    if (!($ImportOption -in @("A", "N", "S"))) {
        Write-Host "Please select A, N or S"
        $ImportOption = Get-ImportMode -ImportName $ImportName
    }
		
    return $ImportOption
}