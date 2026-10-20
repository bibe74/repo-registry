# Repository Registry

This project keeps a portable JSON index of Git repositories and provides a
script to recreate that directory layout on another location or machine.
Repositories are grouped by their local parent directory, while the JSON
records each repository's Git `origin` URL. The checked-in `repos.json` is the
list used by the clone script.

## Repository list format

`repos.json` is a JSON object whose property names are group paths and whose
values are arrays of Git remote URLs:

```json
{
  "1729": [
    "git@github.com:bibe74/1729.git",
    "git@github.com:bibe74/1729-projects.git"
  ],
  "CodicePlastico/internal": [
    "git@github-cp:CodicePlastico/BibeCatalogue.git"
  ]
}
```

Group names can contain nested paths, using `/` as the separator. Each clone
is placed in a subfolder named from the last part of its remote URL, with a
trailing `.git` removed.

## PowerShell scripts

### `Generate-repos_json.ps1`

Scans the parent directory of this project recursively for directories
containing a `.git` directory. For each repository, it reads the `origin`
remote and groups the URL under the path of the repository's parent directory,
relative to the scan base. It writes the resulting JSON to `repos_new.json`
beside the script, replacing that file if it already exists. It does not
replace `repos.json`, so you can review the new list before making it the
active clone list.

Run from the project directory:

```powershell
.\Generate-repos_json.ps1
```

For example, if the scan base is `C:\Work.Git` and a repository lives at
`C:\Work.Git\CodicePlastico\internal\BibeCatalogue`, its remote is recorded
under the `CodicePlastico/internal` group.

### `Clone-All.ps1`

Reads `repos.json` beside the script, prompts for a destination base directory,
and clones each listed repository into a subfolder under its group path. The
default destination is `C:\Work.Git\new`; press Enter to use it, or enter a
different path. The base directory and any group directories that do not
already exist are created automatically.

Run the script and accept the default destination:

```powershell
.\Clone-All.ps1
```

Or enter a custom destination when prompted, for example:

```text
Base directory for cloned repositories [C:\Work.Git\new]: D:\Source
```

Given the sample list above, the script creates:

```text
C:\Work.Git\new\
├── 1729\
│   ├── 1729\
│   └── 1729-projects\
└── CodicePlastico\
    └── internal\
        └── BibeCatalogue\
```

Existing destination folders are left untouched and skipped, so the script
does not overwrite existing work. If a clone fails, it continues with the
remaining repositories and reports the failed URLs at the end.

## Requirements

- Windows PowerShell or PowerShell 7
- Git installed and available on `PATH`
- Network access and any required SSH keys or credentials for the listed remotes

## Typical workflow

1. Run `Generate-repos_json.ps1` to create an updated `repos_new.json` from the
   repositories under the project’s parent directory.
2. Review `repos_new.json`; if it is the list you want to use, copy its contents
   to `repos.json`.
3. Run `Clone-All.ps1` and choose the destination directory.
