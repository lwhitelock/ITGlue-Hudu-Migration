function Get-ITGPasswordFolders {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$JWTAuthToken,

        [Parameter()]
        [Nullable[Int64]]$organization_id = $null,

        [switch]$ComputePaths,

        [string]$Separator = '/'
    )

    if (-not $script:ITGlue_Base_URI -or [string]::IsNullOrWhiteSpace($script:ITGlue_Base_URI)) {
        $script:ITGlue_Base_URI = 'https://api.itglue.com'
        Write-Warning "ITGlue_Base_URI not set. Using default: $script:ITGlue_Base_URI"
    }

    $resource_uri = if ($organization_id) {
        "/organizations/$organization_id/relationships/password_folders"
    } else {
        '/password_folders'
    }

    $headers = @{ Authorization = "Bearer $JWTAuthToken" }
    $uri = $script:ITGlue_Base_URI + $resource_uri

    $folders = @()
    try {
        $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
        if ($resp -and $resp.data) { $folders = $resp.data }
    } catch {
        Write-Error "Failed to retrieve ITGlue password folders: $($_.Exception.Message)"
        return
    }

    if (-not $ComputePaths) { return $folders }

    # ------- Lookups -------
    $lookup = @{}
    foreach ($f in $folders) { $lookup[[int64]$f.id] = $f }

    # Build parent -> children map
    $childrenByParent = @{}
    foreach ($f in $folders) {
        $parentIdRaw = $f.attributes.'parent-id'
        if ($parentIdRaw) {
            [void][int64]::TryParse("$parentIdRaw", [ref]([ref]$null)) # no-op parse to normalize type
            $parentId64 = [int64]$parentIdRaw
            if (-not $childrenByParent.ContainsKey($parentId64)) { $childrenByParent[$parentId64] = New-Object System.Collections.Generic.List[long] }
            $childrenByParent[$parentId64].Add([int64]$f.id)
        }
    }

    $memoPath = @{}
    $memoAnc  = @{}  # memo for ParentFolderIds

    function Get-Ancestors {
        param([object]$Folder, [hashtable]$Lkp, [hashtable]$MemoAnc)

        $id64 = [int64]$Folder.id
        if ($MemoAnc.ContainsKey($id64)) { return $MemoAnc[$id64] }

        # Prefer provided ancestor-ids if present (assumed root->...->parent)
        $ancRaw = $Folder.attributes.'ancestor-ids'
        $anc = @()
        if ($ancRaw) {
            if ($ancRaw -is [System.Collections.IEnumerable] -and -not ($ancRaw -is [string])) {
                $anc = @($ancRaw) | ForEach-Object { [int64]$_ } | Where-Object { $_ }
            } elseif ($ancRaw -is [string]) {
                $anc = ($ancRaw -split '[^\d]+' | Where-Object { $_ -match '^\d+$' }) | ForEach-Object { [int64]$_ }
            }
        }

        if ($anc.Count -gt 0) {
            $MemoAnc[$id64] = $anc
            return $anc
        }

        # Fallback: walk parent-id up the chain and build ordered list
        $stack = New-Object System.Collections.Generic.List[long]
        $cur = $Folder
        $seen = [System.Collections.Generic.HashSet[long]]::new()

        while ($cur) {
            $parentIdRaw = $cur.attributes.'parent-id'
            if (-not $parentIdRaw) { break }
            $parentId64 = 0
            [void][int64]::TryParse("$parentIdRaw", [ref]$parentId64)
            if (-not $parentId64) { break }
            if ($seen.Contains($parentId64)) { break }
            $seen.Add($parentId64) | Out-Null
            $stack.Insert(0, $parentId64)
            if ($Lkp.ContainsKey($parentId64)) {
                $cur = $Lkp[$parentId64]
            } else {
                break
            }
        }

        $MemoAnc[$id64] = [long[]]$stack.ToArray()
        return $MemoAnc[$id64]
    }

    function Resolve-Path {
        param([object]$Folder, [hashtable]$Lkp, [hashtable]$MemoPath, [hashtable]$MemoAnc, [string]$Sep)

        $id = [int64]$Folder.id
        if ($MemoPath.ContainsKey($id)) { return $MemoPath[$id] }

        $name = "$($Folder.attributes.name)".Trim()

        $anc = Get-Ancestors -Folder $Folder -Lkp $Lkp -MemoAnc $MemoAnc
        if ($anc.Count -gt 0) {
            $parts = foreach ($aid in $anc) {
                if ($Lkp.ContainsKey($aid)) { "$($Lkp[$aid].attributes.name)".Trim() }
            }
            $parts += $name
            $path = ($parts -join $Sep)
            $MemoPath[$id] = $path
            return $path
        }

        # No ancestors -> just name
        $MemoPath[$id] = $name
        return $name
    }

    $enriched = foreach ($f in $folders) {
        $id64 = [int64]$f.id
        $ancestors = Get-Ancestors -Folder $f -Lkp $lookup -MemoAnc $memoAnc
        $path = Resolve-Path -Folder $f -Lkp $lookup -MemoPath $memoPath -MemoAnc $memoAnc -Sep $Separator

        $childIds = @()
        if ($childrenByParent.ContainsKey($id64)) {
            $childIds = [long[]]$childrenByParent[$id64].ToArray()
        }

        [pscustomobject]@{
            id                = $f.id
            name              = $f.attributes.name
            org_id            = $f.attributes.'organization-id'
            org_name          = $f.attributes.'organization-name'
            parent_id         = $f.attributes.'parent-id'
            path              = $path
            depth             = ($path -split [regex]::Escape($Separator)).Count
            resource_url      = $f.attributes.'resource-url'
            ParentFolderIds   = [long[]]$ancestors
            ChildFolderIds    = [long[]]$childIds
        }
    }

    return $enriched
}
