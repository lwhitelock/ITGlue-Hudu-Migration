function Normalize-String {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputString,
        [switch]$PreserveWhitespace,
        [switch]$PreserveExtension
    )
    $extension = ""
    $basename = $InputString
    if ($PreserveExtension) {
        $extension = [IO.Path]::GetExtension($InputString)
        $basename = [IO.Path]::GetFileNameWithoutExtension($InputString)
    }

    # Normalize Unicode (decompose accents), then remove non-ASCII
    $normalized = $basename.Normalize([Text.NormalizationForm]::FormD)
    $chars = $normalized.ToCharArray() | Where-Object {
        ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark')
    }
    $ascii = -join $chars
    if ($PreserveWhitespace) {
        $ascii = $ascii -replace '[^a-zA-Z0-9 _-]', ''
    } else {
        $ascii = $ascii -replace '[^a-zA-Z0-9]', ''
    }
    return "$ascii$extension"
}


function Limit-FilenameLength {
    param (
        [string]$FullFilename,
        [int]$MaxLength = 100,
        [switch]$PreserveExtension
    )

    if ($PreserveExtension) {
        $extension = [IO.Path]::GetExtension($FullFilename)
        $basename = [IO.Path]::GetFileNameWithoutExtension($FullFilename)

        $maxBaseLength = $MaxLength - $extension.Length
        if ($basename.Length -gt $maxBaseLength) {
            $basename = $basename.Substring(0, $maxBaseLength)
        }

        return "$basename$extension"
    } else {
        # Trim the entire string to max length regardless of extension
        return if ($FullFilename.Length -gt $MaxLength) {
            $FullFilename.Substring(0, $MaxLength)
        } else {
            $FullFilename
        }
    }
}

