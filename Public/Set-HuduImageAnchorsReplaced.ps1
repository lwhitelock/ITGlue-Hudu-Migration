
function Set-HuduImageAnchorsReplaced {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Html,[bool]$IncludeUploads = $false)

    $base = (Get-HuduBaseURL).TrimEnd('/')
    $e    = [regex]::Escape($base)

    if ($IncludeUploads) {
        $serverPatterns = @(
            "^/public_photo[s]?/",
            "^$e/public_photo[s]?/",
            "^/uploads/",
            "^$e/uploads/"
        )
    }
    else {
        $serverPatterns = @(
            "^/public_photo[s]?/",
            "^$e/public_photo[s]?/"
        )
    }

    # 1) Remove existing anchors that ONLY wrap an <img> tag
    # <a ...><img ...></a>  ->  <img ...>
    $noAnchors = [regex]::Replace(
        $Html,
        '<a\b[^>]*>\s*(<img\b[^>]*>)\s*</a>',
        '$1',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase `
            -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    # 2) Wrap qualifying <img> tags in <a href="fullsrc">
    $imgPattern = '<img\b[^>]*\bsrc\s*=\s*["'']([^"'']+)["''][^>]*>'

    $result = [regex]::Replace(
        $noAnchors,
        $imgPattern,
        {
            param($match)

            $imgTag = $match.Value
            $src    = $match.Groups[1].Value

            # Only touch "our" images (public_photo / uploads)
            $isOurImage = $false
            foreach ($p in $serverPatterns) {
                if ($src -match $p) {
                    $isOurImage = $true
                    break
                }
            }

            if (-not $isOurImage) {
                return $imgTag   # leave external images alone
            }

            # Normalize to absolute URL
            if ($src -match '^https?://') {
                $full = $src
            }
            else {
                if ($src.StartsWith('/')) {
                    $full = "$base$src"
                }
                else {
                    $full = "$base/$src"
                }
            }

            "<a href=""$full"">$imgTag</a>"
        },
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    return $result
}

function Get-AllHuduHostedImageAnchorsReplaced {
    param ([array]$allHuduArticles=@(),[bool]$includeUploads=$false)
    foreach ($a in $allarticles) {
    if ([string]::IsNullOrEmpty($a.content)){write-host "skipping $($a.id)"; continue;}
        Set-HuduArticle -id $a.id -Content "$(Set-HuduImageAnchorsReplaced -Html $a.content)"
    }
}