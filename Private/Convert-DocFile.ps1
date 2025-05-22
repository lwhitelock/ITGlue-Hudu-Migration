function Convert-DocFile {
    param (
        [string]$docxFile,
        [string]$outputHtmlFile
    )
    $doc = [DocumentFormat.OpenXml.Packaging.WordprocessingDocument]::Open($docxFile, $false)
    
    # Extract the main document part
    $mainPart = $doc.ExtendedProperties.PackageProperties.GetPart($doc.ExtendedProperties.PackageProperties.ExtendedProperty)

    # Initialize an HTML string to hold the converted content
    $htmlContent = "<html><body>"

    # Loop through each element in the document (e.g., paragraphs)
    foreach ($body in $doc.Paragraphs) {
        $htmlContent += "<p>$($body.InnerText)</p>"
    }

    # Close the HTML tags
    $htmlContent += "</body></html>"

    # Write the HTML content to the output file
    Set-Content -Path $outputHtmlFile -Value $htmlContent
    $doc.Close()
}
