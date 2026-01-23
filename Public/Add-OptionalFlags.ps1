
function Set-OptionalFlags {
  param(
    [hashtable]$ObjectFlagMap,
    [pscustomobject]$Object,
    [string]$ObjectType
  )
  if ($null -eq $Object -or $null -eq $object.id -or $object.id -lt 1) {
    write-warning "bad object id $($object.id)"
    return
  }

  # possible cononical names for object types (itglue-side). Generally mapped in flag map as plurals
  $mapKey = switch ($ObjectType.ToLower()) {
    'company'        { 'Companies' }
    'configuration'  { 'Configurations' }
    'location'       { 'Locations' }
    'Checklist'      { 'Checklists' }
    default          { $ObjectType }
  }

  # cononical names from itglue-side mapped to flagable_types on hudu-side. these have more open-ended naming
  $flagableType = switch ($ObjectType.ToLower()) {
    'company'        { 'Company' }
    'articles'       { 'Article' }
    'websites'       { 'Website' }
    'passwords'      { 'AssetPassword' }
    'contacts'       { 'Asset' }
    'configuration'  { 'Asset' }
    'location'       { 'Asset' }
    'checklist'      { 'Procedure' }
    'checklists'     { 'Procedure' }
    default          { 'Asset' }
  }

  $flagType = $ObjectFlagMap[$mapKey]
  if (-not $flagType) {
    Write-Warning "No FlagType configured for ObjectType='$ObjectType' (mapKey='$mapKey'). Skipping."
    return
  }

  try {
    New-HuduFlag -FlagTypeID $flagType.id -FlagableType $flagableType -Flagable_Id $Object.id
  } catch {
    Write-Error "Failed to add flag to $ObjectType '$($Object.Name)'. Error: $_"
  }
}

function Get-UserFlagSetup {

        $ObjectFlagMap = @{}
        $completedFlagSetup = $false
        while ($completedFlagSetup -ne $true){
            $flagColor = $null; $flagColor = Select-ObjectFromList -message "Select the color to use for a new flag type. First we create flag types, then we attribute flag types to the objects that you'd like. Select a Color or Enter '0' or 1-'None' to skip creating FlagTypes if you already created some in Hudu." -objects @('None', 'red', 'crimson', 'scarlet', 'rot', 'karminrot', 'scharlachrot', 'rouge', 'cramoisi', 'écarlate', 'rosso', 'cremisi', 'scarlatto', 'rojo', 'carmesí', 'escarlata', 'blue', 'navy', 'blau', 'marineblau', 'bleu', 'bleu marine', 'blu', 'blu navy', 'azul', 'azul marino', 'green', 'lime', 'grün', 'limettengrün', 'vert', 'vert citron', 'verde', 'verde lime', 'verde lima', 'yellow', 'gold', 'gelb', 'jaune', 'or', 'giallo', 'oro', 'amarillo', 'purple', 'violet', 'lila', 'violett', 'pourpre', 'viola', 'porpora', 'púrpura', 'violeta', 'orange', 'arancione', 'naranja', 'light pink', 'pink', 'baby pink', 'hellrosa', 'rosa', 'rose clair', 'rose', 'rosa chiaro', 'rosa claro', 'light blue', 'baby blue', 'sky blue', 'hellblau', 'babyblau', 'himmelblau', 'bleu clair', 'bleu ciel', 'azzurro', 'blu chiaro', 'azul claro', 'celeste', 'light green', 'mint', 'hellgrün', 'mintgrün', 'vert clair', 'menthe', 'verde chiaro', 'menta', 'verde claro', 'light purple', 'lavender', 'helllila', 'lavendel', 'violet clair', 'lavande', 'viola chiaro', 'lavanda', 'morado claro', 'light orange', 'peach', 'hellorange', 'pfirsich', 'orange clair', 'pêche', 'arancione chiaro', 'pesca', 'naranja claro', 'melocotón', 'light yellow', 'cream', 'hellgelb', 'creme', 'jaune clair', 'crème', 'giallo chiaro', 'crema', 'amarillo claro', 'white', 'weiß', 'blanc', 'bianco', 'blanco', 'grey', 'gray', 'silver', 'grau', 'silber', 'gris', 'argent', 'grigio', 'argento', 'plateado', 'lightpink', 'lightblue', 'lightgreen', 'lightpurple', 'lightorange', 'lightyellow') -allowNull $true;
            if ($null -eq $flagColor -or $flagColor -ieq "None"){
                $completedFlagSetup = $true
                break
            }
            $flagName = $null; $flagName = $(Read-Host "Enter the Name of your New Flag Type to use with color $flagColor") ?? "$flagColor Flag"
            if ([string]::IsNullOrWhiteSpace($flagName)){
                write-error "Empty flag name, try again or enter NONE at the next prompt to finish."
            } else {
                try {
                    New-HuduFlagType -Color $flagColor -Name $flagName
                } catch {
                    Write-Error "Failed to create FlagType $flagName with color $flagColor. It may already exist. Error: $_" -ForegroundColor Yellow
                }
            }
        }
        $SelectableFlagTypes = Get-HuduFlagTypes
        if ($SelectableFlagTypes.count -eq 0){
            Write-Error "No flag types found in Hudu. You can either create these in this setup or create them directly in Hudu, but you'll need flag types to exist before you can attribute flag types to objects"
            return [PSCustomObject]@{
                AllowSettingFlags = $false
                ObjectFlagMap     = @{}
                $passwordFlagCategories = $false
            }
        }
        $passwordFlagCategories = ("yes" -eq $(Select-Objectfromlist -objects @("yes","no") -message "Would you like to attribute flags to passwords per password-category" -allowNull $false -inspectObjects $false) -eq "no")
        if ($true -eq $passwordFlagCategories){
            $FlagableObjects = @("Companies","Locations","Contacts","Configurations","Assets","Articles","Websites","Checklists")
        } else {
            $FlagableObjects = @("Companies","Locations","Contacts","Configurations","Assets","Articles","Websites","Passwords","Checklists")
        }


        Write-Host "Done setting up flagtypes, Now we can attribute them to certain source objects to-be migrated."
        foreach ($flagable in $FlagableObjects){
            $selectedFlagType = $null; $selectedFlagType = Select-ObjectFromList -message "Select the Flag Type to attribute to incoming '$($flagable)' objects. Select '0' or 'None' to skip attributing this flagtype." -objects $SelectableFlagTypes -allowNull $true -inspectObjects $true;
            if ($null -eq $selectedFlagType){continue}
            $ObjectFlagMap["$flagable"] = $selectedFlagType
        }
        if ($ObjectFlagMap.Keys.count -gt 0){
            $allowSettingFlagsAndTypes = $true
        } else {
            Write-Host "No Flag Types were selected for any objects, skipping flag attribution." -ForegroundColor Yellow
            return [PSCustomObject]@{
                AllowSettingFlags = $false
                ObjectFlagMap     = $ObjectFlagMap
                passwordFlagCategories = $passwordFlagCategories
            }
        }
    $completedFlagSetup = $true

    return [PSCustomObject]@{
        AllowSettingFlags = $allowSettingFlagsAndTypes
        ObjectFlagMap     = $ObjectFlagMap
        passwordFlagCategories = $passwordFlagCategories
    }
}

