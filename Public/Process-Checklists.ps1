
$HuduCompanies  = $HuduCompanies ?? $(Get-HuduCompanies)
$huduUsers      = $huduUsers ?? $(Get-HuduUsers)    
$userIndex = @{}
foreach ($u in $huduUsers) {$key = "$($u.first_name) $($u.last_name)".ToLower(); $userIndex[$key] = $u;}


$ITGlueJWT = $ITGlueJWT ?? $(read-host "Please enter your ITGlue JWT as retrieved from browser.")
Clear-Host

while ($true){
    Write-Host "Testing provided JWT"
    try {
        Get-ITGlueCheckLists -JWTAuthToken $ITGlueJWT -page_size $PageSize -page_number $PageNum
        break
    } catch {
        Write-Host "Issue getting checklists. $_; Re-enter a fresh JWT if possible or enter 0 to cancel checklists"
        $ITGlueJWT = $(read-host "Please enter your ITGlue JWT as retrieved from browser.")
        Clear-Host
        if ("$ITGlueJWT".Trim() -eq "0"){break}

    }
}

Write-Host "Retrieving all checklists from ITGlue"
$PageSize = 1000
$PageNum = 0
while ($true) {
    $checkListsResult = $(Get-ITGlueCheckLists -JWTAuthToken $ITGlueJWT -page_size $PageSize -page_number $PageNum).data
    foreach ($checklistEntry in $checkListsResult) {
        $ITGChecklistItems=$null
        $checklistEntry | Add-Member -MemberType 'NoteProperty' -Name 'IsTemplate' -Value $false -Force
        try {
            $ITGChecklistItems=$(Get-ITGlueChecklistItems -JWTAuthToken $ITGlueJWT -filter_checklist_id $checklistEntry.id)
            $checklistEntry | Add-Member -MemberType 'NoteProperty' -Name 'ITGChecklistItems' -Value $ITGChecklistItems -Force
        }catch{
            Write-host "Error getting checklist items $_"
        }
        $ITGLueChecklists.Add($checklistEntry)
    }
    $PageNum = $PageNum +1
    if (-not $checkListsResult -or $checkListsResult.count -lt $PageSize) {break}
}
$PageNum = 0
Write-Host "Retrieving all checklist templates from ITGlue"
while ($true) {
    $checkListsResult = $(Get-ITGlueChecklistTemplates -JWTAuthToken $ITGlueJWT -page_size $PageSize -page_number $PageNum).data
    foreach ($checklistTemplate in $checkListsResult) {
        $ITGChecklistItems=$null
        $checklistTemplate | Add-Member -MemberType 'NoteProperty' -Name 'IsTemplate' -Value $true -Force
        try {
            $ITGChecklistItems=$(Get-ITGlueChecklistItems -JWTAuthToken $ITGlueJWT -filter_checklist_id $checklistTemplate.id)
            $checklistTemplate | Add-Member -MemberType 'NoteProperty' -Name 'ITGChecklistItems' -Value $ITGChecklistItems -Force
        }catch{
            Write-host "Error getting checklist template items $_"
        }
        $ITGLueChecklists.Add($checklistTemplate)
    }
    $PageNum = $PageNum +1
    if (-not $checkListsResult -or $checkListsResult.count -lt $PageSize) {break}
}
Write-Host "Got $($($ITGLueChecklists | where-object {$_.IsTemplate -eq $false}).count) and $($($ITGLueChecklists | where-object {$_.IsTemplate -eq $true}).count) checklist templates with $($checklistsResult.ITGChecklistItems.count) Checklist Items."
$MatchedChecklists = $MatchedChecklists ?? @()
# Match/Add Checklists/Items
$ChecklistIDX=0
foreach ($checklist in $ITGLueChecklists) {
    $ChecklistIDX=$ChecklistIDX+1

    $HuduProcedureTasks = @()
    $procedureRequest = @{
        Name = ($checklist.attributes.name ?? 'Unnamed Procedure') 
        CompanyTemplate = $checklist.IsTemplate
        Description =  $($($checklist.attributes.description ?? "No description found for procedure.") + "`n" + 
            "Imported from ITGlue. <a href='$($checklist.attributes.'resource-url')'>itglue checklist url</a>")
    }
    
    $matchedCompany = $($($MatchedCompanies | Where-Object {[int]$checklist.attributes.'organization-id' -eq [int]$_.ITGID} | Select-Object -First 1) ??
                        $(Select-ObjectFromList -objects $HuduCompanies -message "Which company to attribute checklist, named $($checklist.attributes.name), was for org $($checklist.attributes.'organization-name') to? $($($checklist | ConvertTo-Json).ToString())" -allowNull $true))

    if ($matchedCompany -and $matchedCompany.HuduID -and $matchedCompany.HuduID -gt 0){
        $procedureRequest["CompanyID"] = $matchedCompany.HuduID
    }

    try {
        $newProcedure = $(New-HuduProcedure @procedureRequest).procedure
    } catch {
        Write-Host "Error creating procedure in Hudu $_"
        continue
    }

    if ($newProcedure -and $newProcedure.Id) {
        $checklist | Add-Member -MemberType 'NoteProperty' -Name 'HuduProcedure' -Value $newProcedure -Force
        Write-Host "Created $(if (-not $newProcedure.company_id) {'Global'} else {'Company'}) Procedure $(if ($true -eq $checklist.IsTemplate) {'Template'}) $($ChecklistIDX) of $($ITGLueChecklists.count)"

        $TaskIDX=0
        foreach ($task in $checklist.ITGChecklistItems){
            $TaskIDX=$TaskIDX+1

            $NewProcedureTask=$null
            $DueDate = $null
            $assigneeCandidates = @($checklist.attributes.'assignee-name',$task.attributes.'assignee-name') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }            
            $priority="unsure"

            $NewTaskRequest = @{
                ProcedureId = $newProcedure.id 
                Name = ($task.attributes.name ??
                    ("Task #$($task.attributes.order)" ?? "Unnamed Task"))
                Description = $($task.attributes.description ?? "Imported from ITglue with no description") 
                AssignedUsers = @()                  
            }
            if ($task.attributes.order) {
                $NewTaskRequest["Position"]=$task.attributes.order
            }
            
            foreach ($a in $assigneeCandidates) {
                $first,$last = ($a -replace '\s+', ' ').Trim() -split '\s+', 2
                if ($last) {
                    $key = "$first $last".ToLower()
                    if ($userIndex.ContainsKey($key)) {
                        $NewTaskRequest['AssignedUsers'] += $userIndex[$key].id
                    }
                }
            }
            if ($task.attributes.'due-date') {
                $dueDate = [datetime]$task.attributes.'due-date'
                $NewTaskRequest['DueDate'] = $dueDate.ToString('yyyy-MM-dd')
                $age = (Get-Date) - $dueDate
                $priority = if ($age.TotalDays -lt 0)      { 'urgent' }
                            elseif ($age.TotalDays -le 14) { 'high' }
                            else                           { 'normal' }
            } else { $priority = 'unsure' }
            $NewTaskRequest['Priority'] = $priority

            try {
                $NewProcedureTask=New-HuduProcedureTask @NewTaskRequest
            }catch {
                Write-Host "Error adding checklist $_"
            }
            if ($NewProcedureTask) {
                Write-Host "Added $(if ($NewTaskRequest.AssignedUsers.count -gt 0) {'User-Assigned'} else {'Unassigned'}) procedure task $($TaskIDX) of $($checklist.ITGChecklistItems.count)"
                $HuduProcedureTasks+=$NewProcedureTask
            }
        }
        $checklist.HuduProcedure | Add-Member -MemberType 'NoteProperty' -Name 'HuduProcedureTasks' -Value $HuduProcedureTasks -Force
        $MatchedChecklists+=$checklist
    }
}

Write-Host "Proceduires and tasks migrated"
