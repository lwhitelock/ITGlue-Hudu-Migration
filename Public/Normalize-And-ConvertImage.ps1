[string]$WorkingDirectory = "/tmp/safeimages"

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
    Copy-Item -Path $InputPath -Destination $safePath -Force

    # If no extension, guess and rename
    if (-not $originalExt) {
        $guessedExt = (New-Object ImageMagick.MagickImage($safePath)).Format.ToString().ToLower()
        $safePathWithExt = "$safePath.$guessedExt"
        Move-Item -Path $safePath -Destination $safePathWithExt -Force
        $safePath = $safePathWithExt
    }

    # Detect type
    $type = Get-ImageType $safePath
    $detectedAs = $type
    Write-Verbose "Detected image type: $type" -Verbose

    $preserveExt = @('jpg', 'jpeg', 'png') -contains $type

    # Convert if needed
    if ($type -and -not $preserveExt) {
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

    $extension = [IO.Path]::GetExtension($limited)
    $basename = [IO.Path]::GetFileNameWithoutExtension($limited)

    if (-not $basename) { $basename = "file" }
    if (-not $extension) { $extension = ".$type" }
    if ($basename.Length -lt 5) {
        $basename = $basename.PadRight(5, '_')
    }

    $finalFilename = "$basename$extension"
    $finalPath = Join-Path -Path $directory -ChildPath $finalFilename

    if ($safePath -ne $finalPath) {
        Copy-Item -Path $safePath -Destination $finalPath -Force
    }

    return @{
        FinalPath  = $finalPath
        Original   = $original
        Extention  = $extension
        DetectedAS = $detectedAs
        BaseName   = $basename
    }
}
