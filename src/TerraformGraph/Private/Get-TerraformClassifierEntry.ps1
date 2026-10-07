function Get-TerraformClassifierEntry {
    # Not exported. Every classifier file in lookup order, highest precedence first:
    # -ClassifierPath (a file, or the *.json files in a folder), the user root, the bundled
    # root. Rank is that position, 0 highest, and Location names it (ClassifierPath, User,
    # Bundled). provider and version are read from the start of each file, never its name
    # (address slugs contain dots and dashes); files that do not start with them, such as
    # drawers.json and map.json, are skipped. generatedOn and mapVersion come from the same
    # head, for Select-TerraformClassifierWinner.
    param([string]$ClassifierPath)

    $locations = @('ClassifierPath', 'User', 'Bundled')

    $rank = 0
    foreach ($source in @($ClassifierPath, $script:TerraformClassifierUserRoot, $script:TerraformClassifierBundledRoot)) {
        $files = if (-not $source) { @() }
        elseif (Test-Path -LiteralPath $source -PathType Leaf) { @(Get-Item -LiteralPath $source) }
        elseif (Test-Path -LiteralPath $source -PathType Container) { @(Get-ChildItem -LiteralPath $source -Filter '*.json' -File | Sort-Object Name) }
        else { @() }
        foreach ($file in $files) {
            try {
                $reader = [System.IO.StreamReader]::new($file.FullName, [System.Text.Encoding]::UTF8)
                try {
                    $buffer = [char[]]::new(1024)
                    $head = [string]::new($buffer, 0, $reader.ReadBlock($buffer, 0, 1024))
                }
                finally {
                    $reader.Dispose()
                }
            }
            catch {
                Write-Verbose "Skipping $($file.FullName): $($_.Exception.Message)"
                continue
            }
            if ($head -match '^\s*\{\s*"provider"\s*:\s*"([^"]+)"\s*,\s*"version"\s*:\s*"([^"]+)"') {
                $address = $Matches[1]
                $version = $Matches[2]
                $generatedOn = if ($head -match '"generatedOn"\s*:\s*"([^"]+)"') { $Matches[1] } else { $null }
                $mapVersion = if ($head -match '"mapVersion"\s*:\s*"([^"]+)"') { $Matches[1] } else { $null }
                [pscustomobject]@{
                    ProviderAddress = $address
                    Version         = $version
                    Path            = $file.FullName
                    Rank            = $rank
                    Location        = $locations[$rank]
                    GeneratedOn     = $generatedOn
                    MapVersion      = $mapVersion
                }
            }
        }
        $rank++
    }
}
