function Get-ITGFileUrlParts {
    param([string]$Url)

    if ($Url -match '/assets/(?<layoutId>\d+)-(?<assetType>[^/]+)/records/(?<recordId>\d+)/files/(?<fileId>\d+)') {
        [pscustomobject]@{
            LayoutId  = $Matches.layoutId
            AssetType = $Matches.assetType
            RecordId  = $Matches.recordId
            FileId    = $Matches.fileId
        }
    }
}

function Normalize-ITGAttachmentName {
    param(
        [string]$Name,
        [switch]$WithoutExtension
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }

    $text = if ($WithoutExtension) {
        [IO.Path]::GetFileNameWithoutExtension($Name)
    } else {
        [IO.Path]::GetFileName($Name)
    }

    # IT Glue upload fields often keep the original name, while exports sanitize
    # punctuation and sometimes append a timestamp before the extension.
    $text = $text -replace '^\d{5,}-', ''
    $text = $text -replace '-\d{8,14}$', ''
    $text = $text.Normalize([Text.NormalizationForm]::FormD)
    $chars = $text.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark
    }
    $text = (-join $chars).ToLowerInvariant()
    $text = $text -replace '&', ' and '
    $text = $text -replace '[^a-z0-9]+', ' '
    $text = $text.Trim()
    $text = $text -replace '\s+', ' '

    return $text
}

function Get-ITGAttachmentNameScore {
    param(
        [string]$ExpectedName,
        [System.IO.FileInfo]$Candidate
    )

    if ($Candidate.Name -ieq $ExpectedName) { return 100 }

    $expectedFull = Normalize-ITGAttachmentName -Name $ExpectedName
    $candidateFull = Normalize-ITGAttachmentName -Name $Candidate.Name
    if ($expectedFull -and $expectedFull -eq $candidateFull) { return 96 }

    $expectedStem = Normalize-ITGAttachmentName -Name $ExpectedName -WithoutExtension
    $candidateStem = Normalize-ITGAttachmentName -Name $Candidate.Name -WithoutExtension
    if ($expectedStem -and $expectedStem -eq $candidateStem) { return 94 }
    if ($expectedStem -and ($candidateStem.Contains($expectedStem) -or $expectedStem.Contains($candidateStem))) { return 86 }

    $expectedTokens = @($expectedStem -split ' ' | Where-Object { $_ })
    $candidateTokens = @($candidateStem -split ' ' | Where-Object { $_ })
    if ($expectedTokens.Count -eq 0 -or $candidateTokens.Count -eq 0) { return 0 }

    $candidateSet = @{}
    foreach ($token in $candidateTokens) { $candidateSet[$token] = $true }

    $shared = 0
    foreach ($token in $expectedTokens) {
        if ($candidateSet.ContainsKey($token)) { $shared++ }
    }

    return [math]::Round(80 * ($shared / [math]::Max($expectedTokens.Count, $candidateTokens.Count)), 2)
}

function Get-ITGAttachmentMatch {
    param(
        [string]$ExpectedName,
        [Nullable[Int64]]$ExpectedSize,
        [object]$UrlParts,
        [object]$UploadAsset,
        [array]$Candidates
    )

    if (-not $Candidates -or $Candidates.Count -eq 0) { return $null }

    $hintIds = @(
        if ($UrlParts) { $UrlParts.RecordId; $UrlParts.FileId }
        $UploadAsset.ITGID
        $UploadAsset.HuduID
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } | Select-Object -Unique

    $scored = foreach ($candidate in $Candidates) {
        $nameScore = Get-ITGAttachmentNameScore -ExpectedName $ExpectedName -Candidate $candidate
        if ($nameScore -le 0) { continue }

        $fileIdPrefixMatch = $UrlParts -and $UrlParts.FileId -and $candidate.Name -like "$($UrlParts.FileId)-*"
        $score = $nameScore
        if ($ExpectedSize -and $candidate.Length -eq $ExpectedSize) { $score += 20 }
        if ($hintIds -contains $candidate.Directory.Name) { $score += 30 }
        if ($fileIdPrefixMatch) { $score += 40 }

        [pscustomobject]@{
            File              = $candidate
            Score             = $score
            NameScore         = $nameScore
            SizeMatch         = [bool]($ExpectedSize -and $candidate.Length -eq $ExpectedSize)
            DirMatch          = [bool]($hintIds -contains $candidate.Directory.Name)
            FileIdPrefixMatch = [bool]$fileIdPrefixMatch
        }
    }

    $ranked = @($scored | Sort-Object Score, NameScore -Descending)
    if ($ranked.Count -eq 0) { return $null }

    $best = $ranked[0]
    if ($best.Score -ge 90) { return $best }

    return $null
}

$AttachRoot = Join-Path $ITGLueExportPath "attachments"
$Attachfiles = if (Test-Path $AttachRoot) { @(Get-ChildItem $AttachRoot -Recurse -File) } else { @() }
$UploadFieldExportDirs = @(
    Get-ChildItem $ITGLueExportPath -Directory |
        Where-Object { $_.Name -ne 'attachments' -and $_.Name -match '^[^-]+-.+' }
)
$UploadFieldFiles = @($UploadFieldExportDirs | ForEach-Object { Get-ChildItem $_.FullName -Recurse -File })
$AllUploadCandidateFiles = @($Attachfiles + $UploadFieldFiles)
$AttachFilesByAssetType = @{}
foreach ($file in $AllUploadCandidateFiles) {
    $relative = $file.FullName.Substring((Resolve-Path $ITGLueExportPath).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).Length).TrimStart([char[]]@('\', '/'))
    $assetType = if ($relative -like "attachments\*" -or $relative -like "attachments/*") {
        ($relative -split '[\\/]', 3)[1]
    } else {
        (($relative -split '[\\/]', 2)[0] -split '-', 2)[0]
    }
    if ([string]::IsNullOrWhiteSpace($assetType)) { continue }
    if (-not $AttachFilesByAssetType.ContainsKey($assetType)) { $AttachFilesByAssetType[$assetType] = New-Object System.Collections.ArrayList }
    [void]$AttachFilesByAssetType[$assetType].Add($file)
}

$MatchedUploadFields = @{}
$UnresolvedUploadFields = @{}
foreach ($UploadAsset in $MatchedAssets | Where-Object { $_.HuduID -and $_.HuduID -gt 0 }) {
    $traits = $UploadAsset.ITGObject.attributes.traits

    foreach ($prop in $traits.PSObject.Properties) {
        $name  = $prop.Name
        $value = $prop.Value

        if ($value -isnot [pscustomobject]) { continue }

        $propNames = $value.PSObject.Properties.Name
        if ($propNames -notcontains 'url' -or $propNames -notcontains 'name') { continue }

        $filename = $value.name
        $size     = $value.size
        $parts    = Get-ITGFileUrlParts $value.url

        $candidates = @()

        if ($parts) {
            $hintDir = Join-Path $AttachRoot "$($parts.AssetType)\$($parts.RecordId)"

            if (Test-Path $hintDir) {
                $candidates = Get-ChildItem $hintDir -File
            }
        }

        $expectedSize = $null
        if ($size) {
            $parsedSize = 0L
            if ([Int64]::TryParse("$size", [ref]$parsedSize)) { $expectedSize = $parsedSize }
        }

        $typeCandidates = if ($parts -and $AttachFilesByAssetType.ContainsKey($parts.AssetType)) {
            @($AttachFilesByAssetType[$parts.AssetType])
        } else {
            @($AllUploadCandidateFiles)
        }

        $match =
            (Get-ITGAttachmentMatch -ExpectedName $filename -ExpectedSize $expectedSize -UrlParts $parts -UploadAsset $UploadAsset -Candidates $candidates) ??
            (Get-ITGAttachmentMatch -ExpectedName $filename -ExpectedSize $expectedSize -UrlParts $parts -UploadAsset $UploadAsset -Candidates $typeCandidates) ??
            (Get-ITGAttachmentMatch -ExpectedName $filename -ExpectedSize $expectedSize -UrlParts $parts -UploadAsset $UploadAsset -Candidates $AllUploadCandidateFiles)

        if ($null -eq $match.file){
            $UnresolvedUploadFields["$($UploadAsset.HuduID):$name"] = @{
                UploadAsset = $UploadAsset
                FieldName   = $name
                FilePath    = $null
                ITGFileUrl  = $value.url
                ITGFileName = $filename
                MatchScore  = 0
            }
            Write-Warning "Unable to resolve file for '$filename' with url hint '$($value.url)' in asset ID $($UploadAsset.HuduID)"
            continue
        }
        write-host "Matched '$filename' to '$($match.File.FullName)' with score $($match.Score) for asset ID $($UploadAsset.HuduID)"

        $matchedFile = $match.File
        $newUpload = $null; $newUpload = New-HuduUpload -uploadable_id $UploadAsset.HuduID -filePath $matchedFile.FullName -uploadable_type "Asset"; $newUpload = $newUpload.upload ?? $newUpload;
        if ($null -eq $newUpload) {
            Write-Warning "Failed to create upload for '$filename' at '$($matchedFile.FullName)' for asset ID $($UploadAsset.HuduID)"
            $UnresolvedUploadFields["$($UploadAsset.HuduID):$name"] = @{
                UploadAsset = $UploadAsset
                FieldName   = $name
                FilePath    = $null
                ITGFileUrl  = $value.url
                ITGFileName = $filename
                MatchScore  = 0
            }            
            continue
        }

        if ($matchedFile) {
            $MatchedUploadFields["$($UploadAsset.HuduID):$name"] = @{
                UploadAsset = $UploadAsset
                FieldName   = $name
                FilePath    = $matchedFile.FullName
                ITGFileUrl  = $value.url
                ITGFileName = $filename
                MatchScore  = $match.Score
                Upload      = $newUpload
            }
        }
        else {
            Write-Warning "No matching file found for '$filename' with url hint '$($value.url)' in asset ID $($UploadAsset.HuduID)"
        }
    }
}