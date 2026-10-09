function Get-TerraformGraphSkillFile {
    # Not exported. Every bundled skill file as {Source, Relative}, Relative using the
    # platform separator, in ordinal order so installs are deterministic.
    $root = (Resolve-Path -LiteralPath $script:TerraformGraphSkillSource -ErrorAction Stop).ProviderPath
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object { $_.FullName } -Culture '')
    foreach ($file in $files) {
        [pscustomobject]@{
            Source   = $file.FullName
            Relative = [System.IO.Path]::GetRelativePath($root, $file.FullName)
        }
    }
}
