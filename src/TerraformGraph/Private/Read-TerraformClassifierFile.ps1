function Read-TerraformClassifierFile {
    # Not exported. One classifier file as TerraformGraph.Classifier with
    # TerraformGraph.ClassifiedType Types and TerraformGraph.ClassifierFinding Findings.
    param([string]$Path)

    $document = Read-TerraformClassifierJson -Path $Path
    $address = [string]$document['provider']
    $version = [string]$document['version']
    $types = [object[]]@(foreach ($item in @($document['types'])) {
            [pscustomobject]@{
                PSTypeName  = 'TerraformGraph.ClassifiedType'
                Type        = [string]$item['type']
                Kind        = [string]$item['kind']
                Subcategory = $item['subcategory']
                Drawer      = [string]$item['drawer']
                Source      = $item['source']
            }
        })
    $findings = [object[]]@(foreach ($item in @($document['findings'])) {
            [pscustomobject]@{
                PSTypeName      = 'TerraformGraph.ClassifierFinding'
                ProviderAddress = $address
                Version         = $version
                Type            = [string]$item['type']
                Kind            = [string]$item['kind']
                Subcategory     = $item['subcategory']
                Finding         = [string]$item['finding']
            }
        })
    [pscustomobject]@{
        PSTypeName      = 'TerraformGraph.Classifier'
        ProviderAddress = $address
        Version         = $version
        DocsVersion     = [string]$document['docsVersion']
        GeneratedOn     = [string]$document['generatedOn']
        MapVersion      = [string]$document['mapVersion']
        Source          = [string]$document['source']
        Types           = $types
        Findings        = $findings
        TypeCount       = $types.Length
        FindingCount    = $findings.Length
        Path            = $Path
    }
}
