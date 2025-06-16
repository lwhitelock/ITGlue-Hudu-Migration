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

    # If no extension, guess and copy with guessed extension
    if ((Get-Item -Path $InputPath).Extension -eq '') {
        $Magick = New-Object ImageMagick.MagickImage($InputPath)
        $guessedExt = $Magick.Format.ToString().ToLower()
        $InputPath += ".$guessedExt"
        Copy-Item -Path $original -Destination $InputPath -Force
    }

    # Detect type
    $type = Get-ImageType $InputPath
    $detectedAs = $type

    Write-Verbose "Detected image type: $type" -Verbose

    $preserveExt = @('jpg', 'jpeg', 'png') -contains $type

    # Only convert and change extension if not in safe list
    if ($type -and -not $preserveExt) {
        $Magick = New-Object ImageMagick.MagickImage($InputPath)
        $convertedPath = [System.IO.Path]::ChangeExtension($InputPath, 'jpg')
        $Magick.Format = [ImageMagick.MagickFormat]::Jpeg
        $Magick.Write($convertedPath)
        $InputPath = $convertedPath
        $type = 'jpg'  # Important: Update type since we converted
    }

    # Normalize and shorten
    $filename = [IO.Path]::GetFileName($InputPath)
    $directory = [IO.Path]::GetDirectoryName($InputPath)
    $normalized = Normalize-String -InputString $filename -PreserveExtension -PreserveWhitespace
    $limited = Limit-FilenameLength -FullFilename $normalized -MaxLength $MaxLength -PreserveExtension

    # Rebuild parts
    $extension = [IO.Path]::GetExtension($limited)
    $basename = [IO.Path]::GetFileNameWithoutExtension($limited)

    if (-not $basename) { $basename = "file" }
    if (-not $extension) { $extension = ".$type" }

    if ($basename.Length -lt 5) {
        $basename = $basename.PadRight(5, '_')
    }

    $finalFilename = "$basename$extension"
    $finalPath = Join-Path -Path $directory -ChildPath $finalFilename

    if ($InputPath -ne $finalPath) {
        Copy-Item -Path $InputPath -Destination $finalPath -Force
    }

    return @{
        FinalPath = $finalPath
        Original  = $original
        Extention = $extension
        DetectedAS = $detectedAs
        BaseName = $basename
    }
}
