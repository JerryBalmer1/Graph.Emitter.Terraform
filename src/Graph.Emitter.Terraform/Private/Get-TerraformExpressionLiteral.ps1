function Get-TerraformExpressionLiteral {
    # Not exported. Value of a literal expression (a LiteralValueExpr, or a TemplateExpr with
    # IsLiteral), else $null. The leading comma keeps a list value from being unrolled.
    param(
        [AllowNull()]
        $Expr
    )

    if ($null -eq $Expr) { return $null }
    if ($Expr.Kind -eq 'LiteralValueExpr' -or $Expr.IsLiteral) { return , $Expr.Value }
    $null
}
