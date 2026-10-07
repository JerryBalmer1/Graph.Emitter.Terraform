function Get-TerraformExpressionReferences {
    # Not exported. Walks an expression object from the Go parser and returns every
    # ScopeTraversalExpr Traversal in source order, deduplicated, as {Traversal, Root}.
    # Root is the binding root: var.<name>, local.<name> or module.<name>.<output>, with
    # index and attribute suffixes stripped; $null for anything else (resources, data,
    # path, terraform, each, count, self, for-expression variables).
    param(
        [AllowNull()]
        $Expr
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $found = [System.Collections.Generic.List[object]]::new()

    $walk = {
        param($e)
        if ($null -eq $e) { return }
        switch ([string]$e.Kind) {
            'ScopeTraversalExpr' {
                $traversal = [string]$e.Traversal
                if ($seen.Add($traversal)) {
                    # One index step is [key]; a quoted key may contain ] or an escaped ".
                    $index = '\[(?:"(?:[^"\\]|\\.)*"|[^\]"]*)\]'
                    $root = $null
                    if ($traversal -match '^(var|local)\.([A-Za-z_][\w-]*)') {
                        $root = "$($Matches[1]).$($Matches[2])"
                    }
                    elseif ($traversal -match "^module\.([A-Za-z_][\w-]*)(?:$index)*\.([A-Za-z_][\w-]*)") {
                        $root = "module.$($Matches[1]).$($Matches[2])"
                    }
                    $found.Add([pscustomobject]@{ Traversal = $traversal; Root = $root })
                }
            }
            'TemplateExpr'          { foreach ($p in @($e.Parts)) { & $walk $p } }
            'FunctionCallExpr'      { foreach ($a in @($e.Args)) { & $walk $a } }
            'ObjectConsExpr'        { foreach ($i in @($e.Items)) { & $walk $i.Key; & $walk $i.Value } }
            'TupleConsExpr'         { foreach ($x in @($e.Exprs)) { & $walk $x } }
            'ConditionalExpr'       { & $walk $e.Condition; & $walk $e.TrueResult; & $walk $e.FalseResult }
            'BinaryOpExpr'          { & $walk $e.LHS; & $walk $e.RHS }
            'UnaryOpExpr'           { & $walk $e.Val }
            'IndexExpr'             { & $walk $e.Collection; & $walk $e.Key }
            'SplatExpr'             { & $walk $e.Source; & $walk $e.Each }
            'ForExpr'               { & $walk $e.CollExpr; & $walk $e.KeyExpr; & $walk $e.ValExpr; & $walk $e.CondExpr }
            'ParenthesesExpr'       { & $walk $e.Expression }
            'TemplateWrapExpr'      { & $walk $e.Wrapped }
            # A RelativeTraversalExpr's Traversal is relative to Source (.id), not a scope.
            'RelativeTraversalExpr' { & $walk $e.Source }
        }
    }
    & $walk $Expr

    , $found.ToArray()
}
