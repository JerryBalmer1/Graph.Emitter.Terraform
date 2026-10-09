function Get-TerraformModuleSourceKind {
    # Not exported. Classifies a module source string by prefix, the way Terraform's
    # module installer does. Local is checked first so ./ and ../ never look like Registry.
    param(
        [AllowNull()]
        [string]
        $Source
    )

    if ([string]::IsNullOrEmpty($Source)) { return 'Unknown' }

    switch -Regex ($Source) {
        '^\.\.?/'                                { return 'Local' }
        '^(git::|github\.com/|bitbucket\.org/)'  { return 'Git' }
        '^https?://'                             { return 'Http' }
        '^s3::'                                  { return 'S3' }
        '^gcs::'                                 { return 'Gcs' }
        # [host/]namespace/name/provider, optional //subdir.
        '^([A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d+)?/)?[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+(//.*)?$' { return 'Registry' }
    }

    'Unknown'
}
