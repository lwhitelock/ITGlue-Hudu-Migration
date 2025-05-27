# This will be used to remake the ITGlue Links to Hudu, and relies on the articles logs existing.


$EscapedITGURL = [regex]::Escape($ITGURL)

if ($environmentSettings.ITGCustomDomains) {
    $combinedEscapedURLs = ($environmentSettings.ITGCustomDomains -split "," | ForEach-Object { [regex]::Escape($_) }) -join "|"
    $EscapedITGURL = "(?:$EscapedITGURL|$combinedEscapedURLs)"
}

# Gather all the Hudu Migration logs
# This should create $MatchedArticleBase, $MatchedAssetts, $MatchedCompanies, $MatchedConfigurations, $MatchedPasswords etc.
<# 
Disabling this block to merge this file under the main migration.
foreach ($File in (Get-ChildItem  "$MigrationLogs\*.json")) {
    try {
        New-Variable -Name "Matched$($file.name.replace('.json',''))" -Value (Get-Content $File.FullName -raw |ConvertFrom-Json -Depth 100) -ErrorAction Stop
    }
    catch {
        "Variable clobbering is occurring. Please clear the variables"
    }
    
}
$MatchedArticles = $MatchedArticleBase
#>

# Disabling this line, since we'll have article content already.
# $AllArticles = Get-HuduArticles
# Disabling this line as we'll have the article content already
# $ArticlesWithITGlueLinks = $AllArticles | Where-Object {$_.content -like "*$ITGlueURL*"}


# We want to grab all assets, passwords, websites, and companies, filter to fields and notes that have ITGlue URLs in them and prime for replacement.
# Following capture Groups
# 0 = Entire match found
# 1,5 = A/a (not important)
# 2 = ITGlue Company ID (Important for LOCATOR)
# 3 = type of Entity (Important for location)
# 4 = ITGlue Entity ID

$RichRegexPatternToMatchSansAssets = "<(A|a) href=\S$EscapedITGURL/([0-9]{1,20})/(docs|passwords|configurations)/([0-9]{1,20})\S.*?</(A|a)>"
$RichRegexPatternToMatchWithAssets = "<(A|a) href=\S$EscapedITGURL/([0-9]{1,20})/(assets)/.*?/([0-9]{1,20})\S.*?</(A|a)>"
$ImgRegexPatternToMatch = @"
$EscapedITGURL/([0-9]{1,20}/docs/([0-9]{1,20})/(images)/([0-9]{1,20}).*?)(?=")
"@
$RichDocLocatorUrlPatternToMatch = @"
<(A|a) href=\S$EscapedITGURL/(DOC-.*?)(?=")\S.*?</(A|a)>
"@
$RichDocLocatorRelativeURLPatternToMatch = @"
<(A|a) href=\S/(DOC-.*?)(?=")\S.*?</(A|a)>
"@

$TextRegexPatternToMatchSansAssets = "$EscapedITGURL/([0-9]{1,20})/(docs|passwords|configurations)/([0-9]{1,20})"
$TextRegexPatternToMatchWithAssets = "$EscapedITGURL/([0-9]{1,20})/(assets)/.*?/([0-9]{1,20})"
$TextDocLocatorUrlPatternToMatch = "$EscapedITGURL/(DOC-[0-9]{0,20}-[0-9]{0,20}).*(?= )"

function Update-StringWithCaptureGroups {
    [cmdletbinding()]
    param (
      [Parameter(Mandatory=$true, Position=0)]
      [string]$inputString,
      [Parameter(Mandatory=$true, Position=1)]
      [string]$pattern,
      [Parameter(Mandatory=$true, Position=2)]
      [string]$type
    )
  
    $regex = [regex]::new($pattern)
    
    $matchesPattern = $regex.Matches($inputString)

    Write-Host "Found $($matchesPattern.count) matches to replace"
  
    foreach ($match in $matchesPattern) {

        # Compare the 3rd Group to identify where to find the new content

        switch ($match.groups[3].value) {

            "docs" {
                Write-Host "Found an $($match.groups[3].value) URL to replace for ITGID $($match.groups[4].value)..." -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedArticles |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
                $HuduName = ($MatchedArticles |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
                if ($HuduUrl -and $HuduName) {
                Write-Host "Matched $($match.groups[3].value) URL to Hudu doc: $HuduName" -ForegroundColor 'Cyan'
                } else { Remove-Variable HuduName,HuduURL; Write-Warning "The matched regex did not resolve to a Hudu article" }
               
            }

            "a" {
                Write-Host "Found a DOC Locator link for locator $($match.groups[2].value)" -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedArticles |Where-Object {$_.ITGLocator -eq $match.groups[2].value}).HuduObject.url
                $HuduName = ($MatchedArticles |Where-Object {$_.ITGLocator -eq $match.groups[2].value}).HuduObject.name
                if ($HuduURL -and $HuduName) {
                    Write-Host "Matched $($match.groups[2].value) Locator to Hudu doc: $HuduName" -ForegroundColor 'Cyan'
                } else { Remove-Variable HuduName,HuduURL; Write-Warning "The matched regex did not resolve to a Hudu article" }

            }

            "passwords" {
                Write-Host "Found an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedPasswords |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
                $HuduName = ($MatchedPasswords |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
                if ($HuduUrl -and $HuduName) {
                Write-Host "Matched $($match.groups[3].value) URL to Hudu Passsword: $HuduName" -ForegroundColor 'Cyan'
                } else { Remove-Variable HuduName,HuduURL; Write-Warning "The matched regex did not resolve to a Hudu article" }
            }

            "configurations" {
                Write-Host "Found an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedConfigurations |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
                $HuduName = ($MatchedConfigurations |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
                if ($HuduUrl -and $HuduName) {
                Write-Host "Matched $($match.groups[3].value) URL to Hudu Asset: $HuduName" -ForegroundColor 'Cyan'
                } else { Remove-Variable HuduName,HuduURL; Write-Warning "The matched regex did not resolve to a Hudu article" }
            }

            "assets" {
                Write-Host "Found an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedAssets |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
                $HuduName = ($MatchedAssets |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
                if ($HuduUrl -and $HuduName) {
                Write-Host "Matched $($match.groups[3].value) URL to Hudu Asset: $HuduName" -ForegroundColor 'Cyan'
                } else { Remove-Variable HuduName,HuduURL; Write-Warning "The matched regex did not resolve to a Hudu article" }
            }

            "images" {
                Write-Host "Found an external image using a Direct ITGlue link" -ForegroundColor 'Blue'
                $OriginalArticle = ($MatchedArticles | Where-Object {$_.ITGID -eq $match.groups[2].value}).Path
                $ImagePath = $match.groups[1].value.replace('/','\')
                $FullImagePath = Join-Path -Path $OriginalArticle -ChildPath $ImagePath
                $ImageItem = Get-Item -Path "$FullImagePath*" -ErrorAction SilentlyContinue
                if ($ImageItem) {
                    Return [pscustomobject]@{
                        "path" = $ImageItem.FullName
                        "url" = $match.Groups[1]
                    }
                }
                else { return $false}
                }
            default {
                if ($match.groups[1].value -like 'DOC-*') {
                    Write-Host "Found a DOC Locator link for locator $($match.groups[1].value)" -ForegroundColor 'Blue'
                    $HuduUrl = ($MatchedArticles |Where-Object {$_.ITGLocator -eq $match.groups[1].value}).HuduObject.url
                    $HuduName = ($MatchedArticles |Where-Object {$_.ITGLocator -eq $match.groups[1].value}).HuduObject.name
                    if ($HuduURL -and $HuduName) {
                        Write-Host "Matched $($match.groups[1].value) Locator to Hudu doc: $HuduName" -ForegroundColor 'Cyan'
                    } else { Remove-Variable HuduName,HuduURL; Write-Warning "The matched regex did not resolve to a Hudu article" }
                }
            }



        }
    
        if ($HuduUrl) {
            $HuduUrl = $HuduUrl.replace("http://","https://")
            if ($type -eq 'rich') {
            $ReplacementString = @"
            <A HREF="$HuduUrl">$HuduName</A>
"@
            }
            else {
                $ReplacementString = $HuduUrl
            }

            $inputString = $inputString -replace [regex]::Escape([string]$match.Value),[string]$ReplacementString
        }

      

    }
  
    return $inputString
  }
  

function ConvertTo-HuduURL {
    param(
        $Content
    )
    $NewContent = Update-StringWithCaptureGroups -inputString $Content -pattern $RegexPatternToMatchSansAssets
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RegexPatternToMatchWithAssets

    return $NewContent

}



<# Disabled block for merging into main conversion module
Write-Warning "Found $($ArticlesWithITGlueLinks.count) Articles with ITGlue Links. Cancel now if you don't want to replace them!"
Pause

$articlesUpdated = @()
foreach ($articleFound in $ArticlesWithITGlueLinks) {
    $NewContent = Update-StringWithCaptureGroups -inputString $articleFound.content -pattern $RegexPatternToMatchSansAssets
    $NewContent = Update-StringWithCaptureGroups -inputString $NewContent -pattern $RegexPatternToMatchWithAssets
    Write-Host "Updating Article $($articleFound.name) with replaced Content" -ForegroundColor 'Green'
    $articlesUpdated += @{"original_article" = $articleFound; "updated_article" = Set-HuduArticle -Name $articleFound.name -id $articleFound.id -Content $NewContent}

}

$articlesUpdated | ConvertTo-Json -depth 100 |Out-file "$MigrationLogs\ReplacedArticlesURL.json"
#>
