function Test-HuduAPIKeyScope {
    [CmdletBinding()]
    param(
        [string]$HuduBaseUrl = $(Get-HuduBaseURL),
        [securestring]$HuduApiKey = $(Get-HuduApiKey),
        [switch]$Detailed,
        [switch]$ThrowOnFailure
    )

    $resolvedBaseUrl = $null
    $resolvedApiKey = $null
    $requestUri = $null

    try {
        if ([string]::IsNullOrWhiteSpace($HuduBaseUrl)) {
            throw "Hudu base URL is not set."
        }

        if ($null -eq $HuduApiKey) {
            throw "Hudu API key is not set."
        }

        $resolvedBaseUrl = $HuduBaseUrl.TrimEnd('/')
        $resolvedApiKey = (New-Object PSCredential 'user', $HuduApiKey).GetNetworkCredential().Password

        if ([string]::IsNullOrWhiteSpace($resolvedApiKey)) {
            throw "Resolved Hudu API key is empty."
        }

        $requestUri = "$resolvedBaseUrl/api/v1/asset_passwords?page=1&page_size=1"
        $response = Invoke-WebRequest `
            -Method Get `
            -Uri $requestUri `
            -Headers @{ 'x-api-key' = $resolvedApiKey } `
            -ContentType 'application/json; charset=utf-8' `
            -SkipHttpErrorCheck `
            -ErrorAction Stop

        $statusCode = [int]$response.StatusCode
        $rawContent = $response.Content
        $parsedContent = $null

        if (-not [string]::IsNullOrWhiteSpace($rawContent)) {
            $parsedContent = try {
                $rawContent | ConvertFrom-Json -Depth 10 -ErrorAction Stop
            } catch {
                $rawContent
            }
        }

        $success = $statusCode -ge 200 -and $statusCode -lt 300
        $message = switch ($statusCode) {
            { $_ -ge 200 -and $_ -lt 300 } {
                "Hudu API key can access password endpoints."
                break
            }
            401 {
                "Hudu rejected the password endpoint request with 401 Bad credentials. This usually means the API key is invalid or is missing password access."
                break
            }
            403 {
                "Hudu authenticated the API key but denied access to password endpoints with 403 Forbidden."
                break
            }
            default {
                "Hudu returned HTTP $statusCode while checking password endpoint access."
                break
            }
        }

        $result = [pscustomobject]@{
            Success      = $success
            StatusCode   = $statusCode
            Uri          = $requestUri
            Message      = $message
            ResponseBody = $parsedContent
        }
    } catch {
        $result = [pscustomobject]@{
            Success      = $false
            StatusCode   = $null
            Uri          = $requestUri
            Message      = "Failed to verify Hudu password endpoint access: $($_.Exception.Message)"
            ResponseBody = $_
        }
    }

    if (-not $result.Success) {
        Write-Warning $result.Message
        if ($ThrowOnFailure) {
            throw $result.Message
        }
    }

    if ($Detailed) {
        return $result
    }

    return $result.Success
}

function Test-ITGlueAPIKeyPasswordScope {
    [CmdletBinding()]
    param(
        [string]$ITGlueBaseUrl = $(Get-ITGlueBaseURI),
        [securestring]$ITGlueApiKey = $(Get-ITGlueAPIKey),
        [Nullable[Int64]]$PasswordId = $null,
        [switch]$Detailed,
        [switch]$ThrowOnFailure
    )

    $resolvedBaseUrl = $null
    $resolvedApiKey = $null
    $listUri = $null
    $showUri = $null

    try {
        if ([string]::IsNullOrWhiteSpace($ITGlueBaseUrl)) {
            throw "IT Glue base URL is not set."
        }

        if ($null -eq $ITGlueApiKey) {
            throw "IT Glue API key is not set."
        }

        $resolvedBaseUrl = $ITGlueBaseUrl.TrimEnd('/')
        $resolvedApiKey = (New-Object PSCredential 'user', $ITGlueApiKey).GetNetworkCredential().Password

        if ([string]::IsNullOrWhiteSpace($resolvedApiKey)) {
            throw "Resolved IT Glue API key is empty."
        }

        $headers = @{
            'x-api-key'     = $resolvedApiKey
            'Content-Type'  = 'application/vnd.api+json'
        }

        if (-not $PasswordId) {
            $listResult = $null
            $listBody = $null
            $listStatusCode = 200

            if (Get-Command -Name Get-ITGluePasswords -ErrorAction SilentlyContinue) {
                $listUri = "Get-ITGluePasswords -page_size 1"
                $listResult = Get-ITGluePasswords -page_size 1
                $listBody = $listResult
            } else {
                $listUri = "$resolvedBaseUrl/passwords?page[size]=1"
                $listResponse = Invoke-WebRequest `
                    -Method Get `
                    -Uri $listUri `
                    -Headers $headers `
                    -ContentType 'application/vnd.api+json' `
                    -SkipHttpErrorCheck `
                    -ErrorAction Stop

                $listStatusCode = [int]$listResponse.StatusCode
                $listBody = if ([string]::IsNullOrWhiteSpace($listResponse.Content)) {
                    $null
                } else {
                    $listResponse.Content | ConvertFrom-Json -Depth 20 -ErrorAction Stop
                }
            }

            if ($null -eq $listBody) {
                $result = [pscustomobject]@{
                    Success       = $false
                    Determined    = $true
                    StatusCode    = $listStatusCode
                    ListUri       = $listUri
                    ShowUri       = $null
                    PasswordId    = $null
                    Message       = "IT Glue password list request did not return usable data."
                    ResponseBody  = $listResult
                }

                if ($ThrowOnFailure) {
                    throw $result.Message
                }

                Write-Warning $result.Message
                if ($Detailed) { return $result }
                return $false
            }

            $PasswordId = $listBody.data | Select-Object -First 1 -ExpandProperty id
            if (-not $PasswordId) {
                $result = [pscustomobject]@{
                    Success       = $false
                    Determined    = $false
                    StatusCode    = $listStatusCode
                    ListUri       = $listUri
                    ShowUri       = $null
                    PasswordId    = $null
                    Message       = "IT Glue password records are accessible, but no passwords exist to verify whether the API key can read password values."
                    ResponseBody  = $listBody
                }

                Write-Warning $result.Message
                if ($ThrowOnFailure) {
                    throw $result.Message
                }
                if ($Detailed) { return $result }
                return $false
            }
        }

        $showBody = $null
        if (Get-Command -Name Get-ITGluePasswords -ErrorAction SilentlyContinue) {
            $showUri = "Get-ITGluePasswords -id $PasswordId -show_password `$true"
            $showBody = Get-ITGluePasswords -id $PasswordId -show_password $true
            $showStatusCode = if ($null -ne $showBody) { 200 } else { $null }
        } else {
            $showUri = "$resolvedBaseUrl/passwords/${PasswordId}?show_password=true"
            $showResponse = Invoke-WebRequest `
                -Method Get `
                -Uri $showUri `
                -Headers $headers `
                -ContentType 'application/vnd.api+json' `
                -SkipHttpErrorCheck `
                -ErrorAction Stop

            $showStatusCode = [int]$showResponse.StatusCode
            $showBody = if ([string]::IsNullOrWhiteSpace($showResponse.Content)) {
                $null
            } else {
                $showResponse.Content | ConvertFrom-Json -Depth 20 -ErrorAction Stop
            }
        }

        $passwordAttributes = $showBody.data.attributes
        $passwordProperty = if ($null -ne $passwordAttributes) {
            $passwordAttributes.PSObject.Properties['password']
        } else {
            $null
        }
        $hasPasswordValueAccess = (
            $showStatusCode -ge 200 -and
            $showStatusCode -lt 300 -and
            $null -ne $passwordProperty -and
            $null -ne $passwordProperty.Value
        )

        $message = if ($hasPasswordValueAccess) {
            "IT Glue API key can read password values from the Passwords API."
        } elseif ($showStatusCode -eq 401) {
            "IT Glue rejected the password details request with 401 Unauthorized."
        } elseif ($showStatusCode -eq 403) {
            "IT Glue rejected the password details request with 403 Forbidden."
        } elseif ($showStatusCode -ge 200 -and $showStatusCode -lt 300) {
            "IT Glue returned the password record, but not the password value. This usually means the API key can list password metadata but does not have Password Access enabled."
        } else {
            "IT Glue returned HTTP $showStatusCode while checking password value access."
        }

        $result = [pscustomobject]@{
            Success       = $hasPasswordValueAccess
            Determined    = $true
            StatusCode    = $showStatusCode
            ListUri       = $listUri
            ShowUri       = $showUri
            PasswordId    = $PasswordId
            Message       = $message
            ResponseBody  = $showBody
        }
    } catch {
        $result = [pscustomobject]@{
            Success       = $false
            Determined    = $false
            StatusCode    = $null
            ListUri       = $listUri
            ShowUri       = $showUri
            PasswordId    = $PasswordId
            Message       = "Failed to verify IT Glue password value access: $($_.Exception.Message)"
            ResponseBody  = $_
        }
    }

    if (-not $result.Success) {
        Write-Warning $result.Message
        if ($ThrowOnFailure) {
            throw $result.Message
        }
    }

    if ($Detailed) {
        return $result
    }

    return $result.Success
}

function ConvertTo-ReadableByteSize {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Bytes
    )

    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $value = [double]$Bytes
    $unitIndex = 0

    while ($value -ge 1024 -and $unitIndex -lt ($units.Count - 1)) {
        $value = $value / 1024
        $unitIndex++
    }

    return ('{0:N2} {1}' -f $value, $units[$unitIndex])
}

function Resolve-ExistingFilesystemPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $candidate = $Path
    while (-not [string]::IsNullOrWhiteSpace($candidate)) {
        if (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue) {
            $item = Get-Item -LiteralPath $candidate -ErrorAction Stop
            if ($item.PSProvider.Name -ne 'FileSystem') {
                throw "Path '$Path' resolved to non-filesystem provider '$($item.PSProvider.Name)'."
            }
            return $item
        }

        $parent = Split-Path -Path $candidate -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) {
            break
        }
        $candidate = $parent
    }

    throw "Could not resolve '$Path' or any parent directory to an existing filesystem path."
}

function Test-ITGlueExportDiskSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExportPath,

        [AllowNull()]
        [string]$TargetPath,

        [ValidateRange(0, 1000)]
        [double]$BufferPercent = 15,

        [switch]$Detailed,
        [switch]$ThrowOnFailure
    )

    $resolvedExport = $null
    $resolvedTarget = $null
    $result = $null

    try {
        if ([string]::IsNullOrWhiteSpace($ExportPath)) {
            throw "IT Glue export path is blank."
        }

        $resolvedExport = Get-Item -LiteralPath $ExportPath -ErrorAction Stop
        if (-not $resolvedExport.PSIsContainer) {
            throw "IT Glue export path '$ExportPath' is not a directory."
        }

        if ([string]::IsNullOrWhiteSpace($TargetPath)) {
            $TargetPath = $resolvedExport.FullName
        }

        $measureErrors = @()
        $measure = Get-ChildItem -LiteralPath $resolvedExport.FullName -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable +measureErrors |
            Measure-Object -Property Length -Sum

        $exportBytes = [int64]($measure.Sum ?? 0)
        $requiredBytes = [int64][Math]::Ceiling($exportBytes * (1 + ($BufferPercent / 100)))
        $resolvedTarget = Resolve-ExistingFilesystemPath -Path $TargetPath
        $drive = Get-PSDrive -Name $resolvedTarget.PSDrive.Name -ErrorAction Stop
        $freeBytes = [int64]($drive.Free ?? 0)
        $success = $freeBytes -ge $requiredBytes
        $message = if ($success) {
            "Disk space check passed. Export is $(ConvertTo-ReadableByteSize $exportBytes); required free space with $BufferPercent% buffer is $(ConvertTo-ReadableByteSize $requiredBytes); available on $($drive.Name): is $(ConvertTo-ReadableByteSize $freeBytes)."
        } else {
            "Disk space check failed. Export is $(ConvertTo-ReadableByteSize $exportBytes); required free space with $BufferPercent% buffer is $(ConvertTo-ReadableByteSize $requiredBytes); available on $($drive.Name): is only $(ConvertTo-ReadableByteSize $freeBytes)."
        }

        $result = [pscustomobject]@{
            Success                 = $success
            ExportPath              = $resolvedExport.FullName
            TargetPath              = $TargetPath
            CheckedPath             = $resolvedTarget.FullName
            DriveName               = $drive.Name
            ExportBytes             = $exportBytes
            RequiredFreeBytes       = $requiredBytes
            AvailableFreeBytes      = $freeBytes
            BufferPercent           = $BufferPercent
            EnumerationErrorCount   = @($measureErrors).Count
            Message                 = $message
        }
    } catch {
        $result = [pscustomobject]@{
            Success                 = $false
            ExportPath              = $ExportPath
            TargetPath              = $TargetPath
            CheckedPath             = if ($resolvedTarget) { $resolvedTarget.FullName } else { $null }
            DriveName               = $null
            ExportBytes             = $null
            RequiredFreeBytes       = $null
            AvailableFreeBytes      = $null
            BufferPercent           = $BufferPercent
            EnumerationErrorCount   = $null
            Message                 = "Disk space check failed: $($_.Exception.Message)"
        }
    }

    if (-not $result.Success) {
        Write-Warning $result.Message
        if ($ThrowOnFailure) {
            throw $result.Message
        }
    }

    if ($Detailed) {
        return $result
    }

    return $result.Success
}

function Get-HuduAssetLayoutManagementUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$HuduAssetLayout,

        [AllowNull()]
        [string]$HuduBaseUrl
    )

    if ([string]::IsNullOrWhiteSpace($HuduBaseUrl)) { return $null }
    if (-not $HuduAssetLayout.PSObject.Properties['slug']) { return $null }

    $slug = "$($HuduAssetLayout.slug)"
    if ([string]::IsNullOrWhiteSpace($slug)) { return $null }

    return "$($HuduBaseUrl.TrimEnd('/'))/admin/asset_layouts/$slug"
}

function Test-HuduAssetLayoutTargetNameCollision {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$TargetLayouts,

        [object[]]$HuduAssetLayouts = $(Get-HuduAssetLayouts),

        [AllowNull()]
        [string]$HuduBaseUrl,

        [switch]$Detailed,
        [switch]$ThrowOnCollision
    )

    $huduLayoutNames = @{}

    foreach ($layout in @($HuduAssetLayouts | Where-Object { $_ })) {
        $name = "$($layout.name)"
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $key = $name.Trim().ToLowerInvariant()
        if (-not $huduLayoutNames.ContainsKey($key)) {
            $huduLayoutNames[$key] = @()
        }

        $huduLayoutNames[$key] += $layout
    }

    $collisions = foreach ($targetLayout in @($TargetLayouts | Where-Object { $_ })) {
        $targetName = $targetLayout.TargetName
        if ([string]::IsNullOrWhiteSpace($targetName)) { continue }

        $targetKey = $targetName.Trim().ToLowerInvariant()

        if ($huduLayoutNames.ContainsKey($targetKey)) {
            foreach ($huduLayout in @($huduLayoutNames[$targetKey])) {
                [pscustomobject]@{
                    SourceType        = $targetLayout.SourceType
                    SourceName        = $targetLayout.SourceName
                    TargetName        = $targetName
                    SourceId          = $targetLayout.SourceId
                    HuduLayoutName    = $huduLayout.name
                    HuduLayoutId      = $huduLayout.id
                    HuduManagementUrl = Get-HuduAssetLayoutManagementUrl -HuduAssetLayout $huduLayout -HuduBaseUrl $HuduBaseUrl
                }
            }
        }
    }

    $result = [pscustomobject]@{
        Success    = (@($collisions).Count -eq 0)
        Collisions = @($collisions)
    }

    if (-not $result.Success) {
        $message = "One or more target asset layout names would collide with existing Hudu asset layouts."
        Write-Warning $message

        if ($ThrowOnCollision) {
            throw $message
        }
    }

    if ($Detailed) {
        return $result
    }

    return $result.Success
}

function Test-HuduFlexibleAssetLayoutNameCollision {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$ITGlueFlexibleAssetLayouts,

        [object[]]$HuduAssetLayouts = $(Get-HuduAssetLayouts),

        [AllowNull()]
        [string]$FlexibleLayoutPrefix = "",

        [AllowNull()]
        [string]$HuduBaseUrl,

        [switch]$Detailed,
        [switch]$ThrowOnCollision
    )

    $prefix = $FlexibleLayoutPrefix ?? ""
    $targetLayouts = foreach ($itgLayout in @($ITGlueFlexibleAssetLayouts | Where-Object { $_ })) {
        $sourceName = $null
        if ($itgLayout.PSObject.Properties['attributes'] -and $itgLayout.attributes) {
            $sourceName = $itgLayout.attributes.name
        }
        if ([string]::IsNullOrWhiteSpace($sourceName) -and $itgLayout.PSObject.Properties['name']) {
            $sourceName = $itgLayout.name
        }
        if ([string]::IsNullOrWhiteSpace($sourceName)) { continue }

        [pscustomobject]@{
            SourceType = "Flexible Asset Layout"
            SourceName = $sourceName
            TargetName = "$prefix$sourceName"
            SourceId   = $itgLayout.id
        }
    }

    $result = Test-HuduAssetLayoutTargetNameCollision `
        -TargetLayouts $targetLayouts `
        -HuduAssetLayouts $HuduAssetLayouts `
        -HuduBaseUrl $HuduBaseUrl `
        -Detailed

    if ($ThrowOnCollision -and -not $result.Success) {
        throw "One or more IT Glue flexible asset layout names would collide with existing Hudu asset layouts."
    }

    if ($Detailed) {
        $result | Add-Member -MemberType NoteProperty -Name Prefix -Value $prefix -Force
        return $result
    }

    return $result.Success
}

