function Get-ITGlueSslCertificates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JWTAuthToken,

        [Nullable[Int64]]$OrganizationId = $null,

        [ValidateRange(1,1000)]
        [int]$PageSize = 250
    )

    $baseUri = 'https://api.itglue.com/ssl_certificates'
    $headers = @{
        Authorization = "Bearer $JWTAuthToken"
        Accept        = 'application/json'
    }

    $page = 1
    $all  = @()

    do {
        $qs = [System.Collections.Generic.List[string]]::new()
        if ($OrganizationId) { $qs.Add("filter[organization_id]=$OrganizationId") }
        $qs.Add("page[size]=$PageSize")
        $qs.Add("page[number]=$page")

        $uri = "$baseUri`?$($qs -join '&')"

        try {
            $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop
        }
        catch {
            throw "SSL cert request failed on page $page- $($_.Exception.Message)"
        }

        $data = @($resp.data)
        $all  += $data
        $page++
    }
    while ($data.Count -gt 0)

    return $all
}
