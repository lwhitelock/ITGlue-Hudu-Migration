

$HuduCompanies  = $HuduCompanies ?? $(Get-HuduCompanies)
$huduUsers      = $huduUsers ?? $(Get-HuduUsers)    
$userIndex = @{}
$MatchedChecklists = $MatchedChecklists ?? @()
foreach ($u in $huduUsers) {$key = "$($u.first_name) $($u.last_name)".ToLower(); $userIndex[$key] = $u;}

if (-not (Get-Command -Name Get-ITGlueCheckLists -ErrorAction SilentlyContinue)) { . "$($(get-childitem -path "." -Recurse -file "Get-Checklists.ps1" | Select-Object -first 1).fullname)" }
if (-not (Get-Command -Name Get-ITGlueJWTAuth -ErrorAction SilentlyContinue)) { . "$($(get-childitem -path "." -Recurse -file "JWT-Auth.ps1" | Select-Object -first 1).fullname)" }


$ITGAPIEndpoint = @($ITGBaseURI,$ITGAPIEndpoint, $settings.ITGAPIEndpoint) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($ITGAPIEndpoint)) {
    $ITGAPIEndpoint = Select-ObjectFromList -objects @("https://api.itglue.com", "https://api.eu.itglue.com", "https://api.au.itglue.com") -message "Select ITGlue API Endpoint for your instance/region"
}
$ITGAPIEndpoint= ($ITGAPIEndpoint.Trim() -replace '[\\/]+$', '')

$ChecklistHuduVersion = $CurrentVersion
if (-not $ChecklistHuduVersion -and (Get-Command -Name Get-HuduAppInfo -ErrorAction SilentlyContinue)) {
    try {
        $ChecklistHuduVersion = [version]$(Get-HuduAppInfo).version
        $CurrentVersion = $ChecklistHuduVersion
    } catch {
        Write-Host "Could not detect Hudu version for checklist import. Due dates and assignees will only be sent to confirmed process runs."
    }
}

$UsesHuduProcessRunModel = $true
if ($ChecklistHuduVersion -and $ChecklistHuduVersion -lt [version]'2.41.0') {
    $UsesHuduProcessRunModel = $false
}

$StartHuduProcedureCommand = Get-Command -Name Start-HuduProcedure -ErrorAction SilentlyContinue
$StartHuduProcedureIdParameter = $null
if ($StartHuduProcedureCommand) {
    if ($StartHuduProcedureCommand.Parameters.ContainsKey('ProcedureId')) {
        $StartHuduProcedureIdParameter = 'ProcedureId'
    } elseif ($StartHuduProcedureCommand.Parameters.ContainsKey('Id')) {
        $StartHuduProcedureIdParameter = 'Id'
    }
}
$GetHuduProcedureTasksCommand = Get-Command -Name Get-HuduProcedureTasks -ErrorAction SilentlyContinue
$SetHuduProcedureTaskCommand = Get-Command -Name Set-HuduProcedureTask -ErrorAction SilentlyContinue



if (-not (test-path "$MigrationLogs\RetrievedChecklists.json")){
    Write-Host "No preloaded checklists found. attempting second-line retrieval"
    $ITGlueJWT = $ITGlueJWT ?? (Read-Host "Please enter your ITGlue JWT as retrieved from browser.")
    $ITGlueJWT = Get-ITGlueJWTAuth -ITglueJWT $ITglueJWT -ITGBaseURI $ITGAPIEndpoint
    $MatchedChecklists = $MatchedChecklists ?? @(); $ITGlueRawChecklists = $ITGlueRawChecklists ?? @(); $ITglueChecklists = $ITglueChecklists ?? [System.Collections.ArrayList]@();
    # $MatchedChecklists = @(); $ITGlueRawChecklists = @(); $ITglueChecklists = [System.Collections.ArrayList]@();
    $PageSize = 200
    $PageNum = 0
    while ($true) {
        $ITGlueRawChecklists = $(Get-ITGlueCheckLists -JWTAuthToken $ITGlueJWT -page_size $($PageSize ?? 200) -page_number $PageNum  -ITGBaseURI $ITGAPIEndpoint).data
        foreach ($checklistEntry in $ITGlueRawChecklists) {
            $ITGChecklistItems=$null
            try {
                $checklistEntry | Add-Member -MemberType 'NoteProperty' -Name 'IsTemplate' -Value $false -Force
                $ITGChecklistItems=$(Get-ITGlueChecklistItems -JWTAuthToken $ITGlueJWT -filter_checklist_id $checklistEntry.id -ITGBaseURI $ITGAPIEndpoint)
                $checklistEntry | Add-Member -MemberType 'NoteProperty' -Name 'ITGChecklistItems' -Value $ITGChecklistItems -Force
            }catch{
                Write-host "Error getting checklist items $_"
            }
            $ITGLueChecklists.Add($checklistEntry)
        }
        $PageNum = $PageNum +1
        if (-not $ITGlueRawChecklists -or $ITGlueRawChecklists.count -lt $PageSize) {break}
    }
    $PageNum = 0
    Write-Host "Retrieving all checklist templates from ITGlue"
    while ($true) {
        $ITGlueRawChecklists = @(Get-ITGlueChecklistTemplates -JWTAuthToken $ITGlueJWT -page_size ($PageSize ?? 200) -page_number $PageNum -ITGBaseURI $ITGAPIEndpoint)
        foreach ($checklistTemplate in $ITGlueRawChecklists | Where-Object {$_}) {
            $ITGChecklistItems=$null
            try {
                $checklistTemplate | Add-Member -MemberType 'NoteProperty' -Name 'IsTemplate' -Value $true -Force
                $ITGChecklistItems=$(Get-ITGlueChecklistTemplateItems -JWTAuthToken $ITGlueJWT -filter_checklist_id $checklistTemplate.id -ITGBaseURI $ITGAPIEndpoint)
                $checklistTemplate | Add-Member -MemberType 'NoteProperty' -Name 'ITGChecklistItems' -Value $ITGChecklistItems -Force
            } catch {
                Write-host "Error getting checklist template items $_"
            }

            $ITGLueChecklists.Add($checklistTemplate)
        }
        $PageNum = $PageNum +1
        if (-not $ITGlueRawChecklists -or $ITGlueRawChecklists.count -lt $PageSize) {break}
    }
    $ChecklistCount = @($ITGLueChecklists | Where-Object { $_.IsTemplate -eq $false }).Count
    $ChecklistTemplateCount = @($ITGLueChecklists | Where-Object { $_.IsTemplate -eq $true }).Count
    $ChecklistItemCount = ($ITGLueChecklists | Where-Object { $_.IsTemplate -eq $false } | ForEach-Object { @($_.ITGChecklistItems | Where-Object { $_ }).Count } | Measure-Object -Sum).Sum
    $ChecklistTemplateItemCount = ($ITGLueChecklists | Where-Object { $_.IsTemplate -eq $true } | ForEach-Object { @($_.ITGChecklistItems | Where-Object { $_ }).Count } | Measure-Object -Sum).Sum
    Write-Host "Got $ChecklistCount ITGlue checklists ($ChecklistItemCount tasks) and $ChecklistTemplateCount ITGlue checklist templates ($ChecklistTemplateItemCount template tasks)."
    $ITGLueChecklists | convertto-json -depth 99 | Out-File "$MigrationLogs\RetrievedChecklists.json"    
} else {
    write-host "Preloaded checklists found, loading from file if needed."
    if (-not $ITGLueChecklists) {
        $loaded = Get-Content "$MigrationLogs\RetrievedChecklists.json" -Raw | ConvertFrom-Json -Depth 99
        $ITGLueChecklists = [System.Collections.ArrayList]@()
        foreach ($item in @($loaded)) {
            [void]$ITGLueChecklists.Add($item)
        }
    } else {
        Write-Host "ITGLueChecklists variable already populated, skipping loading from file."
    }
}


# Match/Add Checklists/Items
# Hudu process mapping:
# - ITGlue checklist templates are reusable definitions, so they become Hudu process templates.
#   With a matched company they become company process templates; otherwise they become global process templates.
# - ITGlue checklists are single-use company records. On Hudu 2.41.0+, a company process is kicked off
#   as a run only when run-only metadata like due dates, assignees, or start/completion dates is present.
$ChecklistIDX=0
foreach ($checklist in $ITGLueChecklists) {
    $ChecklistIDX=$ChecklistIDX+1

    $HuduProcedureTasks = @()
    $isChecklistTemplate = $true -eq $checklist.IsTemplate
    $matchedCompany = $null
    $matchedCompany = $($($MatchedCompanies | Where-Object {[string]$checklist.attributes.'organization-id' -eq [string]$_.ITGID} | Select-Object -First 1))

    $runMetadataValues = @(
        $checklist.attributes.'assignee-name'
        $checklist.attributes.'due-date'
        $checklist.attributes.'started-at'
        $checklist.attributes.'started_at'
        $checklist.attributes.'start-date'
        $checklist.attributes.'completed-at'
        $checklist.attributes.'completed_at'
        $checklist.attributes.'completed-by-name'
    )
    foreach ($item in @($checklist.ITGChecklistItems | Where-Object { $_ })) {
        $runMetadataValues += $item.attributes.'assignee-name'
        $runMetadataValues += $item.attributes.'due-date'
        $runMetadataValues += $item.attributes.'started-at'
        $runMetadataValues += $item.attributes.'started_at'
        $runMetadataValues += $item.attributes.'start-date'
        $runMetadataValues += $item.attributes.'completed-at'
        $runMetadataValues += $item.attributes.'completed_at'
        $runMetadataValues += $item.attributes.'completed-by-name'
    }
    $hasRunMetadata = (-not $isChecklistTemplate) -and @( $runMetadataValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0

    $importExplanation = if ($isChecklistTemplate) {
        if ($matchedCompany -and $matchedCompany.HuduID -and $matchedCompany.HuduID -gt 0) {
            'checklist template as a reusable Hudu company process template.'
        } else {
            'checklist template as a reusable Hudu global process template.'
        }
    } elseif ($UsesHuduProcessRunModel -and $hasRunMetadata) {
        if ($matchedCompany -and $matchedCompany.HuduID -and $matchedCompany.HuduID -gt 0) {
            'checklist as a Hudu process run.'
        } else {
            'checklist as a Hudu global process template because no matched company was found to kick off a run.'
        }
    } elseif ($UsesHuduProcessRunModel) {
        'checklist as a Hudu company/global process template; no run-only metadata was found.'
    } elseif ($hasRunMetadata) {
        'checklist as a Hudu procedure with due dates or assignees applied to tasks where supported.'
    } else {
        'checklist as a Hudu procedure; no due dates or assignees were found.'
    }

    $procedureRequest = @{
        Name = [System.Net.WebUtility]::UrlDecode("$($checklist.attributes.name ?? 'Unnamed Procedure')")
        CompanyTemplate = $checklist.IsTemplate ?? $false
        Description =  $($($checklist.attributes.description ?? "No description found for procedure.") + "`n" + 
            "Imported from ITGlue $importExplanation <a href='$($checklist.attributes.'resource-url')'>ITGlue source</a>")
    }

    if ($matchedCompany -and $matchedCompany.HuduID -and $matchedCompany.HuduID -gt 0){
        $procedureRequest["CompanyID"] = $matchedCompany.HuduID
    }

    try {
        $newProcedure = $null
        $newProcedure = New-HuduProcedure @procedureRequest
        $newProcedure = $newProcedure.procedure ?? $newProcedure

    } catch {
        Write-Host "Error creating procedure in Hudu $_"
        continue
    }

    if ($newProcedure -and $newProcedure.Id) {
        $checklist | Add-Member -MemberType 'NoteProperty' -Name 'HuduProcedure' -Value $newProcedure -Force
        Write-Host "Created $(if (-not $newProcedure.company_id) {'Global'} else {'Company'}) Procedure $(if ($true -eq $checklist.IsTemplate) {'Template'}) $($ChecklistIDX) of $($ITGLueChecklists.count)"

        $sourceTasks = @($checklist.ITGChecklistItems | Where-Object { $_ })
        if ($sourceTasks.Count -eq 0) {
            $sourceTasks = @(
                [pscustomobject]@{
                    attributes = [pscustomobject]@{
                        name = 'Imported checklist placeholder'
                        description = 'This ITGlue checklist did not include any checklist items. Placeholder task added so Hudu can track this process.'
                        order = 1
                    }
                    IsMigrationPlaceholder = $true
                }
            )
            Write-Host "ITGlue checklist $($checklist.id) has no tasks. Adding one placeholder task for Hudu tracking."
        }

        $TaskRunFieldRequests = @()
        $TaskIDX=0

        foreach ($task in $sourceTasks){
            $TaskIDX = $TaskIDX + 1

            $NewProcedureTask = $null
            $DueDate = $null
            $assignedUsers = @()

            $NewTaskRequest = @{
                ProcedureId = $newProcedure.id
                Name        = [System.Net.WebUtility]::UrlDecode("$($task.attributes.name ?? ("Task #$($task.attributes.order)" ?? "Unnamed Task"))")
                Description = ($task.attributes.description ?? "Imported from ITglue with no description")
            }

            if ($task.attributes.order) {
                $NewTaskRequest["Position"] = $task.attributes.order
            }

            $assigneeCandidates = @(
                $checklist.attributes.'assignee-name',
                $task.attributes.'assignee-name'
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            foreach ($a in $assigneeCandidates) {
                $first,$last = ($a -replace '\s+', ' ').Trim() -split '\s+', 2
                if ($last) {
                    $key = "$first $last".ToLower()
                    if ($userIndex.ContainsKey($key)) {
                        $assignedUsers += $userIndex[$key].id
                    }
                }
            }

            $RunFieldRequest = @{
                Name = $NewTaskRequest['Name']
            }
            if ($NewTaskRequest.ContainsKey('Position')) {
                $RunFieldRequest['Position'] = $NewTaskRequest['Position']
            }

            $canApplyRunFields = -not $UsesHuduProcessRunModel
            if ($canApplyRunFields) {
                if ($assignedUsers.Count -gt 0) {
                    $NewTaskRequest['AssignedUsers'] = $assignedUsers
                }

                if ($task.attributes.'due-date') {
                    $dueDate = [datetime]$task.attributes.'due-date'
                    $NewTaskRequest['DueDate'] = $dueDate.ToString('yyyy-MM-dd')

                    $age = (Get-Date) - $dueDate
                    $NewTaskRequest['Priority'] = if ($age.TotalDays -lt 0) { 'urgent' }
                                                elseif ($age.TotalDays -le 14) { 'high' }
                                                else { 'normal' }
                }
            } else {
                if ($assignedUsers.Count -gt 0) {
                    $RunFieldRequest['AssignedUsers'] = $assignedUsers
                }

                if ($task.attributes.'due-date') {
                    $dueDate = [datetime]$task.attributes.'due-date'
                    $RunFieldRequest['DueDate'] = $dueDate.ToString('yyyy-MM-dd')

                    $age = (Get-Date) - $dueDate
                    $RunFieldRequest['Priority'] = if ($age.TotalDays -lt 0) { 'urgent' }
                                                elseif ($age.TotalDays -le 14) { 'high' }
                                                else { 'normal' }
                }
            }

            if ($RunFieldRequest.ContainsKey('AssignedUsers') -or $RunFieldRequest.ContainsKey('DueDate') -or $RunFieldRequest.ContainsKey('Priority')) {
                $TaskRunFieldRequests += [pscustomobject]$RunFieldRequest
            }

            try {             
                $NewProcedureTask = New-HuduProcedureTask @NewTaskRequest
            }
            catch {
                Write-Host "Error adding checklist Task $_"
            }

            if ($NewProcedureTask) {
                Write-Host "Added $(if ($NewTaskRequest.ContainsKey('AssignedUsers')) {'User-Assigned '} else {''})procedure task $($TaskIDX) of $($sourceTasks.Count)"
                $HuduProcedureTasks += $NewProcedureTask
            }
        }

        $newProcedureRun = $null
        $HuduProcedureRunTasks = @()
        if ((-not $isChecklistTemplate) -and $UsesHuduProcessRunModel -and $hasRunMetadata -and $newProcedure.company_id -and $StartHuduProcedureIdParameter) {
            try {
                $startProcedureRequest = @{
                    $StartHuduProcedureIdParameter = $newProcedure.id
                    Name = $procedureRequest['Name']
                }
                $newProcedureRun = Start-HuduProcedure @startProcedureRequest
                $newProcedureRun = $newProcedureRun.procedure ?? $newProcedureRun
            } catch {
                Write-Host "Error starting Hudu process run for checklist $($checklist.id): $_"
            }

            if ($newProcedureRun -and $newProcedureRun.Id) {
                $checklist | Add-Member -MemberType 'NoteProperty' -Name 'HuduProcedureRun' -Value $newProcedureRun -Force
                Write-Host "Started Hudu process run $($newProcedureRun.Id) from procedure $($newProcedure.Id)"

                if ($TaskRunFieldRequests.Count -gt 0 -and $GetHuduProcedureTasksCommand -and $SetHuduProcedureTaskCommand) {
                    try {
                        $HuduProcedureRunTasks = @(Get-HuduProcedureTasks -ProcedureId $newProcedureRun.Id)
                    } catch {
                        Write-Host "Error retrieving Hudu process run tasks for checklist $($checklist.id): $_"
                    }

                    foreach ($runFieldRequest in $TaskRunFieldRequests) {
                        $matchedRunTask = $null
                        if ($runFieldRequest.Position) {
                            $matchedRunTask = $HuduProcedureRunTasks | Where-Object { [string]$_.position -eq [string]$runFieldRequest.Position } | Select-Object -First 1
                        }
                        if (-not $matchedRunTask) {
                            $matchedRunTask = $HuduProcedureRunTasks | Where-Object { $_.name -eq $runFieldRequest.Name } | Select-Object -First 1
                        }

                        if ($matchedRunTask -and $matchedRunTask.Id) {
                            $SetTaskRequest = @{
                                Id = $matchedRunTask.Id
                                RunTask = $true
                            }
                            if ($runFieldRequest.AssignedUsers) { $SetTaskRequest['AssignedUsers'] = $runFieldRequest.AssignedUsers }
                            if ($runFieldRequest.DueDate) { $SetTaskRequest['DueDate'] = $runFieldRequest.DueDate }
                            if ($runFieldRequest.Priority) { $SetTaskRequest['Priority'] = $runFieldRequest.Priority }

                            try {
                                [void](Set-HuduProcedureTask @SetTaskRequest)
                                Write-Host "Updated Hudu process run task '$($runFieldRequest.Name)' with imported due date/assignee metadata."
                            } catch {
                                Write-Host "Error updating Hudu process run task '$($runFieldRequest.Name)': $_"
                            }
                        } else {
                            Write-Host "Could not match Hudu process run task '$($runFieldRequest.Name)' to apply due date/assignee metadata."
                        }
                    }
                } elseif ($TaskRunFieldRequests.Count -gt 0) {
                    Write-Host "Get-HuduProcedureTasks or Set-HuduProcedureTask was not found; due dates and assignees could not be applied to checklist $($checklist.id)."
                }
            } elseif ($hasRunMetadata) {
                Write-Host "Could not start a Hudu process run for checklist $($checklist.id); due dates and assignees may not be applied."
            }
        } elseif ((-not $isChecklistTemplate) -and $UsesHuduProcessRunModel -and $newProcedure.company_id -and $hasRunMetadata -and (-not $StartHuduProcedureIdParameter)) {
            Write-Host "Start-HuduProcedure with Id or ProcedureId support was not found; due dates and assignees will not be applied to checklist $($checklist.id)."
        }
        
        $checklist.HuduProcedure | Add-Member -MemberType 'NoteProperty' -Name 'HuduProcedureTasks' -Value $HuduProcedureTasks -Force
        if ($newProcedureRun -and $newProcedureRun.Id) {
            $checklist.HuduProcedureRun | Add-Member -MemberType 'NoteProperty' -Name 'HuduProcedureRunTasks' -Value $HuduProcedureRunTasks -Force
        }
        $MatchedChecklists+=$checklist
    }
}
$MatchedChecklists | ConvertTo-Json -Depth 99 | Out-File "$MigrationLogs\Checklists.json"

Write-Host "Procedures and tasks migrated"
