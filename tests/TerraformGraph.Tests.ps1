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

    Context "Get-TerraformModuleGraph" {

        BeforeAll {
            # All infra sources are local, so no terraform init is needed.
            $flat      = Get-TerraformModuleGraph -Path $Infra -ErrorAction Stop
            $recursive = Get-TerraformModuleGraph -Path $Infra -Recurse -ErrorAction Stop
            $bySource  = Get-TerraformModuleGraph -Path $Infra -Recurse -GroupBy Source -ErrorAction Stop
            Set-Variable -Name FlatGraph      -Value $flat      -Scope Script
            Set-Variable -Name RecursiveGraph -Value $recursive -Scope Script
            Set-Variable -Name SourceGraph    -Value $bySource  -Scope Script

            $missing = Join-Path $TestDrive 'missing-local'
            New-Item -ItemType Directory -Path $missing | Out-Null
            Set-Content -Path (Join-Path $missing 'main.tf') -Value "module `"gone`" {`n  source = `"./does-not-exist`"`n}"
            Set-Variable -Name MissingLocal -Value $missing -Scope Script

            $registry = Join-Path $TestDrive 'registry'
            New-Item -ItemType Directory -Path $registry | Out-Null
            Set-Content -Path (Join-Path $registry 'main.tf') -Value "module `"vpc`" {`n  source = `"terraform-aws-modules/vpc/aws`"`n}"
            Set-Variable -Name RegistryRoot -Value $registry -Scope Script

            # Writes main.tf into $Dir with one module block per label = source pair.
            function New-ModuleFixture([string]$Dir, [System.Collections.Specialized.OrderedDictionary]$Calls) {
                New-Item -ItemType Directory -Path $Dir -Force | Out-Null
                $tf = foreach ($label in $Calls.Keys) {
                    "module `"$label`" {`n  source = `"$($Calls[$label])`"`n}"
                }
                Set-Content -Path (Join-Path $Dir 'main.tf') -Value ($tf -join "`n") -Encoding utf8NoBOM
            }

            # root calls ./shared twice; shared calls ./leaf.
            $diamond = Join-Path $TestDrive 'diamond'
            New-ModuleFixture $diamond ([ordered]@{ a = './shared'; b = './shared' })
            New-ModuleFixture (Join-Path $diamond 'shared') ([ordered]@{ leaf = './leaf' })
            New-Item -ItemType File -Path (Join-Path $diamond 'shared' 'leaf' 'main.tf') -Value 'locals {}' -Force | Out-Null
            Set-Variable -Name DiamondRoot -Value $diamond -Scope Script

            # root -> ./x -> ../y -> ../x. x and y are siblings so ../x leads back to x.
            $cycle = Join-Path $TestDrive 'cycle'
            New-ModuleFixture $cycle ([ordered]@{ x = './x' })
            New-ModuleFixture (Join-Path $cycle 'x') ([ordered]@{ y = '../y' })
            New-ModuleFixture (Join-Path $cycle 'y') ([ordered]@{ x = '../x' })
            Set-Variable -Name CycleRoot -Value $cycle -Scope Script
        }

        It "is exported from TerraformGraph" {
            (Get-Command Get-TerraformModuleGraph -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
        }

        It "stops at direct children without -Recurse" {
            @($FlatGraph.Nodes).Count | Should -Be 2
            @($FlatGraph.Edges).Count | Should -Be 1
            $network = $FlatGraph.Nodes | Where-Object Key -eq 'network'
            $network.Depth | Should -Be 1
            $network.Resolved | Should -BeTrue
            $network.Blocks | Should -BeNullOrEmpty
        }

        It "follows nested calls with -Recurse" {
            @($RecursiveGraph.Nodes).Count | Should -Be 3
            @($RecursiveGraph.Edges).Count | Should -Be 2
            $endpoint = $RecursiveGraph.Nodes | Where-Object Name -eq 'endpoint'
            $endpoint.Depth | Should -Be 2
            $endpoint.ParentKey | Should -Be 'network'
            $endpoint.ModuleAddress | Should -Be 'module.network.module.endpoint'
            @($endpoint.Blocks).Count | Should -BeGreaterThan 0
        }

        It "describes the root node" {
            $root = $RecursiveGraph.Nodes | Where-Object ModuleAddress -eq 'root'
            $root.Key | Should -Be ''
            $root.ModuleAddress | Should -Be 'root'
            $root.ParentKey | Should -BeNullOrEmpty
            $root.Depth | Should -Be 0
            $root.Source | Should -BeNullOrEmpty
            $root.SourceKind | Should -Be 'Root'
        }

        It "keeps the calling module block on the network node" {
            $network = $RecursiveGraph.Nodes | Where-Object Key -eq 'network'
            $network.SourceKind | Should -Be 'Local'
            $network.Block.Type | Should -Be 'module'
            $network.Block.Name | Should -Be 'network'
        }

        It "links edges by Id and records the module block line" {
            $root    = $RecursiveGraph.Nodes | Where-Object ModuleAddress -eq 'root'
            $network = $RecursiveGraph.Nodes | Where-Object Key -eq 'network'
            $edge    = $RecursiveGraph.Edges | Where-Object Call -eq 'module.network'
            $edge.From | Should -Be $root.Id
            $edge.To | Should -Be $network.Id
            $line = (Select-String -LiteralPath $MainTf -Pattern '^module "network"').LineNumber
            $edge.Line | Should -Be $line
        }

        It "uses Source as Id with -GroupBy Source and ModuleAddress with -GroupBy Call" {
            $bySource = $SourceGraph.Nodes | Where-Object Name -eq 'endpoint'
            $bySource.Id | Should -Be $bySource.Source
            $byCall = $RecursiveGraph.Nodes | Where-Object Name -eq 'endpoint'
            $RecursiveGraph.GroupBy | Should -Be 'Call'
            $byCall.Id | Should -Be $byCall.ModuleAddress
        }

        It "marks a missing local source as LocalPathMissing" {
            $graph = Get-TerraformModuleGraph -Path $MissingLocal -ErrorAction Stop
            $gone = $graph.Nodes | Where-Object Name -eq 'gone'
            $gone.Resolved | Should -BeFalse
            $gone.Reason | Should -Be 'LocalPathMissing'
            $graph.Unresolved.ModuleAddress | Should -Contain 'module.gone'
        }

        It "walks a module called from two places once per call" {
            $graph = Get-TerraformModuleGraph -Path $DiamondRoot -Recurse -ErrorAction Stop
            $a = $graph.Nodes | Where-Object Key -eq 'a'
            $b = $graph.Nodes | Where-Object Key -eq 'b'
            $a.Blocks | Should -Not -BeNullOrEmpty
            $b.Blocks | Should -Not -BeNullOrEmpty
            $a.Dir | Should -Be $b.Dir
            $graph.Nodes.ModuleAddress | Should -Contain 'module.a.module.leaf'
            $graph.Nodes.ModuleAddress | Should -Contain 'module.b.module.leaf'
            @($graph.Nodes).Count | Should -Be 5
            @($graph.Edges).Count | Should -Be 4
        }

        It "stops at a call whose Dir is one of its own ancestors" {
            $graph = Get-TerraformModuleGraph -Path $CycleRoot -Recurse -ErrorAction Stop
            $cycles = @($graph.Nodes | Where-Object Reason -eq 'Cycle')
            $cycles.Count | Should -Be 1
            $cycles[0].ModuleAddress | Should -Be 'module.x.module.y.module.x'
            $cycles[0].Resolved | Should -BeTrue
            $cycles[0].Dir | Should -Be ($graph.Nodes | Where-Object Key -eq 'x').Dir
            $cycles[0].Blocks | Should -BeNullOrEmpty
            @($graph.Nodes).Count | Should -Be 4
            @($graph.Edges).Count | Should -Be 3
            @($graph.Unresolved).Count | Should -Be 0
        }

        It "marks a registry source without .terraform as NotInitialized" {
            $graph = Get-TerraformModuleGraph -Path $RegistryRoot -ErrorAction Stop
            $vpc = $graph.Nodes | Where-Object Name -eq 'vpc'
            $vpc.Resolved | Should -BeFalse
            $vpc.Reason | Should -Be 'NotInitialized'
            $vpc.SourceKind | Should -Be 'Registry'
        }

        It "sets the default display properties" {
            (Get-TypeData TerraformGraph.ModuleNode).DefaultDisplayPropertySet.ReferencedProperties |
                Should -Be @('ModuleAddress', 'SourceKind', 'Depth', 'Resolved', 'Dir')
            (Get-TypeData TerraformGraph.ModuleGraph).DefaultDisplayPropertySet.ReferencedProperties |
                Should -Be @('Root', 'GroupBy', 'NodeCount', 'EdgeCount', 'UnresolvedCount')
            $RecursiveGraph.NodeCount | Should -Be 3
            $RecursiveGraph.EdgeCount | Should -Be 2
            $RecursiveGraph.UnresolvedCount | Should -Be 0
        }
    }
}
