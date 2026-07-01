
function Get-RelatedToDoc {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ITGKey,

        [Parameter(Mandatory = $true)]
        [long]$OrganizationId,

        [Parameter(Mandatory = $true)]
        [long]$DocID,

        [string]$ITGlue_Base_URI = 'https://api.itglue.com'
    )

    if ($OrganizationId -le 0 -or $DocID -le 0) {
        Write-Warning "Skipping ITGlue document lookup because doc/org id is invalid. DocID=$DocID OrganizationId=$OrganizationId"
        return
    }

    $headers = @{
        'x-api-key'    = $ITGKey
        'Content-Type' = 'application/vnd.api+json'
    }

    $baseUri = $ITGlue_Base_URI.TrimEnd('/')
    $candidateUris = @(
        "$baseUri/organizations/$OrganizationId/relationships/documents/$DocID?include=related_items",
        "$baseUri/organizations/$OrganizationId/documents/$DocID?include=related_items",
        "$baseUri/documents/$DocID?include=related_items",
        "$baseUri/organizations/$OrganizationId/relationships/documents/$DocID"
    ) | Select-Object -Unique

    $LastError = $null
    foreach ($uri in $candidateUris) {
        try {
            $Response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
            if ($Response) {
                return $Response
            }
        }
        catch {
            $LastError = $_
        }
    }

    Write-Warning "Failed to retrieve ITGlue document $DocID for organization $OrganizationId"
    if ($LastError) {
        if ($LastError.ErrorDetails.Message) {
            Write-Warning $LastError.ErrorDetails.Message
        } else {
            Write-Warning $LastError.Exception.Message
        }
    }
}
function Add-UnknownITGlueRelationType {
    param(
        [string]$TypeName
    )

    $TypeName = [string]($TypeName ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($TypeName)) {
        return
    }

    if (-not $script:UnknownITGlueRelationTypeCounts) {
        $script:UnknownITGlueRelationTypeCounts = @{}
    }

    if ($script:UnknownITGlueRelationTypeCounts.ContainsKey($TypeName)) {
        $script:UnknownITGlueRelationTypeCounts[$TypeName]++
        return
    }

    $script:UnknownITGlueRelationTypeCounts[$TypeName] = 1
    Write-Warning "Encountered unsupported ITGlue relation type '$TypeName'"
}
function Add-UnresolvedITGlueRelationSample {
    param(
        [string]$TypeName,
        [string]$Reason,
        $RelationObject
    )

    if (-not $settings -or -not $settings.MigrationLogs) {
        return
    }

    $TypeName = [string]($TypeName ?? 'unknown')
    if (-not $script:UnresolvedITGlueRelationSamples) {
        $script:UnresolvedITGlueRelationSamples = [System.Collections.ArrayList]@()
        $script:UnresolvedITGlueRelationSampleCounts = @{}
    }

    $CurrentCount = [int]($script:UnresolvedITGlueRelationSampleCounts[$TypeName] ?? 0)
    if ($CurrentCount -ge 5) {
        return
    }

    $script:UnresolvedITGlueRelationSampleCounts[$TypeName] = $CurrentCount + 1
    [void]$script:UnresolvedITGlueRelationSamples.Add([pscustomobject]@{
        TypeName = $TypeName
        Reason   = $Reason
        Sample   = $RelationObject
    })

    $script:UnresolvedITGlueRelationSamples |
        ConvertTo-Json -Depth 20 |
        Out-File (Join-Path $settings.MigrationLogs 'unresolved-relation-samples.json')
}
function Convert-ITGlueTypeToRelationAssetType {
    param(
        [string]$TypeName
    )

    switch -Regex (($TypeName ?? '').Trim().ToLower()) {
        '^flexible[-_\s]?assets?$' { return 'flexible_asset' }
        '^configurations?$' { return 'configuration' }
        '^passwords?$' { return 'password' }
        '^documents?$' { return 'document' }
        '^document[/\\]folders?$' { return 'document_folder' }
        '^document[-_\s]?folders?$' { return 'document_folder' }
        '^article[-_\s]?folders?$' { return 'document_folder' }
        '^checklists?$' { return 'checklist' }
        '^checklist[-_\s]?templates?$' { return 'checklist_template' }
        '^tags?$' { return $null }
        '^contacts?$' { return 'contact' }
        '^locations?$' { return 'location' }
        '^organizations?$' { return 'organization' }
        '^companies$' { return 'organization' }
        '^domains?$' { return 'domain' }
        '^websites?$' { return 'domain' }
        default {
            Add-UnknownITGlueRelationType -TypeName $TypeName
            return $null
        }
    }
}
function Convert-ITGlueTagSubTypeToRelationAssetType {
    param(
        [string]$SubType
    )

    switch -Regex (($SubType ?? '').Trim()) {
        '^Configurations$' { return 'configuration' }
        '^Contacts$' { return 'contact' }
        '^Documents$' { return 'document' }
        '^Document[-_\s]?Folders$' { return 'document_folder' }
        '^Domains$' { return 'domain' }
        '^Websites$' { return 'domain' }
        '^Passwords$' { return 'password' }
        '^Organizations$' { return 'organization' }
        '^Companies$' { return 'organization' }
        '^Locations$' { return 'location' }
        '^FlexibleAssetType$' { return 'flexible_asset' }
        '^Flexible[-_\s]?Assets?$' { return 'flexible_asset' }
        '^Checklists$' { return 'checklist' }
        '^Checklist[-_\s]?Templates$' { return 'checklist_template' }
        default { return $null }
    }
}
function Get-NormalizedRelationLookupName {
    param(
        [string]$Name
    )

    $Name = [string]($Name ?? '').Trim()
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    return ($Name -replace '\s+', ' ').ToLowerInvariant()
}
function Resolve-ITGlueRelationReference {
    param(
        $ITGlueRelationObject
    )

    if (-not $ITGlueRelationObject) {
        return $null
    }

    $AssetType = $null
    $ResourceId = $null
    $ResourceName = $null

    if ($ITGlueRelationObject.type -match '^related[-_]?items?$') {
        $AssetType = Convert-ITGlueTypeToRelationAssetType -TypeName (
            $ITGlueRelationObject.attributes.'destination_type' ??
            $ITGlueRelationObject.attributes.'destination-type' ??
            $ITGlueRelationObject.attributes.'asset-type' ??
            $ITGlueRelationObject.attributes.'resource-type'
        )

        $ResourceId = (
            $ITGlueRelationObject.attributes.'destination_id' ??
            $ITGlueRelationObject.attributes.'destination-id' ??
            $ITGlueRelationObject.attributes.'resource-id'
        )

        $ResourceName = $ITGlueRelationObject.attributes.'name'
    } elseif ($ITGlueRelationObject.type -eq 'tag') {
        $AssetType = Convert-ITGlueTypeToRelationAssetType -TypeName (
            $ITGlueRelationObject.attributes.'destination_type' ??
            $ITGlueRelationObject.attributes.'destination-type' ??
            $ITGlueRelationObject.attributes.'tag-type' ??
            $ITGlueRelationObject.attributes.'taggable-type' ??
            $ITGlueRelationObject.attributes.'resource-type' ??
            $ITGlueRelationObject.attributes.'asset-type'
        )

        $ResourceId = (
            $ITGlueRelationObject.attributes.'destination_id' ??
            $ITGlueRelationObject.attributes.'destination-id' ??
            $ITGlueRelationObject.attributes.'tag-id' ??
            $ITGlueRelationObject.attributes.'taggable-id' ??
            $ITGlueRelationObject.attributes.'resource-id'
        )

        $ResourceName = $ITGlueRelationObject.attributes.'name'
    } elseif ($ITGlueRelationObject.attributes.'asset-type' -and $ITGlueRelationObject.attributes.'resource-id') {
        $AssetType = Convert-ITGlueTypeToRelationAssetType -TypeName $ITGlueRelationObject.attributes.'asset-type'
        $ResourceId = $ITGlueRelationObject.attributes.'resource-id'
        $ResourceName = $ITGlueRelationObject.attributes.'name'
    } elseif ($ITGlueRelationObject.attributes.'destination_type' -and $ITGlueRelationObject.attributes.'destination_id') {
        $AssetType = Convert-ITGlueTypeToRelationAssetType -TypeName $ITGlueRelationObject.attributes.'destination_type'
        $ResourceId = $ITGlueRelationObject.attributes.'destination_id'
        $ResourceName = $ITGlueRelationObject.attributes.'name'
    } elseif ($ITGlueRelationObject.type -and $ITGlueRelationObject.id) {
        $AssetType = Convert-ITGlueTypeToRelationAssetType -TypeName $ITGlueRelationObject.type
        $ResourceId = $ITGlueRelationObject.id
        $ResourceName = $ITGlueRelationObject.attributes.'name'
    } else {
        $ITGlueRelationObject | convertto-json -Depth 10 | out-file (Join-Path $settings.MigrationLogs "unresolved-relation-$($ITGlueRelationObject.GetHashCode()).json")
    }

    if (-not $AssetType -or -not $ResourceId) {
        Add-UnresolvedITGlueRelationSample -TypeName $ITGlueRelationObject.type -Reason 'Could not resolve target type or id' -RelationObject $ITGlueRelationObject
        return $null
    }

    return [pscustomobject]@{
        AssetType  = $AssetType
        ResourceId = [string]$ResourceId
        Name       = [string]$ResourceName
    }
}
function Get-HuduIdFromItglueObject {
    param(
        $ITGObjectId,
        $AssetType
    )

    $ITGObjectId = [string]$ITGObjectId
    $FoundHuduObject = $null
    $FoundHuduAssetType = $null

    switch ($AssetType) {
        'configuration' {
            $FoundHuduObject = $MatchedConfigurationMap[$ITGObjectId].HuduObject
            $FoundHuduAssetType = "Asset"
        }
        'document' {
            $FoundHuduObject = $MatchedArticleMap[$ITGObjectId].HuduObject
            $FoundHuduAssetType = 'Article'
        }
        'document_folder' {
            $FoundHuduObject = $MatchedArticleDocumentFolderMap[$ITGObjectId].HuduObject
            $FoundHuduAssetType = 'Article'
        }
        'contact' {
            $FoundHuduObject = $MatchedContactMap[$ITGObjectId].HuduObject
            $FoundHuduAssetType = 'Asset'
        }
        'flexible_asset' {
            $FoundHuduObject = $MatchedAssetMap[$ITGObjectId].HuduObject
            $FoundHuduAssetType = "Asset"
        }
        'location' {
            $FoundHuduObject = $MatchedLocationMap[$ITGObjectId].HuduObject
            $FoundHuduAssetType = "Asset"
        }
        'password' {
            $FoundHuduObject = $MatchedPasswordMap[$ITGObjectId].HuduObject
            $FoundHuduAssetType = 'AssetPassword'
        }
        'organization' {
            $FoundHuduObject = $MatchedCompanyMap[$ITGObjectId].HuduCompanyObject
            $FoundHuduAssetType = 'Company'
        }
        'domain' {
            $FoundHuduObject = $MatchedWebsiteMap[$ITGObjectId].HuduObject
            $FoundHuduAssetType = 'Website'
        }
        'checklist' {
            $FoundHuduObject = $MatchedChecklistsMap[$ITGObjectId].HuduProcedure
            $FoundHuduAssetType = 'Procedure'
        }
        'checklist_template' {
            $FoundHuduObject = $MatchedChecklistsMap[$ITGObjectId].HuduProcedure
            $FoundHuduAssetType = 'Procedure'
        }
                
    }

    if ($FoundHuduObject) {
        return [pscustomobject]@{
            HuduObject = $FoundHuduObject
            Type       = $FoundHuduAssetType
        }
    }
    else {
        Write-Warning "Unable to match ITGlue $AssetType to Hudu object for ITG object $ITGObjectId"
    }
}
function Get-HuduItemsFromItglueObject {
    param(
        $ITGObjectId,
        $AssetType,
        $RelationReference
    )

    $ITGObjectId = [string]$ITGObjectId

    if ($AssetType -eq 'document_folder') {
        $FolderArticles = @($MatchedArticleDocumentFolderMap[$ITGObjectId])
        if ($FolderArticles.Count -gt 0) {
            return $FolderArticles | ForEach-Object {
                [pscustomobject]@{
                    HuduObject = $_.HuduObject
                    Type       = 'Article'
                }
            }
        }

        Write-Warning "Unable to match ITGlue document folder to child Hudu articles for ITG folder $ITGObjectId"
        return
    }

    if ($AssetType -eq 'checklist_template') {
        $DirectTemplateObject = $MatchedChecklistsMap[$ITGObjectId].HuduProcedure
        if ($DirectTemplateObject) {
            return [pscustomobject]@{
                HuduObject = $DirectTemplateObject
                Type       = 'Procedure'
            }
        }

        $TemplateNameKey = Get-NormalizedRelationLookupName -Name $RelationReference.Name
        if ($TemplateNameKey) {
            $TemplateNameMatches = @($MatchedChecklistsByNameMap[$TemplateNameKey])
            if ($TemplateNameMatches.Count -eq 1) {
                return [pscustomobject]@{
                    HuduObject = $TemplateNameMatches[0].HuduProcedure
                    Type       = 'Procedure'
                }
            }

            if ($TemplateNameMatches.Count -gt 1) {
                Write-Warning "Unable to match ITGlue checklist_template $ITGObjectId by name '$($RelationReference.Name)' because multiple migrated procedures have that name"
                return
            }
        }
    }

    $MatchedItem = Get-HuduIdFromItglueObject -ITGObjectId $ITGObjectId -AssetType $AssetType
    if ($MatchedItem) {
        return $MatchedItem
    }
}
function Get-SingleRelationValue {
    param(
        $Value,
        [string]$Label
    )

    $Values = @($Value | Where-Object { $null -ne $_ -and "$_".Trim() -ne '' } | Select-Object -Unique)
    if ($Values.Count -eq 1) {
        return $Values[0]
    }

    if ($Values.Count -gt 1) {
        Write-Warning "Skipping relation because $Label resolved to multiple values: $($Values -join ', ')"
    }

    return $null
}
function Get-ITGlueDocumentFolderId {
    param(
        $Article,
        $ITGlueDocumentResponse
    )

    $FolderId = Get-SingleRelationValue -Value @(
        $Article.ITGObject.attributes.'document-folder-id'
        $Article.ITGObject.attributes.'document_folder_id'
        $ITGlueDocumentResponse.data.attributes.'document-folder-id'
        $ITGlueDocumentResponse.data.attributes.'document_folder_id'
    ) -Label 'Document folder ITGID'

    if ($FolderId) {
        return [string]$FolderId
    }
}
function Get-ArticleLookupInfo {
    param(
        $Article
    )

    $ResolvedDocId = Get-SingleRelationValue -Value @(
        $Article.ITGID
        $Article.ITGObject.id
    ) -Label 'Document ITGID'

    $ResolvedOrganizationId = Get-SingleRelationValue -Value @(
        $Article.Company.ITGID
        $Article.Company.ITGCompanyObject.id
        $Article.ITGObject.attributes.'organization-id'
    ) -Label 'Document OrganizationId'

    if (-not $ResolvedDocId -or -not $ResolvedOrganizationId) {
        return $null
    }

    return [pscustomobject]@{
        DocID          = [long]$ResolvedDocId
        OrganizationId = [long]$ResolvedOrganizationId
    }
}
function Test-ITGlueResponseHasRelationData {
    param(
        $Response
    )

    if (-not $Response) {
        return $false
    }

    if (@($Response.included).Count -gt 0) {
        return $true
    }

    if (@($($Response.data.relationships.'related-items' ?? $Response.data.relationships.'related-item').data).Count -gt 0) {
        return $true
    }

    return $false
}
function Test-ITGlueRelationPointerOnly {
    param(
        $ITGlueRelationObject
    )

    if (-not $ITGlueRelationObject) {
        return $false
    }

    if ($ITGlueRelationObject.attributes) {
        return $false
    }

    return [bool]($ITGlueRelationObject.id -and $ITGlueRelationObject.type -match '^(related[-_]?items?|tags?)$')
}
function Get-PasswordDocumentLookupInfo {
    param(
        $Password
    )

    if (-not $Password -or -not $Password.ITGObject) {
        return $null
    }

    $ParentUrl = [string]$Password.ITGObject.attributes.'parent-url'
    $ResourceType = [string]$Password.ITGObject.attributes.'resource-type'
    $ResourceId = Get-SingleRelationValue -Value @(
        $Password.ITGObject.attributes.'resource-id'
        if ($ParentUrl -match '/docs/(\d+)') { $Matches[1] }
    ) -Label 'Password Document ITGID'

    if (-not $ResourceId) {
        return $null
    }

    if (($ResourceType -and $ResourceType -notmatch '^documents?$') -and ($ParentUrl -notmatch '/docs/')) {
        return $null
    }

    return [pscustomobject]@{
        PasswordItgId = [string]$Password.ITGID
        DocumentItgId = [string]$ResourceId
    }
}
function New-HuduRelationPair {
    param(
        [string]$LeftType,
        [int]$LeftId,
        [string]$RightType,
        [int]$RightId
    )

    @(
        [pscustomobject]@{
            FromableType = $LeftType
            FromableID   = $LeftId
            ToableType   = $RightType
            ToableID     = $RightId
        }
        [pscustomobject]@{
            FromableType = $RightType
            FromableID   = $RightId
            ToableType   = $LeftType
            ToableID     = $LeftId
        }
    )
}
function Get-HuduRelationObject {
    param(
        $ITGlueSourceObjects
    )

    $NewHuduRelations = foreach ($ITGlueSourceObject in $ITGlueSourceObjects) {
        $AssetType = Convert-ITGlueTypeToRelationAssetType -TypeName $ITGlueSourceObject.data.type
        if (-not $AssetType) { continue }

        $FromableHudu = Get-HuduIdFromItglueObject -AssetType $AssetType -ITGObjectId $ITGlueSourceObject.data.id
        if (-not $FromableHudu) { continue }

        Write-Host "Determining Hudu objects for source $AssetType / ITGID: $($ITGlueSourceObject.data.id)" -ForegroundColor Cyan

        foreach ($LinkedITGlueObject in @($ITGlueSourceObject.included) + @($ITGlueSourceObject.data.relationships.'related-items'.data)) {
            if (Test-ITGlueRelationPointerOnly -ITGlueRelationObject $LinkedITGlueObject) { continue }

            $LinkedReference = Resolve-ITGlueRelationReference -ITGlueRelationObject $LinkedITGlueObject
            if (-not $LinkedReference) { continue }

            foreach ($LinkedHuduItem in @(Get-HuduItemsFromItglueObject -AssetType $LinkedReference.AssetType -ITGObjectId $LinkedReference.ResourceId -RelationReference $LinkedReference)) {
                $FromableType = Get-SingleRelationValue -Value $FromableHudu.type -Label 'FromableType'
                $FromableID = Get-SingleRelationValue -Value $FromableHudu.HuduObject.id -Label 'FromableID'
                $ToableType = Get-SingleRelationValue -Value $LinkedHuduItem.type -Label 'ToableType'
                $ToableID = Get-SingleRelationValue -Value $LinkedHuduItem.HuduObject.id -Label 'ToableID'

                if (-not $FromableType -or -not $FromableID -or -not $ToableType -or -not $ToableID) {
                    continue
                }

                [pscustomobject]@{
                    FromableType = [string]$FromableType
                    FromableID   = [int]$FromableID
                    ToableType   = [string]$ToableType
                    ToableID     = [int]$ToableID
                }
            }
        }
    }

    return $NewHuduRelations
}
function Get-HuduRelationObjectFromTagFields {
    param(
        $MatchedAssets,
        $MatchedAssetLayoutFields
    )

    if (-not $MatchedAssetLayoutFields) {
        return
    }

    foreach ($UpdateAsset in $MatchedAssets) {
        if (-not $UpdateAsset.ITGObject.attributes.traits) { continue }

        $SourceHuduId = Get-SingleRelationValue -Value @(
            $UpdateAsset.HuduID
            $UpdateAsset.HuduObject.id
        ) -Label 'Tag source HuduID'

        if (-not $SourceHuduId) { continue }

        $traits = $UpdateAsset.ITGObject.attributes.traits
        foreach ($TraitProperty in $traits.PSObject.Properties) {
            $ITGParsed = $TraitProperty.Name
            $ITGValues = $TraitProperty.Value
            $field = $MatchedAssetLayoutFields | Where-Object {
                $_.IGLayoutID -eq $UpdateAsset.ITGObject.attributes.'flexible-asset-type-id' -and
                $_.ITGParsedName -eq $ITGParsed
            } | Select-Object -First 1

            if (-not $field -or $field.FieldType -ne 'Tag') { continue }

            $TargetAssetType = Convert-ITGlueTagSubTypeToRelationAssetType -SubType $field.FieldSubType
            if (-not $TargetAssetType) { continue }
            if ($TargetAssetType -eq 'domain' -and $true -ne $ImportDomains) {
                Write-Host "Skipping website/domain tag relations for $($field.FieldName) in $($UpdateAsset.Name) because website migration is disabled." -ForegroundColor Yellow
                continue
            }

            foreach ($TagValue in @($ITGValues.values)) {
                $TargetItgId = Get-SingleRelationValue -Value @(
                    $TagValue.id
                    $TagValue.'resource-id'
                    $TagValue.'resource_id'
                ) -Label "Tag target ITGID for $($field.FieldName)"

                if (-not $TargetItgId) { continue }

                $RelationReference = [pscustomobject]@{
                    AssetType  = $TargetAssetType
                    ResourceId = [string]$TargetItgId
                    Name       = [string]$TagValue.name
                }

                foreach ($LinkedHuduItem in @(Get-HuduItemsFromItglueObject -AssetType $TargetAssetType -ITGObjectId $TargetItgId -RelationReference $RelationReference)) {
                    $ToableType = Get-SingleRelationValue -Value $LinkedHuduItem.Type -Label 'Tag ToableType'
                    $ToableID = Get-SingleRelationValue -Value $LinkedHuduItem.HuduObject.id -Label 'Tag ToableID'
                    if (-not $ToableType -or -not $ToableID) { continue }

                    [pscustomobject]@{
                        FromableType = 'Asset'
                        FromableID   = [int]$SourceHuduId
                        ToableType   = [string]$ToableType
                        ToableID     = [int]$ToableID
                    }
                }
            }
        }
    }
}
function Convert-QueuedTagRelationToHuduRelationObject {
    param(
        $Relation
    )

    if (-not $Relation) { return }

    $SourceHuduId = Get-SingleRelationValue -Value $Relation.hudu_from_id -Label 'Queued tag source HuduID'
    if (-not $SourceHuduId) { return }

    $TargetAssetType = switch ($Relation.relation_type) {
        'Article' { 'document' }
        'AssetPassword' { 'password' }
        'Company' { 'organization' }
        'Website' { 'domain' }
        'Procedure' { 'checklist' }
        default { $null }
    }

    if (-not $TargetAssetType) { return }

    if ($Relation.relation_type -eq 'Procedure') {
        $ProcedureObject = $MatchedChecklistsMap[[string]$Relation.itg_to_id].HuduProcedure
        if ($ProcedureObject) {
            $LinkedHuduItem = [pscustomobject]@{
                HuduObject = $ProcedureObject
                Type       = 'Procedure'
            }
        }
    }
    else {
        $LinkedHuduItem = Get-HuduIdFromItglueObject -AssetType $TargetAssetType -ITGObjectId $Relation.itg_to_id
    }
    if (-not $LinkedHuduItem) { return }

    $ToableType = Get-SingleRelationValue -Value $LinkedHuduItem.Type -Label 'Queued tag ToableType'
    $ToableID = Get-SingleRelationValue -Value $LinkedHuduItem.HuduObject.id -Label 'Queued tag ToableID'
    if (-not $ToableType -or -not $ToableID) { return }

    [pscustomobject]@{
        FromableType = 'Asset'
        FromableID   = [int]$SourceHuduId
        ToableType   = [string]$ToableType
        ToableID     = [int]$ToableID
    }
}
function Get-PasswordDocumentRelationObject {
    param(
        $MatchedPasswords
    )

    foreach ($Password in $MatchedPasswords) {
        $Lookup = Get-PasswordDocumentLookupInfo -Password $Password
        if (-not $Lookup) { continue }

        if (-not $MatchedPasswordMap.ContainsKey($Lookup.PasswordItgId)) { continue }
        if (-not $MatchedArticleMap.ContainsKey($Lookup.DocumentItgId)) { continue }

        $PasswordHuduObject = $MatchedPasswordMap[$Lookup.PasswordItgId].HuduObject
        $DocumentHuduObject = $MatchedArticleMap[$Lookup.DocumentItgId].HuduObject
        if (-not $PasswordHuduObject -or -not $DocumentHuduObject) { continue }

        $PasswordType = Get-SingleRelationValue -Value 'AssetPassword' -Label 'PasswordType'
        $PasswordId = Get-SingleRelationValue -Value $PasswordHuduObject.id -Label 'PasswordID'
        $DocumentType = Get-SingleRelationValue -Value 'Article' -Label 'DocumentType'
        $DocumentId = Get-SingleRelationValue -Value $DocumentHuduObject.id -Label 'DocumentID'

        if (-not $PasswordType -or -not $PasswordId -or -not $DocumentType -or -not $DocumentId) {
            continue
        }

        New-HuduRelationPair -LeftType $PasswordType -LeftId ([int]$PasswordId) -RightType $DocumentType -RightId ([int]$DocumentId)
    }
}


if (-not $MatchedAssets -and (Test-Path -LiteralPath "$MigrationLogs\Assets.json")) {$MatchedAssets = (Get-Content -path "$MigrationLogs\Assets.json" | ConvertFrom-json -depth 100) }
if (-not $matchedConfigurations -and (Test-Path -LiteralPath "$MigrationLogs\Configurations.json")) {$matchedConfigurations = (Get-Content -path "$MigrationLogs\Configurations.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedPasswords -and (Test-Path -LiteralPath "$MigrationLogs\Passwords.json")) {$MatchedPasswords = (Get-Content -path "$MigrationLogs\Passwords.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedAssetPasswords -and (Test-Path -LiteralPath "$MigrationLogs\AssetPasswords.json")) {$MatchedAssetPasswords = (Get-Content -path "$MigrationLogs\AssetPasswords.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedContacts -and (Test-Path -LiteralPath "$MigrationLogs\Contacts.json")) {$MatchedContacts = (Get-Content -path "$MigrationLogs\Contacts.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedArticles -and (Test-Path -LiteralPath "$MigrationLogs\Articles.json")) {$MatchedArticles = (Get-Content -path "$MigrationLogs\Articles.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedCompanies -and (Test-Path -LiteralPath "$MigrationLogs\Companies.json")) {$MatchedCompanies = (Get-Content -path "$MigrationLogs\Companies.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedLocations -and (Test-Path -LiteralPath "$MigrationLogs\Locations.json")) {$MatchedLocations = (Get-Content -path "$MigrationLogs\Locations.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedPasswords -and (Test-Path -LiteralPath "$MigrationLogs\Passwords.json")) {$MatchedPasswords = (Get-Content -path "$MigrationLogs\Passwords.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedWebsites -and (Test-Path -LiteralPath "$MigrationLogs\websites.json")) {$MatchedWebsites = (Get-Content -path "$MigrationLogs\websites.json" | ConvertFrom-json -depth 100) }
if (-not $MatchedAssetLayoutFields -and (Test-Path -LiteralPath "$MigrationLogs\AssetLayoutsFields.json")) {$MatchedAssetLayoutFields = (Get-Content -path "$MigrationLogs\AssetLayoutsFields.json" | ConvertFrom-json -depth 100) }
if (-not $RelationsToCreate -and (Test-Path -LiteralPath "$MigrationLogs\RelationsToCreate.json")) {$RelationsToCreate = (Get-Content -path "$MigrationLogs\RelationsToCreate.json" | ConvertFrom-json -depth 100) }
if (-not $matchedChecklists -and (Test-Path -LiteralPath "$MigrationLogs\Checklists.json")) {$matchedChecklists = (Get-Content -path "$MigrationLogs\Checklists.json" | ConvertFrom-json -depth 100) }

$script:UnknownITGlueRelationTypeCounts = @{}
$script:UnresolvedITGlueRelationSamples = [System.Collections.ArrayList]@()
$script:UnresolvedITGlueRelationSampleCounts = @{}
foreach ($DiagnosticFileName in @('unknown-relation-types.json', 'unresolved-relation-samples.json')) {
    $DiagnosticFilePath = Join-Path $settings.MigrationLogs $DiagnosticFileName
    if (Test-Path -LiteralPath $DiagnosticFilePath) {
        Remove-Item -LiteralPath $DiagnosticFilePath -Force
    }
}

write-host "refreshing $($MatchedAssets.count) assets"
$FreshITGAssets= $FreshITGAssets ?? $($MatchedAssets |ForEach-Object { Get-ITGlueFlexibleAssets -id $_.ITGObject.id -include related_items})
$RelatedAssets = $RelatedAssets ?? $($FreshITGAssets | Where-Object { Test-ITGlueResponseHasRelationData -Response $_ })

write-host "refreshing $($MatchedConfigurations.count) configs"
$FreshConfigurations = $FreshConfigurations ?? $($MatchedConfigurations | ForEach-Object {Get-ITGlueConfigurations -id $_.itgobject.id -include related_items})
$RelatedConfigurations = $RelatedConfigurations ?? $($FreshConfigurations | Where-Object { Test-ITGlueResponseHasRelationData -Response $_ })

write-host "refreshing $($MatchedPasswords.count) passwords"
$FreshPasswords = $FreshPasswords ?? $($MatchedPasswords | ForEach-Object {Get-ITGluePasswords -id $_.itgobject.id -include related_items})
$RelatedPasswords = $RelatedPasswords ?? $($FreshPasswords | Where-Object { Test-ITGlueResponseHasRelationData -Response $_ })

write-host "refreshing $($MatchedContacts.count) contacts"
$FreshContacts = $FreshContacts ?? $($MatchedContacts | ForEach-Object {Get-ITGlueContacts -id $_.ITGObject.id -include related_items})
$RelatedContacts = $RelatedContacts ?? $($FreshContacts | Where-Object { Test-ITGlueResponseHasRelationData -Response $_ })

write-host "refreshing $($MatchedArticles.count) articles"
$FreshDocuments = $FreshDocuments ?? ($MatchedArticles | ForEach-Object {
    $ArticleLookup = Get-ArticleLookupInfo -Article $_
    if ($ArticleLookup) {
        Get-RelatedToDoc -DocID $ArticleLookup.DocID -OrganizationId $ArticleLookup.OrganizationId -ITGKey $ITGKey -ITGlue_Base_URI $settings.ITGAPIEndpoint
    }
})
$RelatedDocuments = $RelatedDocuments ?? ($FreshDocuments | Where-Object { Test-ITGlueResponseHasRelationData -Response $_ })

write-host "mapping configs"
$MatchedConfigurationMap = @{}
$MatchedConfigurations | ForEach-Object { $MatchedConfigurationMap[[string]$_.ITGID] = $_ }

write-host "mapping articles"
$MatchedArticleMap = @{}
$MatchedArticles | ForEach-Object { $MatchedArticleMap[[string]$_.ITGID] = $_ }

write-host "mapping article folders"
$FreshDocumentMap = @{}
$FreshDocuments | Where-Object { $_ -and $_.data -and $_.data.id } | ForEach-Object {
    $FreshDocumentMap[[string]$_.data.id] = $_
}

$MatchedArticleDocumentFolderMap = @{}
$MatchedArticles | ForEach-Object {
    $Article = $_
    $DocumentResponse = $FreshDocumentMap[[string]$Article.ITGID]
    $DocumentFolderId = Get-ITGlueDocumentFolderId -Article $Article -ITGlueDocumentResponse $DocumentResponse
    if ($DocumentFolderId) {
        if (-not $MatchedArticleDocumentFolderMap.ContainsKey($DocumentFolderId)) {
            $MatchedArticleDocumentFolderMap[$DocumentFolderId] = [System.Collections.ArrayList]@()
        }

        [void]$MatchedArticleDocumentFolderMap[$DocumentFolderId].Add($Article)
    }
}

write-host "mapping contacts"
$MatchedContactMap = @{}
$MatchedContacts | ForEach-Object { $MatchedContactMap[[string]$_.ITGID] = $_ }

write-host "mapping assets"
$MatchedAssetMap = @{}
$MatchedAssets | ForEach-Object { $MatchedAssetMap[[string]$_.ITGID] = $_ }

write-host "mapping companies"
$MatchedCompanyMap = @{}
$MatchedCompanies | ForEach-Object { $MatchedCompanyMap[[string]$_.ITGID] = $_ }

write-host "mapping locations"
$MatchedLocationMap = @{}
$MatchedLocations | ForEach-Object { $MatchedLocationMap[[string]$_.ITGID] = $_ }

write-host "mapping passwords"
$MatchedPasswordMap = @{}
$MatchedPasswords | ForEach-Object { $MatchedPasswordMap[[string]$_.ITGID] = $_ }
$MatchedAssetPasswords | ForEach-Object { $MatchedPasswordMap[[string]$_.ITGID] = $_ }

write-host "mapping websites"
$MatchedWebsiteMap = @{}
$MatchedWebsites | ForEach-Object { $MatchedWebsiteMap[[string]$_.ITGID] = $_ }

write-host "mapping checklists"
$MatchedChecklistsMap = @{}
$MatchedChecklistsByNameMap = @{}
$MatchedChecklists | Where-Object { $_ -and $_.id -and $_.HuduProcedure } | ForEach-Object {
    $MatchedChecklistsMap[[string]$_.id] = $_

    $ChecklistNameKey = Get-NormalizedRelationLookupName -Name $_.attributes.name
    if ($ChecklistNameKey) {
        if (-not $MatchedChecklistsByNameMap.ContainsKey($ChecklistNameKey)) {
            $MatchedChecklistsByNameMap[$ChecklistNameKey] = [System.Collections.ArrayList]@()
        }

        [void]$MatchedChecklistsByNameMap[$ChecklistNameKey].Add($_)
    }
}

$DocumentRelationsToCreate = Get-HuduRelationObject -ITGlueSourceObjects $RelatedDocuments
$ContactRelationsToCreate = Get-HuduRelationObject -ITGlueSourceObjects $RelatedContacts
$ConfigurationRelationsToCreate = Get-HuduRelationObject -ITGlueSourceObjects $RelatedConfigurations
$AssetRelationsToCreate = Get-HuduRelationObject -ITGlueSourceObjects $RelatedAssets
$PasswordRelationsToCreate = Get-HuduRelationObject -ITGlueSourceObjects $RelatedPasswords
$PasswordDocumentRelationsToCreate = Get-PasswordDocumentRelationObject -MatchedPasswords $MatchedPasswords
$TagFieldRelationsToCreate = Get-HuduRelationObjectFromTagFields -MatchedAssets $MatchedAssets -MatchedAssetLayoutFields $MatchedAssetLayoutFields
$QueuedTagRelationsToCreate = $RelationsToCreate | ForEach-Object { Convert-QueuedTagRelationToHuduRelationObject -Relation $_ }

$AllRelationsToCreate =
    @($AssetRelationsToCreate) +
    @($DocumentRelationsToCreate) +
    @($ContactRelationsToCreate) +
    @($PasswordRelationsToCreate) +
    @($PasswordDocumentRelationsToCreate) +
    @($TagFieldRelationsToCreate) +
    @($QueuedTagRelationsToCreate) +
    @($ConfigurationRelationsToCreate) |
    Where-Object { $_ } |
    Sort-Object FromableType, FromableID, ToableType, ToableID -Unique


if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
write-host "Creating approximately $($AllRelationsToCreate.count) relations"
$NewRelationsCreated = @(
    $AllRelationsToCreate | ForEach-Object {
        New-HuduRelation -FromableType $_.FromableType -FromableID $_.FromableID -ToableType $_.ToableType -ToableID $_.ToableID
    }
)

$AllRelationsToCreate | ConvertTo-Json -Depth 75 | Out-File (Join-Path $settings.MigrationLogs 'relations-to-create.json')
$NewRelationsCreated | ConvertTo-Json -Depth 75 | Out-File (Join-Path $settings.MigrationLogs 'relations-created.json')

if ($script:UnknownITGlueRelationTypeCounts -and $script:UnknownITGlueRelationTypeCounts.Count -gt 0) {
    $UnknownRelationTypes = $script:UnknownITGlueRelationTypeCounts.GetEnumerator() |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                TypeName = $_.Name
                Count    = $_.Value
            }
        }

    $UnknownRelationTypes | ConvertTo-Json -Depth 10 | Out-File (Join-Path $settings.MigrationLogs 'unknown-relation-types.json')
    Write-Warning "Encountered $($UnknownRelationTypes.Count) unsupported ITGlue relation type(s). Details saved to unknown-relation-types.json"
}
