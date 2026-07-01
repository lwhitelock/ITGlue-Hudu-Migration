
function Initialize-MigrationJobTimeline {
    if ($null -eq $script:JobStartTime -or $script:JobStartTime -isnot [hashtable]) {
        $script:JobStartTime = @{}
    }

    if ($null -eq $script:MigrationJobTimeline -or $script:MigrationJobTimeline -isnot [System.Collections.ArrayList]) {
        $script:MigrationJobTimeline = [System.Collections.ArrayList]@()
    }
}

function Format-MigrationJobDuration {
    param(
        [AllowNull()]
        [timespan]$Duration
    )

    if ($null -eq $Duration) { return '' }

    if ($Duration.TotalDays -ge 1) {
        return "{0}d {1:hh\:mm\:ss}" -f [math]::Floor($Duration.TotalDays), $Duration
    }

    $Duration.ToString('hh\:mm\:ss')
}

function Start-MigrationJob {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [datetime]$StartedAt = (Get-Date)
    )

    Initialize-MigrationJobTimeline

    for ($i = $script:MigrationJobTimeline.Count - 1; $i -ge 0; $i--) {
        $job = $script:MigrationJobTimeline[$i]
        if ($null -eq $job.FinishedAt) {
            $job.FinishedAt = $StartedAt
            $job.Duration = $StartedAt - [datetime]$job.StartedAt
            $job.Status = 'Completed'
            break
        }
    }

    $newJob = [pscustomobject]@{
        Job        = $Name
        StartedAt  = $StartedAt
        FinishedAt = $null
        Duration   = $null
        Status     = 'Running'
    }

    $script:JobStartTime[$Name] = $StartedAt
    $null = $script:MigrationJobTimeline.Add($newJob)
    $newJob
}

function Complete-MigrationJob {
    param(
        [string]$Name,
        [datetime]$CompletedAt = (Get-Date),
        [string]$Status = 'Completed'
    )

    Initialize-MigrationJobTimeline

    for ($i = $script:MigrationJobTimeline.Count - 1; $i -ge 0; $i--) {
        $job = $script:MigrationJobTimeline[$i]
        if ($null -ne $job.FinishedAt) { continue }
        if (-not [string]::IsNullOrWhiteSpace($Name) -and $job.Job -ne $Name) { continue }

        $job.FinishedAt = $CompletedAt
        $job.Duration = $CompletedAt - [datetime]$job.StartedAt
        $job.Status = $Status
        return $job
    }
}

function Get-MigrationJobDurationReport {
    param(
        [System.Collections.IEnumerable]$Timeline = $script:MigrationJobTimeline,
        [datetime]$ReportEndTime = (Get-Date)
    )

    Initialize-MigrationJobTimeline

    foreach ($job in @($Timeline | Sort-Object StartedAt)) {
        $startedAt = [datetime]$job.StartedAt
        $finishedAt = if ($null -ne $job.FinishedAt) { [datetime]$job.FinishedAt } else { $ReportEndTime }
        $duration = if ($null -ne $job.Duration) { [timespan]$job.Duration } else { $finishedAt - $startedAt }

        [pscustomobject]@{
            Job             = $job.Job
            Status          = if ($null -ne $job.FinishedAt) { $job.Status } else { 'Running' }
            Started         = $startedAt.ToString('HH:mm:ss')
            Finished        = $finishedAt.ToString('HH:mm:ss')
            Duration        = Format-MigrationJobDuration -Duration $duration
            DurationSeconds = [math]::Round($duration.TotalSeconds, 2)
        }
    }
}