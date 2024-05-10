function Import-ITGlueItems {
    Param(
        $ItemSelect
    )
    $i = 1
    $ITGImports = do {
        $itgimport = & $ItemSelect
        $i++
        $itgimport
        Write-Host "Retrieved $($itgimport.count) $MigrationName" -ForegroundColor Yellow
    }while ($itgimport.count % 1000 -eq 0 -and $itgimport.count -ne 0)
    return $ITGImports
}