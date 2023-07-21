# Import ImageMagick Modules, prompt for path if the module is missing
Write-Host "Adding Imagemagick commands from dot NET assemblies" -ForegroundColor Cyan
try {
    if (!('ImageMagick.MagickImage' -as [type])) {
        Add-Type -Path '.\Magick.NET-Q16-AnyCPU.dll'
    }
}
catch {
    $ImageMagickPath = (Read-Host "Failed to load ImageMagick. Please provide path for the three DLLs.") + "\Magick.NET-Q16-AnyCPU.dll"
    if (Test-Path "$ImageMagickPath") {
        Add-Type -Path $ImageMagickPath
    }
    else {
        throw "ImageMagick wasn't found at the location specified"

    }
}