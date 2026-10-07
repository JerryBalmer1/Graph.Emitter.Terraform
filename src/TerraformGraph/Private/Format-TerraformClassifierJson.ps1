function Format-TerraformClassifierJson {
    # Not exported. Indented JSON with LF line endings and a final newline, so a classifier
    # file is the same bytes on every machine and rerun.
    param($Document)

    ([TerraformGraph.Json]::Serialize($Document, 64, $false)).Replace("`r`n", "`n") + "`n"
}
