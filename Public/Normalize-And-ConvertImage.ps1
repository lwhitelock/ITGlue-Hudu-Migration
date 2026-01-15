[string]$WorkingDirectory = "c:\tmp\images"

function Get-ImageType {
    param (
        [string]$FilePath
    )
    try {
        $Magick = New-Object ImageMagick.MagickImage($FilePath)
        return $Magick.Format.ToString().ToLower()
    } catch {
        return $null
    }
}
function Get-SafeFilename {
    param([string]$Name,
        [int]$MaxLength=25
    )

    # If there's a '?', take only the part before it
    $BaseName = $Name -split '\?' | Select-Object -First 1

    # Extract extension (including the dot), if present
    $Extension = [System.IO.Path]::GetExtension($BaseName)
    $NameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($BaseName)

    # Sanitize name and extension
    $SafeName = $NameWithoutExt -replace '[\\\/:*?"<>|]', '_'
    $SafeExt = $Extension -replace '[\\\/:*?"<>|]', '_'

    # Truncate base name to 25 chars
    if ($SafeName.Length -gt $MaxLength) {
        $SafeName = $SafeName.Substring(0, $MaxLength)
    }

    return "$SafeName$SafeExt"
}
function Normalize-And-ConvertImage {
    param (
        [string]$InputPath,
        [int]$MaxLength = 64
    )

    $original = $InputPath
    $originalExt = [IO.Path]::GetExtension($InputPath)
    $originalName = [IO.Path]::GetFileNameWithoutExtension($InputPath)

    if (-not (Test-Path $WorkingDirectory)) {
        New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
    }

    # Create a safe temp copy before doing anything else
    $safeName = [guid]::NewGuid().ToString() + $originalExt
    $safePath = Join-Path $WorkingDirectory $safeName
    write-host "MOVING IMAGE FROM $InputPath to SAFE PATH $safePath" -ForegroundColor Magenta

    Copy-Item -Path $InputPath -Destination $safePath -Force

    # If no extension, guess and rename
    if (-not $originalExt) {
        write-host "NO EXTENTION FOR PRESUMED IMAGE: $InputPath" -ForegroundColor Magenta
        $guessedExt = (New-Object ImageMagick.MagickImage($safePath)).Format.ToString().ToLower()
        $safePathWithExt = "$safePath.$guessedExt"
        write-host "NO EXTENTION IMAGE MOVED TO: $safePathWithExt" -ForegroundColor Magenta
        Move-Item -Path $safePath -Destination $safePathWithExt -Force
        $safePath = $safePathWithExt
    }

    # Detect type
    $type = Get-ImageType $safePath
    $detectedAs = $type
    write-host "IMAGE AT SAFEPATH $safePath detected as $detectedAs" -ForegroundColor Magenta

    $preserveExt = @('jpg', 'jpeg', 'png') -contains $type

    # Convert if needed
    if ($type -and -not $preserveExt) {
        write-host "IMAGE TYPE NOT IN ALLOWABLE SET... $safePath => $detectedAs converting to jpg" -ForegroundColor Magenta
        $Magick = New-Object ImageMagick.MagickImage($safePath)
        $convertedPath = [System.IO.Path]::ChangeExtension($safePath, 'jpg')
        $Magick.Format = [ImageMagick.MagickFormat]::Jpeg
        $Magick.Write($convertedPath)
        $safePath = $convertedPath
        $type = 'jpg'
    }

    # Normalize name
    $filename = [IO.Path]::GetFileName($safePath)
    $directory = [IO.Path]::GetDirectoryName($safePath)
    $normalized = Normalize-String -InputString $filename -PreserveExtension -PreserveWhitespace
    $limited = Limit-FilenameLength -FullFilename $normalized -MaxLength $MaxLength -PreserveExtension
    write-host "IMAGE FILENAME $InputPath NORMALIZED and LIMITED from $limited TO $normalized" -ForegroundColor Magenta

    # Rebuild parts
    $extension = [IO.Path]::GetExtension($limited)
    $basename = [IO.Path]::GetFileNameWithoutExtension($limited)

    if (-not $basename) { $basename = "file" }
    if (-not $extension) { $extension = ".$type" }

    if ($basename.Length -lt 5) {
        $basename = $basename.PadRight(5, '_')
        write-host "IMAGE BASENAME ($basename) from $InputPath NORMALIZED TO $basename" -ForegroundColor Magenta
    }

    $finalFilename = "$basename$extension".ToLower()
    $finalPath = Join-Path -Path $directory -ChildPath $finalFilename

    if ($safePath -ne $finalPath) {
        Copy-Item -Path $safePath -Destination $finalPath -Force
        write-host "FINAL IMAGE FROM $InputPath PLACED AS $safePath" -ForegroundColor Magenta
    }

    return @{
        FinalPath  = $finalPath
        Original   = $original
        Extention  = $extension
        DetectedAS = $detectedAs
        BaseName   = $basename
    }
}
