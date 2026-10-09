function Get-TerraformClassifierFinding {
    <#
    .SYNOPSIS
        Gets the types a classifier could not place in a drawer, and why.

    .DESCRIPTION
        Get-TerraformClassifierFinding returns the findings of the classifiers
        Get-TerraformClassifier selects, one TerraformGraph.ClassifierFinding per type in
        the unclassified drawer:
            NoDocPage            the schema has the type but the docs have no page for it
            NoSubcategory        the page has an empty subcategory
            UnmappedSubcategory  the map has no row for the page's subcategory
        Findings are what to look at before adding map rows (with a reason) or recording a
        decision in classifiers\DECISIONS.md not to.

    .PARAMETER Provider
        Providers, as for Get-TerraformClassifier. Default: every provider with a
        classifier.

    .PARAMETER Version
        Classifier version. Default: as for Get-TerraformClassifier.

    .PARAMETER ClassifierPath
        A classifier file, or a folder of them, searched before the user and bundled
        folders.

    .EXAMPLE
        Get-TerraformClassifierFinding -Provider azurerm

        The azurerm types in the unclassified drawer as a table of Type, Kind, Subcategory,
        Finding.

    .EXAMPLE
        Get-TerraformClassifierFinding -Provider azurerm | Group-Object Subcategory | Sort-Object Count -Descending

        Which unmapped subcategories hold the most types.

    .OUTPUTS
        TerraformGraph.ClassifierFinding: ProviderAddress, Version, Type, Kind,
        Subcategory, Finding. Default view is a table of Type, Kind, Subcategory, Finding.

    .LINK
        Get-TerraformClassifier

    .LINK
        New-TerraformClassifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]
        $Provider,

        [string]
        $Version,

        [ValidateScript({ if (Test-Path -LiteralPath $_) { $true } else { throw "ClassifierPath '$_' does not exist." } })]
        [string]
        $ClassifierPath
    )

    try {
        $entries = @(Resolve-TerraformClassifier -Name $Provider -Version $Version -ClassifierPath $ClassifierPath)
    }
    catch {
        Stop-TerraformGraphCommand -Id 'ClassifierNotFound' -Category ObjectNotFound -Target $Provider -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message ($_.Exception.Message)
    }
    foreach ($entry in $entries) { (Read-TerraformClassifierFile -Path $entry.Path).Findings }
}
