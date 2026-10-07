@{

    RootModule        = 'TerraformGraph.psm1'
    ModuleVersion     = '0.13.0'
    GUID              = '852206b0-33a6-4dc3-91eb-e9fd6166b17d'
    Author            = 'Jerry Balmer'
    CompanyName       = 'Jerry Balmer'
    Copyright         = '(c) Jerry Balmer. All rights reserved.'
    Description       = 'Parse Terraform configurations into an HCL AST and build graphs of module calls and provider schemas.'
    PowerShellVersion = '7.4'

    FunctionsToExport = @('Get-TerraformAST', 'ConvertTo-TerraformJson', 'ConvertFrom-TerraformJson', 'Get-TerraformProviderSchema', 'Get-TerraformModuleGraph', 'ConvertTo-TerraformSchemaGraph', 'ConvertTo-TerraformVariableGraph', 'Get-TerraformVariableTrace', 'ConvertTo-TerraformResourceGraph', 'Install-TerraformGraphSkill', 'Test-TerraformGraphSkill', 'Update-TerraformRegistryCache', 'Get-TerraformRegistryProvider', 'Get-TerraformSchemaPack', 'Get-TerraformSchemaCache', 'Update-TerraformProviderDocCache', 'Get-TerraformProviderDoc', 'Get-TerraformDocPack', 'Get-TerraformDocCache', 'New-TerraformClassifier', 'Get-TerraformClassifier', 'Get-TerraformClassifierFinding', 'Get-TerraformGraphBundle', 'New-TerraformGraphBundle', 'Test-TerraformGraphBundle', 'Get-TerraformSubcategorySurvey')
    FormatsToProcess  = @('TerraformGraph.Format.ps1xml')
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
            ReleaseNotes               = '0.13.0: Bundle and survey: data/bundle.json names the shipped provider set (official tier plus microsoft/azuredevops and vmware/vsphere) with per-provider versions; Get-TerraformGraphBundle, New-TerraformGraphBundle, Test-TerraformGraphBundle (Fresh/Stale/Missing, -Strict, -Online); Update-TerraformProviderDocCache -BundlePath and -Resume with a DocHarvestSummary; Get-TerraformSubcategorySurvey; registry 429s retried for minutes; integration drawer (21 drawers) graded against the survey; map.json prefix rows place types of providers with no labels (azuredevops: 177 of 177 classified); Invoke-Build HarvestBundleDocs and CheckBundle; README and ONTOLOGY.md. 0.12.0: Classifier drawers: an optional overlay grouping resource and data source types into drawers (network, compute, storage, ..., unclassified) from the providers own doc subcategories through a reasoned map; New-TerraformClassifier, Get-TerraformClassifier, Get-TerraformClassifierFinding; -Classify and -ClassifierPath on ConvertTo-TerraformSchemaGraph and ConvertTo-TerraformResourceGraph (Drawer, Subcategory, Drawers summary; same Ids, nodes and edges); bundled classifiers for azurerm 5.8.0, azuredevops 1.16.0 and vsphere 2.17.1 with drawers.json, map.json and DECISIONS.md. 0.11.0: Provider docs sidecar: Update-TerraformProviderDocCache, Get-TerraformProviderDoc (by provider, Id, type, category, -Examples, or piped SchemaNode/ResourceNode), Get-TerraformDocPack, Get-TerraformDocCache; docs keyed on schema node Ids; manifest.json entries carry kind schema|docs; pack downloads from private GitHub releases with GH_TOKEN. 0.10.0: Schema packs and a local provider schema cache: Get-TerraformSchemaPack, Get-TerraformSchemaCache, Get-TerraformProviderSchema -SaveToCache, ConvertTo-TerraformSchemaGraph -Provider/-Version from the cache, ConvertTo-TerraformResourceGraph -Provider and -AutoSchema. 0.9.0: Provider registry cache: Update-TerraformRegistryCache, Get-TerraformRegistryProvider, bundled data/registry.json, wildcard -Provider and argument completers for Get-TerraformProviderSchema. 0.8.0: Ship the terraformgraph agent skill; add Install-TerraformGraphSkill and Test-TerraformGraphSkill; import hint for detected agent tools. 0.7.0: Add ConvertTo-TerraformResourceGraph. 0.6.0: Add ConvertTo-TerraformVariableGraph and Get-TerraformVariableTrace. 0.5.1: Provider config nodes in ConvertTo-TerraformSchemaGraph; performance. 0.5.0: Add ConvertTo-TerraformSchemaGraph. 0.4.0: Get-TerraformProviderSchema -Provider set fetches a provider schema on demand. 0.3.0: Add Get-TerraformModuleGraph. 0.2.0: Breaking. Expression nodes now carry Kind, Raw and values. 0.1.0: Initial release. Get-TerraformAST, ConvertTo-TerraformJson, ConvertFrom-TerraformJson, Get-TerraformProviderSchema.'
            RequireLicenseAcceptance   = $false
            ExternalModuleDependencies = @()
        }
    }

}
