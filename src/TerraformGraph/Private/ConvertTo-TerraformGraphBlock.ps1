function ConvertTo-TerraformGraphBlock {
    param($Block)
    $Block.PSObject.TypeNames.Insert(0, 'TerraformGraph.Block')
    $Block
}
