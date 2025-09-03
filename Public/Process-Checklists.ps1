$ITGLueChecklists = [System.Collections.ArrayList]@()


if ($true -eq $ImportChecklists) {
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
                $r | Add-Member -MemberType 'NoteProperty' -Name 'CheckListItems' -Value $checklistItems -Force
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
    Write-Host "Got $($ITGLueChecklists.count) checklists"
}

$huduProcedures = Get-HuduProcedureTasks
$huduUsers      = Get-HuduUsers

foreach ($checklist in $ITGLueChecklists) {
    $matchedCompany = $MatchedCompanies | Where-Object {[int]$checklist.attributes.'organization-id' -eq [int]$_.ITGID} | Select-Object -First 1

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



}