if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Assets.json")) {
    Write-Host "Loading Previous Asset Migration"
    $MatchedAssets = Get-Content "$MigrationLogs\Assets.json" -raw | Out-String | ConvertFrom-Json -depth 100
    $MatchedAssetPasswords = Get-Content "$MigrationLogs\AssetPasswords.json" -raw | Out-String | ConvertFrom-Json -depth 100
    $RelationsToCreate = [System.Collections.ArrayList](Get-Content "$MigrationLogs\RelationsToCreate.json" -raw | Out-String | ConvertFrom-Json -depth 100)
    $ManualActions = [System.Collections.ArrayList](Get-Content "$MigrationLogs\ManualActions.json" -raw | Out-String | ConvertFrom-Json -depth 100)
} else {
    # Load raw passwords for embedded fields and future use
    $ITGPasswordsRaw = Import-CSV -Path "$ITGLueExportPath\passwords.csv"
    
    if ($ImportFlexibleAssets -eq $true) {
        $RelationsToCreate = [System.Collections.ArrayList]@()
        $MatchedAssets = [System.Collections.ArrayList]@()
        $MatchedAssetPasswords = [System.Collections.ArrayList]@()

        #We need to do a first pass creating empty assets with just the ITG migrated data. This builds an array we need to use to lookup relations when populating the entire assets
        
        #limit scope for matched layouts.
        if ($ScopedMigration) {
            $OriginalLayoutsCount = $($MatchedLayouts.count)
            Write-Host "Setting layouts to those in scope..." -foregroundcolor Yellow               
            $MatchedLayouts = Filter-ScopedAssets -Layouts $MatchedLayouts -ScopedCompanyIds $ScopedCompanyIds
            Write-Host "Layouts scoped... $OriginalLayoutsCount => $($MatchedLayouts.count)"
        }

        Foreach ($Layout in $MatchedLayouts) {
            Write-Host "Creating base assets for $($layout.name)"
            foreach ($ITGAsset in $Layout.ITGAssets) {
                # Match Company
                $HuduCompanyID = ($MatchedCompanies | Where-Object { $_.ITGID -eq $ITGAsset.attributes.'organization-id' }).HuduID

                $AssetFields = @{ 
                    'Imported From ITGlue' = Get-Date -Format "o"
                    'ITGlue URL' = $ITGAsset.attributes.'resource-url'
                    'ITGlue ID' = $ITGAsset.id
                }
			
                $NewHuduAsset = (New-HuduAsset -name $ITGAsset.attributes.name -company_id $HuduCompanyID -asset_layout_id $Layout.HuduObject.id -fields $AssetFields).asset

                $AssetDetails = [PSCustomObject]@{
                    "Name"       = $ITGAsset.attributes.name
                    "ITGID"      = $ITGAsset.id
                    "HuduID"     = $NewHuduAsset.Id
                    "Matched"    = $false
                    "HuduObject" = $NewHuduAsset
                    "ITGObject"  = $ITGAsset
                    "Imported"   = "First Pass"
                }

                $null = $MatchedAssets.add($AssetDetails)

            }
		
        }
	
	
        #We now need to loop through all Assets again updating the assets to their final version
        foreach ($UpdateAsset in $MatchedAssets) {
            Write-Host "Populating $($UpdateAsset.Name)"
		
            $AssetFields = @{ 
                'imported_from_itglue' = Get-Date -Format "o"
            }

            $traits = $UpdateAsset.ITGObject.attributes.traits
            $traits.PSObject.Properties | ForEach-Object {
                # Find the corresponding field we are working on
                $ITGParsed = $_.name
                $ITGValues = $_.value
                $field = $AllFields | Where-Object { $_.IGLayoutID -eq $UpdateAsset.ITGObject.attributes.'flexible-asset-type-id' -and $_.ITGParsedName -eq $ITGParsed }
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
                        if ($CurrentVersion -ge [version]("2.37.1")){
                            # This version won't cast doubles for 'number' fields. It expects only integers.
                            $coerced = Get-CastIfNumeric ($_.value -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')
                            $null = $AssetFields.add("$($field.HuduParsedName)", [string]"$coerced")
                        }  else {
                            $null = $AssetFields.add("$($field.HuduParsedName)", [string]"$($($_.value) -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')")
                        }
                    } else {
                        $null = $AssetFields.add("$($field.HuduParsedName)", [string]"$($_.value)")
                    }
                } else {
                    Write-Host "Warning $ITGParsed : $ITGValues Could not be added" -ForegroundColor Red
                }
            }

            $UpdatedHuduAsset = (Set-HuduAsset -asset_id $UpdateAsset.HuduID -name $UpdateAsset.name -company_id $($UpdateAsset.HuduObject.company_id) -asset_layout_id $UpdateAsset.HuduObject.asset_layout_id -fields $AssetFields).asset

            $UpdateAsset.HuduObject = $UpdatedHuduAsset
            $UpdateAsset.Imported = "Created-By-Script"
        }


        $MatchedAssets | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Assets.json"
        $MatchedAssetPasswords | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\AssetPasswords.json"
        $ManualActions | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\ManualActions.json"
        $RelationsToCreate | ConvertTo-Json -Depth 20 | Out-File "$MigrationLogs\RelationsToCreate.json"
        Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Assets Migrated Continue?" -DefaultResponse "continue to Documents/Articles, please."
    }
}

