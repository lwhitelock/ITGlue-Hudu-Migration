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

    # Convert image if needed
    $type = Invoke-ImageTest $InputPath
    if ($type -and $type -notin @('jpg', 'jpeg', 'png')) {
        $Magick = New-Object ImageMagick.MagickImage($InputPath)
        $converted = [System.IO.Path]::ChangeExtension($InputPath, 'jpg')
        $Magick.Format = [ImageMagick.MagickFormat]::Jpeg
        $Magick.Write($converted)
        $InputPath = $converted
    }

    # Normalize, limit length, and pad if needed
    $filename = [IO.Path]::GetFileName($InputPath)
    $directory = [IO.Path]::GetDirectoryName($InputPath)

    $normalized = Normalize-String -InputString $filename -PreserveExtension -PreserveWhitespace
    $limited = Limit-FilenameLength -FullFilename $normalized -MaxLength $MaxLength -PreserveExtension

    $extension = [IO.Path]::GetExtension($limited)
    $basename = [IO.Path]::GetFileNameWithoutExtension($limited)

    # Fallback if either part is blank
    if (-not $basename) { $basename = "file" }
    if (-not $extension) { $extension = ".jpg" }

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
    }
}
