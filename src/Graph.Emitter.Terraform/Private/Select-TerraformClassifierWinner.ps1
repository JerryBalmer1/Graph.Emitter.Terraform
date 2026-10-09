function Select-TerraformClassifierWinner {
    # Not exported. Which of several classifier files for the same provider version wins
    # (DECISIONS 48): a file from -ClassifierPath always; else the files whose mapVersion is
    # the current map.json's first, then the newest generatedOn, then lookup order. Returns
    # @{ Winner; Shadowed (the others); Reason }.
    param([object[]]$Candidate)

    $sorted = @($Candidate | Sort-Object Rank -Stable)
    if ($sorted.Count -le 1) { return @{ Winner = $sorted[0]; Shadowed = @(); Reason = 'only file' } }
    if ($sorted[0].Location -eq 'ClassifierPath') {
        return @{ Winner = $sorted[0]; Shadowed = @($sorted | Select-Object -Skip 1); Reason = '-ClassifierPath always wins' }
    }
    $current = Get-TerraformClassifierCurrentMapVersion
    $ranked = @($sorted | Sort-Object -Stable -Property `
            @{ Expression = { [int]($current -and $_.MapVersion -ceq $current) }; Descending = $true },
            @{ Expression = { [string]$_.GeneratedOn }; Descending = $true },
            @{ Expression = 'Rank'; Descending = $false })
    $winner = $ranked[0]
    $others = @($ranked | Select-Object -Skip 1)
    $reason = if ($current -and $winner.MapVersion -ceq $current -and @($others | Where-Object { $_.MapVersion -cne $current }).Count) { "mapVersion $current matches map.json" }
    elseif (@($others | Where-Object { [string]$_.GeneratedOn -ne [string]$winner.GeneratedOn }).Count) { "newer generatedOn $($winner.GeneratedOn)" }
    else { 'same mapVersion and generatedOn; lookup order' }
    @{ Winner = $winner; Shadowed = $others; Reason = $reason }
}
