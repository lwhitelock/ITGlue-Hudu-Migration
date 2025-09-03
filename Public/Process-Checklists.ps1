$ITGLueChecklists = [System.Collections.ArrayList]@()

$HuduCompanies = $HuduCompanies ?? $(Get-HuduCompanies)

if ($true -eq $ImportChecklists) {
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
    Write-Host "Got $($ITGLueChecklists.count) checklists with $($checklistsResult.ChecklistItems.count) Checklist Items."
    # Match/Add Checklists/Items
    $ChecklistIDX=0
    foreach ($checklist in $ITGLueChecklists) {
        $ChecklistIDX=$ChecklistIDX+1
        $huduChecklistItems = @()
        Write-Host "Matching/Adding checklist $ChecklistIDX of $($ITGLueChecklists.count)"
        $matchedCompany = $MatchedCompanies | Where-Object {[int]$checklist.attributes.'organization-id' -eq [int]$_.ITGID} | Select-Object -First 1

        if (-not $matchedCompany){
            $matchedCompany = $(Select-ObjectFromList -objects $HuduCompanies -message "Which company to attribute checklist, named $($checklist.attributes.name), was for org $($checklist.attributes.'organization-name') to? $($($checklist | ConvertTo-Json).ToString())" -allowNull $true)
        }

        write-host "Matched company $($matchedCompany.CompanyName) / $($matchedCompany.HuduID)"
        $procedureRequest = @{
            Name = $($checklist.attributes.name ?? "Unnamed Procedure")
        }
        if ($matchedCompany -and $matchedCompany.HuduID -and $matchedCompany.HuduID -gt 0){
            $procedureRequest["CompanyID"] = $matchedCompany.HuduID
        } else {
            Write-InspectObject -object $matchedCompany; continue
        }
        if ($checklist.description){
            $procedureRequest["Description"] = $checklist.description
        }
        Write-InspectObject -object $procedureRequest
        read-host
        $newProcedure = New-HuduProcedure @procedureRequest
        if ($newProcedure -and $newProcedure.Id) {
            $TaskIDX=0
            foreach ($task in $checklist.ITGChecklistItems){
                $TaskIDx=$TaskIDX+1
                Write-Host "Adding checklist task, $($task.attributes.name), $($TaskIDX) of $($checklist.ChecklistItems.count) for checklist $ChecklistIDX of $($ITGLueChecklists.count), $($checklist.attributes.name)"
                $NewChecklistItem=$null
                try {


                }catch {
                    Write-Host "Error adding checklist task $($task.attributes.name), $($TaskIDX) of $($checklist.ChecklistItems.count) for checklist $ChecklistIDX of $($ITGLueChecklists.count), $($checklist.attributes.name); $_"
                }

                $huduChecklistItems+=

            }
            $checklist | Add-Member -MemberType 'NoteProperty' -Name 'HuduChecklistItems' -Value $checklistItems -Force


        }



    }
}
