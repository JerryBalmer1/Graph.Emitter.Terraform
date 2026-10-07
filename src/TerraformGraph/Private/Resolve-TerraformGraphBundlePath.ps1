function Resolve-TerraformGraphBundlePath {
    # Not exported. The bundle file to read: -Path (which must exist), else the user copy when
    # there is one, else the bundled file. Throws when there is none.
    param([string]$Path)

    if ($Path) {
        $full = [System.IO.Path]::GetFullPath($Path, (Get-Location -PSProvider FileSystem).ProviderPath)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { Stop-TerraformGraphCommand -Throw -Id 'BundleNotFound' -Category ObjectNotFound -Target $Path -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message "Bundle '$Path' does not exist. Write one with New-TerraformGraphBundle -OutputPath '$Path'." }
        return $full
    }
    foreach ($candidate in @($script:TerraformGraphBundleUserPath, $script:TerraformGraphBundleBundledPath)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    Stop-TerraformGraphCommand -Throw -Id 'BundleNotFound' -Category ObjectNotFound -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message 'No bundle manifest found. Pass -BundlePath, or write one with New-TerraformGraphBundle.'
}
