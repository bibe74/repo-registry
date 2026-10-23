$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory)]
        [string] $Repository,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $output = & git -C $Repository @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        ExitCode = $exitCode
        Lines = @($output | ForEach-Object { $_.ToString() })
    }
}

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git was not found on PATH.'
    }

    $baseDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $repositories = [System.Collections.Generic.List[string]]::new()
    $directoriesToVisit = [System.Collections.Generic.Stack[string]]::new()

    if (Test-Path -LiteralPath (Join-Path $baseDirectory '.git')) {
        $repositories.Add($baseDirectory)
    }
    foreach ($directory in Get-ChildItem -LiteralPath $baseDirectory -Directory -Force) {
        if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
            $directoriesToVisit.Push($directory.FullName)
        }
    }

    while ($directoriesToVisit.Count -gt 0) {
        $directory = $directoriesToVisit.Pop()
        if (Test-Path -LiteralPath (Join-Path $directory '.git')) {
            $repositories.Add($directory)
        }

        foreach ($childDirectory in Get-ChildItem -LiteralPath $directory -Directory -Force) {
            if ($childDirectory.Name -ne '.git' -and
                ($childDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                $directoriesToVisit.Push($childDirectory.FullName)
            }
        }
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $scanErrors = [System.Collections.Generic.List[string]]::new()

    foreach ($repository in ($repositories | Sort-Object -Unique)) {
        $repositoryCheck = Invoke-GitCommand -Repository $repository -Arguments @('rev-parse', '--is-inside-work-tree')
        if ($repositoryCheck.ExitCode -ne 0 -or $repositoryCheck.Lines -notcontains 'true') {
            $scanErrors.Add("$repository`: $($repositoryCheck.Lines -join ' ')")
            continue
        }

        $repositoryErrors = [System.Collections.Generic.List[string]]::new()
        $branchResult = Invoke-GitCommand -Repository $repository -Arguments @('branch', '--show-current')
        if ($branchResult.ExitCode -eq 0) {
            $branch = [string]($branchResult.Lines | Select-Object -First 1)
            $branch = $branch.Trim()
            if ([string]::IsNullOrEmpty($branch)) {
                $headResult = Invoke-GitCommand -Repository $repository -Arguments @('rev-parse', '--short', 'HEAD')
                if ($headResult.ExitCode -eq 0) {
                    $branch = "detached HEAD ($($headResult.Lines | Select-Object -First 1))"
                }
                else {
                    $branch = 'unknown'
                    $repositoryErrors.Add("Could not determine detached HEAD: $($headResult.Lines -join ' ')")
                }
            }
        }
        else {
            $branch = 'unknown'
            $repositoryErrors.Add("Could not determine current branch: $($branchResult.Lines -join ' ')")
        }

        $statusResult = Invoke-GitCommand -Repository $repository -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
        $changedFiles = [System.Collections.Generic.List[object]]::new()
        if ($statusResult.ExitCode -eq 0) {
            foreach ($line in $statusResult.Lines) {
                if ($line.Length -ge 3) {
                    $changedFiles.Add([pscustomobject]@{
                        Status = $line.Substring(0, 2)
                        Path = $line.Substring(3)
                    })
                }
            }
        }
        else {
            $repositoryErrors.Add("Could not read working-tree status: $($statusResult.Lines -join ' ')")
        }

        $remoteRefs = Invoke-GitCommand -Repository $repository -Arguments @(
            'for-each-ref', '--format=%(refname)', 'refs/remotes'
        )
        $unpushedCommits = [System.Collections.Generic.List[string]]::new()
        $unpushedState = 'unknown (no remote-tracking branches)'
        if ($remoteRefs.ExitCode -ne 0) {
            $repositoryErrors.Add("Could not list remote-tracking branches: $($remoteRefs.Lines -join ' ')")
        }
        elseif ($remoteRefs.Lines.Count -gt 0) {
            $commitResult = Invoke-GitCommand -Repository $repository -Arguments @(
                'log', '--oneline', '--decorate', 'HEAD', '--not', '--remotes'
            )
            if ($commitResult.ExitCode -eq 0) {
                foreach ($commit in $commitResult.Lines) {
                    if (-not [string]::IsNullOrWhiteSpace($commit)) {
                        $unpushedCommits.Add($commit)
                    }
                }
                $unpushedState = if ($unpushedCommits.Count -gt 0) { 'unpushed' } else { 'none' }
            }
            else {
                $repositoryErrors.Add("Could not list unpushed commits: $($commitResult.Lines -join ' ')")
            }
        }

        $results.Add([pscustomobject]@{
            Path = $repository
            Branch = $branch
            ChangedFiles = @($changedFiles)
            UnpushedCommits = @($unpushedCommits)
            UnpushedState = $unpushedState
            Errors = @($repositoryErrors)
        })
    }

    Write-Output "Scanned $($results.Count) Git repositories under '$baseDirectory'."

    $repositoriesWithFileChanges = @($results | Where-Object { $_.ChangedFiles.Count -gt 0 })
    Write-Output "`nUncommitted changes:"
    if ($repositoriesWithFileChanges.Count -eq 0) {
        Write-Output '  None.'
    }
    else {
        foreach ($result in $repositoriesWithFileChanges) {
            Write-Output "  $($result.Path)"
            foreach ($file in $result.ChangedFiles) {
                Write-Output "    [$($file.Status)] $($file.Path)"
            }
        }
    }

    $repositoriesWithUnpushedCommits = @($results | Where-Object { $_.UnpushedCommits.Count -gt 0 })
    Write-Output "`nUnpushed commits (commits on HEAD absent from all local remote-tracking branches):"
    if ($repositoriesWithUnpushedCommits.Count -eq 0) {
        Write-Output '  None.'
    }
    else {
        foreach ($result in $repositoriesWithUnpushedCommits) {
            Write-Output "  $($result.Path)"
            foreach ($commit in $result.UnpushedCommits) {
                Write-Output "    $commit"
            }
        }
    }

    $repositoriesOnOtherBranches = @($results | Where-Object { $_.Branch -notin @('main', 'master') })
    Write-Output "`nRepositories not on main or master:"
    if ($repositoriesOnOtherBranches.Count -eq 0) {
        Write-Output '  None.'
    }
    else {
        foreach ($result in $repositoriesOnOtherBranches) {
            Write-Output "  $($result.Path) [$($result.Branch)]"
        }
    }

    $repositoriesWithoutRemoteRefs = @($results | Where-Object { $_.UnpushedState -like 'unknown*' })
    if ($repositoriesWithoutRemoteRefs.Count -gt 0) {
        Write-Output "`nUnpushed status unavailable (no remote-tracking branches):"
        foreach ($result in $repositoriesWithoutRemoteRefs) {
            Write-Output "  $($result.Path)"
        }
    }

    $repositoriesWithErrors = @($results | Where-Object { $_.Errors.Count -gt 0 })
    if ($repositoriesWithErrors.Count -gt 0 -or $scanErrors.Count -gt 0) {
        Write-Output "`nRepository scan errors:"
        foreach ($result in $repositoriesWithErrors) {
            foreach ($errorMessage in $result.Errors) {
                Write-Output "  $($result.Path): $errorMessage"
            }
        }
        foreach ($scanError in $scanErrors) {
            Write-Output "  $scanError"
        }
    }
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
