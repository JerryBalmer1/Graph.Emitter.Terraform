@{

    RootModule        = 'TerraformGraph.psm1'
    ModuleVersion     = '0.3.0'
    GUID              = '852206b0-33a6-4dc3-91eb-e9fd6166b17d'
    Author            = 'Jerry Balmer'
    CompanyName       = 'Jerry Balmer'
    Copyright         = '(c) Jerry Balmer. All rights reserved.'
    Description       = 'Parse Terraform configurations into an HCL AST and build a graph of module and provider relationships. Graph layer in progress; AST, JSON and provider-schema cmdlets are available.'
    PowerShellVersion = '7.4'

    FunctionsToExport = @('Get-TerraformAST', 'ConvertTo-TerraformJson', 'ConvertFrom-TerraformJson', 'Get-TerraformProviderSchema', 'Get-TerraformModuleGraph')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # ExternalModuleDependencies is PowerShell *modules* only (names Install-Module
    # would resolve). terraform.exe is a native binary, not a module. The HCL
    # parser loads TerraformGraph.dll; Get-TerraformProviderSchema calls terraform from PATH.
    PrivateData = @{
        PSData = @{
            Tags                       = @('Terraform', 'HCL', 'Graph', 'AST', 'PowerShell', 'PowerShell74')
            ProjectUri                 = 'https://github.com/JerryBalmer1/TerraformGraph'
            LicenseUri                 = 'https://github.com/JerryBalmer1/TerraformGraph'
            ReleaseNotes               = '0.3.0: Add Get-TerraformModuleGraph. 0.2.0: Breaking. Expression nodes now carry Kind, Raw and values. 0.1.0: Initial release. Get-TerraformAST, ConvertTo-TerraformJson, ConvertFrom-TerraformJson, Get-TerraformProviderSchema.'
            RequireLicenseAcceptance   = $false
            ExternalModuleDependencies = @()
        }
    }

}
