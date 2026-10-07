@{

    RootModule        = 'TerraformGraph.psm1'
    ModuleVersion     = '0.9.0'
    GUID              = '852206b0-33a6-4dc3-91eb-e9fd6166b17d'
    Author            = 'Jerry Balmer'
    CompanyName       = 'Jerry Balmer'
    Copyright         = '(c) Jerry Balmer. All rights reserved.'
    Description       = 'Parse Terraform configurations into an HCL AST and build graphs of module calls and provider schemas.'
    PowerShellVersion = '7.4'

    FunctionsToExport = @('Get-TerraformAST', 'ConvertTo-TerraformJson', 'ConvertFrom-TerraformJson', 'Get-TerraformProviderSchema', 'Get-TerraformModuleGraph', 'ConvertTo-TerraformSchemaGraph', 'ConvertTo-TerraformVariableGraph', 'Get-TerraformVariableTrace', 'ConvertTo-TerraformResourceGraph', 'Install-TerraformGraphSkill', 'Test-TerraformGraphSkill', 'Update-TerraformRegistryCache', 'Get-TerraformRegistryProvider')
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
            ReleaseNotes               = '0.9.0: Provider registry cache: Update-TerraformRegistryCache, Get-TerraformRegistryProvider, bundled data/registry.json, wildcard -Provider and argument completers for Get-TerraformProviderSchema. 0.8.0: Ship the terraformgraph agent skill; add Install-TerraformGraphSkill and Test-TerraformGraphSkill; import hint for detected agent tools. 0.7.0: Add ConvertTo-TerraformResourceGraph. 0.6.0: Add ConvertTo-TerraformVariableGraph and Get-TerraformVariableTrace. 0.5.1: Provider config nodes in ConvertTo-TerraformSchemaGraph; performance. 0.5.0: Add ConvertTo-TerraformSchemaGraph. 0.4.0: Get-TerraformProviderSchema -Provider set fetches a provider schema on demand. 0.3.0: Add Get-TerraformModuleGraph. 0.2.0: Breaking. Expression nodes now carry Kind, Raw and values. 0.1.0: Initial release. Get-TerraformAST, ConvertTo-TerraformJson, ConvertFrom-TerraformJson, Get-TerraformProviderSchema.'
            RequireLicenseAcceptance   = $false
            ExternalModuleDependencies = @()
        }
    }

}
