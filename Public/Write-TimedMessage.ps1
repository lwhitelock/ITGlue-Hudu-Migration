function Write-TimedMessage {
    Param(
        [string]$Message,
        [string]$DefaultResponse,
        [int]$Timeout = 0  # Optional timeout in seconds for non-interactive mode
    )

    # Check non-interactive mode
    if ($NonInteractive -eq $true) {
        if ($Timeout -gt 0) {
            $TimeoutStatement = "- Waiting for $Timeout seconds due to noninteractive mode. Control + c now if you do not wish to continue."
        } else {
            $TimeoutStatement = ""
        }
        if ($DefaultResponse -eq $null -or $DefaultResponse -eq ""){
            $DefaultResponse="Proceeding"
        }

        if ($null -eq $DefaultResponse) {
            Write-Host "$Message $TimeoutStatement"
        } else {
            Write-Host "$Message $TimeoutStatement - Noninteractive mode. Assuming response of ($DefaultResponse) after timeout."
        }

        # Apply timeout if specified
        if ($Timeout -gt 0) {
            Start-Sleep -Seconds $Timeout
        }

        return $DefaultResponse
    } else {
        # Interactive mode
        return Read-Host -Prompt $Message
    }
}