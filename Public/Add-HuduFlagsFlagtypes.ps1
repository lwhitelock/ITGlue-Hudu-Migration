if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}

$TaggingTargets = @{
    "Company"        = $MatchedCompanies.HuduCompanyObject | Where-Object { $_.archived -ne $true }
    "Articles"       = $MatchedArticles.HuduObject         | Where-Object { $_.archived -ne $true }
    "Contacts"       = $MatchedContacts.HuduObject         | Where-Object { $_.archived -ne $true }
    "Configurations" = $MatchedConfigurations.HuduObject   | Where-Object { $_.archived -ne $true }
    "Locations"      = $MatchedLocations.HuduObject        | Where-Object { $_.archived -ne $true }
    "Websites"       = $MatchedWebsites.HuduObject         | Where-Object { $_.archived -ne $true }
    "Checklists"     = $MatchedChecklists.HuduProcedure    | Where-Object { $_.HuduProcedureTasks.count -gt 0 }
}

if ($true -eq $flagPasswordsByType){
    write-host "Flagging passwords by category name"
    $passwordFlagMap = @{}

    $passwordFlagCategories = $matchedpasswords.ITGObject.attributes.'password-category-name' | Select-Object -Unique | Sort-Object
    foreach ($category in $passwordFlagCategories) {
        if (-not [string]::IsNullOrWhiteSpace($category)) {
            $passwordColor = Get-Random -InputObject @('red', 'crimson', 'scarlet', 'rot', 'karminrot', 'scharlachrot', 'rouge', 'cramoisi', 'écarlate', 'rosso', 'cremisi', 'scarlatto', 'rojo', 'carmesí', 'escarlata', 'blue', 'navy', 'blau', 'marineblau', 'bleu', 'bleu marine', 'blu', 'blu navy', 'azul', 'azul marino', 'green', 'lime', 'grün', 'limettengrün', 'vert', 'vert citron', 'verde', 'verde lime', 'verde lima', 'yellow', 'gold', 'gelb', 'jaune', 'or', 'giallo', 'oro', 'amarillo', 'purple', 'violet', 'lila', 'violett', 'pourpre', 'viola', 'porpora', 'púrpura', 'violeta', 'orange', 'arancione', 'naranja', 'light pink', 'pink', 'baby pink', 'hellrosa', 'rosa', 'rose clair', 'rose', 'rosa chiaro', 'rosa claro', 'light blue', 'baby blue', 'sky blue', 'hellblau', 'babyblau', 'himmelblau', 'bleu clair', 'bleu ciel', 'azzurro', 'blu chiaro', 'azul claro', 'celeste', 'light green', 'mint', 'hellgrün', 'mintgrün', 'vert clair', 'menthe', 'verde chiaro', 'menta', 'verde claro', 'light purple', 'lavender', 'helllila', 'lavendel', 'violet clair', 'lavande', 'viola chiaro', 'lavanda', 'morado claro', 'light orange', 'peach', 'hellorange', 'pfirsich', 'orange clair', 'pêche', 'arancione chiaro', 'pesca', 'naranja claro', 'melocotón', 'light yellow', 'cream', 'hellgelb', 'creme', 'jaune clair', 'crème', 'giallo chiaro', 'crema', 'amarillo claro', 'white', 'weiß', 'blanc', 'bianco', 'blanco', 'grey', 'gray', 'silver', 'grau', 'silber', 'gris', 'argent', 'grigio', 'argento', 'plateado', 'lightpink', 'lightblue', 'lightgreen', 'lightpurple', 'lightorange', 'lightyellow')
            if ($passwordFlagMap.ContainsKey($category)) {
                write-host "Flag type for category $($category) already exists, skipping creation"
            } else {
                $passwordFlagMap[$category] = New-HuduFlagType -name "Password Category: $category" -color $passwordColor
            }
            $matchedpasswords | Where-Object { $_.ITGObject.attributes.'password-category-name' -ieq $category -and $_.huduID -and $_.huduID -gt 0 } | ForEach-Object {
                write-host "Setting password flag for $($category) with color $($passwordColor) on password in hudu with ID $($_.huduID)"
                New-HuduFlag -FlagTypeId $passwordFlagMap[$category].id -Flagable_Type "Password" -flagable_id $_.huduID
            }
        }
    }
} else {
    write-host "Flagging passwords to singlular import tag"
    $TaggingTargets["Passwords"]= $MatchedPasswords.HuduObject        | Where-Object { $_.archived -ne $true }
}

foreach ($objectType in $TaggingTargets.GetEnumerator()) {
    $key   = $objectType.Key
    $items = @($objectType.Value)

    if ($ObjectFlagMap -and $ObjectFlagMap.$key -and $null -ne $ObjectFlagMap.$key) {
        Write-Host "Setting optional flags for $key ($($items.Count)) objects per user configuration"
        $items | ForEach-Object {
            Set-OptionalFlags -ObjectFlagMap $ObjectFlagMap -Object $_ -ObjectType $key
        }
    } else {
        Write-Host "No optional flags configured for $key, skipping"
    }
}
if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $false} catch {}}
