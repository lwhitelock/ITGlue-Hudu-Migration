if (-not (Get-Command -Name Get-ITGlueJWTAuth -ErrorAction SilentlyContinue)) { . .\Public\Jwt-Auth.ps1 }
if (-not (Get-Command -Name Get-ITGlueSslCertificates -ErrorAction SilentlyContinue)) { . .\Public\Get-ITGlueSslCertificates.ps1 }
if (-not (Get-Command -Name Get-ITGlueChecklists -ErrorAction SilentlyContinue)) { . .\Public\Get-Checklists.ps1 }


$ITGlueJWT = $ITGlueJWT ?? (Read-Host "Please enter your ITGlue JWT as retrieved from browser.")
$ITGlueJWT = Get-ITGlueJWTAuth -ITglueJWT $ITglueJWT

Write-Host "Retrieving all certificates from ITGlue"
$sslCerts = Get-ITGlueSslCertificates -JWTAuthToken $ITGlueJWT
Write-Host "Got $($sslCerts.Count) SSL Certificates from ITGlue. Saving"