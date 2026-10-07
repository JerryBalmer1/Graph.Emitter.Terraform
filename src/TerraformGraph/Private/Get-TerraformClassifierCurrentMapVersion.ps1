function Get-TerraformClassifierCurrentMapVersion {
    # Not exported. mapVersion of the bundled map.json, memoized per file version; $null when
    # the map does not read (Test-TerraformGraphBundle reports that).
    $item = Get-Item -LiteralPath $script:TerraformClassifierMapPath -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    $key = "$($item.LastWriteTimeUtc.Ticks)|$($item.Length)"
    if ($script:TerraformClassifierMapVersionMemo -and $script:TerraformClassifierMapVersionMemo.Key -ceq $key) { return $script:TerraformClassifierMapVersionMemo.Value }
    $value = try { (Read-TerraformClassifierMap -Path $item.FullName).MapVersion }
    catch {
        # Once per map file version (memoized below).
        Write-Warning "Classifier map $($item.FullName) does not read, so classifier precedence by mapVersion is disabled and the newer generatedOn decides: $($_.Exception.Message)"
        $null
    }
    $script:TerraformClassifierMapVersionMemo = @{ Key = $key; Value = $value }
    $value
}
