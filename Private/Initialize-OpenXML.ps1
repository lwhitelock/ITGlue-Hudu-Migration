# Import OpenXML Module, prompt for path if the module is missing
Write-Host "Adding OpenXML commands from dot NET assemblies" -ForegroundColor Cyan
try {
    if (!('DocumentFormat.OpenXml' -as [type])) {
        Add-Type -Path ".\DocumentFormat.OpenXml.dll"
    }
}
catch {
    $OpenXML_Path = (Read-Host "Failed to load OpenXML. Please provide path for this DLL.") + "\DocumentFormat.OpenXml.dll"
    if (Test-Path "$OpenXML_Path") {
        Add-Type -Path $OpenXML_Path
    }
    else {
        throw "OpenXML wasn't found at the location specified"
    }
}








