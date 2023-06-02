# This will be used to remake the ITGlue Links to Hudu, and relies on the articles logs existing.

#Enter the Export folder path e.g C:\Clients\company\itglue\export
$ITGlueExportPath = ''
# Enter the ITGlue URL to update, e.g https://company.itglue.com/
$ITGlueURl = ''
$EscapedITGURL = [regex]::Escape($ITGlueURl)
# Enter your HUDU API Information
$HuduAPIKey = ''
$HuduBaseURL = ''


Import-Module HuduAPI
New-HuduAPIKey -ApiKey $HuduAPIKey
New-HuduBaseURL -BaseURL $HuduBaseURL

# Gather all the Hudu Migration logs
# This should create $MatchedArticleBase, $MatchedAssetts, $MatchedCompanies, $MatchedConfigurations, $MatchedPasswords etc.
foreach ($File in (Get-ChildItem  "$ITGlueExportPath\..\MigrationLogs\*.json")) {
    try {
        New-Variable -Name "Matched$($file.name.replace('.json',''))" -Value (Get-Content $File.FullName -raw |ConvertFrom-Json -Depth 100) -ErrorAction Stop
    }
    catch {
        "Variable clobbering is occurring. Please clear the variables"
    }
    
}

$AllArticles = Get-HuduArticles

# Following capture Groups
# 0 = Entire match found
# 1,5 = A/a (not important)
# 2 = ITGlue Company ID (Important for LOCATOR)
# 3 = type of Entity (Important for location)
# 4 = ITGlue Entity ID

$RegexPatternToMatchSansAssets = "<(A|a) href=.*$EscapedITGURL\/([0-9]{1,6})\/(docs|passwords|configurations)\/([0-9]{1,10})\S*<\/(A|a)>"
$RegexPatternToMatchWithAssets = "<(A|a) href=.*$EscapedITGURL\/([0-9]{1,10})\/(assets)\/.*\/([0-9]{1,10})\S*<\/(A|a)>"
$ArticlesWithITGlueLinks = $AllArticles | Where-Object {$_.content -like "*$ITGlueURL*"}


function Update-StringWithCaptureGroups {
    [cmdletbinding()]
    param (
      [Parameter(Mandatory=$true, Position=0)]
      [string]$inputString,
      [Parameter(Mandatory=$true, Position=1)]
      [string]$pattern
    )
  
    $regex = [regex]::new($pattern)
    
    $matchesPattern = $regex.Matches($inputString)

    Write-Host "Found $($matchesPattern.count) matches to replace"
  
    foreach ($match in $matchesPattern) {

        # Compare the 3rd Group to identify where to find the new content

        switch ($match.groups[3].value) {

            "articles" {
                Write-Host "Matched an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
               $HuduUrl = ($MatchedArticleBase |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
               $HuduName = ($MatchedArticleBase |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
               Write-Host "Matched $($match.groups[3].value) URL to $HuduName" -ForegroundColor 'Cyan'
               
            }

            "passwords" {
                Write-Host "Matched an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedPasswords |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
                $HuduName = ($MatchedPasswords |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
                Write-Host "Matched $($match.groups[3].value) URL to $HuduName" -ForegroundColor 'Cyan'
            }

            "configurations" {
                Write-Host "Matched an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedConfigurations |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
                $HuduName = ($MatchedConfigurations |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
                Write-Host "Matched $($match.groups[3].value) URL to $HuduName" -ForegroundColor 'Cyan'
            }

            "assets" {
                Write-Host "Matched an $($match.groups[3].value) URL to replace" -ForegroundColor 'Blue'
                $HuduUrl = ($MatchedAssets |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.url
                $HuduName = ($MatchedAssets |Where-Object {$_.ITGID -eq $match.groups[4].value}).HuduObject.name
                Write-Host "Matched $($match.groups[3].value) URL to $HuduName" -ForegroundColor 'Cyan'
            }



        }
    
        if ($HuduUrl) {
            $HuduUrl = $HuduUrl.replace("http://","https://")
            $ReplacementString = @"
            <A HREF="$HuduUrl">$HuduName</A>
"@
            $inputString = $inputString -replace [string]$match.Value,[string]$ReplacementString
        }

      

    }
  
    return $inputString
  }
  

Write-Warning "Found $($ArticlesWithITGlueLinks.count) Articles with ITGlue Links. Cancel now if you don't want to replace them!"
Pause

$articlesUpdated = @()
foreach ($articleFound in $ArticlesWithITGlueLinks) {
    $NewContent = Replace-StringWithCaptureGroups -inputString $articleFound.content -pattern $RegexPatternToMatchSansAssets
    $NewContent = Replace-StringWithCaptureGroups -inputString $NewContent -pattern $RegexPatternToMatchWithAssets
    Write-Host "Updating Article $($articleFound.name) with replaced Content" -ForegroundColor 'Green'
    $articlesUpdated += Set-HuduArticle -Name $articleFound.name -id $articleFound.id -Content $NewContent

}

$articlesUpdated | ConvertTo-Json -depth 100 |Out-file "$ITGlueExportPath\..\MigrationLogs\ReplacedArticlesURL.json"
