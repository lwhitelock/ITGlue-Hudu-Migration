function Resolve-ArticleFolderPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$FullPath,

        [switch]$IncludeIgnoredFirstArticleDirectory
    )

    $resolvedBasePath = [System.IO.Path]::GetFullPath($BasePath)
    $resolvedFullPath = [System.IO.Path]::GetFullPath($FullPath)
    $basePrefix = $resolvedBasePath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

    if (
        $resolvedFullPath -ne $resolvedBasePath -and
        -not $resolvedFullPath.StartsWith($basePrefix, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "FullPath '$resolvedFullPath' is not inside BasePath '$resolvedBasePath'."
    }

    $relativePath = [System.IO.Path]::GetRelativePath($resolvedBasePath, $resolvedFullPath)
    $folderSegments = @()

    if (-not [string]::IsNullOrWhiteSpace($relativePath) -and $relativePath -ne '.') {
        foreach ($segment in ($relativePath -split '[\\/]')) {
            $segment = $segment.Trim()
            if (-not [string]::IsNullOrWhiteSpace($segment)) {
                $folderSegments += $segment
            }
        }
    }

    $leafFolder = if ($folderSegments.Count -gt 0) { $folderSegments[-1] } else { $null }
    $parentFolders = if ($folderSegments.Count -gt 1) {
        @($folderSegments[0..($folderSegments.Count - 2)])
    } else {
        @()
    }

    $foldersToInitialize = if ($IncludeIgnoredFirstArticleDirectory) {
        $parentFolders
    } elseif ($parentFolders.Count -gt 1) {
        @($parentFolders | Select-Object -Skip 1)
    } else {
        @()
    }

    $filenameFromFolder = $leafFolder
    if ($leafFolder -match '^\S+\s+(.+)$') {
        $filenameFromFolder = $matches[1]
    }

    [PSCustomObject]@{
        RelativePath                 = $relativePath
        FolderSegments               = $folderSegments
        ParentFolders                = $parentFolders
        FoldersToInitialize          = $foldersToInitialize
        IgnoredFirstDirectory        = if ($parentFolders.Count -gt 0) { $parentFolders[0] } else { $null }
        LeafFolder                   = $leafFolder
        FilenameFromFolder           = $filenameFromFolder
        IncludedIgnoredFirstDirectory = [bool]$IncludeIgnoredFirstArticleDirectory
    }
}
