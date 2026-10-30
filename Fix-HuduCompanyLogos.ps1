# Load required assemblies for Selenium
function Initialize-SeleniumDependencies {
    param(
        [string]$OutputPath = "$env:TEMP\selenium-deps",
        [switch]$Force,
        [switch]$DiagnosticMode
    )
    
    Write-Host "Starting Selenium dependencies initialization..." -ForegroundColor Cyan
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $OutputPath)) {
        Write-Host "Creating output directory: $OutputPath"
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    } else {
        Write-Host "Using existing output directory: $OutputPath"
    }
    
    # Define required NuGet packages with correct mappings for assembly files
    $seleniumPackages = @(
        @{
            Name = "Selenium.WebDriver"
            Version = "4.15.0"
            DirectDownloadUrl = "https://www.nuget.org/api/v2/package/Selenium.WebDriver/4.15.0"
            AssemblyFileName = "WebDriver.dll"
        },
        @{
            Name = "Selenium.Support"
            Version = "4.15.0"
            DirectDownloadUrl = "https://www.nuget.org/api/v2/package/Selenium.Support/4.15.0"
            AssemblyFileName = "WebDriver.Support.dll"
        }
    )
    
    if ($DiagnosticMode) {
        Write-Host "DIAGNOSTIC INFO:" -ForegroundColor Magenta
        Write-Host "Internet Connection Test:" -ForegroundColor Magenta
        $testResult = Test-NetConnection -ComputerName "api.nuget.org" -Port 443
        Write-Host "  Connection to api.nuget.org: $($testResult.TcpTestSucceeded)" -ForegroundColor ($testResult.TcpTestSucceeded ? "Green" : "Red")
        
        Write-Host "PowerShell Package Provider Info:" -ForegroundColor Magenta
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if ($nugetProvider) {
            Write-Host "  NuGet Provider Version: $($nugetProvider.Version)" -ForegroundColor Green
        } else {
            Write-Host "  NuGet Provider not found!" -ForegroundColor Red
        }
        
        Write-Host "Package Sources:" -ForegroundColor Magenta
        Get-PackageSource | Format-Table -AutoSize
    }
    
    Write-Host "Checking NuGet package source..."
    # Register NuGet source if not already registered
    if (-not (Get-PackageSource -Name "nuget.org" -ErrorAction SilentlyContinue)) {
        Write-Host "Registering NuGet package source..." -ForegroundColor Yellow
        Register-PackageSource -Name "nuget.org" -Location "https://api.nuget.org/v3/index.json" -ProviderName NuGet
        Write-Host "NuGet package source registered successfully" -ForegroundColor Green
    } else {
        Write-Host "NuGet package source already registered" -ForegroundColor Green
    }
    
    $packagesProcessed = 0
    $totalPackages = $seleniumPackages.Count
    
    # Download and load required assemblies
    foreach ($package in $seleniumPackages) {
        $packagesProcessed++
        $packagePath = Join-Path $OutputPath "$($package.Name).$($package.Version)"
        
        Write-Host "[$packagesProcessed/$totalPackages] Processing $($package.Name) v$($package.Version)..." -ForegroundColor Cyan
        
        $needToDownload = $Force -or (-not (Test-Path $packagePath))
        
        if ($needToDownload) {
            Write-Host "   Package not found locally or Force specified. Downloading from NuGet..." -ForegroundColor Yellow
            
            # Attempt direct download first (usually faster)
            $downloadStartTime = Get-Date
            $downloadSuccess = $false
            
            try {
                Write-Host "   Attempting direct download from NuGet API..." -ForegroundColor Yellow
                $tempZipFile = Join-Path $env:TEMP "$($package.Name)-$($package.Version).nupkg"
                
                # Use WebClient for direct download (usually faster than Save-Package)
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "PowerShell NuGet Client")
                
                Write-Host "   Downloading from: $($package.DirectDownloadUrl)" -ForegroundColor Yellow
                $wc.DownloadFile($package.DirectDownloadUrl, $tempZipFile)
                
                # Create target directory
                if (-not (Test-Path $packagePath)) {
                    New-Item -ItemType Directory -Path $packagePath -Force | Out-Null
                }
                
                # Extract the NuGet package (which is just a ZIP file)
                Write-Host "   Extracting package..." -ForegroundColor Yellow
                Expand-Archive -Path $tempZipFile -DestinationPath $packagePath -Force
                
                # Clean up temp file
                Remove-Item $tempZipFile -Force -ErrorAction SilentlyContinue
                
                $downloadDuration = (Get-Date) - $downloadStartTime
                Write-Host "   Direct download completed in $($downloadDuration.TotalSeconds.ToString('0.00')) seconds" -ForegroundColor Green
                $downloadSuccess = $true
            }
            catch {
                Write-Host "   Direct download failed: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "   Falling back to Save-Package method..." -ForegroundColor Yellow
            }
            
            # Fall back to Save-Package if direct download failed
            if (-not $downloadSuccess) {
                $downloadStartTime = Get-Date
                try {
                    Save-Package -Name $package.Name -RequiredVersion $package.Version -Path $OutputPath -Source "nuget.org" -ProviderName NuGet -Force
                    $downloadDuration = (Get-Date) - $downloadStartTime
                    Write-Host "   Download completed in $($downloadDuration.TotalSeconds.ToString('0.00')) seconds" -ForegroundColor Green
                    $downloadSuccess = $true
                } catch {
                    Write-Host "   Error downloading package: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "   Try running this script with administrator privileges or manually download the package from nuget.org" -ForegroundColor Yellow
                    continue
                }
            }
            
            # If all downloads failed, suggest manual download
            if (-not $downloadSuccess) {
                Write-Host "   All download methods failed." -ForegroundColor Red
                Write-Host "   Please manually download $($package.Name) v$($package.Version) from nuget.org and place it in: $packagePath" -ForegroundColor Yellow
                continue
            }
        } else {
            Write-Host "   Package already exists locally" -ForegroundColor Green
        }
        
        # Find and load assemblies - First look specifically for netstandard2.0
        Write-Host "   Looking for .NET assemblies..."
        $assemblyPath = $null
        
        # Priority order for framework directory search
        $frameworkDirPriority = @(
            "netstandard2.0",
            "net45",
            "net451",
            "net452",
            "net46",
            "net461",
            "net462",
            "net47",
            "net471",
            "net472",
            "net48",
            "netstandard2.1"
        )
        
        # Try the priority list first
        $libDir = Join-Path $packagePath "lib"
        if (Test-Path $libDir) {
            foreach ($framework in $frameworkDirPriority) {
                $frameworkDir = Join-Path $libDir $framework
                if (Test-Path $frameworkDir) {
                    Write-Host "   Found framework directory: $framework"
                    $assemblyFilePath = Join-Path $frameworkDir $package.AssemblyFileName
                    if (Test-Path $assemblyFilePath) {
                        $assemblyPath = $assemblyFilePath
                        Write-Host "   Found assembly at: $assemblyPath" -ForegroundColor Green
                        break
                    }
                }
            }
        }
        
        # If not found with priority list, search recursively
        if (-not $assemblyPath) {
            Write-Host "   Assembly not found in expected locations, searching recursively..." -ForegroundColor Yellow
            $foundAssemblies = Get-ChildItem -Path $packagePath -Filter $package.AssemblyFileName -Recurse
            if ($foundAssemblies) {
                $assemblyPath = $foundAssemblies[0].FullName
                Write-Host "   Found assembly at: $assemblyPath" -ForegroundColor Green
            } else {
                Write-Host "   Could not find $($package.AssemblyFileName) in the package" -ForegroundColor Red
                continue
            }
        }
        
        # Load the assembly if found
        if ($assemblyPath) {
            try {
                Write-Host "   Loading assembly from: $assemblyPath"
                Add-Type -Path $assemblyPath -ErrorAction Stop
                Write-Host "   Successfully loaded $($package.Name) assembly" -ForegroundColor Green
            } catch {
                Write-Host "   Error loading $($package.Name) assembly: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "   This may be because the assembly is already loaded or there's a version conflict" -ForegroundColor Yellow
            }
        } else {
            Write-Host "   Could not find assembly for $($package.Name)" -ForegroundColor Red
        }
        
        Write-Host ""
    }
    
    Write-Host "Selenium dependencies initialization completed" -ForegroundColor Cyan
}

function Get-ChromeVersion {
    $chrome = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe').'(Default)'
    if ($chrome) {
        $version = (Get-Item $chrome).VersionInfo.FileVersion
        return $version.Split('.')[0..2] -join '.'
    }
    return $null
}

function Download-MatchingChromeDriver {
    param (
        [string]$OutputPath = "$env:TEMP\chromedriver"
    )
    
    # Get Chrome version
    $chromeVersion = Get-ChromeVersion
    if (-not $chromeVersion) {
        throw "Chrome not found on system"
    }
    
    Write-Host "Chrome version detected: $chromeVersion"
    
    # Check if ChromeDriver already exists and matches version
    $driverPath = Join-Path $OutputPath "chromedriver-win64\chromedriver.exe"
    if (Test-Path $driverPath) {
        Write-Host "Found existing ChromeDriver..."
        try {
            $existingVersion = & $driverPath --version
            if ($existingVersion -match $chromeVersion) {
                Write-Host "Existing ChromeDriver version matches Chrome. Reusing..."
                return $driverPath
            }
            Write-Host "Version mismatch. Downloading new version..."
        }
        catch {
            Write-Host "Error checking existing ChromeDriver. Will download new version..."
        }
    }
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    # Clear existing ChromeDriver files only if we need to download new version
    Get-ChildItem $OutputPath | Remove-Item -Force -Recurse
    
    # Download matching ChromeDriver version
    $downloadUrl = "https://storage.googleapis.com/chrome-for-testing-public/$chromeVersion.0/win64/chromedriver-win64.zip"
    
    Write-Host "Downloading ChromeDriver version $chromeVersion..."
    
    try {
        $zipPath = Join-Path $OutputPath "chromedriver.zip"
        
        # Use faster download method
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($downloadUrl, $zipPath)
        
        Expand-Archive -Path $zipPath -DestinationPath $OutputPath -Force
        Remove-Item $zipPath -Force
        
        return $driverPath
    }
    catch {
        throw "Failed to download ChromeDriver: $($_.Exception.Message)"
    }
}

function Download-FileWithSeleniumCookies {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Url,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory=$true)]
        [object]$Driver
    )

    # Verify parameters are not null
    if ([string]::IsNullOrEmpty($Url)) {
        Write-Host "Error: URL parameter cannot be null or empty" -ForegroundColor Red
        return $false
    }
    
    if ([string]::IsNullOrEmpty($OutputPath)) {
        Write-Host "Error: OutputPath parameter cannot be null or empty" -ForegroundColor Red
        return $false
    }
    
    if ($null -eq $Driver) {
        Write-Host "Error: Driver parameter cannot be null" -ForegroundColor Red
        return $false
    }

    $handler = $null
    $client = $null
    
    try {
        Write-Host "Preparing to download from: $Url"
        
        # Create a new WebClient with cookies from Selenium
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.CookieContainer = New-Object System.Net.CookieContainer
        
        # Verify that the driver has a cookie manager
        $cookieManager = $Driver.Manage()
        if ($null -eq $cookieManager) {
            Write-Host "Error: Unable to access the driver's cookie manager" -ForegroundColor Red
            return $false
        }
        
        # Get cookies from Selenium session
        $cookies = $cookieManager.Cookies
        if ($null -eq $cookies) {
            Write-Host "Error: Unable to access cookies from the driver" -ForegroundColor Red
            return $false
        }
        
        $allCookies = $cookies.AllCookies
        if ($null -eq $allCookies -or $allCookies.Count -eq 0) {
            Write-Host "Warning: No cookies found in the browser session" -ForegroundColor Yellow
        } else {
            Write-Host "Found $($allCookies.Count) cookies to transfer"
            
            # Copy cookies from Selenium session
            foreach ($cookie in $allCookies) {
                if ($null -ne $cookie -and 
                    ![string]::IsNullOrEmpty($cookie.Name) -and 
                    ![string]::IsNullOrEmpty($cookie.Domain)) {
                    
                    try {
                        $netCookie = New-Object System.Net.Cookie(
                            $cookie.Name,
                            $cookie.Value,
                            $cookie.Path,
                            $cookie.Domain
                        )
                        $handler.CookieContainer.Add($netCookie)
                    } catch {
                        Write-Host "Warning: Failed to add cookie $($cookie.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
            }
        }

        # Create HttpClient with the handler
        $client = New-Object System.Net.Http.HttpClient($handler)
        $client.Timeout = [System.TimeSpan]::FromMinutes(5) # Set a reasonable timeout
        
        # Add headers to mimic browser
        $client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0.4472.124 Safari/537.36")
        $client.DefaultRequestHeaders.Add("Accept", "*/*")
        $client.DefaultRequestHeaders.Add("Accept-Encoding", "gzip, deflate")
        $client.DefaultRequestHeaders.Add("Referer", $Driver.Url)
        
        # Create directory if it doesn't exist
        $outputDir = [System.IO.Path]::GetDirectoryName($OutputPath)
        if (![System.IO.Directory]::Exists($outputDir)) {
            [System.IO.Directory]::CreateDirectory($outputDir)
        }

        Write-Host "Starting download..."
        
        # Download the file
        $downloadTask = $client.GetByteArrayAsync($Url)
        
        # Wait for the task to complete
        if (-not $downloadTask.Wait(300000)) { # 5 minute timeout
            Write-Host "Error: Download timed out after 5 minutes" -ForegroundColor Red
            return $false
        }
        
        # Check if task was successful
        if ($downloadTask.IsFaulted) {
            if ($null -ne $downloadTask.Exception) {
                Write-Host "Error during download: $($downloadTask.Exception.InnerException.Message)" -ForegroundColor Red
            } else {
                Write-Host "Error during download: Unknown error" -ForegroundColor Red
            }
            return $false
        }
        
        # Get the result and write to file
        $responseBytes = $downloadTask.Result
        if ($null -eq $responseBytes -or $responseBytes.Length -eq 0) {
            Write-Host "Error: Downloaded content is empty" -ForegroundColor Red
            return $false
        }
        
        Write-Host "Download complete. Writing $($responseBytes.Length) bytes to: $OutputPath"
        [System.IO.File]::WriteAllBytes($OutputPath, $responseBytes)
        
        # Verify the file was written
        if (Test-Path -Path $OutputPath) {
            $fileInfo = Get-Item -Path $OutputPath
            Write-Host "File successfully saved. Size: $([Math]::Round($fileInfo.Length / 1KB, 2)) KB" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Error: File was not created at the specified path" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "Error downloading file: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        return $false
    }
    finally {
        # Ensure resources are properly disposed
        if ($null -ne $client) {
            $client.Dispose()
        }
        if ($null -ne $handler) {
            $handler.Dispose()
        }
    }
}

function Download-ITGlueLogos {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Email,
        
        [Parameter(Mandatory=$true)]
        [string]$Password,
        
        [string]$WebBaseUrl = "https://pendello.itglue.com",
        
        [string]$OutputDir = "$MigrationLogs\ITGExport\organization-logos"
    )

    try {
        # Create output directory if it doesn't exist
        if (-not (Test-Path -Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }

        # Get all organizations first
        Write-Host "Getting organizations from IT Glue API..."
        $Orgs = Get-ITGlueOrganizations
        $totalOrgs = $Orgs.data.Count
        Write-Host "Found $totalOrgs organizations"

        # Download matching ChromeDriver
        Write-Host "Setting up ChromeDriver..."
        $chromeDriverPath = Download-MatchingChromeDriver
        Write-Host "ChromeDriver path: $chromeDriverPath"

        # Set ChromeDriver directory in environment path
        $env:PATH = "$(Split-Path $chromeDriverPath -Parent);$env:PATH"

        # Create Chrome options
        $chromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
        $chromeOptions.AddArgument('--start-maximized')
        $chromeOptions.AddArgument('--disable-extensions')
        
        # Set the binary location explicitly
        $chromeOptions.BinaryLocation = "C:\Program Files\Google\Chrome\Application\chrome.exe"

        # Create ChromeDriver service
        $service = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService((Split-Path $chromeDriverPath -Parent), "chromedriver.exe")

        # Create WebClient for downloading files
        $webClient = New-Object System.Net.WebClient

        # Start Chrome with options and service
        Write-Host "Starting Chrome..."
        $driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($service, $chromeOptions)
        
        # Navigate to IT Glue with SSO disabled
        Write-Host "Navigating to IT Glue..."
        $driver.Navigate().GoToUrl("$WebBaseUrl/?sso_disabled=true")

        # Handle login and 2FA
        Write-Host "Entering credentials..."
        Start-Sleep -Seconds 2

        try {
            $emailField = $driver.FindElement([OpenQA.Selenium.By]::Name("username"))
            $emailField.SendKeys($Email)
            
            $passwordField = $driver.FindElement([OpenQA.Selenium.By]::Name("password"))
            $passwordField.SendKeys($Password)
            
            $loginButton = $driver.FindElement([OpenQA.Selenium.By]::ClassName("login__button"))
            $loginButton.Click()

            $2faCode = Read-Host "Enter 2FA code"

            $codeField = $driver.FindElement([OpenQA.Selenium.By]::Name("mfa"))
            $codeField.SendKeys($2faCode)

            $loginButton.Click()
            Start-Sleep -Seconds 5
        } catch {
            Write-Host "Error during login: $($_.Exception.Message)" -ForegroundColor Red
            throw
        }

        # Process organizations
        $current = 0
        foreach ($Org in $Orgs.data) {
            $current++
            $orgID = $Org.id
            $orgName = $Org.attributes.name
            
            Write-Host "`nProcessing ($current/$totalOrgs): $orgName" -ForegroundColor Cyan
            
            try {
                # Navigate to logo URL
                $logoUrl = "$WebBaseUrl/$orgID/logo"
                Write-Host "Accessing: $logoUrl"
                $driver.Navigate().GoToUrl($logoUrl)
                Start-Sleep -Seconds 2
        
                # Get the AWS URL after redirect
                $awsUrl = $driver.Url
                Write-Host "Redirected to: $awsUrl"
        
                # Only proceed if we got redirected to an AWS URL
                if ($awsUrl -match "amazonaws.com") {
                    # Create safe filename
                    $safeName = $orgName -replace '[^\w\-\.]', '_'
                    $safeName = $safeName -replace '\.+$', '' # Remove trailing dots
                    $fileName = "$orgID`_$safeName.png"
                    $filePath = Join-Path $OutputDir $fileName
        
                    Write-Host "Downloading logo to: $filePath"
                    if (Download-FileWithSeleniumCookies -Url $awsUrl -OutputPath $filePath -Driver $driver) {
                        Write-Host "Successfully downloaded logo" -ForegroundColor Green
                    }
                }
                else {
                    Write-Host "No logo found for this organization" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "Error processing $orgName`: $($_.Exception.Message)" -ForegroundColor Red
            }
        
            # Small delay between organizations
            Start-Sleep -Seconds 1
        }
        
        Write-Host "`nAll organizations processed!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if ($webClient) {
            $webClient.Dispose()
        }
        if ($driver) {
            $driver.Quit()
        }
        if ($service) {
            $service.Dispose()
        }
    }
}

function Get-CompanyMapping {
    
    # Import the JSON file
    $companyData = Get-Content -Path "C:\Users\JacobNewman\AppData\Roaming\HuduMigration\pendello.itglue.com\MigrationLogs\Companies.json" | ConvertFrom-Json

    # Create a lookup table/reference
    $companyMatches = @{}

    foreach ($company in $companyData) {
        $companyMatches[$company.CompanyName] = @{
            'ITGlueID' = $company.ITGID
            'HuduID'   = $company.HuduID
        }
    }

    # Sort by company name for easy reference
    $companyMatches = $companyMatches.GetEnumerator() | Sort-Object Name | ForEach-Object {
        [PSCustomObject]@{
            CompanyName = $_.Name
            ITGlueID    = $_.Value.ITGlueID
            HuduID      = $_.Value.HuduID
        }
    }

    # Output to CSV for easy reference
    $companyMatches | Export-Csv -Path "C:\Users\JacobNewman\AppData\Roaming\HuduMigration\pendello.itglue.com\MigrationLogs\CompanyIDMapping.csv" -NoTypeInformation

    # Display the matches
    $companyMatches | Format-Table -AutoSize

    Write-Host "`nTotal Companies: $($companyMatches.Count)"
    Write-Host "Results exported to CompanyIDMapping.csv"
}

# Upload Logo to associated Hudu Company
function Upload-CompanyLogos {
    param(
        [string]$LogoPath = "C:\Users\JacobNewman\AppData\Roaming\HuduMigration\pendello.itglue.com\MigrationLogs\ITGExport\organization-logos",
        [string]$HuduBaseURL = (Get-Content -Path "C:\Users\JacobNewman\AppData\Roaming\HuduMigration\pendello.itglue.com\settings.json" | ConvertFrom-Json -Depth 50).HuduBaseDomain,
        [Parameter(Mandatory=$true)]
        [string]$HuduEmail,
        [Parameter(Mandatory=$true)]
        [string]$HuduPassword
    )

    try {

        Write-Host "$MigrationLogs"

        # Import the JSON file
        $companyData = Get-Content -Path "C:\Users\JacobNewman\AppData\Roaming\HuduMigration\pendello.itglue.com\MigrationLogs\Companies.json" | ConvertFrom-Json
        
        # Create a lookup table/reference
        $companies = $companyData | ForEach-Object {
            [PSCustomObject]@{
                CompanyName = $_.CompanyName
                ITGlueID = $_.ITGID
                HuduID = $_.HuduID
                HuduSlug = $_.HuduCompanyObject.slug
            }
        } | Sort-Object CompanyName

        # Setup ChromeDriver
        Write-Host "Setting up ChromeDriver..."
        $chromeDriverPath = Download-MatchingChromeDriver
        Write-Host "ChromeDriver path: $chromeDriverPath"

        # Set ChromeDriver directory in environment path
        $env:PATH = "$(Split-Path $chromeDriverPath -Parent);$env:PATH"

        # Create Chrome options
        $chromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
        $chromeOptions.AddArgument('--start-maximized')
        $chromeOptions.AddArgument('--disable-extensions')
        
        # Set the binary location explicitly
        $chromeOptions.BinaryLocation = "C:\Program Files\Google\Chrome\Application\chrome.exe"

        # Create ChromeDriver service
        $service = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService((Split-Path $chromeDriverPath -Parent), "chromedriver.exe")
        
        # Start Chrome with options and service
        Write-Host "Starting Chrome..."
        $driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($service, $chromeOptions)
        
        # Login to Hudu
        Write-Host "Logging into Hudu..."
        $driver.Navigate().GoToUrl("$HuduBaseURL")
        Start-Sleep -Seconds 2

        # Fill in login credentials
        $driver.FindElement([OpenQA.Selenium.By]::Id("email")).SendKeys($HuduEmail)
        $driver.FindElement([OpenQA.Selenium.By]::Id("user_password")).SendKeys($HuduPassword)
        $driver.FindElement([OpenQA.Selenium.By]::ClassName("button--primary")).Click()
        Start-Sleep -Seconds 2
        $HuduOTP = Read-Host "Enter 2FA code"
        $driver.FindElement([OpenQA.Selenium.By]::id("otp")).SendKeys($HuduOTP)
        $driver.FindElement([OpenQA.Selenium.By]::ClassName("button--primary")).Click()

        Start-Sleep -Seconds 5

        # Process each logo file
        Get-ChildItem -Path $LogoPath -Filter "*.png" | ForEach-Object {
            $logoFile = $_
            
            # Extract ITGlue ID from filename
            $itglueId = ($logoFile.BaseName -split '_')[0]
            
            # Find matching company
            $company = $companies | Where-Object { $_.ITGlueID -eq $itglueId }
            
            if ($company) {
                Write-Host "Processing logo for $($company.CompanyName)..."
                
                try {
                    # Navigate to company edit page
                    $editUrl = "$HuduBaseURL/c/$($company.HuduSlug)/edit"
                    $driver.Navigate().GoToUrl($editUrl)
                    Start-Sleep -Seconds 2

                    # Find and interact with logo upload field
                    $fileInput = $driver.FindElement([OpenQA.Selenium.By]::CssSelector("input[type='file']"))
                    $fileInput.SendKeys($logoFile.FullName)

                    # Click save button
                    $saveButton = $driver.FindElement([OpenQA.Selenium.By]::CssSelector("input[type='submit']"))
                    $saveButton.Click()
                    
                    Start-Sleep -Seconds 3
                    Write-Host "Successfully uploaded logo for $($company.CompanyName)" -ForegroundColor Green
                }
                catch {
                    Write-Host "Error uploading logo for $($company.CompanyName): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            else {
                Write-Host "No matching company found for logo file: $($logoFile.Name)" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if ($driver) {
            $driver.Quit()
        }
        if ($service) {
            $service.Dispose()
        }
    }
}