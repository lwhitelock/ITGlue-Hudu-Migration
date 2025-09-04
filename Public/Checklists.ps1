<#
.SYNOPSIS
    Retrieves checklists from IT Glue using the Checklists API endpoint.

.DESCRIPTION
    This function queries the IT Glue Checklists endpoint, which requires a JWT token for authentication.
    The token can be obtained from browser developer tools when logged into the IT Glue web interface.
    Supports filtering, sorting, pagination, and including related resources.

.PARAMETER JWTAuthToken
    The JWT token required for authenticating to the Checklists endpoint.

.PARAMETER organization_id
    The ID of the organization to retrieve checklists for. If specified, uses the /organizations/{id}/relationships/checklists endpoint.

.EXAMPLE
    Get-ITGlueCheckLists -JWTAuthToken "your_jwt_token" -organization_id 12345
    Retrieves all checklists for the specified organization.

.NOTES
    This endpoint requires a JWT token, not an API key. Ensure the token is valid and not expired.
#>

function Get-ITGlueCheckLists {
    [CmdletBinding(DefaultParameterSetName = 'index')]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$JWTAuthToken,

        [Parameter(ParameterSetName = 'index')]
        [Nullable[Int64]]$organization_id = $null,

        [Parameter(ParameterSetName = 'index')]
        [Nullable[Int64]]$filter_id = '',

        [Parameter(ParameterSetName = 'index')]
        [Nullable[Int64]]$filter_organization_id = '',

        [Parameter(ParameterSetName = 'index')]
        [ValidateSet('created_at', 'updated_at')]
        [String]$sort = '',

        [Parameter(ParameterSetName = 'index')]
        [Nullable[Int64]]$page_number = $null,

        [Parameter(ParameterSetName = 'index')]
        [Nullable[int]]$page_size = $null,

        [Parameter(ParameterSetName = 'index')]
        [ValidateSet('passwords', 'attachments', 'user_resource_accesses', 'group_resource_accesses')]
        [String]$include = ''
    )

    if (-not $ITGlue_Base_URI) {
        $ITGlue_Base_URI = 'https://api.itglue.com'
        Write-Warning "ITGlue_Base_URI not set. Using default: $ITGlue_Base_URI"
    }

    $resource_uri = '/checklists'
    if ($organization_id) {
        $resource_uri = ('/organizations/{0}/relationships/checklists' -f $organization_id)
    }

    $body = @{}

    if ($PSCmdlet.ParameterSetName -eq 'index') {
        if ($filter_id) {
            $body += @{'filter[id]' = $filter_id}
        }
        if ($filter_organization_id) {
            $body += @{'filter[organization_id]' = $filter_organization_id}
        }
        if ($sort) {
            $body += @{'sort' = $sort}
        }
        if ($page_number) {
            $body += @{'page[number]' = $page_number}
        }
        if ($page_size) {
            $body += @{'page[size]' = $page_size}
        }
    }

    if($include) {
        $body += @{'include' = $include}
    }

    try {
        $ITGlueAuthHeaders = @{'Authorization' = "Bearer $JWTAuthToken"}
        $rest_output = Invoke-RestMethod -method 'GET' -uri ($ITGlue_Base_URI + $resource_uri) -headers $ITGlueAuthHeaders -body $body
    } catch {
        Write-Error $_
    } finally {
        [void] $ITGlueAuthHeaders.Remove('Authorization') # Quietly clean up scope so the API key doesn't persist
    }


    $data = @{}
    $data = $rest_output
    return $data
}


<#
.SYNOPSIS
    Retrieves checklist items from IT Glue using the Checklist Tasks API endpoint.

.DESCRIPTION
    This function queries the IT Glue Checklist Tasks endpoint to retrieve items for a specific checklist.
    It requires a JWT token for authentication, which can be obtained from browser developer tools when logged into the IT Glue web interface.
    Supports filtering by checklist ID, sorting, and pagination.

.PARAMETER JWTAuthToken
    The JWT token required for authenticating to the Checklist Tasks endpoint.

.PARAMETER filter_checklist_id
    The ID of the checklist to retrieve items for. This parameter is mandatory.

.PARAMETER sort
    Specifies the field to sort results by. Valid values are 'created_at' or 'updated_at'.

.PARAMETER page_number
    The page number to retrieve for paginated results.

.PARAMETER page_size
    The number of results per page (max 1000, as per IT Glue API limits).

.EXAMPLE
    Get-ITGlueChecklistItems -JWTAuthToken "your_jwt_token" -filter_checklist_id 3510640306421985
    Retrieves all checklist items for the specified checklist ID.

.EXAMPLE
    Get-ITGlueChecklistItems -JWTAuthToken "your_jwt_token" -filter_checklist_id 3510640306421985 -page_size 1000
    Retrieves up to 1000 checklist items for the specified checklist ID.

.NOTES
    This endpoint requires a JWT token, not an API key. Ensure the token is valid and not expired.
    The function respects IT Glue's API rate limits (10 requests/second, 10,000/day).
#>
function Get-ITGlueChecklistItems {
    [CmdletBinding(DefaultParameterSetName = 'index')]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$JWTAuthToken,

        [Parameter(Mandatory = $true)]
        [Nullable[Int64]]$filter_checklist_id,

        [Parameter(ParameterSetName = 'index')]
        [ValidateSet('created_at', 'updated_at')]
        [String]$sort = '',

        [Parameter(ParameterSetName = 'index')]
        [Nullable[Int64]]$page_number = $null,

        [Parameter(ParameterSetName = 'index')]
        [ValidateRange(1, 1000)]
        [Nullable[int]]$page_size = $null
    )

    if (-not $ITGlue_Base_URI) {
        $ITGlue_Base_URI = 'https://api.itglue.com'
        Write-Warning "ITGlue_Base_URI not set. Using default: $ITGlue_Base_URI"
    }

    $resource_uri = '/checklist_tasks'

    $body = @{'filter[checklist_id]' = $filter_checklist_id}
    if ($sort) { $body['sort'] = $sort }
    if ($page_number) { $body['page[number]'] = $page_number }
    if ($page_size) { $body['page[size]'] = $page_size }

    $query_string = ($body.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '&'
    $uri = if ($query_string) { "$ITGlue_Base_URI$resource_uri`?$query_string" } else { "$ITGlue_Base_URI$resource_uri" }

    try {
        $ITGlueAuthHeaders = @{ 'Authorization' = "Bearer $JWTAuthToken" }
        $rest_output = Invoke-RestMethod -Method 'GET' -Uri $uri -Headers $ITGlueAuthHeaders -ErrorAction Stop
        return $rest_output.data
    }
    catch {
        $error_message = $_.Exception.Message
        if ($_.Exception.Response) {
            $status_code = $_.Exception.Response.StatusCode.value__
            Write-Error "API request failed with status $status_code`: $error_message"
        } else {
            Write-Error "API request failed: $error_message"
        }
    }
    finally {
        [void] $ITGlueAuthHeaders.Remove('Authorization')
    }
}