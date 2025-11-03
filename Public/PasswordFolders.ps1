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

function Get-ITGPasswordFolders {
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

    $resource_uri = '/password_folders'
    if ($organization_id) {
        $resource_uri = ('/organizations/{0}/relationships/password_folders' -f $organization_id)
    }

    $body = @{}

    if ($PSCmdlet.ParameterSetName -eq 'index') {
        if ($filter_id) {
            $body += @{'filter[id]' = $filter_id}
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
