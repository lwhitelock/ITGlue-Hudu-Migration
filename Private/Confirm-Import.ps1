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