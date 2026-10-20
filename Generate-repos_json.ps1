$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
$locationPushed = $false

try {
    $baseDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    Push-Location -LiteralPath $baseDirectory
    $locationPushed = $true

    $repositoryDirectories = [System.Collections.Generic.List[string]]::new()
    $directoriesToVisit = [System.Collections.Generic.Stack[string]]::new()

    foreach ($directory in Get-ChildItem -LiteralPath $baseDirectory -Directory -Force) {
        $directoriesToVisit.Push($directory.FullName)
    }

    while ($directoriesToVisit.Count -gt 0) {
        $directory = $directoriesToVisit.Pop()

        if (Test-Path -LiteralPath (Join-Path $directory '.git') -PathType Container) {
            $repositoryDirectories.Add($directory)
        }

        foreach ($childDirectory in Get-ChildItem -LiteralPath $directory -Directory -Force) {
            if ($childDirectory.Name -ne '.git' -and
                ($childDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                $directoriesToVisit.Push($childDirectory.FullName)
            }
        }
    }

    $repositoriesByGroup = [ordered]@{}
    foreach ($repositoryDirectory in $repositoryDirectories) {
        $groupDirectory = Split-Path -Parent $repositoryDirectory
        $groupName = $groupDirectory.Substring($baseDirectory.Length).TrimStart([char[]]@('\', '/'))
        if ([string]::IsNullOrEmpty($groupName)) {
            $groupName = '.'
        }
        $groupName = $groupName.Replace('\', '/')

        $remoteUrl = & git -C $repositoryDirectory remote get-url origin 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($remoteUrl -join ''))) {
            throw "Could not read the origin remote for repository '$repositoryDirectory': $($remoteUrl -join ' ')"
        }

        if (-not $repositoriesByGroup.Contains($groupName)) {
            $repositoriesByGroup[$groupName] = [System.Collections.Generic.List[string]]::new()
        }
        $repositoriesByGroup[$groupName].Add(($remoteUrl -join '').Trim())
    }

    $jsonObject = [ordered]@{}
    foreach ($groupName in ($repositoriesByGroup.Keys | Sort-Object)) {
        $jsonObject[$groupName] = @($repositoriesByGroup[$groupName] | Sort-Object)
    }

    $outputPath = Join-Path $PSScriptRoot 'repos_new.json'
    $jsonObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding UTF8
}
finally {
    if ($locationPushed) {
        Pop-Location
    }
    $ErrorActionPreference = $previousErrorActionPreference
}
