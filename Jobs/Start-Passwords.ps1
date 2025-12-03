if ($ResumeFound -eq $true -and (Test-Path "$MigrationLogs\Passwords.json")) {
    Write-Host "Loading Previous Paswords Migration"
    $MatchedPasswords = Get-Content "$MigrationLogs\Passwords.json" -raw | Out-String | ConvertFrom-Json
} else {

    #Import Passwords
    Write-Host "Fetching Passwords from IT Glue" -ForegroundColor Green
    $PasswordSelect = { (Get-ITGluePasswords -page_size 1000 -page_number $i).data }

    $ITGPasswords = Import-ITGlueItems -ItemSelect $PasswordSelect -MigrationName 'Passwords'

    if ($ScopedMigration) {
        $OriginalPasswordsCount = $($ITGPasswords.count)
        Write-Host "Setting passwords to those in scope..." -foregroundcolor Yellow        
        $ITGPasswords         = $ITGPasswords | Where-Object { $ScopedCompanyIds -contains $_.attributes.'organization-id' }
        Write-Host "Passwords scoped... $OriginalPasswordsCount => $($ITGPasswords.count)"
    }

    try {
        Write-Host "Loading Passwords from CSV for faster import" -foregroundcolor Cyan
        $ITGPasswordsRaw = Import-CSV -Path "$ITGLueExportPath\passwords.csv"
    }
	catch {
        $ITGPasswordsSingle = foreach ($ITGRawPass in $ITGPasswords) {
            $ITGPassword = (Get-ITGluePasswords -id $ITGRawPass.id -include related_items).data
            $ITGPassword
        }
        $ITGPasswords = $ITGPasswordsSingle
    }
    
    Write-Host "$($ITGPasswords.count) IT Glue Passwords Found"

    $PasswordsInCSV = [System.Collections.ArrayList]::new()
    $PasswordsNotInCSV = [System.Collections.ArrayList]::new()

    $IdOrganizationMap = @{}
    foreach ($row in $ITGPasswordsRaw) {
        $IdOrganizationMap[[string]$row.id] = @{
            'password' = $row.password
            'otp_secret' = $row.otp_secret
        }
    }

    foreach ($row in $ITGPasswords) {
        if ($IdOrganizationMap.ContainsKey([string]$row.id) -eq $true) {
            $row.attributes | Add-Member -MemberType 'NoteProperty' -Name 'password' -Value $IdOrganizationMap[[string]$row.id].password
            $row.attributes | Add-Member -MemberType 'NoteProperty' -Name 'otp_secret' -Value $IdOrganizationMap[[string]$row.id].otp_secret
            [void]$PasswordsInCSV.Add($row)
        } else {
            [void]$PasswordsNotInCSV.Add($row)
        }
    }

    $MatchedPasswords = New-Object 'System.Collections.ArrayList'
    foreach ($itgpassword in $PasswordsInCSV) {
        [void]$MatchedPasswords.Add(
            [PSCustomObject]@{
                "Name"       = $itgpassword.attributes.name
                "ITGID"      = $itgpassword.id
                "HuduID"     = ""
                "Matched"    = $false
                "HuduObject" = ""
                "ITGObject"  = $itgpassword
                "Imported"   = ""
            }
        )
    }
    foreach ($itgpassword in $PasswordsNotInCSV) {
        $FullPassword = (Get-ITGluePasswords -id $itgpassword.id -include related_items).data
        [void]$MatchedPasswords.Add(
            [PSCustomObject]@{
                "Name"       = $itgpassword.attributes.name
                "ITGID"      = $itgpassword.id
                "HuduID"     = ""
                "Matched"    = $false
                "HuduObject" = ""
                "ITGObject"  = $FullPassword
                "Imported"   = ""
            }
        )
    }

    Write-Host "Passwords to Migrate"
    $MatchedPasswords | Sort-Object Name |  Select-Object Name | Format-Table


    $UnmappedPasswordCount = ($MatchedPasswords | Where-Object { $_.Matched -eq $false } | measure-object).count

    if ($ImportPasswords -eq $true -and $UnmappedPasswordCount -gt 0) {

        $importOption = Get-ImportMode -ImportName "Passwords"

        if (($importOption -eq "A") -or ($importOption -eq "S") ) {		

            foreach ($company in $CompaniesToMigrate) {
                Write-Host "Migrating $($company.CompanyName)" -ForegroundColor Green

                foreach ($unmatchedPassword in ($MatchedPasswords | Where-Object { $_.Matched -eq $false -and $company.ITGCompanyObject.id -eq $_."ITGObject".attributes."organization-id" })) {

                    Confirm-Import -ImportObjectName "$($unmatchedPassword.Name)" -ImportObject $unmatchedPassword -ImportSetting $ImportOption

                    Write-Host "Starting $($unmatchedPassword.Name)"

                    $PasswordableType = 'Asset'
                    $ParentItemID = $null
		    
                    if ($($unmatchedPassword.ITGObject.attributes."resource-id")) {
						
                        if ($unmatchedPassword.ITGObject.attributes."resource-type" -eq "flexible-asset-traits") {
                            # Check if it has already migrated with Assets
                            $FoundItem = $MatchedAssetPasswords | Where-Object { $_.ITGID -eq $($unmatchedPassword.ITGID) }
                            if (!$FoundItem) {
                                Write-Host "Could not find password field on asset. ParentID: $($unmatchedPassword.ITGObject.attributes.`"resource-id`")"
                                $FoundItem = $MatchedAssets | Where-Object { $_.ITGID -eq $unmatchedPassword.ITGObject.attributes."resource-id" }
                                $ManualLog = [PSCustomObject]@{
                                    Document_Name = $FoundItem.name
                                    Field_Name    = $unmatchedPassword.ITGObject.attributes.name
                                    Asset_Type    = "Asset password field"
                                    Company_Name  = $unmatchedPassword.ITGObject."organization-name"
                                    HuduID        = $unmatchedPassword.HuduID
                                    Notes         = "Password from FA Field not found."
                                    Action        = "Manually create password"
                                    Data          = "Type: $($unmatchedPassword.ITGObject.attributes.`"resource-type`")"
                                    Hudu_URL      = $FoundItem.HuduObject.url
                                    ITG_URL       = $unmatchedPassword.ITGObject.attributes."parent-url"
                                }
                                $null = $ManualActions.add($ManualLog)
                            } else {
                                Write-Host "Migrated with Asset: $FoundItem.HuduID"
                            }
                        } else {
                            # Check if it needs to link to websites
                            if ($($unmatchedPassword.ITGObject.attributes."resource-type") -eq "domains") {
                                $ParentItemID = ($MatchedWebsites | Where-Object { $_.ITGID -eq $($unmatchedPassword.ITGObject.attributes."resource-id") }).HuduID
                                if ($ParentItemID) {
                                    Write-Host "Matched to $ParentItemID" -ForegroundColor Green
                                } else {
                                    Write-Host "Could not find asset to Match. ParentID: $($unmatchedPassword.ITGObject.attributes.`"resource-id`")"
                                    $ManualLog = [PSCustomObject]@{
                                        Document_Name = $unmatchedPassword.ITGObject.attributes.name
                                        Field_Name    = "N/A"
                                        Asset_Type    = $unmatchedPassword.HuduObject.asset_type
                                        Company_Name  = $unmatchedPassword.HuduObject.company_name
                                        HuduID        = $unmatchedPassword.HuduID
                                        Notes         = "Password could not be related."
                                        Action        = "Manually relate password"
                                        Data          = "Type: $($unmatchedPassword.ITGObject.attributes.`"resource-type`")"
                                        Hudu_URL      = $unmatchedPassword.HuduObject.url
                                        ITG_URL       = $unmatchedPassword.ITGObject.attributes."parent-url"
                                    }
                                    $null = $ManualActions.add($ManualLog)
                                }

                            } else {
                                # Deal with all others
                                $ParentItemID = (Find-MigratedItem -ITGID $($unmatchedPassword.ITGObject.attributes."resource-id")).HuduID
                                if ($ParentItemID) {
                                    Write-Host "Matched to $ParentItemID" -ForegroundColor Green
                                } else {
                                    Write-Host "Could not find asset to Match. ParentID: $($unmatchedPassword.ITGObject.attributes.`"resource-id`")"
                                    $ManualLog = [PSCustomObject]@{
                                        Document_Name = $unmatchedPassword.ITGObject.attributes.name
                                        Field_Name    = "N/A"
                                        Asset_Type    = $unmatchedPassword.HuduObject.asset_type
                                        Company_Name  = $unmatchedPassword.HuduObject.company_name
                                        HuduID        = $unmatchedPassword.HuduID
                                        Notes         = "Password could not be related."
                                        Action        = "Manually relate password"
                                        Data          = "Type: $($unmatchedPassword.ITGObject.attributes.`"resource-type`")"
                                        Hudu_URL      = $unmatchedPassword.HuduObject.url
                                        ITG_URL       = $unmatchedPassword.ITGObject.attributes."parent-url"
                                    }
                                    $null = $ManualActions.add($ManualLog)
                                }
                            }
                        }
                    }
					
                    if (!($($unmatchedPassword.ITGObject.attributes."resource-type") -eq "flexible-asset-traits")) {

                        $validated_otp = "$($unmatchedPassword.ITGObject.attributes.otp_secret)".Trim().ToUpper()
                        if ($validated_otp) {
                            $isValidBase32 = $validated_otp -match '^[A-Z2-7]+$'
                            $lengthOK = $validated_otp.Length -ge 16 -and $validated_otp.Length -le 80

                            $validated_otp = if ($isValidBase32 -and $lengthOK) { $validated_otp } else { $null }

                            if (-not ($isValidBase32 -and $lengthOK)) {
                                Write-Warning "Invalid OTP secret for $($unmatchedPassword.ITGObject.attributes.name): $($unmatchedPassword.ITGObject.attributes.otp_secret)... valid base32? $isValidBase32 length ok? $lengthOK (min / max is 16 / 80 chars)"
                            }                            
                        }


                        $PasswordSplat = @{
                            name              = "$($unmatchedPassword.ITGObject.attributes.name)"
                            company_id        = $company.HuduCompanyObject.ID
                            description       = $unmatchedPassword.ITGObject.attributes.notes
                            passwordable_type = $PasswordableType
                            passwordable_id   = $ParentItemID
                            in_portal         = $false
                            password          = $unmatchedPassword.ITGObject.attributes.password
                            url               = if ($url = $unmatchedPassword.ITGObject.attributes.url) {$url} Else {$unmatchedPassword.ITGObject.attributes.'resource-url'}
                            username          = $unmatchedPassword.ITGObject.attributes.username
                            otpsecret         = $validated_otp

                        }
                        if ([string]::IsNullOrWhiteSpace($unmatchedPassword.ITGObject.attributes.password) -or $unmatchedPassword.ITGObject.attributes.password.Length -lt 1) {
                            $manualActions.add([PSCustomObject]@{
                                name              = "$($unmatchedPassword.ITGObject.attributes.name)"
                                company_id        = $company.HuduCompanyObject.ID
                                description       = $unmatchedPassword.ITGObject.attributes.notes
                                passwordable_type = $PasswordableType
                                passwordable_id   = $ParentItemID
                                in_portal         = $false
                                password          = ""
				                Hudu_URL      	  = $unmatchedPassword.HuduObject.url
                                ITG_URL           = if ($url = $unmatchedPassword.ITGObject.attributes.url) {$url} Else {$unmatchedPassword.ITGObject.attributes.'resource-url'}
                                username          = $unmatchedPassword.ITGObject.attributes.username
                                otpsecret         = "removed for security purposes"
                                problem           = "password was null or empty"
                            })
                            $unmatchedPassword.matched = $false
                            Write-Warning "$($HuduNewPassword.Name) Has been skipped and added to manual actions due to being empty"                            
                        } else {
                            $HuduNewPassword = (New-HuduPassword @PasswordSplat).asset_password 
                            $unmatchedPassword.matched = $true
                            $unmatchedPassword.HuduID = $HuduNewPassword.id
                            $unmatchedPassword."HuduObject" = $HuduNewPassword
                            $unmatchedPassword.Imported = "Created-By-Script"
                            $ImportsMigrated = $ImportsMigrated + 1
                            Write-host "$($HuduNewPassword.Name) Has been created in Hudu"
                        }
                    }
                }
            }
        }


    } else {
        if ($UnmappedPasswordCount -eq 0) {
            Write-Host "All Passwords matched, no migration required" -foregroundcolor green
        } else {
            Write-Host "Warning Import passwords is set to disabled so the above unmatched passwords will not have data migrated" -foregroundcolor red
            Write-TimedMessage -Timeout 3 -Message "Press any key to continue or CTRL+C to quit"  -DefaultResponse "continue wrap-up of passwords, please."
        }
    }

    # Save the results to resume from if needed
    $MatchedPasswords | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\Passwords.json"
    $ManualActions | ConvertTo-Json -depth 100 | Out-File "$MigrationLogs\ManualActions.json"
    Write-TimedMessage -Timeout 3 -Message "Snapshot Point: Passwords Finished. Continue?"  -DefaultResponse "continue to Document/Article Updates, please."
}
