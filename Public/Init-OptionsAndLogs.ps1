function Write-InspectObject {
    param (
        [object]$object,
        [int]$Depth = 32,
        [int]$MaxLines = 16
    )

    $stringifiedObject = $null

    if ($null -eq $object) {
        return "Unreadable Object (null input)"
    }
    # Try JSON
    $stringifiedObject = try {
        $json = $object | ConvertTo-Json -Depth $Depth -ErrorAction Stop
        "# Type: $($object.GetType().FullName)`n$json"
    } catch { $null }

    # Try Format-Table
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $object | Format-Table -Force | Out-String
        } catch { $null }
    }

    # Try Format-List
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $object | Format-List -Force | Out-String
        } catch { $null }
    }

    # Fallback to manual property dump
    if (-not $stringifiedObject) {
        $stringifiedObject = try {
            $props = $object | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
            $lines = foreach ($p in $props) {
                try {
                    "$p = $($object.$p)"
                } catch {
                    "$p = <unreadable>"
                }
            }
            "# Type: $($object.GetType().FullName)`n" + ($lines -join "`n")
        } catch {
            "Unreadable Object"
        }
    }

    if (-not $stringifiedObject) {
        $stringifiedObject =  try {"$($($object).ToString())"} catch {$null}
    }
    # Truncate to max lines if necessary
    $lines = $stringifiedObject -split "`r?`n"
    if ($lines.Count -gt $MaxLines) {
        $lines = $lines[0..($MaxLines - 1)] + "... (truncated)"
    }

    return $lines -join "`n"
}

function Select-ObjectFromList($objects, $message, $inspectObjects = $false, $allowNull = $false) {
    $validated = $false
    while (-not $validated) {
        if ($allowNull) { Write-Host "0: None/Custom" }

        for ($i = 0; $i -lt $objects.Count; $i++) {
            $object = $objects[$i]
            $displayLine = if ($inspectObjects) {
                "$($i+1): $(Write-InspectObject -object $object)"
            } elseif ($null -ne $object.OptionMessage) {
                "$($i+1): $($object.OptionMessage)"
            } elseif (-not $([string]::IsNullOrEmpty($object.attributes.name))) {
                "$($i+1): $($object.attributes.name)"
            } elseif (-not $([string]::IsNullOrEmpty($object.name))) {
                "$($i+1): $($object.name)"
            } else {
                "$($i+1): $($object)"
            }
            Write-Host $displayLine -ForegroundColor $(if ($i % 2 -eq 0) { 'Cyan' } else { 'Yellow' })
        }

        $raw = Read-Host $message

        $parsed = 0
        if (-not [int]::TryParse($raw, [ref]$parsed)) {
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
            continue
        }

        if ($parsed -eq 0 -and $allowNull) { return $null }

        if ($parsed -ge 1 -and $parsed -le $objects.Count) {
            return $objects[$parsed - 1]
        } else {
            Write-Host "Invalid selection. Please enter a number from the list." -ForegroundColor Red
        }
    }
}
function Get-EnsuredPath {
    param([string]$path)
    $outpath = if (-not $path -or [string]::IsNullOrWhiteSpace($path)) { $(join-path $(Resolve-Path .).path "debug") } else {$path}
    if (-not (Test-Path $outpath)) {
        Get-ChildItem -Path "$outpath" -File -Recurse -Force | Remove-Item -Force
        New-Item -ItemType Directory -Path $outpath -Force -ErrorAction Stop | Out-Null
        write-host "path is now present: $outpath"
    } else {write-host "path is present: $outpath"}
    return $outpath
}

function Write-ErrorObjectsToFile {
    param (
        [Parameter(Mandatory)]
        [object]$ErrorObject,

        [Parameter()]
        [string]$Name = "unnamed",

        [Parameter()]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color,

        [Parameter()]
        [string]$childDir = $null        
    )

    $stringOutput = try {
        $ErrorObject | Format-List -Force | Out-String
    } catch {
        "Failed to stringify object: $_"
    }

    $propertyDump = try {
        $props = $ErrorObject | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        $lines = foreach ($p in $props) {
            try {
                "$p = $($ErrorObject.$p)"
            } catch {
                "$p = <unreadable>"
            }
        }
        $lines -join "`n"
    } catch {
        "Failed to enumerate properties: $_"
    }

    $logContent = @"
==== OBJECT STRING ====
$stringOutput

==== PROPERTY DUMP ====
$propertyDump
"@

    if ($ErroredItemsFolder -and (Test-Path $ErroredItemsFolder)) {
        $SafeName = ($Name -replace '[\\/:*?"<>|]', '_') -replace '\s+', ''
        if ($SafeName.Length -gt 60) {
            $SafeName = $SafeName.Substring(0, 60)
        }
        $filename = "${SafeName}_error_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $fullPath = Join-Path $ErroredItemsFolder $filename
        Set-Content -Path $fullPath -Value $logContent -Encoding UTF8
        if ($Color) {
            Write-Host "Error written to $fullPath" -ForegroundColor $Color
        } else {
            Write-Host "Error written to $fullPath"
        }
    }

    if ($Color) {
        Write-Host "$logContent" -ForegroundColor $Color
    } else {
        Write-Host "$logContent"
    }
}


function Set-HuduInstance {
    param(
        [string]$HuduBaseURL,
        [string]$HuduAPIKey
    )

    while ([string]::IsNullOrWhiteSpace($HuduBaseURL)) {
        $HuduBaseURL = (Read-Host -Prompt 'Set the base domain of your Hudu instance (e.g. https://myinstance.huducloud.com)').Trim()
        $HuduBaseURL = $HuduBaseURL -replace '[\\/]+$', ''
        $HuduBaseURL = $HuduBaseURL -replace '^(?!https://)', 'https://'
    }

    while ([string]::IsNullOrWhiteSpace($HuduAPIKey) -or $HuduAPIKey.Length -ne 24) {
        $HuduAPIKey = (Read-Host -Prompt "Get a Hudu API key from $HuduBaseURL/admin/api_keys").Trim()

        if ($HuduAPIKey.Length -ne 24) {
            Write-Host "This doesn't seem to be a valid Hudu API key. It is $($HuduAPIKey.Length) characters long, but should be 24." -ForegroundColor Red
        }
    }

    New-HuduAPIKey $HuduAPIKey
    New-HuduBaseURL $HuduBaseURL
}

function Set-ExternalModulesInitialized {
    param (
            [string]$HAPImodulePath = "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI\HuduAPI\HuduAPI.psm1",
            [bool]$use_hudu_fork = $true,
            [bool]$RefreshHuduApiForkEachRun = $true,
            [version]$RequiredHuduVersion = [version]"2.39.6",
            $DisallowedVersions = @([version]"2.37.0"),
            [string]$HuduApiRepositoryUrl = $($env:HUDUAPI_REPOSITORY_URL ?? "https://github.com/Hudu-Technologies-Inc/HuduAPI.git"),
            [string]$HuduApiBranch = $($env:HUDUAPI_REPOSITORY_BRANCH ?? "master"),
            [string]$HuduApiZipUrl = $env:HUDUAPI_ZIP_URL,
            [string]$BundledHuduApiZipPath = (
                Join-Path (
                    $(if ($PSScriptRoot) { $PSScriptRoot } else { (Resolve-Path .).Path })
                ) 'HAPI.zip'
            ),
            [string]$HuduBaseURL,
            [string]$HuduAPIKey            
        )
    $AllowHuduGalleryFallback = $false

    function Test-HuduApiModuleLayout {
        param([Parameter(Mandatory)][string]$ModulePath)

        if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
            return $false
        }

        $moduleDirectory = Split-Path -Path $ModulePath -Parent
        return (
            (Test-Path -LiteralPath (Join-Path $moduleDirectory "Public") -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $moduleDirectory "Private") -PathType Container)
        )
    }

    function Get-GitHubRepositoryParts {
        param([Parameter(Mandatory)][string]$RepositoryUrl)

        if ($RepositoryUrl -notmatch 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$') {
            return $null
        }

        [PSCustomObject]@{
            Owner = $matches.owner
            Repo  = ($matches.repo -replace '\.git$', '')
        }
    }

    function New-HuduApiStagingRoot {
        $tempRoot = Join-Path $env:TEMP "HuduAPI-Fork-$([guid]::NewGuid().Guid)"
        New-Item -ItemType Directory -Path $tempRoot -Force -ErrorAction Stop | Out-Null
        return (Join-Path $tempRoot "HuduAPI")
    }

    function Unblock-HuduApiPath {
        param([Parameter(Mandatory)][string]$Path)

        try {
            if (Test-Path -LiteralPath $Path) {
                Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                    Unblock-File -ErrorAction SilentlyContinue
                Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    function Expand-HuduApiZipToStaging {
        param(
            [Parameter(Mandatory)][string]$ZipPath,
            [Parameter(Mandatory)][string]$StagingRepoRoot
        )

        $stagingParent = Split-Path -Path $StagingRepoRoot -Parent
        $extractRoot = Join-Path $stagingParent "zip-extract"

        Unblock-HuduApiPath -Path $ZipPath
        Expand-Archive -Path $ZipPath -DestinationPath $extractRoot -Force -ErrorAction Stop
        Unblock-HuduApiPath -Path $extractRoot

        $candidateRoots = @((Get-Item -LiteralPath $extractRoot -ErrorAction Stop))
        $candidateRoots += @(Get-ChildItem -LiteralPath $extractRoot -Directory -Recurse -ErrorAction Stop)
        $extracted = $candidateRoots |
            Where-Object { Test-HuduApiModuleLayout -ModulePath (Join-Path $_.FullName "HuduAPI\HuduAPI.psm1") } |
            Select-Object -First 1

        if (-not $extracted) {
            throw "Archive did not contain a complete HuduAPI module layout."
        }

        Move-Item -LiteralPath $extracted.FullName -Destination $StagingRepoRoot -Force -ErrorAction Stop
    }

    function Install-HuduApiForkSamuraiStyle {
        param(
            [Parameter(Mandatory)][string]$RepositoryUrl,
            [Parameter(Mandatory)][string]$Branch,
            [Parameter(Mandatory)][string]$StagingRepoRoot
        )

        $git = Get-Command git -ErrorAction SilentlyContinue
        if (-not $git) {
            throw "git was not found on this machine."
        }

        $oldGitPrompt = $env:GIT_TERMINAL_PROMPT
        $oldGitSshCommand = $env:GIT_SSH_COMMAND
        try {
            $env:GIT_TERMINAL_PROMPT = "0"
            $env:GIT_SSH_COMMAND = "ssh -o BatchMode=yes"
            & $git.Source clone --depth 1 --branch $Branch $RepositoryUrl $StagingRepoRoot 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "git clone exited with code $LASTEXITCODE."
            }
        } finally {
            $env:GIT_TERMINAL_PROMPT = $oldGitPrompt
            $env:GIT_SSH_COMMAND = $oldGitSshCommand
        }
    }

    function Install-HuduApiForkAshigaruStyle {
        param(
            [Parameter(Mandatory)][string]$RepositoryUrl,
            [Parameter(Mandatory)][string]$Branch,
            [Parameter(Mandatory)][string]$StagingRepoRoot,
            [string]$ZipUrl
        )

        if ([string]::IsNullOrWhiteSpace($ZipUrl)) {
            $repoParts = Get-GitHubRepositoryParts -RepositoryUrl $RepositoryUrl
            if (-not $repoParts) {
                throw "Ashigaru-Warrior-Style install only supports github.com repository URLs unless HuduApiZipUrl is set."
            }
            $ZipUrl = "https://codeload.github.com/$($repoParts.Owner)/$($repoParts.Repo)/zip/refs/heads/$Branch"
        }

        $stagingParent = Split-Path -Path $StagingRepoRoot -Parent
        $zip = Join-Path $stagingParent "HuduAPI.zip"
        $headers = @{ "User-Agent" = "ITGlue-Hudu-Migration" }

        Invoke-WebRequest -Uri $ZipUrl -Headers $headers -OutFile $zip -ErrorAction Stop | Out-Null
        Expand-HuduApiZipToStaging -ZipPath $zip -StagingRepoRoot $StagingRepoRoot
    }

    function Install-HuduApiForkBundledZipStyle {
        param(
            [Parameter(Mandatory)][string]$ZipPath,
            [Parameter(Mandatory)][string]$StagingRepoRoot
        )

        if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
            throw "Bundled HuduAPI zip was not found at $ZipPath."
        }

        Expand-HuduApiZipToStaging -ZipPath $ZipPath -StagingRepoRoot $StagingRepoRoot
    }

    function Install-HuduApiFork {
        param(
            [Parameter(Mandatory)][string]$ModulePath,
            [Parameter(Mandatory)][string]$RepositoryUrl,
            [Parameter(Mandatory)][string]$Branch,
            [string]$ZipUrl,
            [string]$BundledZipPath
        )

        $targetRepoRoot = Split-Path -Path (Split-Path -Path $ModulePath -Parent) -Parent
        $targetParent = Split-Path -Path $targetRepoRoot -Parent
        $stagingRepoRoot = $null
        $successfulMethod = $null

        $installMethods = @(
            @{
                Name = "Ashigaru-Warrior-Style"
                Script = {
                    param($repoUrl, $branchName, $stagingRoot, $directZipUrl)
                    Install-HuduApiForkAshigaruStyle -RepositoryUrl $repoUrl -Branch $branchName -StagingRepoRoot $stagingRoot -ZipUrl $directZipUrl
                }
            },
            @{
                Name = "Samurai-Style"
                Script = {
                    param($repoUrl, $branchName, $stagingRoot, $directZipUrl)
                    Install-HuduApiForkSamuraiStyle -RepositoryUrl $repoUrl -Branch $branchName -StagingRepoRoot $stagingRoot
                }
            },
            @{
                Name = "Bundled-Zip"
                Script = {
                    param($repoUrl, $branchName, $stagingRoot, $directZipUrl, $localZipPath)
                    Install-HuduApiForkBundledZipStyle -ZipPath $localZipPath -StagingRepoRoot $stagingRoot
                }
            }
        )

        foreach ($method in $installMethods) {
            $stagingRepoRoot = New-HuduApiStagingRoot
            $stagingContainer = Split-Path -Path $stagingRepoRoot -Parent

            try {
                $methodSource = if ($method.Name -eq "Bundled-Zip") { $BundledZipPath } else { "$RepositoryUrl ($Branch)" }
                Write-Host "Trying HuduAPI fork install via $($method.Name) from $methodSource." -ForegroundColor Cyan
                & $method.Script $RepositoryUrl $Branch $stagingRepoRoot $ZipUrl $BundledZipPath

                $stagedModulePath = Join-Path $stagingRepoRoot "HuduAPI\HuduAPI.psm1"
                if (-not (Test-HuduApiModuleLayout -ModulePath $stagedModulePath)) {
                    throw "Downloaded fork did not include a complete HuduAPI module layout."
                }

                $successfulMethod = $method.Name
                break
            } catch {
                Write-Warning "$($method.Name) HuduAPI fork install failed: $($_.Exception.Message)"
                if (Test-Path -LiteralPath $stagingContainer) {
                    Remove-Item -LiteralPath $stagingContainer -Recurse -Force -ErrorAction SilentlyContinue
                }
                $stagingRepoRoot = $null
            }
        }

        if (-not $successfulMethod) {
            throw "Unable to install HuduAPI fork from $RepositoryUrl ($Branch)."
        }

        New-Item -ItemType Directory -Path $targetParent -Force -ErrorAction Stop | Out-Null
        if (Test-Path -LiteralPath $targetRepoRoot) {
            $backupPath = if (Test-HuduApiModuleLayout -ModulePath $ModulePath) {
                "$targetRepoRoot.previous"
            } else {
                "$targetRepoRoot.backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
            }

            if (Test-Path -LiteralPath $backupPath) {
                Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            Move-Item -LiteralPath $targetRepoRoot -Destination $backupPath -Force -ErrorAction Stop
            Write-Host "Existing HuduAPI path was moved to $backupPath before refresh." -ForegroundColor DarkGray
        }

        $stagingGitPath = Join-Path $stagingRepoRoot ".git"
        if (Test-Path -LiteralPath $stagingGitPath) {
            Remove-Item -LiteralPath $stagingGitPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Unblock-HuduApiPath -Path $stagingRepoRoot

        $stagingContainer = Split-Path -Path $stagingRepoRoot -Parent
        New-Item -ItemType Directory -Path $targetRepoRoot -Force -ErrorAction Stop | Out-Null
        Get-ChildItem -LiteralPath $stagingRepoRoot -Force -ErrorAction Stop |
            Copy-Item -Destination $targetRepoRoot -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $stagingContainer) {
            Remove-Item -LiteralPath $stagingContainer -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Installed HuduAPI fork via $successfulMethod to $targetRepoRoot." -ForegroundColor Green
    }

    try {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop
        Write-Host "Process execution policy set to Bypass for this PowerShell session." -ForegroundColor DarkGray
    } catch {
        Write-Warning "Could not set process execution policy to Bypass: $($_.Exception.Message)"
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Warning "Could not force TLS 1.2 for this PowerShell session: $($_.Exception.Message)"
    }
    $ProgressPreference = 'SilentlyContinue'

    if ([string]::IsNullOrWhiteSpace($BundledHuduApiZipPath) -and -not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $BundledHuduApiZipPath = Join-Path $repoRoot "ExternalModules\HuduAPI.zip"
    }

    if ($true -eq $use_hudu_fork) {
        $hasCompleteLocalFork = Test-HuduApiModuleLayout -ModulePath $HAPImodulePath
        if ($RefreshHuduApiForkEachRun -or -not $hasCompleteLocalFork) {
            $refreshReason = if ($RefreshHuduApiForkEachRun) {
                "Refreshing local HuduAPI fork from the latest $HuduApiBranch branch."
            } else {
                "No complete local HuduAPI fork found. Downloading the latest $HuduApiBranch branch."
            }

            Write-Host $refreshReason -ForegroundColor Cyan
            Install-HuduApiFork -ModulePath $HAPImodulePath -RepositoryUrl $HuduApiRepositoryUrl -Branch $HuduApiBranch -ZipUrl $HuduApiZipUrl -BundledZipPath $BundledHuduApiZipPath
        } else {
            Write-Host "Using existing HuduAPI fork at $HAPImodulePath." -ForegroundColor DarkGray
        }
    } else {
        Write-Host "HuduAPI fork loading is disabled. PSGallery will only be used if AllowHuduGalleryFallback is true."
    }

    Remove-Module HuduAPI -Force -ErrorAction SilentlyContinue
    if (Test-HuduApiModuleLayout -ModulePath $HAPImodulePath) {
        $huduApiManifestPath = [System.IO.Path]::ChangeExtension($HAPImodulePath, ".psd1")
        $huduApiImportPath = if (Test-Path -LiteralPath $huduApiManifestPath -PathType Leaf) { $huduApiManifestPath } else { $HAPImodulePath }
        Import-Module $huduApiImportPath -Force -ErrorAction Stop
        Write-Host "Module imported from $huduApiImportPath"
    } elseif (-not $AllowHuduGalleryFallback) {
        write-host "Sorry, it seems we weren't able to load the Hudu-Fork of HuduAPI module, which is required for the latest features that this fork provides."
        write-host "You can manually download this project https://github.com/Hudu-Technologies-Inc/HuduAPI and extract it to Documents/GitHub folder."
        throw "HuduAPI fork was requested, but no complete fork module was available at $HAPImodulePath. PSGallery fallback is disabled."
    } elseif ((Get-Module -ListAvailable -Name HuduAPI).Version -ge [version]'3.1.1') {
        Import-Module HuduAPI -ErrorAction Stop
        Write-Host "Module 'HuduAPI' imported from global/module path"
    } else {
        Install-Module HuduAPI -MinimumVersion 3.1.1 -Scope CurrentUser -Force -ErrorAction Stop
        Import-Module HuduAPI -ErrorAction Stop
        Write-Host "Installed and imported HuduAPI from PSGallery"
    }

    #Login to Hudu
    Set-HuduInstance -HuduBaseURL $HuduBaseURL -HuduAPIKey $HuduAPIKey

    # Check we have the correct version
    $CurrentVersion = [version]($(Get-HuduAppInfo).version)

    try {
        remove-module ITGlueAPI -ErrorAction SilentlyContinue
    } catch {
    }
    #Grabbing ITGlue Module and installing.
    If (Get-Module -ListAvailable -Name "ITGlueAPIv2") { 
        Import-module ITGlueAPIv2 
    } Else { 
        Install-Module ITGlueAPIv2 -Force
        Import-Module ITGlueAPIv2
    }


    #Settings IT-Glue logon information
    Add-ITGlueBaseURI -base_uri $ITGAPIEndpoint
    Add-ITGlueAPIKey $ITGKey
    return $CurrentVersion
}


function Unset-Vars {
    param (
        [string]$varname,
        [string[]]$scopes = @('Local', 'Script', 'Global', 'Private')
    )

    foreach ($scope in $scopes) {
        try {
            if (Get-Variable -Name $varname -Scope $scope -ErrorAction SilentlyContinue) {
                Remove-Variable -Name $varname -Scope $scope -Force -ErrorAction SilentlyContinue
                Write-Host "Unset `$${varname} from scope: $scope"
            }
        } catch {}
    }
}
