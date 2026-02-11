
if (-not (Get-Command -Name Get-EnsuredPath -ErrorAction SilentlyContinue)) { . .\Public\Init-OptionsAndLogs.ps1 }
if (-not (Get-Command -Name Get-ITGlueJWTAuth -ErrorAction SilentlyContinue)) { . .\Public\Jwt-Auth.ps1 }
if (-not (Get-Command -Name Get-ITGlueSslCertificates -ErrorAction SilentlyContinue)) { . .\Public\Get-ITGlueSslCertificates.ps1 }
if (-not (Get-Command -Name Get-ITGlueChecklists -ErrorAction SilentlyContinue)) { . .\Public\Get-Checklists.ps1 }


$ITGlueJWT = $ITGlueJWT ?? (Read-Host "Please enter your ITGlue JWT as retrieved from browser.")
$ITGlueJWT = Get-ITGlueJWTAuth -ITglueJWT $ITglueJWT

Write-Host "Retrieving all certificates from ITGlue"
$sslCerts = Get-ITGlueSslCertificates -JWTAuthToken $ITGlueJWT
if ($sslCerts.Count -lt 1) {
    Write-Host "No SSL Certificates found in ITGlue, exiting."
    exit
}

Write-Host "Got $($sslCerts.Count) SSL Certificates from ITGlue"

$cookieJar = $null
$cookiejarfile = $(get-childitem -path ..\ -filter "cookiejar.json" -recurse -file | Select-Object -first 1)
if (-not $cookiejarfile) {
    $cookiejarfile = resolve-path $(read-host "please enter the full path to cookiejar file")
}
if (-not (test-path $cookiejarfile.FullName)) {
    throw "cookiejar file $($cookiejarfile.FullName) not found"
    exit
} else {
    Write-Host "Using cookiejar file at $($cookiejarfile.FullName)"
}
$cookiejar = $(get-content $cookiejarfile.FullName | ConvertFrom-Json -depth 99)

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$session.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36"
foreach ($cookie in $cookiejar) {
    $session.Cookies.Add((New-Object System.Net.Cookie("$($cookie.Name)", "$($cookie.Value)", "$($cookie.Path)", "$($cookie.Domain)")))
}

foreach ($cert in $sslCerts) {
    $orgid = $cert.attributes.'organization-id'
    $certid = $cert.id
    $requesturi = "$($settings.ITGURL)/$orgid/ssl_certificates/$certid.pdf"
    write-host "Downloading certificate $($certid) from $($requesturi)"

    Invoke-WebRequest -UseBasicParsing -Uri  $requesturi `
        -WebSession $session `
        -Headers @{
        "authority"="$($settings.ITGURL -replace 'https://','')"
        "method"="GET"
        "path"="/$orgid/ssl_certificates/$certid.pdf"
        "scheme"="https"
        "accept"="text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
        "accept-encoding"="gzip, deflate, br, zstd"
        "accept-language"="en-US,en;q=0.9"
        "priority"="u=0, i"
        "referer"="$($settings.ITGURL)/$orgid/ssl_certificates/$certid"
        "sec-ch-ua"="`"Not(A:Brand`";v=`"8`", `"Chromium`";v=`"144`", `"Google Chrome`";v=`"144`""
        "sec-ch-ua-mobile"="?0"
        "sec-ch-ua-platform"="`"Windows`""
        "sec-fetch-dest"="document"
        "sec-fetch-mode"="navigate"
        "sec-fetch-site"="same-origin"
        "sec-fetch-user"="?1"
        "upgrade-insecure-requests"="1"
        } -OutFile "$debug_folder\$($certid).pdf"
}