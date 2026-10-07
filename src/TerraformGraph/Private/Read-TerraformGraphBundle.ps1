function Read-TerraformGraphBundle {
    # Not exported. A bundle file as an ordered dictionary with tiers, providers and exclude
    # as string arrays and entries as an array; throws listing every problem.
    param([string]$Path)

    $document = Read-TerraformClassifierJson -Path $Path
    $problems = @(Get-TerraformGraphBundleProblem -Bundle $document)
    if ($problems.Count) {
        Stop-TerraformGraphCommand -Throw -Id 'BundleInvalid' -Category InvalidData -Target $Path -ExceptionType ([System.IO.InvalidDataException]) -Message "Bundle '$Path' has $($problems.Count) problem(s):`n  $($problems -join "`n  ")`nRewrite it with New-TerraformGraphBundle -OutputPath '$Path'."
    }
    foreach ($key in 'tiers', 'providers', 'exclude') {
        $document[$key] = [string[]]@($document[$key] | Where-Object { $null -ne $_ })
    }
    $document['entries'] = [object[]]@($document['entries'] | Where-Object { $null -ne $_ })
    $document
}
