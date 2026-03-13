# ui/build_exe.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$CLEAN_BUILD_OUT_AFTER_SUCCESS = $true

function Log([string]$msg) {
  $ts = Get-Date -Format "HH:mm:ss"
  Write-Host "[$ts] $msg"
}

function Ensure-Dir([string]$Path) {
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Remove-WithRetry([string]$Path, [int]$Retries = 12, [int]$DelayMs = 600) {
  if (-not (Test-Path $Path)) { return }
  for ($i = 0; $i -lt $Retries; $i++) {
    try {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      return
    } catch {
      Start-Sleep -Milliseconds $DelayMs
    }
  }
  throw "Failed to delete locked path after retries: $Path"
}

function Invoke-Python {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
  )

  if (-not $script:PythonExe) {
    throw "Python command has not been initialized."
  }

  & $script:PythonExe @script:PythonBaseArgs @Args
}

function New-AppIconFromPng {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PngPath,
    [Parameter(Mandatory = $true)]
    [string]$IcoPath
  )

  Add-Type -AssemblyName System.Drawing
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeIcon {
  [DllImport("user32.dll", CharSet = CharSet.Auto)]
  public static extern bool DestroyIcon(IntPtr handle);
}
"@

  $size = 256
  $src = [System.Drawing.Image]::FromFile($PngPath)
  try {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    try {
      $gfx = [System.Drawing.Graphics]::FromImage($bmp)
      try {
        $gfx.Clear([System.Drawing.Color]::Transparent)
        $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        $scale = [Math]::Min($size / $src.Width, $size / $src.Height)
        $drawW = [int][Math]::Round($src.Width * $scale)
        $drawH = [int][Math]::Round($src.Height * $scale)
        $drawX = [int][Math]::Floor(($size - $drawW) / 2)
        $drawY = [int][Math]::Floor(($size - $drawH) / 2)

        $gfx.DrawImage($src, $drawX, $drawY, $drawW, $drawH)
      } finally {
        $gfx.Dispose()
      }

      $hIcon = $bmp.GetHicon()
      try {
        $icon = [System.Drawing.Icon]::FromHandle($hIcon)
        try {
          $fs = [System.IO.File]::Create($IcoPath)
          try {
            $icon.Save($fs)
          } finally {
            $fs.Dispose()
          }
        } finally {
          $icon.Dispose()
        }
      } finally {
        [NativeIcon]::DestroyIcon($hIcon) | Out-Null
      }
    } finally {
      $bmp.Dispose()
    }
  } finally {
    $src.Dispose()
  }
}

# ---------- start ----------
$scriptPath = $MyInvocation.MyCommand.Path
$uiDir      = Split-Path -Parent $scriptPath
$repoRoot   = Split-Path -Parent $uiDir
Set-Location $repoRoot

$logDir = Join-Path $uiDir "build_logs"
Ensure-Dir $logDir
$logPath = Join-Path $logDir ("build_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

Log "Running script: $scriptPath"
Log "Repo root: $repoRoot"
Log "Transcript: $logPath"

Start-Transcript -Path $logPath -Force | Out-Null

try {
  # ---------- sanity checks ----------
  $mainPy = Join-Path $uiDir "main.py"
  if (-not (Test-Path $mainPy)) { throw "Missing ui/main.py at: $mainPy" }
  $appIconPng = Join-Path $uiDir "hudu_logo.png"
  if (-not (Test-Path $appIconPng)) { throw "Missing app icon PNG: $appIconPng" }

  $required = @("environ.example","ITGlue-Hudu-Migration.ps1","Initialize-Module.ps1","README.md")
  foreach ($f in $required) {
    $p = Join-Path $repoRoot $f
    if (-not (Test-Path $p)) { throw "Missing required repo file: $f ($p)" }
  }

  # ---------- find python ----------
  $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
  $script:PythonExe = $null
  $script:PythonBaseArgs = @()

  if ($pythonCmd) {
    $script:PythonExe = $pythonCmd.Source
  } else {
    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd) {
      $script:PythonExe = $pyCmd.Source
      $script:PythonBaseArgs = @("-3")
    }
  }

  if (-not $script:PythonExe) {
    throw "Neither python nor py was found on PATH. Install Python 3.x and re-open PowerShell."
  }
  Log "Python launcher: $script:PythonExe $($script:PythonBaseArgs -join ' ')"

  # ---------- stop lockers (best effort) ----------
  Log "Killing possible lockers..."
  Get-Process "ITGlue-Hudu-Migration-GUI" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

  # ---------- deps ----------
  Log "Upgrading pip..."
  Invoke-Python -m pip install --upgrade pip | Out-Host

  Log "Installing build dependencies (PySide6, pyinstaller, markdown)..."
  Invoke-Python -m pip install --upgrade PySide6 pyinstaller markdown | Out-Host

  Log "Preflight: python -m py_compile ui/main.py"
  Invoke-Python -m py_compile $mainPy

  # ---------- build paths (kept inside ui/ so repo root stays clean) ----------
  $outRoot  = Join-Path $uiDir "build_out"
  $stage    = Join-Path $outRoot "_stage"
  $workPath = Join-Path $outRoot "_work"
  $specPath = $outRoot
  $appIconIco = Join-Path $outRoot "hudu_logo.ico"

  Ensure-Dir $outRoot

  Log "Cleaning build_out..."
  Remove-WithRetry $stage -Retries 10 -DelayMs 600
  Remove-WithRetry $workPath -Retries 10 -DelayMs 600
  if (Test-Path (Join-Path $specPath "ITGlue-Hudu-Migration-GUI.spec")) {
    Remove-Item -LiteralPath (Join-Path $specPath "ITGlue-Hudu-Migration-GUI.spec") -Force
  }
  if (Test-Path $appIconIco) {
    Remove-Item -LiteralPath $appIconIco -Force
  }
  Ensure-Dir $stage

  Log "Preparing EXE icon..."
  New-AppIconFromPng -PngPath $appIconPng -IcoPath $appIconIco

  # ---------- clean published outputs in repo root ----------
  Log "Cleaning published outputs in repo root..."
  Remove-WithRetry (Join-Path $repoRoot "_internal") -Retries 10 -DelayMs 600
  Remove-WithRetry (Join-Path $repoRoot "ITGlue-Hudu-Migration-GUI.exe") -Retries 10 -DelayMs 600

  # ---------- build into stage ----------
  Log "Running PyInstaller (staging)..."
  Invoke-Python -m PyInstaller `
    --noconsole `
    --clean `
    --name "ITGlue-Hudu-Migration-GUI" `
    --distpath $stage `
    --workpath $workPath `
    --specpath $specPath `
    --contents-directory "_internal" `
    --icon $appIconIco `
    --add-data "$appIconPng;." `
    $mainPy | Out-Host

  $builtDir      = Join-Path $stage "ITGlue-Hudu-Migration-GUI"
  $builtExe      = Join-Path $builtDir "ITGlue-Hudu-Migration-GUI.exe"
  $builtInternal = Join-Path $builtDir "_internal"

  if (-not (Test-Path $builtExe)) { throw "Build finished but EXE not found: $builtExe" }
  if (-not (Test-Path $builtInternal)) { throw "Build finished but _internal not found: $builtInternal" }

  # ---------- publish to repo root ----------
  Log "Publishing into repo root..."
  Move-Item -LiteralPath $builtExe -Destination (Join-Path $repoRoot "ITGlue-Hudu-Migration-GUI.exe") -Force
  Move-Item -LiteralPath $builtInternal -Destination (Join-Path $repoRoot "_internal") -Force

  if ($CLEAN_BUILD_OUT_AFTER_SUCCESS) {
  Log "Cleaning ui\build_out (post-success)..."
  Remove-WithRetry $outRoot -Retries 10 -DelayMs 600
  }

  # Optional: copy any other build outputs (rare)
  Get-ChildItem -LiteralPath $builtDir -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $repoRoot -Force
  }

  Log ""
  Log "✅ Build complete:"
  Log "    EXE:      $(Join-Path $repoRoot "ITGlue-Hudu-Migration-GUI.exe")"
  Log "    INTERNAL: $(Join-Path $repoRoot "_internal")"
  Log ""
  Log "Run it from: $(Join-Path $repoRoot "ITGlue-Hudu-Migration-GUI.exe")"
}
catch {
  Log ""
  Log "❌ BUILD FAILED"
  Log $_.Exception.Message
  Log "See build log: $logPath"
}
finally {
  try { Stop-Transcript | Out-Null } catch {}
  Read-Host "Press Enter to close"
}
