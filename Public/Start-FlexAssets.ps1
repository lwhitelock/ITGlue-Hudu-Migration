function Start-FlexibleAssetContents {
param($UpdateAsset)
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
# $field found
$supported = $true

switch ($field.FieldType) {
    'Tag' {
        switch ($field.FieldSubType) {
            'AccountsUsers'      { Write-Host "Tags to Account Users are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
            'Checklists'         { Write-Host "Tags to Checklists are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
            'ChecklistTemplates' { Write-Host "Tags to Checklists Templates are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
            'Contacts' {
                $ContactsLinked = foreach ($IDMatch in $ITGValues.values) {
                    $MatchedContacts | Where-Object { $_.ITGID -eq $IDMatch.id } |
                        Select-Object @{N='id';E={$_.HuduID}}, @{N='name';E={$_.Name}}
                }
                $ReturnData = $ContactsLinked | ConvertTo-Json -Compress -AsArray | Out-String
                $null = $AssetFields.Add($field.HuduParsedName, $ReturnData)
            }
            'Configurations' {
                $ConfigsLinked = foreach ($IDMatch in $ITGValues.values) {
                    $MatchedConfigurations | Where-Object { $_.ITGID -eq $IDMatch.id } |
                        Select-Object @{N='id';E={$_.HuduID}}, @{N='name';E={$_.Name}}
                }
                $ReturnData = $ConfigsLinked | ConvertTo-Json -Compress -AsArray | Out-String
                $null = $AssetFields.Add($field.HuduParsedName, $ReturnData)
            }
            'Documents' {
                $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) {
                    @{ hudu_from_id = $UpdateAsset.HuduID; relation_type = 'Article'; itg_to_id = $IDMatch.id }
                }
                Write-Host "Tags to Articles $($field.FieldName) in $($UpdateAsset.Name) has been recorded for later."
            }
            'Domains' {
                $DomainsLinked = foreach ($IDMatch in $ITGValues.values) {
                    $MatchedWebsites | Where-Object { $_.ITGID -eq $IDMatch.id }
                }
                $DomainsLinked | ForEach-Object {
                    if ($WebsiteRelation = New-HuduRelation -FromableType 'Asset' -ToableType 'Website' -FromableID $UpdateAsset.HuduID -ToableID $_.HuduID) {
                        Write-Host "Successully Created relation to $($WebsiteRelation.relation.name)"
                    } else {
                        Write-Host "Tags to Websites are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"
                        $supported = $false
                    }
                }
            }
            'Passwords' {
                $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) {
                    @{ hudu_from_id = $UpdateAsset.HuduID; relation_type = 'AssetPassword'; itg_to_id = $IDMatch.id }
                }
                Write-Host "Tags to Password $($field.FieldName) in $($UpdateAsset.Name) has been recorded for later."
            }
            'Locations' {
                $LocationsLinked = foreach ($IDMatch in $ITGValues.values) {
                    $MatchedLocations | Where-Object { $_.ITGID -eq $IDMatch.id } |
                        Select-Object @{N='id';E={$_.HuduID}}, @{N='name';E={$_.Name}}
                }
                $ReturnData = $LocationsLinked | ConvertTo-Json -Compress -AsArray | Out-String
                $null = $AssetFields.Add($field.HuduParsedName, $ReturnData)
            }
            'Organizations' {
                $RelationsToCreate += foreach ($IDMatch in $ITGValues.values) {
                    @{ hudu_from_id = $UpdateAsset.HuduID; relation_type = 'Company'; itg_to_id = $IDMatch.id }
                }
                Write-Host "Tags to Companies $($field.FieldName) in $($UpdateAsset.Name) has been recorded later."
            }
            'SslCertificates' { Write-Host "Tags to SSL Certificates are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
            'Tickets'         { Write-Host "Tags to Tickets are not supported $($field.FieldName) in $($UpdateAsset.Name) will need to be manually migrated, Sorry!"; $supported = $false }
            'FlexibleAssetType' {
                $AssetsLinked = foreach ($IDMatch in $ITGValues.values) {
                    $MatchedAssets | Where-Object { $_.ITGID -eq $IDMatch.id } |
                        Select-Object @{N='id';E={$_.HuduID}}, @{N='name';E={$_.Name}}
                }
                $ReturnData = $AssetsLinked | ConvertTo-Json -Compress -AsArray | Out-String
                $null = $AssetFields.Add($field.HuduParsedName, $ReturnData)
            }
            default {
                Write-Host "Unsupported Tag subtype $($field.FieldSubType) for $($field.FieldName) in $($UpdateAsset.Name)"; $supported = $false
            }
        }

        if (-not $supported) {
            $ManualLog = [PSCustomObject]@{
                Document_Name = $UpdateAsset.Name
                Asset_Type    = $UpdateAsset.HuduObject.asset_type
                Company_Name  = $UpdateAsset.HuduObject.company_name
                HuduID        = $UpdateAsset.HuduID
                Field_Name    = $field.FieldName
                Notes         = "Unsupported Tag Type Manual Tag Required"
                Action        = "Manually tag to Asset"
                Data          = ($ITGValues.values.name -join ",")
                Hudu_URL      = $UpdateAsset.HuduObject.url
                ITG_URL       = $UpdateAsset.ITGObject.attributes.'resource-url'
            }
            $null = $ManualActions.Add($ManualLog)
        }
    }

    'Upload' {
        $ManualLog = [PSCustomObject]@{
            Document_Name = $UpdateAsset.Name
            Asset_Type    = $UpdateAsset.HuduObject.asset_type
            Company_Name  = $UpdateAsset.HuduObject.company_name
            HuduID        = $UpdateAsset.HuduID
            Field_Name    = $field.FieldName
            Notes         = "Uploads not supported"
            Action        = "Manually Upload files to Related Files"
            Data          = ($ITGValues.values -join ",")
            Hudu_URL      = $UpdateAsset.HuduObject.url
            ITG_URL       = $UpdateAsset.ITGObject.attributes.'resource-url'
        }
        $null = $ManualActions.Add($ManualLog)
    }

    'Password' {
        $ITGPassword      = (Get-ITGluePasswords -id $ITGValues -include related_items).data
        $ITGPasswordValue = ($ITGPasswordsRaw | Where-Object { $_.id -eq $ITGPassword.id }).password
        try {
            if ($ITGPasswordValue) {
                $NewPasswordObject = [pscustomobject]@{
                    Name        = "$($UpdateAsset.name) $($Field.fieldname) $($ITGPassword.Username) Password"
                    Username    = $ITGPassword.Username
                    URL         = $ITGPassword.url
                    ITGID       = $ITGPassword.id
                    Description = $ITGPassword.notes
                    CompanyId   = $UpdateAsset.HuduObject.company_id
                    Password    = $ITGPasswordValue
                }
                $null = $AssetFields.Add($field.HuduParsedName, $ITGPasswordValue)
                $MigratedPasswordStatus = "Into Asset"
            }
        } catch {
            Write-Host "Error occured adding field, possible duplicate name" -ForegroundColor Red
            $ManualLog = [PSCustomObject]@{
                Document_Name = $UpdateAsset.Name
                Asset_Type    = "Asset Field"
                Company_Name  = $UpdateAsset.HuduObject.company_name
                HuduID        = $UpdateAsset.HuduID
                Field_Name    = $field.HuduParsedName
                Notes         = "Failed to add password to Asset"
                Action        = "Manually add the password to the asset"
                Data          = ($ITGPassword.attributes.'resource-url' -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')
                Hudu_URL      = $UpdateAsset.HuduObject.url
                ITG_URL       = $UpdateAsset.ITGObject.attributes.'resource-url'
            }
            $null = $ManualActions.Add($ManualLog)
            $MigratedPasswordStatus = "Failed to add"
        }
        $MigratedPassword = [PSCustomObject]@{
            Name      = $ITGPassword.attributes.name
            ITGID     = $ITGPassword.id
            HuduID    = $UpdateAsset.HuduID
            Matched   = $true
            ITGObject = $ITGPassword
            Imported  = $MigratedPasswordStatus
        }
        $null = $MatchedAssetPasswords.Add($MigratedPassword)
    }

    default {
        if ($CurrentVersion -ge [version]'2.37.1') {
            $coerced = Get-CastIfNumeric ($_.value -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]')
            $null = $AssetFields.Add($field.HuduParsedName, $coerced)
        } else {
            $null = $AssetFields.Add($field.HuduParsedName, ($_.value -replace '[^\x09\x0A\x0D\x20-\xD7FF\xE000-\xFFFD\x10000\x10FFFF]'))
        }
    }
}
} else {
                    Write-Host "Warning $ITGParsed : $ITGValues Could not be added" -ForegroundColor Red
                }
            }

            $UpdatedHuduAsset = (Set-HuduAsset -asset_id $UpdateAsset.HuduID -name $UpdateAsset.name -company_id $($UpdateAsset.HuduObject.company_id) -asset_layout_id $UpdateAsset.HuduObject.asset_layout_id -fields $AssetFields).asset

            $UpdateAsset.HuduObject = $UpdatedHuduAsset
            $UpdateAsset.Imported = "Created-By-Script"
            return $UpdateAsset
}
