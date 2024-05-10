# Coming improvements to images
# - replace TestImage with using ImageMagick to validate the image
# - Check for extension of the image, and if it doesn't exist rename it with the extension
# - Check for and use the full size image if the image is a thumbnail

function Invoke-ImageTest {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('PSPath')]
        [string] $FilePath
    )

    try {
        $Magick = New-Object ImageMagick.MagickImage($FilePath)
        $true
    }
    catch {
        $false
    }
}