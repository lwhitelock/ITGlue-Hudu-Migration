function ConvertTo-AttachmentUrlHashtable {
param(
    $MapObject
)
    if ($MapObject -is [hashtable]) { return $MapObject }

    $Hashtable = @{}

    if ($MapObject -is [System.Collections.IDictionary]) {
        foreach ($Key in $MapObject.Keys) {
            $Hashtable[[string]$Key] = [string]$MapObject[$Key]
        }
        return $Hashtable
    }

    foreach ($Property in $MapObject.PSObject.Properties) {
        if ($Property.MemberType -in 'NoteProperty','Property') {
            $Hashtable[[string]$Property.Name] = [string]$Property.Value
        }
    }

    return $Hashtable
}

function Get-AttachmentUrlMap {
param(
    [string]$MapPath = "$MigrationLogs\AttachmentUrlMap.json"
)
    if ($AttachmentUrlMap -and $AttachmentUrlMap.Count -gt 0) {
        return ConvertTo-AttachmentUrlHashtable -MapObject $AttachmentUrlMap
    }

    if (-not (Test-Path $MapPath)) {
        throw "Attachment URL map was not found at '$MapPath'. Run Add-HuduAttachmentsViaAPI.ps1 first."
    }

    $MapObject = Get-Content -Path $MapPath -Raw | ConvertFrom-Json -Depth 100
    return ConvertTo-AttachmentUrlHashtable -MapObject $MapObject
}

function Get-AttachmentUrlReplacementCandidates {
param(
    [string]$OriginalUrl
)
    $Candidates = @($OriginalUrl)

    try {
        $ParsedUrl = [Uri]$OriginalUrl
        if ($ParsedUrl.IsAbsoluteUri) {
            $Candidates += $ParsedUrl.PathAndQuery

            if ($ParsedUrl.AbsolutePath -match '/(?:files|attachments)/(?<AttachmentId>\d{1,20})(?:/|$)') {
                $AttachmentId = $Matches.AttachmentId
                $AttachmentPaths = @(
                    "/attachments/$AttachmentId"
                    "/attachments/$AttachmentId`?preview=1"
                    "/attachments/$AttachmentId`?preview=true"
                )

                foreach ($AttachmentPath in $AttachmentPaths) {
                    $Candidates += $AttachmentPath
                    $Candidates += "$($ParsedUrl.GetLeftPart([UriPartial]::Authority))$AttachmentPath"
                }
            }
        }
        elseif ($OriginalUrl -match '/(?:files|attachments)/(?<AttachmentId>\d{1,20})(?=$|[/?#])') {
            $AttachmentId = $Matches.AttachmentId
            $Candidates += "/attachments/$AttachmentId"
            $Candidates += "/attachments/$AttachmentId`?preview=1"
            $Candidates += "/attachments/$AttachmentId`?preview=true"
        }
    }
    catch {}

    foreach ($Candidate in @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique | Sort-Object Length -Descending)) {
        [pscustomobject]@{
            Url           = $Candidate
            IsHtmlEncoded = $false
            IsRelative    = $Candidate.StartsWith('/')
        }

        $HtmlEncodedCandidate = [System.Net.WebUtility]::HtmlEncode($Candidate)
        if ($HtmlEncodedCandidate -and $HtmlEncodedCandidate -ne $Candidate) {
            [pscustomobject]@{
                Url           = $HtmlEncodedCandidate
                IsHtmlEncoded = $true
                IsRelative    = $Candidate.StartsWith('/')
            }
        }
    }
}

function Get-ITGlueAttachmentUrls {
param(
    [AllowEmptyString()]
    [string]$Content
)
    if ([string]::IsNullOrWhiteSpace($Content)) { return @() }

    $AttachmentPattern = '(?:https?://[^"''\s<>]+)?/attachments/\d{1,20}(?:\?preview=(?:1|true))?'
    @(
        [regex]::Matches($Content, $AttachmentPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) |
            ForEach-Object { $_.Value } |
            Select-Object -Unique
    )
}

function Update-ContentWithAttachmentUrlMap {
param(
    [AllowEmptyString()]
    [string]$Content,
    [hashtable]$UrlMap
)
    $NewContent = $Content
    $Replacements = @()

    foreach ($OriginalUrl in @($UrlMap.Keys | Sort-Object Length -Descending)) {
        if ([string]::IsNullOrWhiteSpace($OriginalUrl) -or [string]::IsNullOrWhiteSpace($UrlMap[$OriginalUrl])) { continue }

        foreach ($Candidate in @(Get-AttachmentUrlReplacementCandidates -OriginalUrl $OriginalUrl)) {
            $CandidateUrl = $Candidate.Url
            $CandidatePattern = [regex]::Escape($CandidateUrl)
            if ($Candidate.IsRelative) {
                $CandidatePattern = "(?<![A-Za-z0-9._~%+-])$CandidatePattern"
            }
            if ($CandidateUrl -notmatch '\?' -and $CandidateUrl -match '/(?:files|attachments)/\d{1,20}$') {
                $CandidatePattern = "$CandidatePattern(?![/?#])"
            }

            $Count = [regex]::Matches($NewContent, $CandidatePattern).Count
            if ($Count -lt 1) { continue }

            $ReplacementUrl = if ($Candidate.IsHtmlEncoded) {
                [System.Net.WebUtility]::HtmlEncode($UrlMap[$OriginalUrl])
            } else {
                $UrlMap[$OriginalUrl]
            }

            $NewContent = [regex]::Replace(
                $NewContent,
                $CandidatePattern,
                [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $ReplacementUrl }
            )
            $Replacements += [pscustomobject]@{
                OriginalUrl    = $OriginalUrl
                MatchedUrl     = $CandidateUrl
                ReplacementUrl = $ReplacementUrl
                Count          = $Count
            }
        }
    }

    [pscustomobject]@{
        Content      = $NewContent
        Changed      = ($NewContent -ne $Content)
        Replacements = $Replacements
    }
}

function Start-HuduAttachmentLinkReplacement {
[CmdletBinding(SupportsShouldProcess)]
param(
    [object[]]$Articles,
    [hashtable]$UrlMap,
    [string]$MapPath = "$MigrationLogs\AttachmentUrlMap.json",
    [string]$OutputPath = "$MigrationLogs\ReplacedAttachmentLinks.json"
)
    if (-not $UrlMap) {
        $UrlMap = Get-AttachmentUrlMap -MapPath $MapPath
    }

    if (-not $UrlMap -or $UrlMap.Count -lt 1) {
        Write-Warning "Attachment URL map is empty. No articles were updated."
        return @()
    }

    if (-not $Articles) {
        $Articles = @(Get-HuduArticles)
    }

    $Results = foreach ($Article in $Articles) {
        if ([string]::IsNullOrEmpty($Article.content)) {
            [pscustomobject]@{
                Status       = 'skipped'
                ArticleId    = $Article.id
                ArticleName  = $Article.name
                Reason       = 'empty content'
                Replacements = @()
            }
            continue
        }

        $Updated = Update-ContentWithAttachmentUrlMap -Content $Article.content -UrlMap $UrlMap
        if (-not $Updated.Changed) {
            $UnresolvedAttachmentUrls = Get-ITGlueAttachmentUrls -Content $Article.content
            if ($UnresolvedAttachmentUrls.Count -gt 0) {
                [pscustomobject]@{
                    Status                   = 'unresolved'
                    ArticleId                = $Article.id
                    ArticleName              = $Article.name
                    Reason                   = 'attachment URLs found but no AttachmentUrlMap match'
                    UnresolvedAttachmentUrls = $UnresolvedAttachmentUrls
                    Replacements             = @()
                }
                continue
            }

            [pscustomobject]@{
                Status       = 'clean'
                ArticleId    = $Article.id
                ArticleName  = $Article.name
                Reason       = 'no attachment URLs found'
                Replacements = @()
            }
            continue
        }

        Write-Host "Replacing $($Updated.Replacements.Count) attachment URL set(s) in article '$($Article.name)'" -ForegroundColor Green

        try {
            $UpdatedArticle = $null
            if ($PSCmdlet.ShouldProcess("Article $($Article.id) '$($Article.name)'", "replace attachment links")) {
                $SetArticleSplat = @{
                    Id      = $Article.id
                    Content = $Updated.Content
                }
                if ($Article.name) { $SetArticleSplat.Name = $Article.name }
                if ($Article.company_id) { $SetArticleSplat.CompanyId = $Article.company_id }

                $UpdatedArticle = Set-HuduArticle @SetArticleSplat -ErrorAction Stop
            }

            [pscustomobject]@{
                Status       = if ($WhatIfPreference) { 'whatif' } else { 'replaced' }
                ArticleId    = $Article.id
                ArticleName  = $Article.name
                Replacements = $Updated.Replacements
                UpdatedArticle = $UpdatedArticle
            }
        }
        catch {
            [pscustomobject]@{
                Status       = 'failed'
                ArticleId    = $Article.id
                ArticleName  = $Article.name
                Error        = $_.Exception.Message
                Replacements = $Updated.Replacements
            }
        }
    }

    $Results | ConvertTo-Json -Depth 100 | Out-File $OutputPath -WhatIf:$false
    return $Results
}
