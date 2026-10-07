function Get-TerraformClassifier {
    <#
    .SYNOPSIS
        Gets provider classifiers: each resource and data source type with its subcategory and drawer.

    .DESCRIPTION
        Get-TerraformClassifier reads classifier files written by New-TerraformClassifier
        (or Invoke-Build BuildClassifier) and returns one TerraformGraph.Classifier per
        provider. It never touches the network.

        Classifiers are looked up in order: -ClassifierPath, then
        $env:LOCALAPPDATA\TerraformGraph\classifiers, then the classifiers folder bundled
        with the module. Without -Version, the first of those that holds a provider at all
        picks the version, its newest there, so your own classifier of an older version wins
        over a newer bundled one. When more than one folder holds that same version, a file
        from -ClassifierPath always wins; otherwise the file whose mapVersion matches the
        bundled map.json wins, then the one with the newer generatedOn, and a warning names
        the file left out. -Shadowed lists those collisions instead of classifiers.

    .PARAMETER Provider
        Providers to return. Patterns match by shape and may use wildcards, as for
        Get-TerraformSchemaCache: 'azurerm', 'azure*', 'hashicorp/azurerm' or a full
        address. Default: every provider with a classifier. A pattern with no classifier is
        a terminating error that names New-TerraformClassifier.

    .PARAMETER Version
        Classifier version (the schema version it was generated from). Default: the newest
        in the first folder that has the provider.

    .PARAMETER ClassifierPath
        A classifier file, or a folder of them, searched before the user and bundled
        folders.

    .PARAMETER Shadowed
        Return one TerraformGraph.ClassifierShadow per provider version present in more than
        one location instead of classifiers: ProviderAddress, Version, Location and Path of
        the file that wins, Reason, ShadowedPath (the others). Nothing when there are none.

    .EXAMPLE
        Get-TerraformClassifier -Provider vsphere

        The bundled vsphere classifier: ProviderAddress, Version, DocsVersion, TypeCount,
        FindingCount.

    .EXAMPLE
        (Get-TerraformClassifier -Provider azurerm).Types | Group-Object Drawer | Sort-Object Count -Descending

        How many azurerm types fall in each drawer.

    .EXAMPLE
        Get-TerraformClassifier -Shadowed | Format-List

        Provider versions with a classifier in both your folder and the module, and which
        file is used.

    .OUTPUTS
        TerraformGraph.Classifier: ProviderAddress, Version, DocsVersion, GeneratedOn,
        MapVersion, Source, Types (TerraformGraph.ClassifiedType: Type, Kind, Subcategory,
        Drawer, Source: subcategory or prefix, the kind of map row that placed the type),
        Findings (TerraformGraph.ClassifierFinding), TypeCount, FindingCount, Path.
        Default view is ProviderAddress, Version, DocsVersion, TypeCount, FindingCount.
        With -Shadowed, TerraformGraph.ClassifierShadow: ProviderAddress, Version, Location
        (ClassifierPath, User or Bundled), Path, Reason, ShadowedPath; default view
        ProviderAddress, Version, Location, Reason.

    .LINK
        New-TerraformClassifier

    .LINK
        Get-TerraformClassifierFinding
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
        $ClassifierPath,

        [switch]
        $Shadowed
    )

    if ($Shadowed) {
        $all = @(Get-TerraformClassifierEntry -ClassifierPath $ClassifierPath)
        $selected = @(Select-TerraformSchemaCacheEntry -Entry $all -Name $Provider | Where-Object { -not $Version -or $_.Version -eq $Version })
        foreach ($group in @($selected | Group-Object { "$($_.ProviderAddress.ToLowerInvariant())|$($_.Version)" } | Sort-Object Name -Culture '')) {
            if (@($group.Group.Location | Select-Object -Unique).Count -lt 2) { continue }
            $pick = Select-TerraformClassifierWinner -Candidate @($group.Group)
            [pscustomobject]@{
                PSTypeName      = 'TerraformGraph.ClassifierShadow'
                ProviderAddress = $pick.Winner.ProviderAddress
                Version         = $pick.Winner.Version
                Location        = $pick.Winner.Location
                Path            = $pick.Winner.Path
                Reason          = $pick.Reason
                ShadowedPath    = [string[]]@($pick.Shadowed.Path)
            }
        }
        return
    }

    try {
        $entries = @(Resolve-TerraformClassifier -Name $Provider -Version $Version -ClassifierPath $ClassifierPath)
    }
    catch {
        Stop-TerraformGraphCommand -Id 'ClassifierNotFound' -Category ObjectNotFound -Target $Provider -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -Message ($_.Exception.Message)
    }
    foreach ($entry in $entries) { Read-TerraformClassifierFile -Path $entry.Path }
}
