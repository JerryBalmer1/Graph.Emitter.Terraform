BeforeAll {
    # Never resolve Get-TerraformAST from an installed copy of the old AST module.
    Remove-Module TerraformAST, TerraformGraph -Force -ErrorAction SilentlyContinue
    Import-Module "$PSScriptRoot\..\src\TerraformGraph\TerraformGraph.psd1" -Force
}

Describe "TerraformGraph" {

    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $infra    = Join-Path $repoRoot "infra"
        $mainTf   = Join-Path $infra "main.tf"
        Set-Variable -Name RepoRoot -Value $repoRoot -Scope Script
        Set-Variable -Name Infra    -Value $infra    -Scope Script
        Set-Variable -Name MainTf   -Value $mainTf   -Scope Script
    }

    Context "Get-TerraformAST" {

        It "is exported" {
            Get-Command Get-TerraformAST -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }

        It "resolves to the TerraformGraph module" {
            (Get-Command Get-TerraformAST -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
        }

        It "parses infra with -Path" {
            $ast = @(Get-TerraformAST -Path $Infra -ErrorAction Stop)
            $ast | Should -Not -BeNullOrEmpty
            $ast.Type | Should -Contain "variable"
            $ast.Type | Should -Contain "module"
            $ast.Type | Should -Not -Contain "nested-only-sentinel"
        }

        It "parses infra with -Path -Recurse and includes nested modules" {
            $ast = @(Get-TerraformAST -Path $Infra -Recurse -ErrorAction Stop)
            $labels = @($ast | ForEach-Object { $_.Labels })
            $labels | Should -Contain "endpoint"
            $labels | Should -Contain "listener"
        }

        It "parses a file with -FilePath" {
            $ast = @(Get-TerraformAST -FilePath $MainTf -ErrorAction Stop)
            $ast | Should -Not -BeNullOrEmpty
            $ast.Type | Should -Contain "terraform"
        }

        It "rejects a missing file" {
            { Get-TerraformAST -FilePath (Join-Path $RepoRoot "does-not-exist.tf") -ErrorAction Stop } |
                Should -Throw
        }

        It "rejects a non-.tf FilePath" {
            { Get-TerraformAST -FilePath $PSCommandPath -ErrorAction Stop } |
                Should -Throw
        }

        It "rejects a missing directory" {
            { Get-TerraformAST -Path (Join-Path $RepoRoot "does-not-exist-dir") -ErrorAction Stop } |
                Should -Throw
        }
    }

    Context "block types in infra" {

        BeforeAll {
            $blocks = @(Get-TerraformAST -Path $Infra -ErrorAction Stop)
            Set-Variable -Name Blocks -Value $blocks -Scope Script
        }

        It "finds terraform" {
            $Blocks.Type | Should -Contain "terraform"
        }

        It "finds provider" {
            $Blocks.Type | Should -Contain "provider"
        }

        It "finds variable" {
            $Blocks.Type | Should -Contain "variable"
        }

        It "finds locals" {
            $Blocks.Type | Should -Contain "locals"
        }

        It "finds resource" {
            $Blocks.Type | Should -Contain "resource"
        }

        It "finds data" {
            $Blocks.Type | Should -Contain "data"
        }

        It "finds module" {
            $Blocks.Type | Should -Contain "module"
        }

        It "finds output" {
            $Blocks.Type | Should -Contain "output"
        }

        It "finds check" {
            $Blocks.Type | Should -Contain "check"
        }
    }

    Context "variable labels in infra" {

        BeforeAll {
            $names = @(
                Get-TerraformAST -Path $Infra -ErrorAction Stop |
                    Where-Object Type -eq "variable" |
                    ForEach-Object { $_.Labels[0] }
            )
            Set-Variable -Name VariableNames -Value $names -Scope Script
        }

        It "includes string variable aws_region" {
            $VariableNames | Should -Contain "aws_region"
        }

        It "includes number variable instance_count" {
            $VariableNames | Should -Contain "instance_count"
        }

        It "includes bool variable enable_public_ip" {
            $VariableNames | Should -Contain "enable_public_ip"
        }

        It "includes list variable availability_zones" {
            $VariableNames | Should -Contain "availability_zones"
        }

        It "includes map variable tags" {
            $VariableNames | Should -Contain "tags"
        }

        It "includes object variable endpoint" {
            $VariableNames | Should -Contain "endpoint"
        }

        It "includes tuple variable pair" {
            $VariableNames | Should -Contain "pair"
        }
    }

    Context "Expression values" {

        BeforeAll {
            $blocks = @(Get-TerraformAST -Path $Infra -ErrorAction Stop)
            $module = $blocks | Where-Object { $_.Type -eq "module" -and $_.Labels[0] -eq "network" }
            $instanceCount = $blocks | Where-Object { $_.Type -eq "variable" -and $_.Labels[0] -eq "instance_count" }
            Set-Variable -Name NetworkModule -Value $module -Scope Script
            Set-Variable -Name InstanceCount -Value $instanceCount -Scope Script
        }

        It "reads module network source as a literal template" {
            $expr = $NetworkModule.Body.Attributes.source.Expr
            $expr.Kind | Should -Be "TemplateExpr"
            $expr.IsLiteral | Should -BeTrue
            $expr.Value | Should -Be "./modules/network"
        }

        It "reads variable instance_count default as a number literal" {
            $expr = $InstanceCount.Body.Attributes.default.Expr
            $expr.Kind | Should -Be "LiteralValueExpr"
            $expr.Value | Should -Be 2
            $expr.ValueType | Should -Be "number"
        }

        It "reads module network aws_region as a scope traversal" {
            $expr = $NetworkModule.Body.Attributes.aws_region.Expr
            $expr.Kind | Should -Be "ScopeTraversalExpr"
            $expr.Traversal | Should -Be "var.aws_region"
        }
    }

    Context "ConvertTo-TerraformJson / ConvertFrom-TerraformJson" {

        BeforeAll {
            # 200 levels: deeper than ConvertTo-Json's 100 limit.
            $deep = [pscustomobject]@{ value = 'leaf' }
            1..200 | ForEach-Object { $deep = [pscustomobject]@{ child = $deep } }
            Set-Variable -Name Deep -Value $deep -Scope Script
        }

        It "are exported" {
            Get-Command ConvertTo-TerraformJson -ErrorAction Stop | Should -Not -BeNullOrEmpty
            Get-Command ConvertFrom-TerraformJson -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }

        It "round-trips an object deeper than ConvertTo-Json allows" {
            $json = $Deep | ConvertTo-TerraformJson -ErrorAction Stop
            $back = $json | ConvertFrom-TerraformJson -ErrorAction Stop
            $node = $back
            1..200 | ForEach-Object { $node = $node.child }
            $node.value | Should -Be 'leaf'
        }

        It "writes indented JSON without escaping HTML characters" {
            $json = [pscustomobject]@{ a = 1; b = '<x & y>' } | ConvertTo-TerraformJson
            $nl = [Environment]::NewLine
            $json | Should -Be "{$nl  `"a`": 1,$nl  `"b`": `"<x & y>`"$nl}"
        }

        It "writes one line with -Compress" {
            [ordered]@{ a = 1; b = @(1, 2) } | ConvertTo-TerraformJson -Compress | Should -Be '{"a":1,"b":[1,2]}'
        }

        It "writes multiple pipeline inputs or -AsArray as an array" {
            1, 2 | ConvertTo-TerraformJson -Compress | Should -Be '[1,2]'
            1 | ConvertTo-TerraformJson -Compress -AsArray | Should -Be '[1]'
        }

        It "throws when nesting exceeds -Depth" {
            { $Deep | ConvertTo-TerraformJson -Depth 50 -ErrorAction Stop } | Should -Throw '*exceeds -Depth 50*'
        }

        It "throws on a circular reference" {
            $a = [pscustomobject]@{ name = 'a' }
            $a | Add-Member -NotePropertyName self -NotePropertyValue $a
            { $a | ConvertTo-TerraformJson -ErrorAction Stop } | Should -Throw '*Circular reference*'
        }

        It "serializes Get-TerraformAST output" {
            $json = Get-TerraformAST -FilePath $MainTf -ErrorAction Stop | ConvertTo-TerraformJson -ErrorAction Stop
            $back = @($json | ConvertFrom-TerraformJson -ErrorAction Stop)
            $back.Type | Should -Contain 'resource'
        }

        It "parses -AsHashtable with case-sensitive keys" {
            $h = '{"Name":1,"name":2}' | ConvertFrom-TerraformJson -AsHashtable
            $h | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $h['Name'] | Should -Be 1
            $h['name'] | Should -Be 2
        }

        It "throws on case-colliding keys without -AsHashtable" {
            { '{"Name":1,"name":2}' | ConvertFrom-TerraformJson -ErrorAction Stop } | Should -Throw '*-AsHashtable*'
        }

        It "enumerates top-level arrays unless -NoEnumerate" {
            @('[1,2,3]' | ConvertFrom-TerraformJson).Count | Should -Be 3
            @('[1,2,3]' | ConvertFrom-TerraformJson -NoEnumerate).Count | Should -Be 1
        }

        It "keeps large integers exact" {
            $n = '{"n":123456789012345678901234567890}' | ConvertFrom-TerraformJson
            $n.n | Should -BeOfType [System.Numerics.BigInteger]
            $n.n.ToString() | Should -Be '123456789012345678901234567890'
        }

        It "joins Get-Content lines from the pipeline" {
            "{", '  "a": 1', "}" | ConvertFrom-TerraformJson | Select-Object -ExpandProperty a | Should -Be 1
        }
    }

    Context "Get-TerraformProviderSchema" {

        BeforeAll {
            # The built-in provider needs no terraform init, so no downloads.
            $builtin = Join-Path $TestDrive 'builtin'
            New-Item -ItemType Directory -Path $builtin | Out-Null
            Set-Content -Path (Join-Path $builtin 'main.tf') -Value 'resource "terraform_data" "x" {}'
            Set-Variable -Name Builtin -Value $builtin -Scope Script

            $uninitialized = Join-Path $TestDrive 'uninitialized'
            New-Item -ItemType Directory -Path $uninitialized | Out-Null
            Set-Content -Path (Join-Path $uninitialized 'main.tf') -Value 'resource "null_resource" "x" {}'
            Set-Variable -Name Uninitialized -Value $uninitialized -Scope Script
        }

        It "is exported" {
            Get-Command Get-TerraformProviderSchema -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }

        It "returns nested ordered dictionaries by default" {
            $schema = Get-TerraformProviderSchema -Path $Builtin -ErrorAction Stop
            $schema | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $provider = $schema['provider_schemas']['terraform.io/builtin/terraform']
            $provider | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $provider['resource_schemas']['terraform_data']['block']['attributes']['id']['type'] | Should -Be 'string'
        }

        It "defaults -Path to the current location" {
            Push-Location $Builtin
            try {
                $schema = Get-TerraformProviderSchema -ErrorAction Stop
                $schema['provider_schemas'].Keys | Should -Contain 'terraform.io/builtin/terraform'
            }
            finally {
                Pop-Location
            }
        }

        It "returns indented JSON with -OutputFormat Json" {
            $json = Get-TerraformProviderSchema -Path $Builtin -OutputFormat Json -ErrorAction Stop
            $json | Should -BeOfType [string]
            $json | Should -Match ([regex]::Escape([Environment]::NewLine + '  "format_version": "1.0"'))
            ($json | ConvertFrom-TerraformJson).provider_schemas.'terraform.io/builtin/terraform' | Should -Not -BeNullOrEmpty
        }

        It "throws when providers are not installed" {
            { Get-TerraformProviderSchema -Path $Uninitialized -ErrorAction Stop } | Should -Throw '*terraform init*'
        }

        It "rejects a missing directory" {
            { Get-TerraformProviderSchema -Path (Join-Path $RepoRoot 'does-not-exist-dir') -ErrorAction Stop } |
                Should -Throw "*is not an existing directory*"
        }
    }
}
