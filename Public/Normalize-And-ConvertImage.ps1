function Normalize-And-ConvertImage {
    param (
        [string]$InputPath,
        [int]$MaxLength = 64
    )

    $original = $InputPath

    # If no extension, guess and copy
    if ((Get-Item -Path $InputPath).Extension -eq '') {
        $Magick = New-Object ImageMagick.MagickImage($InputPath)
        $InputPath += ".$($Magick.Format.ToString().ToLower())"
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

    # Normalize and shorten filename
    $filename = [IO.Path]::GetFileName($InputPath)
    $directory = [IO.Path]::GetDirectoryName($InputPath)

    $normalized = Normalize-String -InputString $filename -PreserveExtension -PreserveWhitespace
    $limited = Limit-FilenameLength -FullFilename $normalized -MaxLength $MaxLength -PreserveExtension
    $finalPath = Join-Path -Path $directory -ChildPath $limited

    if ($InputPath -ne $finalPath) {
        Copy-Item -Path $InputPath -Destination $finalPath -Force
    }

    return @{
        FinalPath = $finalPath
        Original  = $original
    }
}