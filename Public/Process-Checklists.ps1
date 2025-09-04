$ITGLueChecklists = [System.Collections.ArrayList]@()

$HuduCompanies = $HuduCompanies ?? $(Get-HuduCompanies)

# Get Checklists/Items
$huduProcedures = Get-HuduProcedureTasks
$huduUsers      = Get-HuduUsers    
$ITGlueJWT = $ITGlueJWT ?? $(read-host "Please enter your ITGlue JWT as retrieved from browser.")
Clear-Host
Write-Host "Retrieving all checklists from ITGlue while we have JWT present."
$PageSize = 1000
$pageNum = 0
$results = @()
while ($true) {
    $checkListsResult = $(Get-ITGlueCheckLists -JWTAuthToken $ITGlueJWT -page_size $PageSize -page_number $PageNum).data
    Write-InspectObject -object $checkListsResult
    foreach ($r in $checkListsResult) {
        $checklistItems=$null
        try {
            $checklistItems=$(Get-ITGlueChecklistItems -JWTAuthToken $ITGlueJWT -filter_checklist_id $r.id)
            $r | Add-Member -MemberType 'NoteProperty' -Name 'ITGChecklistItems' -Value $checklistItems -Force
        }catch{
            Write-host "Error getting checklist items $_"
        }
        write-host "$($r)"
        $ITGLueChecklists.Add($r)
    }
    $checkListsResult | ConvertTo-Json -depth 90 | Out-File "checklists.json"
    $PageNum = $pageNum +1
    if (-not $checkListsResult -or $checkListsResult.count -lt $PageSize) {break}
}
Write-Host "Got $($ITGLueChecklists.count) checklists with $($checklistsResult.ITGChecklistItems.count) Checklist Items."


# Match/Add Checklists/Items
$ChecklistIDX=0
foreach ($checklist in $ITGLueChecklists) {
    $ChecklistIDX=$ChecklistIDX+1
    $HuduTasks = @()
    Write-Host "Matching/Adding checklist $ChecklistIDX of $($ITGLueChecklists.count)"
    $matchedCompany = $MatchedCompanies | Where-Object {[int]$checklist.attributes.'organization-id' -eq [int]$_.ITGID} | Select-Object -First 1

    if (-not $matchedCompany){
        $matchedCompany = $(Select-ObjectFromList -objects $HuduCompanies -message "Which company to attribute checklist, named $($checklist.attributes.name), was for org $($checklist.attributes.'organization-name') to? $($($checklist | ConvertTo-Json).ToString())" -allowNull $true)
    }
    if (-not $matchedCompany){
        write-host "you hadnt selected a company for this checklist / procedure, so it will be imported as global."
    }
    $procedureRequest = @{
        Name = $($checklist.attributes.name ?? "Unnamed Procedure")
    }
    if ($matchedCompany -and $matchedCompany.HuduID -and $matchedCompany.HuduID -gt 0){
        $procedureRequest["CompanyID"] = $matchedCompany.HuduID
    } else {
        Write-InspectObject -object $matchedCompany; continue
    }
    if ($checklist.description){
        $procedureRequest["Description"] = $($checklist.description ?? "No description found for procedure at <a href='$($checklist.attribures.'resource-url')'>itglue checklist url</a>")
    }
    Write-InspectObject -object $procedureRequest
    try {
        $newProcedure = $(New-HuduProcedure @procedureRequest).procedure
    } catch {
        Write-Host "Error creating procedure in Hudu $_"
    }
    if ($newProcedure -and $newProcedure.Id) {
        $TaskIDX=0
        $checklist | Add-Member -MemberType 'NoteProperty' -Name 'HuduProcedure' -Value $newProcedure -Force

        foreach ($task in $checklist.ITGChecklistItems){
            $TaskIDx=$TaskIDX+1
            Write-Host "Adding checklist task named $($task.attributes.name), $($TaskIDX) of $($checklist.ITGChecklistItems.count) for checklist $ChecklistIDX of $($ITGLueChecklists.count)"
            $NewChecklistTask=$null
            $DueDate = $null
            $assignedUser = $null
            $priority="unsure"

            $NewTaskRequest = @{
                ProcedureId = $newProcedure.id 
                Name = $(
                    $newProcedure.name ??
                    ("Task #$($task.attributes.order)" ?? "Unnamed Task")
                )
                Description = $($task.attributes.description ?? "Imported from ITglue with no description") 
                AssignedUsers = @()                  
            }
            if ($task.attributes.order) {
                $NewTaskRequest["Position"]=$task.attributes.order
            }
            if ($task.attributes.'assignee-name') {
                $firstName, $lastName = $task.attributes.'assignee-name' -split '\s+', 2
                $assignedUser = $huduusers | Where-Object {$_.first_name -like "*$firstName*" -and $_.last_name -like "*$lastName*"} | Select-Object -First 1
            }
            if ($assignedUser) {
                $NewTaskRequest["AssignedUsers"]+=$assignedUser.id
            }
            if ($task.attriburtes.'due-date'){
                $dueDate=([datetime]"$($task.attriburtes.'due-date')").ToString('yyyy-MM-dd')
            }
            if ($dueDate) {
                $NewTaskRequest["DueDate"]+=$dueDate
                if ($([datetime]$DueDate -gt $(Get-Date))){
                    $priority = "urgent"
                } elseif ($([datetime]$DueDate -gt $(Get-Date).AddDays(-14))){
                    $priority = "high"
                } else {
                    $priority = "normal"
                }
                Write-Host "Due date is $dueDate, and urgency is $priority"
            } else {
                Write-Host "no Due Date, assuming priority of $priority"
            }
            
            $NewTaskRequest["Priority"]=$priority

            try {
                $NewChecklistTask=New-HuduProcedureTask @NewTaskRequest
            }catch {
                Write-Host "Error adding checklist $_"
            }
            if ($NewChecklistTask) {
                $HuduTasks+=$NewChecklistTask
            }

        }
        $checklist.HuduProcedure | Add-Member -MemberType 'NoteProperty' -Name 'procedure_tasks_attributes' -Value $HuduTasks -Force

    } else {
        Write-host "Unable to create procedure $ChecklistIDX of $($ITGLueChecklists.count)"
    }
}
Write-Host "Proceduires and tasks migrated"
$ITGLueChecklists | ConvertTo-Json -depth 90 | Out-File "completed-checklists.json"
