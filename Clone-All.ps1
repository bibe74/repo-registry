$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'

try {
    $defaultBaseDirectory = 'C:\Work.Git\new'
    $baseDirectoryInput = Read-Host "Base directory for cloned repositories [$defaultBaseDirectory]"
    if ([string]::IsNullOrWhiteSpace($baseDirectoryInput)) {
        $baseDirectoryInput = $defaultBaseDirectory
    }
    $baseDirectory = [System.IO.Path]::GetFullPath($baseDirectoryInput)
    New-Item -ItemType Directory -Path $baseDirectory -Force | Out-Null

    $jsonPath = Join-Path $PSScriptRoot 'repos.json'
    if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf)) {
        throw "Repository list was not found: '$jsonPath'."
    }
    $repositoryGroups = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json

    $cloneFailures = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $repositoryGroups.PSObject.Properties) {
        $groupName = $group.Name
        if ([string]::IsNullOrWhiteSpace($groupName) -or [System.IO.Path]::IsPathRooted($groupName)) {
            throw "Invalid repository group name: '$groupName'."
        }

        $groupSegments = $groupName -split '[\\/]'
        if (($groupName -ne '.' -and ($groupSegments | Where-Object {
                    $_ -in @('', '.', '..') -or $_.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0
                }).Count -gt 0) -or
            ($groupName -eq '.' -and $groupSegments.Count -ne 1)) {
            throw "Invalid repository group name: '$groupName'."
        }

        if ($group.Value -isnot [array]) {
            throw "Repository group '$groupName' must contain an array of repository URLs."
        }

        $groupDirectory = $baseDirectory
        if ($groupName -ne '.') {
            foreach ($segment in $groupSegments) {
                $groupDirectory = Join-Path $groupDirectory $segment
            }
        }
        New-Item -ItemType Directory -Path $groupDirectory -Force | Out-Null

        foreach ($repositoryUrl in $group.Value) {
            if ($repositoryUrl -isnot [string] -or [string]::IsNullOrWhiteSpace($repositoryUrl)) {
                throw "Repository group '$groupName' contains an empty or invalid repository URL."
            }

            $repositoryName = ($repositoryUrl.TrimEnd('/') -split '/')[-1] -replace '(?i)\.git$', ''
            if ([string]::IsNullOrWhiteSpace($repositoryName) -or
                $repositoryName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
                throw "Could not determine a valid repository folder name from '$repositoryUrl'."
            }

            $destination = Join-Path $groupDirectory $repositoryName
            if (Test-Path -LiteralPath $destination) {
                Write-Warning "Skipping '$repositoryUrl'; destination already exists: '$destination'."
                continue
            }

            & git clone -- $repositoryUrl $destination
            if ($LASTEXITCODE -ne 0) {
                $cloneFailures.Add("'$repositoryUrl' (exit code $LASTEXITCODE)")
            }
        }
    }

    if ($cloneFailures.Count -gt 0) {
        throw "Failed to clone the following repositories:`n$($cloneFailures -join "`n")"
    }
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
