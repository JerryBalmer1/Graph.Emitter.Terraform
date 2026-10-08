@{

    RootModule           = 'TerraformGraph.psm1'
    ModuleVersion        = '0.16.0'
    GUID                 = '852206b0-33a6-4dc3-91eb-e9fd6166b17d'
    Author               = 'Jerry Balmer'
    CompanyName          = 'Jerry Balmer'
    Copyright            = '(c) 2026 Jerry Balmer. Licensed under the Apache License, Version 2.0.'
    Description          = 'Parse Terraform configurations into an HCL AST and build graphs of module calls and provider schemas.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')

    FunctionsToExport = @('Get-TerraformAST', 'ConvertTo-TerraformJson', 'ConvertFrom-TerraformJson', 'Get-TerraformProviderSchema', 'Get-TerraformModuleGraph', 'ConvertTo-TerraformSchemaGraph', 'ConvertTo-TerraformVariableGraph', 'Get-TerraformVariableTrace', 'ConvertTo-TerraformResourceGraph', 'Install-TerraformGraphSkill', 'Test-TerraformGraphSkill', 'Update-TerraformRegistryCache', 'Get-TerraformRegistryProvider', 'Get-TerraformSchemaPack', 'Get-TerraformSchemaCache', 'Update-TerraformProviderDocCache', 'Get-TerraformProviderDoc', 'Get-TerraformDocPack', 'Get-TerraformDocCache', 'New-TerraformClassifier', 'Get-TerraformClassifier', 'Get-TerraformClassifierFinding', 'Get-TerraformGraphBundle', 'New-TerraformGraphBundle', 'Test-TerraformGraphBundle', 'Get-TerraformSubcategorySurvey')
    FormatsToProcess  = @('TerraformGraph.Format.ps1xml')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # What the published module holds: exactly the tree tools/Copy-TerraformGraphModule.ps1
    # assembles (Invoke-Build AssembleModule -> dist/module/TerraformGraph); Pester checks the
    # two agree. LICENSE and NOTICE come from the repo root and the two DLLs are build outputs,
    # so Test-ModuleManifest passes on the assembled tree, not on src/TerraformGraph.
    # lib/TerraformGraph.Json.dll is loaded by the psm1, not RequiredAssemblies: a source
    # checkout without it compiles TerraformGraph.Json.cs instead of failing to import.
    FileList          = @(
        'LICENSE'
        'NOTICE'
        'TerraformGraph.Format.ps1xml'
        'TerraformGraph.psd1'
        'TerraformGraph.psm1'
        'classifiers/DECISIONS.md'
        'classifiers/drawers.json'
        'classifiers/map.json'
        'classifiers/registry.terraform.io-hashicorp-azurerm.5.8.0.json'
        'classifiers/registry.terraform.io-microsoft-azuredevops.1.16.0.json'
        'classifiers/registry.terraform.io-vmware-vsphere.2.17.1.json'
        'data/bundle.json'
        'data/registry.json'
        'lib/TerraformGraph.Json.dll'
        'lib/TerraformGraph.dll'
        'skills/terraformgraph/SKILL.md'
    )

    # ExternalModuleDependencies is PowerShell *modules* only (names Install-Module
    # would resolve). terraform.exe is a native binary, not a module. The HCL
    # parser loads TerraformGraph.dll (Windows x64 only; elsewhere the parser commands throw
    # ParserUnavailable); Get-TerraformProviderSchema calls terraform from PATH.
    PrivateData = @{
        PSData = @{
            Tags                       = @('Terraform', 'HCL', 'Graph', 'AST', 'PowerShell', 'PowerShell74', 'Windows')
            ProjectUri                 = 'https://github.com/JerryBalmer1/TerraformGraph'
            LicenseUri                 = 'https://github.com/JerryBalmer1/TerraformGraph/blob/main/LICENSE'
            ReleaseNotes               = '0.16.0: The module graph contract. TerraformGraph.ModuleNode has Id first and Kind ''Module'' second, plus Callers; TerraformGraph.ModuleEdge has From, To, Kind ''Calls'', Call, Label, File and Line; both have table views. Ids are unique under both -GroupBy modes: Call uses ModuleAddress, Source uses source:<normalised source> with one node per source (Callers lists its calls) and source:<ModuleAddress> for a non-literal source. ModuleGraph gains Findings, the same list as Unresolved. Planned features move one release: view 0.17.0, compare 0.18.0, eras 0.19.0. Full history: https://github.com/JerryBalmer1/TerraformGraph/blob/main/CHANGELOG.md'
            RequireLicenseAcceptance   = $false
            ExternalModuleDependencies = @()
        }
    }

}
