function Find-TerraformClassifierEntry {
    # Not exported. The classifier entry for -Address, or $null when there is none. The
    # version: -Version, else the newest version in the highest-ranked root that holds the
    # provider at all, so an override folder wins even over a newer bundled version
    # (DECISIONS 4). The file at that version: Select-TerraformClassifierWinner, which warns
    # (unless -Quiet) naming every shadowed file whose mapVersion or generatedOn differs from
    # the winner's.
    param([object[]]$Entry, [string]$Address, [string]$Version, [switch]$Quiet)

    $mine = @($Entry | Where-Object { $_.ProviderAddress -eq $Address } | Sort-Object Rank -Stable)
    if (-not $mine.Count) { return $null }
    if (-not $Version) {
        $top = $mine[0].Rank
        $Version = @(Sort-TerraformRegistryVersion -Versions @($mine | Where-Object Rank -eq $top))[0].Record.Version
    }
    $at = @($mine | Where-Object Version -eq $Version)
    if (-not $at.Count) { return $null }
    $pick = Select-TerraformClassifierWinner -Candidate $at
    if (-not $Quiet) {
        foreach ($loser in $pick.Shadowed) {
            if ([string]$loser.MapVersion -ceq [string]$pick.Winner.MapVersion -and [string]$loser.GeneratedOn -ceq [string]$pick.Winner.GeneratedOn) { continue }
            $fix = if ($loser.Location -eq 'User') { "Remove-Item -LiteralPath '$($loser.Path)' removes it." } elseif ($loser.Location -eq 'Bundled') { "Invoke-Build BuildClassifier -Provider $Address promotes the newer one into the module." } else { 'Drop -ClassifierPath to use it.' }
            Write-Warning "Classifier $Address $Version`: using $($pick.Winner.Path) ($($pick.Reason)); $($loser.Path) (mapVersion $($loser.MapVersion), generatedOn $($loser.GeneratedOn)) is shadowed. $fix"
        }
    }
    $pick.Winner
}
