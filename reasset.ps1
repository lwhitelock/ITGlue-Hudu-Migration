        
    if (-not $MatchedCompanies) {$MatchedCompanies = (Get-Content -path "$MigrationLogs\Companies.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedLocations) {$MatchedLocations = (Get-Content -path "$MigrationLogs\Locations.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedContacts) {$MatchedContacts = (Get-Content -path "$MigrationLogs\Contacts.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedCoonfigurations) {$MatchedCoonfigurations = (Get-Content -path "$MigrationLogs\Configurations.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedAssetLayouts) {$MatchedAssetLayouts = (Get-Content -path "$MigrationLogs\AssetLayouts.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedAssetLayoutsFields) {$MatchedAssetLayoutsFields = (Get-Content -path "$MigrationLogs\AssetLayoutsFields.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedAssets) {$MatchedAssets = (Get-Content -path "$MigrationLogs\Assets.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedPasswords) {$MatchedPasswords = (Get-Content -path "$MigrationLogs\Passwords.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedAssetPasswords) {$MatchedAssetPasswords = (Get-Content -path "$MigrationLogs\AssetPasswords.json" | ConvertFrom-json -depth 100) }
    if (-not $MatchedArticles) {$MatchedArticles = (Get-Content -path "$MigrationLogs\Articles.json" | ConvertFrom-json -depth 100) }
    if (-not $ManualActions) {$ManualActions = (Get-Content -path "$MigrationLogs\ManualActions.json" | ConvertFrom-json -depth 100) }
    if (-not $RelationsToCreate) {$RelationsToCreate = (Get-Content -path "$MigrationLogs\RelationsToCreate.json" | ConvertFrom-json -depth 100) }


        
        #We now need to loop through all Assets again updating the assets to their final version
        foreach ($UpdateAsset in $MatchedAssets | where-object {$_.huduobject.asset_layout_id -eq 19}) {
            $assetcheck = $null
            $assetcheck = get-huduassets -id $updateAsset.HuduObject.id
            $assetcheck = $assetcheck.asset ?? $assetcheck
            if ($null -eq $assetcheck -or -not $assetcheck){
                write-host "skipping $($UpdateAsset.name) bc not exists? $([bool]$($null -ne $assetcheck))"
                $assetcheck | format-table -force
                continue                
            } elseif ($assetcheck.archived -eq $true){
                write-host "(not) skipping, is archived $($assetcheck.archived)"
                # continue
            } else {
                Write-Host "Populating $($UpdateAsset.Name)"
            }


		
            $AssetFields = @{ 
                'imported_from_itglue' = Get-Date -Format "o"
            }

            $traits = $UpdateAsset.ITGObject.attributes.traits
            $traits.PSObject.Properties | ForEach-Object {
                # Find the corresponding field we are working on
                $ITGParsed = $_.name
                $ITGValues = $_.value
                $field = $MatchedAssetLayoutsFields | Where-Object { $_.IGLayoutID -eq $UpdateAsset.ITGObject.attributes.'flexible-asset-type-id' -and $_.ITGParsedName -eq $ITGParsed }
                if ($field) {
                    $supported = $true
                    if ($field.FieldType -eq "Date") {
                        $raw = ($ITGValues.values ?? $ITGValues) -as [string]
                        $ReturnData = Get-CoercedDate -InputDate $raw -Cutoff '1000-01-01' -OutputFormat 'MM/DD/YYYY'
                        if (-not $ReturnData) {
                            if ($field.HuduLayoutField.required) {
                                $ReturnData = (Get-Date).ToString('MM/dd/yyyy', [CultureInfo]::InvariantCulture)
                            } else {
                                continue
                            }
                        }
                        $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))
                    } elseif ($field.FieldType -eq "Tag") {
                        switch ($field.FieldSubType) {
                            "AccountsUsers" { Write-Host "Tags to Account Users are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Checklists" { Write-Host "Tags to Checklists are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "ChecklistTemplates" { Write-Host "Tags to Checklists Templates are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Contacts" {
                                $ContactsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $($MatchedContacts | Where-Object { $_.ITGID -eq $IDMatch.id } | Select-Object @{N = 'id'; E = { $_.HuduID } }, @{N = 'name'; E = { $_.Name } })
                                }
                                $ReturnData = $ContactsLinked | convertto-json -compress -AsArray | Out-String
                                $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))
                            }
                            "Configurations" {
                                $ConfigsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $($MatchedConfigurations | Where-Object { $_.ITGID -eq $IDMatch.id } | Select-Object @{N = 'id'; E = { $_.HuduID } }, @{N = 'name'; E = { $_.Name } })
                                }
                                $ReturnData = $ConfigsLinked | convertto-json -compress -AsArray | Out-String
                                $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))
											
                            }
                            "Documents" { $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) { @{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'Article'; itg_to_id = $IDMatch.id}} ;Write-Host "Tags to Articles $($field.FieldName) in $($UpdateAsset.Name) has been recorded for later."; $supported = $true }
                            "Domains" { 
                                $DomainsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $MatchedWebsites | Where-Object { $_.ITGID -eq $IDMatch.id }
                                } 
                                $DomainsLinked | ForEach-Object {
                                     if ($WebsiteRelation = New-HuduRelation -FromableType 'Asset' -ToableType 'Website' -FromableID $UpdateAsset.HuduID -ToableID $_.HuduID) {
                                        Write-Host "Successully Created relation to $($WebsiteRelation.relation.name)"
                                     } else { Write-Host "Tags to Websites are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                                    }
                            }
                            "Passwords" { $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) { @{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'AssetPassword'; itg_to_id = $IDMatch.id}}; Write-Host "Tags to Password $($field.FieldName) in $($UpdateAsset.Name) has been recorded for later."; $supported = $true }
                            "Locations" {
                                $LocationsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $($MatchedLocations | Where-Object { $_.ITGID -eq $IDMatch.id } | Select-Object @{N = 'id'; E = { $_.HuduID } }, @{N = 'name'; E = { $_.Name } })
                                }
                                $ReturnData = $LocationsLinked | convertto-json -compress -AsArray | Out-String
                                $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))
                            }
                            "Organizations" { $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) {@{hudu_from_id = $UpdateAsset.HuduID; relation_type = 'Company'; itg_to_id = $IDMatch.id}}; Write-Host "Tags to Companies $($field.FieldName) in $($UpdateAsset.Name) has been recorded later."; $supported = $true }
                            "SslCertificates" { Write-Host "Tags to SSL Certificates are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "Tickets" { Write-Host "Tags to Tickets are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
                            "FlexibleAssetType" {	
                                $AssetsLinked = foreach ($IDMatch in $ITGValues.values) {
                                    $($MatchedAssets | Where-Object { $_.ITGID -eq $IDMatch.id } | Select-Object @{N = 'id'; E = { $_.HuduID } }, @{N = 'name'; E = { $_.Name } })
                                }
                                $ReturnData = $AssetsLinked | convertto-json -compress -AsArray | Out-String
                                $null = $AssetFields.add("$($field.HuduParsedName)", ("$ReturnData"))	
                            }
                        }
                        if ($Supported -eq $False) {
                            $ManualLog = [PSCustomObject]@{
                                Document_Name = $UpdateAsset.Name
                                Asset_Type    = $UpdateAsset.HuduObject.asset_type
                                Company_Name  = $UpdateAsset.HuduObject.company_name
                                HuduID        = $UpdateAsset.HuduID
                                Field_Name    = $($field.FieldName)
                                Notes         = "Unsupported Tag Type Manual Tag Required"
                                Action        = "Manually tag to Asset"
                                Data          = $ITGValues.values.name -join ","
                                Hudu_URL      = $UpdateAsset.HuduObject.url
                                ITG_URL       = $UpdateAsset.ITGObject.attributes."resource-url"
                            }; $null = $ManualActions.add($ManualLog);
                        }
                    } elseif ($field.FieldType -eq "Upload") {
                            $ManualLog = [PSCustomObject]@{
                                Document_Name = $UpdateAsset.Name
                                Asset_Type    = $UpdateAsset.HuduObject.asset_type
                                Company_Name  = $UpdateAsset.HuduObject.company_name
                                HuduID        = $UpdateAsset.HuduID
                                Field_Name    = $($field.FieldName)
                                Notes         = "Uploads not supported"
                                Action        = "Manually Upload files to Related Files"
                                Data          = $ITGValues.values -join ","
                                Hudu_URL      = $UpdateAsset.HuduObject.url
                                ITG_URL       = $UpdateAsset.ITGObject.attributes."resource-url"
                            }; $null = $ManualActions.add($ManualLog);
                    } elseif ($field.FieldType -eq "Password") {
                        $ITGPassword = (Get-ITGluePasswords -id $ITGValues -include related_items).data
                        $ITGPasswordValue = ($ITGPasswordsRaw |Where-Object {$_.id -eq $ITGPassword.id}).password
                        try {
                            if ($ITGPasswordValue) {
                                $NewPasswordObject = [pscustomobject]@{
                                Name =  "$($UpdateAsset.name) $($Field.fieldname) $($ITGPassword.Username) Password"
                                Username = $ITGPassword.Username
                                URL = $ITGPassword.url
                                ITGID = $ITGPassword.id
                                Description = $ITGpassword.notes
                                CompanyId = $UpdateAsset.HuduObject.company_id
                                Password = $ITGPasswordValue};
                                $null = $AssetFields.add("$($field.HuduParsedName)", $ITGPasswordValue)
                                $MigratedPasswordStatus = "Into Asset"
                            }
                        } catch {
                            Write-Host "Error occured adding field, possible duplicate name" -ForegroundColor Red
                            $ManualLog = [PSCustomObject]@{
                                Document_Name = $UpdateAsset.Name
                                Asset_Type    = "Asset Field"
                                Company_Name  = $UpdateAsset.HuduObject.company_name
                                HuduID        = $UpdateAsset.HuduID
                                Field_Name    = "$field.HuduParsedName"
                                Notes         = "Failed to add password to Asset"
                                Action        = "Manually add the password to the asset"
                                Data          = ($ITGPassword.attributes.'resource-url' -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')
                                Hudu_URL      = $UpdateAsset.HuduObject.url
                                ITG_URL       = $UpdateAsset.ITGObject.attributes.'resource-url'
                            }; $null = $ManualActions.add($ManualLog); $MigratedPasswordStatus = "Failed to add";
                        }
                        $MigratedPassword = [PSCustomObject]@{
                            "Name"      = $ITGPassword.attributes.name
                            "ITGID"     = $ITGPassword.id
                            "HuduID"    = $UpdateAsset.HuduID
                            "Matched"   = $true
                            "ITGObject" = $ITGPassword
                            "Imported"  = $MigratedPasswordStatus
                        }
                        $null = $MatchedAssetPasswords.add($MigratedPassword)
                    } elseif ($field.FieldType -eq "Number") {
                            # This version won't cast doubles for 'number' fields. It expects only integers.
                            $coerced = Get-CastIfNumeric ($_.value -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')
                            $null = $AssetFields.add("$($field.HuduParsedName)", [string]"$coerced")
       
                    } else {
                        $null = $AssetFields.add("$($field.HuduParsedName)", [string]"$($_.value)")
                    }
                } else {
                    Write-Host "Warning $ITGParsed : $ITGValues Could not be added" -ForegroundColor Red
                }
            }


            $UpdatedHuduAsset = (Set-HuduAsset -asset_id $UpdateAsset.HuduID -name $UpdateAsset.name -company_id $($UpdateAsset.HuduObject.company_id) -asset_layout_id $UpdateAsset.HuduObject.asset_layout_id -fields $AssetFields).asset
            write-host "updated" -ForegroundColor Green
            $UpdatedHuduAsset.fields | ForEach-Object {write-host "$($_.label) - $($_.value)" -ForegroundColor Green}
            write-host "from"
            $UpdateAsset.ITGObject.attributes.traits | format-table -force
            read-host
            $UpdateAsset.HuduObject = $UpdatedHuduAsset
            $UpdateAsset.Imported = "Created-By-Script"
        }
