function Assert-TerraformGraphParser {
    # Not exported. Every command that reaches the native HCL parser calls this first, so a
    # missing or foreign-platform DLL is one documented error instead of DllNotFoundException.
    if (-not $script:TerraformGraphParserAvailable) {
        Stop-TerraformGraphCommand -Id 'ParserUnavailable' -Category NotInstalled -Target 'TerraformGraph.dll' -ExceptionType ([System.PlatformNotSupportedException]) -Message $script:TerraformGraphParserUnavailableReason
    }
}
