function Get-TerraformGraphErrorId {
    # Not exported. The id part of a FullyQualifiedErrorId ('BundleNotFound,Get-X' -> 'BundleNotFound').
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    ($ErrorRecord.FullyQualifiedErrorId -split ',')[0]
}
