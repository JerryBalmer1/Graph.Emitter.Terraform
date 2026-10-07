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

        It "binds pipeline FileInfo input to -FilePath" {
            $piped = @(Get-ChildItem $Infra -Filter *.tf | Get-TerraformAST -ErrorAction Stop)
            $piped.Count | Should -Be @(Get-TerraformAST -Path $Infra -ErrorAction Stop).Count
            $groups = $piped | Group-Object File | Sort-Object Name
            $groups.Name | Should -Be @('main.tf', 'outputs.tf', 'variables.tf')
            # Object[] has its own Count, so enumerate the groups' Count explicitly.
            $groups | ForEach-Object Count | Should -Be @(9, 2, 7)
        }

        It "writes a non-terminating error for a directory with no .tf files" {
            $empty = Join-Path $TestDrive 'empty'
            New-Item -ItemType Directory -Path $empty | Out-Null
            $out = Get-TerraformAST -Path $empty -ErrorAction SilentlyContinue -ErrorVariable astErrors
            $out | Should -BeNullOrEmpty
            $astErrors.Count | Should -Be 1
            $astErrors[0].Exception.Message | Should -Be 'No .tf files found.'
        }

        It "writes a non-terminating parse error for an unclosed block" {
            $badFile = Join-Path $TestDrive 'badhcl' 'main.tf'
            New-Item -ItemType File -Path $badFile -Value 'resource "terraform_data" "x" {' -Force | Out-Null
            $out = Get-TerraformAST -Path (Split-Path $badFile) -ErrorAction SilentlyContinue -ErrorVariable astErrors
            $out | Should -BeNullOrEmpty
            $astErrors.Count | Should -Be 1
            $astErrors[0].FullyQualifiedErrorId | Should -Be 'HclParseError,Get-TerraformAST'
            $astErrors[0].Exception.Message |
                Should -BeLike "Error parsing HCL file: $badFile`:1,31-32: Unclosed configuration block; There is no closing brace for this block before the end of the file.*($badFile)"
        }

        It "writes one parse error per bad file and no output" {
            $dir = Join-Path $TestDrive 'badhcl2'
            New-Item -ItemType File -Path (Join-Path $dir 'a.tf') -Value 'resource "terraform_data" "a" {' -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $dir 'b.tf') -Value 'variable "b" {' -Force | Out-Null
            $out = Get-TerraformAST -Path $dir -ErrorAction SilentlyContinue -ErrorVariable astErrors
            $out | Should -BeNullOrEmpty
            $astErrors.Count | Should -Be 2
            $astErrors.TargetObject | Should -Be @((Join-Path $dir 'a.tf'), (Join-Path $dir 'b.tf'))
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

        It "throws when JSON nesting exceeds -Depth" {
            { '[[[[1]]]]' | ConvertFrom-TerraformJson -Depth 2 -ErrorAction Stop } |
                Should -Throw '*maximum configured depth of 2 has been exceeded*'
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

        It "keeps a non-registry host in the required_providers source" {
            # init fails against the fake host; only the written main.tf matters here.
            # Inside It a throw stays terminating even with SilentlyContinue, so catch it.
            $dir = Join-Path $TestDrive 'provider-other-host'
            try {
                Get-TerraformProviderSchema -Provider 'example.com/acme/thing' -WorkingDirectory $dir -ErrorAction SilentlyContinue
            }
            catch {
                $_.Exception.Message | Should -BeLike '*terraform init failed*'
            }
            Get-Content -LiteralPath (Join-Path $dir 'main.tf') -Raw | Should -BeLike '*source = "example.com/acme/thing"*'
        }

        It "prefixes the default working directory with a non-registry host" {
            # init fails against the fake host; the init verbose line carries the default path.
            # Inside It a throw stays terminating even with SilentlyContinue, so catch it.
            $verbose = [System.Collections.Generic.List[string]]::new()
            try {
                Get-TerraformProviderSchema -Provider 'example.com/acme/thing' -Cleanup -Verbose -ErrorAction SilentlyContinue 4>&1 |
                    ForEach-Object { if ($_ -is [System.Management.Automation.VerboseRecord]) { $verbose.Add($_.Message) } }
            }
            catch {
                $_.Exception.Message | Should -BeLike '*terraform init failed*'
            }
            $init = @($verbose | Where-Object { $_ -like 'terraform -chdir=* init *' })
            $init.Count | Should -Be 1
            $dir = ($init[0] -replace '^terraform -chdir=', '') -replace ' init .*$', ''
            $dir | Should -BeLike '*\example_com-acme-thing-latest'
            Test-Path -LiteralPath $dir | Should -BeFalse
        }

        Context "-Provider (registry)" -Skip:(-not (Test-Connection registry.terraform.io -Count 1 -Quiet)) {

            BeforeAll {
                # One provider download shared by every working directory in this context.
                $previousCache = $env:TF_PLUGIN_CACHE_DIR
                $env:TF_PLUGIN_CACHE_DIR = Join-Path $TestDrive 'plugin-cache'
                New-Item -ItemType Directory -Path $env:TF_PLUGIN_CACHE_DIR | Out-Null
                Set-Variable -Name PreviousCache -Value $previousCache -Scope Script

                $nullDir = Join-Path $TestDrive 'provider-null'
                $nullSchema = Get-TerraformProviderSchema -Provider 'null' -Version '= 3.2.3' -WorkingDirectory $nullDir -ErrorAction Stop
                Set-Variable -Name NullDir    -Value $nullDir    -Scope Script
                Set-Variable -Name NullSchema -Value $nullSchema -Scope Script
            }

            AfterAll {
                $env:TF_PLUGIN_CACHE_DIR = $PreviousCache
            }

            It "fetches hashicorp/null with -Provider -Version -WorkingDirectory" {
                $NullSchema | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
                $keys = @($NullSchema['provider_schemas'].Keys)
                $keys.Count | Should -Be 1
                $keys[0] | Should -BeLike '*hashicorp/null'
                $NullSchema['provider_schemas'][$keys[0]]['resource_schemas'].Keys | Should -Contain 'null_resource'
            }

            It "writes the resolved version with -Verbose" {
                $verbose = Get-TerraformProviderSchema -Provider 'null' -Version '= 3.2.3' -WorkingDirectory $NullDir -Verbose -ErrorAction Stop 4>&1 |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
                ($verbose.Message -join [Environment]::NewLine) | Should -BeLike '*3.2.3*'
            }

            It "skips terraform init when the lock file exists" {
                $mainTf = Get-Item -LiteralPath (Join-Path $NullDir 'main.tf')
                $lock = Get-Item -LiteralPath (Join-Path $NullDir '.terraform.lock.hcl')
                $mainBefore = $mainTf.LastWriteTimeUtc
                $lockBefore = $lock.LastWriteTimeUtc
                Get-TerraformProviderSchema -Provider 'null' -Version '= 3.2.3' -WorkingDirectory $NullDir -ErrorAction Stop | Out-Null
                $mainTf.Refresh(); $lock.Refresh()
                $mainTf.LastWriteTimeUtc | Should -Not -Be $mainBefore
                $lock.LastWriteTimeUtc | Should -Be $lockBefore
            }

            It "re-runs terraform init with -Force" {
                $lock = Get-Item -LiteralPath (Join-Path $NullDir '.terraform.lock.hcl')
                $lockBefore = $lock.LastWriteTimeUtc
                Get-TerraformProviderSchema -Provider 'null' -Version '= 3.2.3' -WorkingDirectory $NullDir -Force -ErrorAction Stop | Out-Null
                $lock.Refresh()
                $lock.LastWriteTimeUtc | Should -Not -Be $lockBefore
            }

            It "removes the working directory with -Cleanup and still returns the schema" {
                $dir = Join-Path $TestDrive 'provider-null-cleanup'
                $schema = Get-TerraformProviderSchema -Provider 'null' -Version '= 3.2.3' -WorkingDirectory $dir -Cleanup -ErrorAction Stop
                $schema['provider_schemas'].Keys | Should -Contain 'registry.terraform.io/hashicorp/null'
                Test-Path -LiteralPath $dir | Should -BeFalse
            }

            It "normalizes 'null', 'hashicorp/null', and 'registry.terraform.io/hashicorp/null' to one key" {
                $keys = foreach ($spelling in 'null', 'hashicorp/null', 'registry.terraform.io/hashicorp/null') {
                    $dir = Join-Path $TestDrive "provider-spelling-$($spelling -replace '\W', '_')"
                    $schema = Get-TerraformProviderSchema -Provider $spelling -Version '= 3.2.3' -WorkingDirectory $dir -Cleanup -ErrorAction Stop
                    @($schema['provider_schemas'].Keys)
                }
                $keys.Count | Should -Be 3
                @($keys | Select-Object -Unique) | Should -Be @('registry.terraform.io/hashicorp/null')
            }

            It "rejects an invalid -Provider before running terraform" {
                $dir = Join-Path $TestDrive 'provider-invalid'
                { Get-TerraformProviderSchema -Provider 'not//valid' -WorkingDirectory $dir -ErrorAction Stop } |
                    Should -Throw "*is not a provider address*"
                Test-Path -LiteralPath (Join-Path $dir 'main.tf') | Should -BeFalse
            }

            It "throws terraform's stderr for a nonexistent provider and cleans up" {
                $dir = Join-Path $TestDrive 'provider-missing'
                { Get-TerraformProviderSchema -Provider 'hashicorp/definitely-not-a-provider-xyz' -WorkingDirectory $dir -Cleanup -ErrorAction Stop } |
                    Should -Throw "*terraform init failed*Failed to query available provider packages*"
                Test-Path -LiteralPath $dir | Should -BeFalse
            }
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

        It "rejects a missing directory" {
            { Get-TerraformModuleGraph -Path (Join-Path $RepoRoot 'does-not-exist-dir') -ErrorAction Stop } |
                Should -Throw "*is not an existing directory*"
        }
    }

    Context "ConvertTo-TerraformSchemaGraph" {

        BeforeAll {
            # The built-in provider: terraform init downloads nothing.
            $dir = Join-Path $TestDrive 'schema-builtin'
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {}'
            $null = terraform "-chdir=$dir" init -input=false -no-color
            $schema = Get-TerraformProviderSchema -Path $dir -ErrorAction Stop
            Set-Variable -Name SchemaDir   -Value $dir -Scope Script
            Set-Variable -Name SchemaDoc   -Value $schema -Scope Script
            Set-Variable -Name SchemaGraph -Value ($schema | ConvertTo-TerraformSchemaGraph -ErrorAction Stop) -Scope Script
        }

        It "is exported from TerraformGraph" {
            (Get-Command ConvertTo-TerraformSchemaGraph -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
        }

        It "lists only the built-in provider" {
            $SchemaGraph.Providers | Should -Be @('terraform.io/builtin/terraform')
        }

        It "has one Provider node at Depth 0 with no parent" {
            $providers = @($SchemaGraph.Nodes | Where-Object Kind -eq 'Provider')
            $providers.Count | Should -Be 1
            $providers[0].Depth | Should -Be 0
            $providers[0].ParentId | Should -BeNullOrEmpty
        }

        It "builds the terraform_data Resource node" {
            $resource = $SchemaGraph.Nodes | Where-Object { $_.Kind -eq 'Resource' -and $_.Path -eq 'terraform_data' }
            $resource.Id | Should -Be 'terraform.io/builtin/terraform/resource/terraform_data'
            $resource.Depth | Should -Be 1
        }

        It "builds the terraform_data Attribute nodes with types and flags" {
            $parentId = 'terraform.io/builtin/terraform/resource/terraform_data'
            $attributes = @($SchemaGraph.Nodes | Where-Object { $_.Kind -eq 'Attribute' -and $_.ParentId -eq $parentId })
            $attributes.Name | Should -Be @('id', 'input', 'output', 'triggers_replace')
            ($attributes | Where-Object Name -eq 'input').Type | Should -Be 'any'
            ($attributes | Where-Object Name -eq 'id').Computed | Should -BeTrue
        }

        It "adds no /config/ nodes for the built-in provider's empty config block" {
            @($SchemaGraph.Nodes | Where-Object Id -like 'terraform.io/builtin/terraform/config/*').Count | Should -Be 0
        }

        It "puts terraform_remote_state under /data/ as a DataSource" {
            $data = $SchemaGraph.Nodes | Where-Object Path -eq 'terraform_remote_state'
            $data.Kind | Should -Be 'DataSource'
            $data.Id | Should -Be 'terraform.io/builtin/terraform/data/terraform_remote_state'
        }

        It "gives every non-Provider node exactly one incoming edge from its ParentId" {
            foreach ($node in @($SchemaGraph.Nodes | Where-Object Kind -ne 'Provider')) {
                $incoming = @($SchemaGraph.Edges | Where-Object To -eq $node.Id)
                $incoming.Count | Should -Be 1 -Because $node.Id
                $incoming[0].From | Should -Be $node.ParentId
                $incoming[0].Kind | Should -Be 'Contains'
            }
            $SchemaGraph.EdgeCount | Should -Be ($SchemaGraph.NodeCount - 1)
        }

        It "summarizes counts by Kind" {
            $SchemaGraph.Summary.Keys | Should -Contain 'Provider'
            $SchemaGraph.Summary.Keys | Should -Contain 'Resource'
            $SchemaGraph.Summary.Keys | Should -Contain 'DataSource'
            $SchemaGraph.Summary.Keys | Should -Contain 'Attribute'
            $SchemaGraph.Summary.Keys | Should -Not -Contain 'Function'
        }

        It "returns the same Id sequence on every run" {
            $again = $SchemaDoc | ConvertTo-TerraformSchemaGraph -ErrorAction Stop
            $again.Nodes.Id | Should -Be $SchemaGraph.Nodes.Id
        }

        It "returns the same graph with -Provider 'terraform.io/builtin/terraform'" {
            $filtered = $SchemaDoc | ConvertTo-TerraformSchemaGraph -Provider 'terraform.io/builtin/terraform' -ErrorAction Stop
            $filtered.Nodes.Id | Should -Be $SchemaGraph.Nodes.Id
        }

        It "throws for a -Provider that is not in the document" {
            { $SchemaDoc | ConvertTo-TerraformSchemaGraph -Provider 'hashicorp/null' -ErrorAction Stop } |
                Should -Throw "Provider 'registry.terraform.io/hashicorp/null' is not in provider_schemas. Available: terraform.io/builtin/terraform."
        }

        It "adds Function nodes with -IncludeFunctions" {
            $graph = $SchemaDoc | ConvertTo-TerraformSchemaGraph -IncludeFunctions -ErrorAction Stop
            $functions = @($graph.Nodes | Where-Object Kind -eq 'Function')
            $functions.Id | Should -Contain 'terraform.io/builtin/terraform/function/encode_expr'
            $functions | ForEach-Object Depth | Select-Object -Unique | Should -Be 1
        }

        It "gives the same NodeCount for -OutputFormat Json text and for its PSCustomObject form" {
            $json = Get-TerraformProviderSchema -Path $SchemaDir -OutputFormat Json -ErrorAction Stop
            ($json | ConvertTo-TerraformSchemaGraph -ErrorAction Stop).NodeCount | Should -Be $SchemaGraph.NodeCount
            ($json | ConvertFrom-TerraformJson | ConvertTo-TerraformSchemaGraph -ErrorAction Stop).NodeCount | Should -Be $SchemaGraph.NodeCount
        }

        It "throws when the input has no provider_schemas" {
            { @{} | ConvertTo-TerraformSchemaGraph -ErrorAction Stop } | Should -Throw '*no top-level provider_schemas*'
        }

        It "sets the default display properties" {
            (Get-TypeData TerraformGraph.SchemaNode).DefaultDisplayPropertySet.ReferencedProperties |
                Should -Be @('Kind', 'Path', 'Type', 'Required', 'Depth')
            (Get-TypeData TerraformGraph.SchemaGraph).DefaultDisplayPropertySet.ReferencedProperties |
                Should -Be @('Providers', 'NodeCount', 'EdgeCount')
        }

        It "renders cty type JSON as Terraform type syntax" {
            InModuleScope TerraformGraph {
                $cases = [ordered]@{
                    '"string"'                                         = 'string'
                    '["list","string"]'                                = 'list(string)'
                    '["map",["list","string"]]'                        = 'map(list(string))'
                    '["set",["object",{"a":"string","b":"number"}]]'   = 'set(object({ a = string, b = number }))'
                    '["object",{"a":"string","b":"number"},["b"]]'     = 'object({ a = string, b = optional(number) })'
                    '["tuple",["string","number"]]'                    = 'tuple([string, number])'
                    '"dynamic"'                                        = 'any'
                }
                foreach ($json in $cases.Keys) {
                    $type = $json | ConvertFrom-TerraformJson -AsHashtable -NoEnumerate
                    ConvertTo-TerraformTypeString -Type $type | Should -Be $cases[$json] -Because $json
                }
            }
        }

        It "renders a nested_type as its implied type" {
            InModuleScope TerraformGraph {
                $nested = '{"nesting_mode":"list","attributes":{"x":{"type":"string","required":true},"y":{"type":["list","number"],"optional":true}}}' |
                    ConvertFrom-TerraformJson -AsHashtable
                $type = ConvertTo-TerraformNestedTypeJson -NestedType $nested
                ConvertTo-TerraformTypeString -Type $type | Should -Be 'list(object({ x = string, y = optional(list(number)) }))'
                [TerraformGraph.Json]::Serialize($type, 1024, $true) | Should -Be '["list",["object",{"x":"string","y":["list","number"]},["y"]]]'
            }
        }

        It "rejects an invalid -Provider" {
            { $SchemaDoc | ConvertTo-TerraformSchemaGraph -Provider 'not//valid' -ErrorAction Stop } |
                Should -Throw "*is not a provider address*"
        }

        Context "-Provider null (registry)" -Skip:(-not (Test-Connection registry.terraform.io -Count 1 -Quiet)) {

            It "renders null_resource.triggers as map(string)" {
                $graph = Get-TerraformProviderSchema -Provider null -Cleanup -ErrorAction Stop | ConvertTo-TerraformSchemaGraph -ErrorAction Stop
                $resource = $graph.Nodes | Where-Object { $_.Kind -eq 'Resource' -and $_.Path -eq 'null_resource' }
                $resource | Should -Not -BeNullOrEmpty
                $triggers = $graph.Nodes | Where-Object { $_.Kind -eq 'Attribute' -and $_.ParentId -eq $resource.Id -and $_.Name -eq 'triggers' }
                $triggers.Type | Should -Be 'map(string)'
            }
        }

        Context "-Provider tls (registry)" -Skip:(-not (Test-Connection registry.terraform.io -Count 1 -Quiet)) {

            BeforeAll {
                # random 3.6.3 and local 2.5.2 have empty provider config blocks; tls has a proxy block.
                $graph = Get-TerraformProviderSchema -Provider tls -Version '= 4.0.6' -Cleanup -ErrorAction Stop |
                    ConvertTo-TerraformSchemaGraph -ErrorAction Stop
                Set-Variable -Name TlsGraph -Value $graph -Scope Script
            }

            It "adds the proxy config Block under the Provider node" {
                $proxy = $TlsGraph.Nodes | Where-Object Id -eq 'registry.terraform.io/hashicorp/tls/config/proxy'
                $proxy.Kind | Should -Be 'Block'
                $proxy.Path | Should -Be 'tls.proxy'
                $proxy.ParentId | Should -Be 'registry.terraform.io/hashicorp/tls'
                $proxy.Depth | Should -Be 1
                $proxy.NestingMode | Should -Be 'list'
            }

            It "adds the proxy config Attributes one level deeper" {
                $parentId = 'registry.terraform.io/hashicorp/tls/config/proxy'
                $attributes = @($TlsGraph.Nodes | Where-Object { $_.Kind -eq 'Attribute' -and $_.ParentId -eq $parentId })
                $attributes.Name | Should -Be @('from_env', 'password', 'url', 'username')
                $url = $attributes | Where-Object Name -eq 'url'
                $url.Id | Should -Be 'registry.terraform.io/hashicorp/tls/config/proxy/url'
                $url.Path | Should -Be 'tls.proxy.url'
                $url.Depth | Should -Be 2
                $url.Type | Should -Be 'string'
                ($attributes | Where-Object Name -eq 'password').Sensitive | Should -BeTrue
            }

            It "emits the config subtree right after the Provider node, before resources" {
                $ids = @($TlsGraph.Nodes.Id)
                $ids[0] | Should -Be 'registry.terraform.io/hashicorp/tls'
                $ids[1..5] | Should -Be @(
                    'registry.terraform.io/hashicorp/tls/config/proxy'
                    'registry.terraform.io/hashicorp/tls/config/proxy/from_env'
                    'registry.terraform.io/hashicorp/tls/config/proxy/password'
                    'registry.terraform.io/hashicorp/tls/config/proxy/url'
                    'registry.terraform.io/hashicorp/tls/config/proxy/username'
                )
                $ids[6] | Should -BeLike 'registry.terraform.io/hashicorp/tls/resource/*'
            }
        }
    }

    Context "ConvertTo-TerraformVariableGraph" {

        BeforeAll {
            $graph = Get-TerraformModuleGraph -Path $Infra -Recurse -ErrorAction Stop | ConvertTo-TerraformVariableGraph -ErrorAction Stop
            Set-Variable -Name VarGraph -Value $graph -Scope Script

            # One root that trips each Unresolved reason once.
            $bad = Join-Path $TestDrive 'vargraph-unresolved'
            New-Item -ItemType Directory -Path (Join-Path $bad 'm') -Force | Out-Null
            Set-Content -Path (Join-Path $bad 'main.tf') -Value @'
module "m" {
  source = "./m"
  nope   = 1
}

output "x" {
  value = module.m.missing
}
'@
            Set-Content -Path (Join-Path $bad 'm\main.tf') -Value @'
locals {
  a = var.ghost
}
'@
            Set-Variable -Name UnresolvedGraph -Scope Script -Value (
                Get-TerraformModuleGraph -Path $bad -Recurse -ErrorAction Stop | ConvertTo-TerraformVariableGraph -ErrorAction Stop)

            $refs = Join-Path $TestDrive 'vargraph-refs.tf'
            Set-Content -Path $refs -Value @'
locals {
  indexed  = var.tags["k"]
  listed   = var.zones[0]
  called   = format("%s-%s", var.region, local.prefix)
  resource = aws_instance.web.id
  output   = module.net.ids[0]
}
'@
            Set-Variable -Name RefsTf -Value $refs -Scope Script
        }

        It "exports both variable graph functions from TerraformGraph" {
            (Get-Command ConvertTo-TerraformVariableGraph -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
            (Get-Command Get-TerraformVariableTrace -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
        }

        It "has one node per variable, local and output in root, network and endpoint" {
            # root 7 variables, 2 locals, 2 outputs; network 4 variables, 2 outputs; endpoint 2 variables, 1 output.
            $VarGraph.NodeCount | Should -Be 20
            $VarGraph.Summary['Variable'] | Should -Be 13
            $VarGraph.Summary['Local'] | Should -Be 2
            $VarGraph.Summary['Output'] | Should -Be 5
        }

        It "binds root var.aws_region to its default" {
            $node = $VarGraph.Nodes | Where-Object Id -eq 'root/var/aws_region'
            $node.Kind | Should -Be 'Variable'
            $node.Binding | Should -Be 'Default'
            $node.HasDefault | Should -BeTrue
            $node.Literal | Should -Be 'us-east-1'
            $node.Type | Should -Be 'string'
        }

        It "binds module.network var.aws_region to the root call argument" {
            $node = $VarGraph.Nodes | Where-Object Id -eq 'module.network/var/aws_region'
            $node.Binding | Should -Be 'Argument'
            $node.ArgumentExpr | Should -Not -BeNullOrEmpty
            $node.ArgumentExpr.Raw | Should -Be 'var.aws_region'
            $edge = @($VarGraph.Edges | Where-Object { $_.From -eq 'root/var/aws_region' -and $_.To -eq 'module.network/var/aws_region' })
            $edge.Count | Should -Be 1
            $edge[0].Kind | Should -Be 'Argument'
            $edge[0].Via | Should -Be 'var.aws_region'
        }

        It "binds module.network var.availability_zone, which the root does not pass, to its default" {
            $node = $VarGraph.Nodes | Where-Object Id -eq 'module.network/var/availability_zone'
            $node.Binding | Should -Be 'Default'
            $node.Literal | Should -Be 'us-east-1a'
        }

        It "keeps literal module call arguments on the endpoint variables" {
            ($VarGraph.Nodes | Where-Object Id -eq 'module.network.module.endpoint/var/host').ArgumentLiteral | Should -Be 'localhost'
            ($VarGraph.Nodes | Where-Object Id -eq 'module.network.module.endpoint/var/port').ArgumentLiteral | Should -Be 8080
        }

        It "adds an OutputReference edge for module.endpoint.address in network's endpoint output" {
            $edge = @($VarGraph.Edges | Where-Object Kind -eq 'OutputReference')
            $edge.Count | Should -Be 1
            $edge[0].From | Should -Be 'module.network.module.endpoint/output/address'
            $edge[0].To | Should -Be 'module.network/output/endpoint'
            $edge[0].Via | Should -Be 'module.endpoint.address'
        }

        It "makes no edge for root output network, which reads the whole module.network" {
            @($VarGraph.Edges | Where-Object To -eq 'root/output/network').Count | Should -Be 0
            ($VarGraph.Nodes | Where-Object Id -eq 'root/output/network').References.Traversal | Should -Be 'module.network'
        }

        It "adds a Reference edge for local.enabled reading var.enable_public_ip" {
            $edge = @($VarGraph.Edges | Where-Object To -eq 'root/local/enabled')
            $edge.Count | Should -Be 1
            $edge[0].From | Should -Be 'root/var/enable_public_ip'
            $edge[0].Kind | Should -Be 'Reference'
        }

        It "gives every edge a From and To that exist in Nodes" {
            $ids = @($VarGraph.Nodes.Id)
            foreach ($edge in $VarGraph.Edges) {
                $ids | Should -Contain $edge.From
                $ids | Should -Contain $edge.To
            }
            $VarGraph.EdgeCount | Should -Be 8
        }

        It "has no Unresolved or Skipped entries for infra" {
            $VarGraph.UnresolvedCount | Should -Be 0
            @($VarGraph.Skipped).Count | Should -Be 0
        }

        It "lists module.network in Skipped without -Recurse and has no module.network nodes" {
            $graph = Get-TerraformModuleGraph -Path $Infra -ErrorAction Stop | ConvertTo-TerraformVariableGraph -ErrorAction Stop
            @($graph.Skipped) | Should -Be @('module.network')
            @($graph.Nodes | Where-Object Module -ne 'root').Count | Should -Be 0
            @($graph.Edges | Where-Object Kind -eq 'Argument').Count | Should -Be 0
            $graph.UnresolvedCount | Should -Be 0
        }

        It "reports an argument the child does not declare as UndeclaredArgument" {
            $record = @($UnresolvedGraph.Unresolved | Where-Object Reason -eq 'UndeclaredArgument')
            $record.Count | Should -Be 1
            $record[0].Module | Should -Be 'module.m'
            $record[0].Root | Should -Be 'var.nope'
            $record[0].Line | Should -Be 3
        }

        It "reports module.m.missing as UndeclaredOutput" {
            $record = @($UnresolvedGraph.Unresolved | Where-Object Reason -eq 'UndeclaredOutput')
            $record.Count | Should -Be 1
            $record[0].Module | Should -Be 'root'
            $record[0].Root | Should -Be 'module.m.missing'
        }

        It "reports var.ghost in a child local as UndeclaredReference" {
            $record = @($UnresolvedGraph.Unresolved | Where-Object Reason -eq 'UndeclaredReference')
            $record.Count | Should -Be 1
            $record[0].Module | Should -Be 'module.m'
            $record[0].Root | Should -Be 'var.ghost'
            $UnresolvedGraph.EdgeCount | Should -Be 0
        }

        It "returns the same node and edge sequences on every run" {
            $again = Get-TerraformModuleGraph -Path $Infra -Recurse -ErrorAction Stop | ConvertTo-TerraformVariableGraph -ErrorAction Stop
            $again.Nodes.Id | Should -Be $VarGraph.Nodes.Id
            ($again.Edges | ForEach-Object { "$($_.From)>$($_.To)>$($_.Kind)>$($_.Via)" }) |
                Should -Be ($VarGraph.Edges | ForEach-Object { "$($_.From)>$($_.To)>$($_.Kind)>$($_.Via)" })
        }

        It "orders nodes by module, then Variable, Local, Output, each by name" {
            @($VarGraph.Nodes | Where-Object Module -eq 'root').Id | Should -Be @(
                'root/var/availability_zones', 'root/var/aws_region', 'root/var/enable_public_ip', 'root/var/endpoint'
                'root/var/instance_count', 'root/var/pair', 'root/var/tags'
                'root/local/enabled', 'root/local/name_prefix'
                'root/output/network', 'root/output/region'
            )
        }

        It "sets the default display properties" {
            (Get-TypeData TerraformGraph.VariableNode).DefaultDisplayPropertySet.ReferencedProperties |
                Should -Be @('Kind', 'Module', 'Name', 'Binding', 'Literal')
            (Get-TypeData TerraformGraph.VariableGraph).DefaultDisplayPropertySet.ReferencedProperties |
                Should -Be @('Root', 'NodeCount', 'EdgeCount', 'UnresolvedCount')
        }

        It "finds a plain var reference in an infra expression" {
            $expr = ((Get-TerraformAST -FilePath $MainTf | Where-Object Type -eq 'locals').Body.Attributes.enabled.Expr)
            InModuleScope TerraformGraph -Parameters @{ Expr = $expr } {
                $refs = @(Get-TerraformExpressionReferences -Expr $Expr)
                $refs.Count | Should -Be 1
                $refs[0].Traversal | Should -Be 'var.enable_public_ip'
                $refs[0].Root | Should -Be 'var.enable_public_ip'
            }
        }

        It "gives path.module in an infra template a null Root" {
            $expr = ((Get-TerraformAST -FilePath $MainTf | Where-Object Type -eq 'data').Body.Attributes.filename.Expr)
            InModuleScope TerraformGraph -Parameters @{ Expr = $expr } {
                $refs = @(Get-TerraformExpressionReferences -Expr $Expr)
                $refs.Traversal | Should -Be 'path.module'
                $refs[0].Root | Should -BeNullOrEmpty
            }
        }

        It "strips index suffixes, finds both refs in a function call, and leaves a resource Root null" {
            $attributes = (Get-TerraformAST -FilePath $RefsTf).Body.Attributes
            InModuleScope TerraformGraph -Parameters @{ A = $attributes } {
                $indexed = @(Get-TerraformExpressionReferences -Expr $A.indexed.Expr)
                $indexed[0].Traversal | Should -Be 'var.tags["k"]'
                $indexed[0].Root | Should -Be 'var.tags'

                (@(Get-TerraformExpressionReferences -Expr $A.listed.Expr))[0].Root | Should -Be 'var.zones'

                $called = @(Get-TerraformExpressionReferences -Expr $A.called.Expr)
                $called.Traversal | Should -Be @('var.region', 'local.prefix')
                $called.Root | Should -Be @('var.region', 'local.prefix')

                $resource = @(Get-TerraformExpressionReferences -Expr $A.resource.Expr)
                $resource[0].Traversal | Should -Be 'aws_instance.web.id'
                $resource[0].Root | Should -BeNullOrEmpty

                (@(Get-TerraformExpressionReferences -Expr $A.output.Expr))[0].Root | Should -Be 'module.net.ids'
            }
        }
    }

    Context "Get-TerraformVariableTrace" {

        BeforeAll {
            $graph = Get-TerraformModuleGraph -Path $Infra -Recurse -ErrorAction Stop | ConvertTo-TerraformVariableGraph -ErrorAction Stop
            Set-Variable -Name TraceGraph -Value $graph -Scope Script

            $cycle = Join-Path $TestDrive 'vartrace-cycle'
            New-Item -ItemType Directory -Path $cycle -Force | Out-Null
            Set-Content -Path (Join-Path $cycle 'main.tf') -Value @'
locals {
  a = local.b
  b = local.a
}
'@
            Set-Variable -Name CycleDir -Value $cycle -Scope Script
        }

        It "traces module.network var.aws_region upstream to the root variable at Distance 1" {
            $trace = $TraceGraph | Get-TerraformVariableTrace -Id 'module.network/var/aws_region' -Direction Upstream -ErrorAction Stop
            $trace.Start.Id | Should -Be 'module.network/var/aws_region'
            $trace.Nodes.Id | Should -Be @('module.network/var/aws_region', 'root/var/aws_region')
            ($trace.Nodes | Where-Object Id -eq 'root/var/aws_region').Distance | Should -Be 1
            $trace.Edges.Kind | Should -Be 'Argument'
        }

        It "traces root var.aws_region downstream to the root output and the network variable, and no further" {
            $trace = $TraceGraph | Get-TerraformVariableTrace -Id 'root/var/aws_region' -Direction Downstream -ErrorAction Stop
            $trace.Nodes.Id | Should -Be @('root/var/aws_region', 'root/output/region', 'module.network/var/aws_region')
            ($trace.Nodes | Where-Object Id -eq 'module.network/var/aws_region').Distance | Should -Be 1
        }

        It "has negative and positive distances with Both from the endpoint address output" {
            $trace = $TraceGraph | Get-TerraformVariableTrace -Id 'module.network.module.endpoint/output/address' -ErrorAction Stop
            $trace.Direction | Should -Be 'Both'
            ($trace.Nodes | ForEach-Object { "$($_.Distance) $($_.Id)" }) | Should -Be @(
                '0 module.network.module.endpoint/output/address'
                '-1 module.network.module.endpoint/var/host'
                '-1 module.network.module.endpoint/var/port'
                '1 module.network/output/endpoint'
            )
            $trace.Edges.Count | Should -Be 3
        }

        It "throws for an unknown Id and names the same-named nodes" {
            { $TraceGraph | Get-TerraformVariableTrace -Id 'module.network.module.endpoint/var/aws_region' -ErrorAction Stop } |
                Should -Throw "Node 'module.network.module.endpoint/var/aws_region' is not in the variable graph. Nodes named 'aws_region': root/var/aws_region, module.network/var/aws_region."
        }

        It "terminates on locals that reference each other and returns both" {
            $graph = Get-TerraformModuleGraph -Path $CycleDir -ErrorAction Stop | ConvertTo-TerraformVariableGraph -ErrorAction Stop
            $graph.EdgeCount | Should -Be 2
            $trace = $graph | Get-TerraformVariableTrace -Id 'root/local/a' -ErrorAction Stop
            @($trace.Nodes.Id | Sort-Object) | Should -Be @('root/local/a', 'root/local/b')
            $trace.Edges.Count | Should -Be 2
        }

        It "stops at -MaxDepth" {
            $id = 'module.network/output/endpoint'
            @(($TraceGraph | Get-TerraformVariableTrace -Id $id -Direction Upstream -ErrorAction Stop).Nodes).Count | Should -Be 4
            $limited = $TraceGraph | Get-TerraformVariableTrace -Id $id -Direction Upstream -MaxDepth 1 -ErrorAction Stop
            $limited.Nodes.Id | Should -Be @('module.network/output/endpoint', 'module.network.module.endpoint/output/address')
        }

        It "sets the default display properties of trace nodes" {
            (Get-TypeData TerraformGraph.VariableTraceNode).DefaultDisplayPropertySet.ReferencedProperties |
                Should -Be @('Distance', 'Kind', 'Module', 'Name', 'Binding', 'Literal')
        }
    }

    Context "ConvertTo-TerraformResourceGraph" {

        BeforeAll {
            # The built-in provider: terraform init downloads nothing.
            $dir = Join-Path $TestDrive 'resgraph-builtin'
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir 'main.tf') -Value 'resource "terraform_data" "x" {}'
            $null = terraform "-chdir=$dir" init -input=false -no-color
            $builtin = Get-TerraformProviderSchema -Path $dir -ErrorAction Stop | ConvertTo-TerraformSchemaGraph -ErrorAction Stop
            Set-Variable -Name BuiltinGraph -Value $builtin -Scope Script

            $moduleGraph = Get-TerraformModuleGraph -Path $Infra -Recurse -ErrorAction Stop
            Set-Variable -Name InfraModuleGraph -Value $moduleGraph -Scope Script
            Set-Variable -Name ResGraph -Scope Script -Value (
                $moduleGraph | ConvertTo-TerraformResourceGraph -SchemaGraph $builtin -ErrorAction Stop)

            # One single-file root per case, joined with the builtin schema graph.
            $cases = [ordered]@{
                acme     = "terraform {`n  required_providers {`n    foo = {`n      source = `"acme/foo`"`n    }`n  }`n}`n`nresource `"foo_thing`" `"x`" {}"
                bogus    = "resource `"terraform_data`" `"x`" {`n  bogus = 1`n}"
                count    = "resource `"terraform_data`" `"x`" {`n  count = 2`n}"
                alias    = "resource `"terraform_data`" `"x`" {`n  provider = terraform.alt`n}"
                block    = "resource `"terraform_data`" `"x`" {`n  nope {}`n}"
                nope     = "resource `"terraform_nope`" `"x`" {}"
            }
            $single = @{}
            foreach ($name in $cases.Keys) {
                $root = Join-Path $TestDrive "resgraph-$name"
                New-Item -ItemType Directory -Path $root | Out-Null
                Set-Content -Path (Join-Path $root 'main.tf') -Value $cases[$name]
                $graph = Get-TerraformModuleGraph -Path $root -ErrorAction Stop |
                    ConvertTo-TerraformResourceGraph -SchemaGraph $builtin -ErrorAction Stop
                $single[$name] = $graph.Nodes[0]
            }
            Set-Variable -Name SingleNode -Value $single -Scope Script
        }

        It "is exported from TerraformGraph" {
            (Get-Command ConvertTo-TerraformResourceGraph -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
        }

        It "has one node per resource and data block in infra, in module then source order" {
            # main.tf: null_resource.marker, terraform_data.placeholder, data.local_file.readme;
            # modules/network: null_resource.subnet; modules/network/modules/endpoint: terraform_data.listener.
            $ResGraph.NodeCount | Should -Be 5
            $ResGraph.Nodes.ResourceAddress | Should -Be @(
                'null_resource.marker'
                'terraform_data.placeholder'
                'data.local_file.readme'
                'module.network.null_resource.subnet'
                'module.network.module.endpoint.terraform_data.listener'
            )
            $ResGraph.Nodes.Id | Should -Be @(
                'root/resource/null_resource.marker'
                'root/resource/terraform_data.placeholder'
                'root/data/local_file.readme'
                'module.network/resource/null_resource.subnet'
                'module.network.module.endpoint/resource/terraform_data.listener'
            )
        }

        It "matches terraform_data.placeholder to the builtin schema" {
            $node = $ResGraph.Nodes | Where-Object ResourceAddress -eq 'terraform_data.placeholder'
            $node.ProviderAddress | Should -Be 'terraform.io/builtin/terraform'
            $node.SchemaMatched | Should -BeTrue
            $node.Reason | Should -BeNullOrEmpty
            @($node.UnknownAttributes).Count | Should -Be 0
            $edges = @($ResGraph.Edges | Where-Object From -eq $node.Id)
            $edges.Count | Should -Be 1
            $edges[0].To | Should -Be 'terraform.io/builtin/terraform/resource/terraform_data'
            $edges[0].Kind | Should -Be 'InstanceOf'
        }

        It "reports null_resource.marker as ProviderNotInSchemaGraph with only the builtin graph" {
            $node = $ResGraph.Nodes | Where-Object ResourceAddress -eq 'null_resource.marker'
            $node.ProviderAddress | Should -BeLike '*hashicorp/null'
            $node.SchemaMatched | Should -BeFalse
            $node.Reason | Should -Be 'ProviderNotInSchemaGraph'
            $node.SchemaId | Should -Be 'registry.terraform.io/hashicorp/null/resource/null_resource'
        }

        It "builds data.local_file.readme as a DataSource" {
            $node = $ResGraph.Nodes | Where-Object Type -eq 'local_file'
            $node.Kind | Should -Be 'DataSource'
            $node.Id | Should -Be 'root/data/local_file.readme'
            $node.ResourceAddress | Should -Be 'data.local_file.readme'
            $node.SchemaId | Should -Be 'registry.terraform.io/hashicorp/local/data/local_file'
        }

        It "marks every node NoSchemaGraph without -SchemaGraph" {
            $graph = $InfraModuleGraph | ConvertTo-TerraformResourceGraph -ErrorAction Stop
            $graph.NodeCount | Should -Be $ResGraph.NodeCount
            @($graph.Nodes | Where-Object Reason -ne 'NoSchemaGraph').Count | Should -Be 0
            @($graph.Edges).Count | Should -Be 0
            $graph.MatchedCount | Should -Be 0
        }

        It "counts nodes per provider address" {
            $ResGraph.Providers['terraform.io/builtin/terraform'] | Should -Be 2
            $ResGraph.Providers['registry.terraform.io/hashicorp/null'] | Should -Be 2
            $ResGraph.Providers['registry.terraform.io/hashicorp/local'] | Should -Be 1
            $ResGraph.Providers.Count | Should -Be 3
        }

        It "resolves a required_providers source in the same module" {
            $node = $SingleNode['acme']
            $node.ProviderAddress | Should -Be 'registry.terraform.io/acme/foo'
            $node.Reason | Should -Be 'ProviderNotInSchemaGraph'
        }

        It "lists an attribute the schema does not declare in UnknownAttributes" {
            $node = $SingleNode['bogus']
            $node.SchemaMatched | Should -BeTrue
            $node.UnknownAttributes | Should -Contain 'bogus'
        }

        It "does not report the count meta-argument" {
            @($SingleNode['count'].UnknownAttributes).Count | Should -Be 0
        }

        It "reads the provider local name and alias from a provider argument" {
            $node = $SingleNode['alias']
            $node.ProviderAlias | Should -Be 'alt'
            $node.ProviderLocalName | Should -Be 'terraform'
            @($node.UnknownAttributes).Count | Should -Be 0
        }

        It "lists a block the schema does not declare in UnknownBlocks" {
            $SingleNode['block'].UnknownBlocks | Should -Contain 'nope'
        }

        It "reports a type the provider does not have as TypeNotInProvider" {
            $node = $SingleNode['nope']
            $node.Reason | Should -Be 'TypeNotInProvider'
            $node.SchemaId | Should -Be 'terraform.io/builtin/terraform/resource/terraform_nope'
        }

        It "lists module.network in Skipped without -Recurse and has no module.network nodes" {
            $graph = Get-TerraformModuleGraph -Path $Infra -ErrorAction Stop | ConvertTo-TerraformResourceGraph -SchemaGraph $BuiltinGraph -ErrorAction Stop
            @($graph.Skipped) | Should -Be @('module.network')
            @($graph.Nodes | Where-Object Module -ne 'root').Count | Should -Be 0
        }

        It "gives the same Ids and edges on every run" {
            $again = $InfraModuleGraph | ConvertTo-TerraformResourceGraph -SchemaGraph $BuiltinGraph -ErrorAction Stop
            $again.Nodes.Id | Should -Be $ResGraph.Nodes.Id
            @($again.Edges | ForEach-Object { "$($_.From)>$($_.To)" }) | Should -Be @($ResGraph.Edges | ForEach-Object { "$($_.From)>$($_.To)" })
        }

        It "sets the default display properties" {
            (Get-TypeData TerraformGraph.ResourceNode).DefaultDisplayPropertySet.ReferencedProperties |
                Should -Be @('Kind', 'ResourceAddress', 'ProviderAddress', 'SchemaMatched', 'Reason')
            (Get-TypeData TerraformGraph.ResourceGraph).DefaultDisplayPropertySet.ReferencedProperties |
                Should -Be @('Root', 'NodeCount', 'MatchedCount', 'UnmatchedCount', 'Findings')
        }

        Context "null and local schemas (registry)" -Skip:(-not (Test-Connection registry.terraform.io -Count 1 -Quiet)) {

            BeforeAll {
                $schemas = @(
                    $BuiltinGraph
                    Get-TerraformProviderSchema -Provider null -Version '= 3.2.3' -Cleanup -ErrorAction Stop | ConvertTo-TerraformSchemaGraph -ErrorAction Stop
                    Get-TerraformProviderSchema -Provider local -Version '= 2.5.2' -Cleanup -ErrorAction Stop | ConvertTo-TerraformSchemaGraph -ErrorAction Stop
                )
                Set-Variable -Name AllSchemas -Value $schemas -Scope Script
                Set-Variable -Name FullGraph -Scope Script -Value (
                    $InfraModuleGraph | ConvertTo-TerraformResourceGraph -SchemaGraph $schemas -ErrorAction Stop)
            }

            It "matches every infra node with no findings" {
                @($FullGraph.Nodes | Where-Object { -not $_.SchemaMatched }).Count | Should -Be 0
                $FullGraph.UnmatchedCount | Should -Be 0
                $FullGraph.EdgeCount | Should -Be 5
                $FullGraph.Findings | Should -Be 0
            }

            It "lists filename in MissingRequired for an empty local_file" {
                # local 2.5.2: filename is the only required local_file attribute.
                $root = Join-Path $TestDrive 'resgraph-local-file'
                New-Item -ItemType Directory -Path $root | Out-Null
                Set-Content -Path (Join-Path $root 'main.tf') -Value 'resource "local_file" "x" {}'
                $graph = Get-TerraformModuleGraph -Path $root -ErrorAction Stop | ConvertTo-TerraformResourceGraph -SchemaGraph $AllSchemas -ErrorAction Stop
                $graph.Nodes[0].SchemaMatched | Should -BeTrue
                $graph.Nodes[0].MissingRequired | Should -Be @('filename')
                $graph.Findings | Should -Be 1
            }
        }
    }
}

# Only Claude is exercised: Claude Code is what the author uses. The other tools'
# paths go through the same copy mechanism but are untested.
Describe "Skills" {

    BeforeAll {
        $moduleBase = (Get-Module TerraformGraph).ModuleBase
        Set-Variable -Name Psd1 -Scope Script -Value (Join-Path $moduleBase 'TerraformGraph.psd1')
        Set-Variable -Name BundledSkill -Scope Script -Value (Join-Path $moduleBase 'skills' 'terraformgraph' 'SKILL.md')
        Set-Variable -Name Marker -Scope Script -Value '<!-- terraformgraph-skill -->'

        # Imports the module in a new pwsh process from $Dir and returns what it printed.
        $importOutput = {
            param([string]$Dir, [string]$Hint)
            $setHint = if ($Hint) { "`$env:TERRAFORMGRAPH_SKILL_HINT = '$Hint'" } else { 'Remove-Item Env:TERRAFORMGRAPH_SKILL_HINT -ErrorAction SilentlyContinue' }
            pwsh -NoProfile -Command "$setHint; Set-Location -LiteralPath '$Dir'; Import-Module '$Psd1'" 2>&1 | Out-String
        }
        Set-Variable -Name ImportOutput -Scope Script -Value $importOutput
    }

    BeforeEach {
        # A fake repo that uses Claude, fresh for every test.
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $repo '.claude') -Force | Out-Null
        Set-Variable -Name Repo -Scope Script -Value $repo
        Set-Variable -Name InstalledSkill -Scope Script -Value (Join-Path $repo '.claude' 'skills' 'terraformgraph' 'SKILL.md')
    }

    It "exports Install-TerraformGraphSkill and Test-TerraformGraphSkill from TerraformGraph" {
        (Get-Command Install-TerraformGraphSkill -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
        (Get-Command Test-TerraformGraphSkill -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
    }

    It "installs SKILL.md for Claude identical to the bundled file" {
        $result = Install-TerraformGraphSkill -Path $Repo -Tool Claude -PassThru -ErrorAction Stop
        $result.Tool | Should -Be 'Claude'
        $result.Status | Should -Be 'Installed'
        $result.Files | Should -Be 1
        (Get-FileHash -LiteralPath $InstalledSkill).Hash | Should -Be (Get-FileHash -LiteralPath $BundledSkill).Hash
    }

    It "reports Claude Detected, Installed and not Stale after install" {
        Install-TerraformGraphSkill -Path $Repo -Tool Claude -ErrorAction Stop
        $status = Test-TerraformGraphSkill -Path $Repo -Tool Claude -ErrorAction Stop
        $status.Detected | Should -BeTrue
        $status.Installed | Should -BeTrue
        $status.Stale | Should -BeFalse
    }

    It "returns Unchanged on a second install without -Force" {
        Install-TerraformGraphSkill -Path $Repo -Tool Claude -ErrorAction Stop
        $result = Install-TerraformGraphSkill -Path $Repo -Tool Claude -PassThru -ErrorAction Stop -ErrorVariable errors
        $result.Status | Should -Be 'Unchanged'
        $result.Files | Should -Be 0
        $errors.Count | Should -Be 0
    }

    It "reports an edited copy as Stale, skips it without -Force and restores it with -Force" {
        Install-TerraformGraphSkill -Path $Repo -Tool Claude -ErrorAction Stop
        Add-Content -LiteralPath $InstalledSkill -Value 'local edit'
        (Test-TerraformGraphSkill -Path $Repo -Tool Claude).Stale | Should -BeTrue

        (Install-TerraformGraphSkill -Path $Repo -Tool Claude -PassThru -ErrorAction Stop).Status | Should -Be 'Skipped'
        (Test-TerraformGraphSkill -Path $Repo -Tool Claude).Stale | Should -BeTrue

        (Install-TerraformGraphSkill -Path $Repo -Tool Claude -Force -PassThru -ErrorAction Stop).Status | Should -Be 'Updated'
        (Test-TerraformGraphSkill -Path $Repo -Tool Claude).Stale | Should -BeFalse
        (Get-FileHash -LiteralPath $InstalledSkill).Hash | Should -Be (Get-FileHash -LiteralPath $BundledSkill).Hash
    }

    It "creates AGENTS.md with the marker and never appends it twice" {
        Install-TerraformGraphSkill -Path $Repo -Tool Claude -ErrorAction Stop
        Install-TerraformGraphSkill -Path $Repo -Tool Claude -Force -ErrorAction Stop
        $agents = Join-Path $Repo 'AGENTS.md'
        @(Get-Content -LiteralPath $agents | Where-Object { $_ -eq $Marker }).Count | Should -Be 1
        Get-Content -LiteralPath $agents -Raw | Should -BeLike '*.claude/skills/terraformgraph/SKILL.md*'
    }

    It "appends to an existing AGENTS.md without changing its content" {
        $agents = Join-Path $Repo 'AGENTS.md'
        Set-Content -LiteralPath $agents -Value "# Rules`n`nKeep this line." -NoNewline
        Install-TerraformGraphSkill -Path $Repo -Tool Claude -ErrorAction Stop
        Install-TerraformGraphSkill -Path $Repo -Tool Claude -ErrorAction Stop
        $text = Get-Content -LiteralPath $agents -Raw
        $text | Should -BeLike "# Rules`n`nKeep this line.*"
        @(Get-Content -LiteralPath $agents | Where-Object { $_ -eq $Marker }).Count | Should -Be 1
    }

    It "reports Detected false for every tool in a directory with no markers" {
        $bare = Join-Path $TestDrive 'skills-bare'
        New-Item -ItemType Directory -Path $bare -Force | Out-Null
        $status = @(Test-TerraformGraphSkill -Path $bare -ErrorAction Stop)
        $status.Tool | Should -Be @('Claude', 'Codex', 'Cursor', 'Gemini', 'Copilot')
        @($status | Where-Object Detected).Count | Should -Be 0
        @($status | Where-Object Installed).Count | Should -Be 0
    }

    It "prints the install hint on import where .claude exists without the skill" {
        & $ImportOutput $Repo | Should -BeLike '*Install-TerraformGraphSkill -Tool Claude*'
    }

    It "prints nothing on import when TERRAFORMGRAPH_SKILL_HINT is 0" {
        (& $ImportOutput $Repo '0').Trim() | Should -BeNullOrEmpty
    }

    It "prints nothing on import once the skill is installed" {
        Install-TerraformGraphSkill -Path $Repo -Tool Claude -ErrorAction Stop
        (& $ImportOutput $Repo).Trim() | Should -BeNullOrEmpty
    }
}

# The cache loader reads two module-scoped paths. Every test points them at the fixture or
# at TestDrive, so the real LOCALAPPDATA cache and the bundled file are never read or written.
Describe "Registry" {

    BeforeAll {
        $fixture = Join-Path $PSScriptRoot 'fixtures' 'registry.sample.json'
        Set-Variable -Name Fixture -Scope Script -Value $fixture

        # Point the loader at a bundled and a user path, and forget the parsed cache.
        $usePaths = {
            param([string]$Bundled, [string]$User)
            InModuleScope TerraformGraph -Parameters @{ Bundled = $Bundled; User = $User } {
                param($Bundled, $User)
                $script:TerraformRegistryBundledPath = $Bundled
                $script:TerraformRegistryUserCachePath = $User
                $script:TerraformRegistryCacheMemo = $null
            }
        }
        Set-Variable -Name UsePaths -Scope Script -Value $usePaths

        $saved = InModuleScope TerraformGraph { @{ Bundled = $script:TerraformRegistryBundledPath; User = $script:TerraformRegistryUserCachePath } }
        Set-Variable -Name SavedPaths -Scope Script -Value $saved

        Set-Variable -Name MissingUser -Scope Script -Value (Join-Path $TestDrive 'no-user' 'registry.json')
    }

    AfterAll {
        & $UsePaths $SavedPaths.Bundled $SavedPaths.User
    }

    BeforeEach {
        # Default for each test: the fixture as the bundled file, no user cache.
        & $UsePaths $Fixture $MissingUser
    }

    It "exports Update-TerraformRegistryCache and Get-TerraformRegistryProvider from TerraformGraph" {
        (Get-Command Update-TerraformRegistryCache -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
        (Get-Command Get-TerraformRegistryProvider -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
    }

    It "reads the bundled file when there is no user cache" {
        $all = @(Get-TerraformRegistryProvider -ErrorAction Stop)
        $all.Count | Should -Be 6
        $all[0].ProviderAddress | Should -Be 'registry.terraform.io/acme/null'
    }

    It "prefers the user cache over the bundled file" {
        $user = Join-Path $TestDrive 'user-cache' 'registry.json'
        New-Item -ItemType Directory -Path (Split-Path $user -Parent) -Force | Out-Null
        $document = Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-TerraformJson
        $document.providers = @($document.providers | Where-Object name -eq 'widget')
        $document | ConvertTo-TerraformJson | Set-Content -LiteralPath $user
        & $UsePaths $Fixture $user

        @(Get-TerraformRegistryProvider).ProviderAddress | Should -Be @('registry.terraform.io/acme/widget')
        @(Get-TerraformRegistryProvider -NoBundledData).ProviderAddress | Should -Be @('registry.terraform.io/acme/widget')
    }

    It "warns and returns nothing with -NoBundledData and no user cache" {
        $result = @(Get-TerraformRegistryProvider -NoBundledData -WarningVariable warnings -WarningAction SilentlyContinue)
        $result.Count | Should -Be 0
        @($warnings).Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike '*Update-TerraformRegistryCache*'
    }

    It "matches a wildcard against the bare name in every namespace" {
        @(Get-TerraformRegistryProvider 'aws*').Source | Should -Be @('aws-ia/awsx', 'hashicorp/aws', 'hashicorp/awscc')
    }

    It "matches a bare name in any namespace" {
        @(Get-TerraformRegistryProvider null).Source | Should -Be @('acme/null', 'hashicorp/null')
    }

    It "matches namespace/name and the full address" {
        @(Get-TerraformRegistryProvider 'hashicorp/aws').Source | Should -Be @('hashicorp/aws')
        @(Get-TerraformRegistryProvider 'hashicorp/*').Count | Should -Be 3
        @(Get-TerraformRegistryProvider 'registry.terraform.io/acme/widget').Source | Should -Be @('acme/widget')
    }

    It "filters by -Tier" {
        @(Get-TerraformRegistryProvider -Tier partner).Source | Should -Be @('aws-ia/awsx')
        @(Get-TerraformRegistryProvider -Tier community).Count | Should -Be 2
        @(Get-TerraformRegistryProvider 'aws*' -Tier official).Source | Should -Be @('hashicorp/aws', 'hashicorp/awscc')
    }

    It "computes VersionCount and sets the default display properties" {
        (Get-TerraformRegistryProvider hashicorp/aws).VersionCount | Should -Be 3
        (Get-TypeData TerraformGraph.RegistryProvider).DefaultDisplayPropertySet.ReferencedProperties |
            Should -Be @('ProviderAddress', 'Tier', 'Latest', 'VersionCount')
    }

    It "writes versions newest first and a Latest that skips pre-releases" {
        # The harvest is mocked: this checks sorting, Latest and the file written, offline.
        Mock -ModuleName TerraformGraph Get-TerraformRegistryHarvest {
            [pscustomobject]@{
                Provider = [pscustomobject]@{ Namespace = 'hashicorp'; Name = 'aws'; Tier = 'official'; Description = 'd' }
                Versions = @(
                    [pscustomobject]@{ Version = '5.59.0'; Protocols = [string[]]@('5.0'); Published = '2026-03-15T00:00:00Z' }
                    [pscustomobject]@{ Version = '6.0.0-beta1'; Protocols = [string[]]@('5.0'); Published = '2026-05-01T00:00:00Z' }
                    [pscustomobject]@{ Version = '5.60.0'; Protocols = [string[]]@('5.0'); Published = '2026-04-01T00:00:00Z' }
                )
                Error = $null
            }
        }
        $path = Join-Path $TestDrive 'harvest' 'registry.json'
        $result = Update-TerraformRegistryCache -Path $path -PassThru -ErrorAction Stop
        $result.ProviderCount | Should -Be 1
        $result.VersionCount | Should -Be 3
        $result.Scope | Should -Be 'official,partner'

        & $UsePaths $Fixture $path
        $aws = Get-TerraformRegistryProvider hashicorp/aws
        $aws.ProviderAddress | Should -Be 'registry.terraform.io/hashicorp/aws'
        $aws.Latest | Should -Be '5.60.0'
        @($aws.Versions.version) | Should -Be @('6.0.0-beta1', '5.60.0', '5.59.0')
        @(Get-ChildItem -LiteralPath (Split-Path $path -Parent) -Force).Name | Should -Be @('registry.json')
    }

    It "resolves a wildcard to exactly one provider" {
        $provider = InModuleScope TerraformGraph { Resolve-TerraformRegistryProvider -Name 'hashicorp/awsc*' }
        $provider.ProviderAddress | Should -Be 'registry.terraform.io/hashicorp/awscc'
    }

    It "throws for an ambiguous pattern and lists every match, official first" {
        { InModuleScope TerraformGraph { Resolve-TerraformRegistryProvider -Name 'aws*' } } |
            Should -Throw "'aws*' matches 3 providers: hashicorp/aws, hashicorp/awscc, aws-ia/awsx. Specify one."
    }

    It "throws for a pattern with no match and names the harvest date" {
        { InModuleScope TerraformGraph { Resolve-TerraformRegistryProvider -Name 'foo' } } |
            Should -Throw "'foo' matches no provider in the registry cache (harvested 2026-10-01). Run Update-TerraformRegistryCache or pass a full address."
    }

    It "stops Get-TerraformProviderSchema -Provider 'aws*' with the ambiguous message before running terraform" {
        Mock -ModuleName TerraformGraph Invoke-TerraformCli { throw 'terraform must not run' }
        { Get-TerraformProviderSchema -Provider 'aws*' -WorkingDirectory (Join-Path $TestDrive 'never') -ErrorAction Stop } |
            Should -Throw "'aws*' matches 3 providers: hashicorp/aws, hashicorp/awscc, aws-ia/awsx. Specify one."
        Should -Invoke -ModuleName TerraformGraph Invoke-TerraformCli -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $TestDrive 'never') | Should -BeFalse
    }

    It "completes -Provider with cached addresses, official first" {
        $line = 'Get-TerraformProviderSchema -Provider aws'
        (TabExpansion2 $line $line.Length).CompletionMatches.CompletionText |
            Should -Be @('hashicorp/aws', 'hashicorp/awscc', 'aws-ia/awsx')
    }

    It "completes -Version newest first for the provider already given" {
        $line = 'Get-TerraformProviderSchema -Provider hashicorp/aws -Version '
        (TabExpansion2 $line $line.Length).CompletionMatches.CompletionText |
            Should -Be @('6.0.0-beta1', '5.60.0', '5.59.0')
    }

    It "completes Get-TerraformRegistryProvider -Name" {
        $line = 'Get-TerraformRegistryProvider -Name wid'
        (TabExpansion2 $line $line.Length).CompletionMatches.CompletionText | Should -Be @('acme/widget')
    }

    It "returns no completions when there is no cache" {
        & $UsePaths (Join-Path $TestDrive 'no-bundled.json') $MissingUser
        $results = InModuleScope TerraformGraph {
            @(& $script:TerraformRegistryProviderCompleter 'Get-TerraformProviderSchema' 'Provider' 'aws' $null @{})
            @(& $script:TerraformRegistryVersionCompleter 'Get-TerraformProviderSchema' 'Version' '' $null @{ Provider = 'hashicorp/aws' })
        }
        @($results).Count | Should -Be 0
    }

    Context "live harvest (registry)" -Skip:(-not (Test-Connection registry.terraform.io -Count 1 -Quiet)) {

        It "harvests official and partner providers to a TestDrive path" {
            $path = Join-Path $TestDrive 'live' 'registry.json'
            $result = Update-TerraformRegistryCache -Scope OfficialPartner -Path $path -PassThru -ErrorAction Stop
            $result.ProviderCount | Should -BeGreaterThan 50
            Test-Path -LiteralPath $path | Should -BeTrue
        }
    }
}

# The schema cache root is a module-scoped path. Every test points it at TestDrive, so the
# real LOCALAPPDATA cache is never read or written. Packs are built in TestDrive from the
# null 3.2.3 and local 2.5.2 schemas in tests/fixtures/schemas and the built-in provider's
# schema (terraform init downloads nothing for it).
Describe "Schema cache and packs" {

    BeforeAll {
        $useRoot = {
            param([string]$Root)
            InModuleScope TerraformGraph -Parameters @{ Root = $Root } {
                param($Root)
                $script:TerraformSchemaCacheRoot = $Root
            }
        }
        Set-Variable -Name UseRoot -Scope Script -Value $useRoot
        Set-Variable -Name SavedRoot -Scope Script -Value (InModuleScope TerraformGraph { $script:TerraformSchemaCacheRoot })
        Set-Variable -Name Infra -Scope Script -Value (Join-Path (Split-Path $PSScriptRoot -Parent) 'infra')

        $fixtures = Join-Path $PSScriptRoot 'fixtures' 'schemas'
        $documents = [ordered]@{
            'registry.terraform.io/hashicorp/null'  = @{ Version = '3.2.3'; Document = Get-Content -LiteralPath (Join-Path $fixtures 'null-3.2.3.json') -Raw | ConvertFrom-TerraformJson -AsHashtable }
            'registry.terraform.io/hashicorp/local' = @{ Version = '2.5.2'; Document = Get-Content -LiteralPath (Join-Path $fixtures 'local-2.5.2.json') -Raw | ConvertFrom-TerraformJson -AsHashtable }
        }
        $builtinDir = Join-Path $TestDrive 'packs-builtin'
        New-Item -ItemType Directory -Path $builtinDir | Out-Null
        Set-Content -Path (Join-Path $builtinDir 'main.tf') -Value 'resource "terraform_data" "x" {}'
        $null = terraform "-chdir=$builtinDir" init -input=false -no-color
        $terraformVersion = (terraform version -json | ConvertFrom-TerraformJson).terraform_version
        $documents['terraform.io/builtin/terraform'] = @{ Version = $terraformVersion; Document = Get-TerraformProviderSchema -Path $builtinDir -ErrorAction Stop }
        Set-Variable -Name Documents -Scope Script -Value $documents

        # A pack directory: each schema written through the cache writer into a staging root,
        # copied out under its pack name, and listed in manifest.json with its real sha256.
        $packDir = Join-Path $TestDrive 'packs'
        New-Item -ItemType Directory -Path $packDir | Out-Null
        & $useRoot (Join-Path $TestDrive 'pack-staging')
        $entries = foreach ($address in $documents.Keys) {
            $item = $documents[$address]
            $cached = InModuleScope TerraformGraph -Parameters @{ A = $address; V = $item.Version; D = $item.Document } {
                param($A, $V, $D)
                Write-TerraformSchemaCache -Provider $A -Version $V -Document $D
            }
            $file = "$($address.Replace('/', '-')).$($item.Version).json.gz"
            Copy-Item -LiteralPath $cached -Destination (Join-Path $packDir $file)
            [ordered]@{
                address = $address
                version = $item.Version
                file    = $file
                sha256  = (Get-FileHash -LiteralPath (Join-Path $packDir $file) -Algorithm SHA256).Hash.ToLowerInvariant()
                bytes   = (Get-Item -LiteralPath (Join-Path $packDir $file)).Length
            }
        }
        [ordered]@{ builtOn = '2026-10-06T00:00:00Z'; packs = [object[]]@($entries) } |
            ConvertTo-TerraformJson | Set-Content -LiteralPath (Join-Path $packDir 'manifest.json')
        Set-Variable -Name PackDir -Scope Script -Value $packDir
        Set-Variable -Name PackEntries -Scope Script -Value @($entries)
    }

    AfterAll {
        & $UseRoot $SavedRoot
    }

    BeforeEach {
        # A new, empty cache root per test.
        $root = Join-Path $TestDrive "cache-$([guid]::NewGuid().ToString('n'))"
        & $UseRoot $root
        Set-Variable -Name CacheRoot -Scope Script -Value $root
    }

    It "exports Get-TerraformSchemaPack and Get-TerraformSchemaCache from TerraformGraph" {
        (Get-Command Get-TerraformSchemaPack -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
        (Get-Command Get-TerraformSchemaCache -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
        @((Get-Command Get-TerraformProviderSchema).Parameters['SaveToCache'].ParameterSets.Keys) | Should -Be @('Provider')
    }

    It "writes registry.terraform.io-hashicorp-null/3.2.3.json.gz and reads back byte-identical JSON" {
        $document = $Documents['registry.terraform.io/hashicorp/null'].Document
        $path = InModuleScope TerraformGraph -Parameters @{ D = $document } {
            param($D)
            Write-TerraformSchemaCache -Provider hashicorp/null -Version 3.2.3 -Document $D
        }
        $path | Should -Be (Join-Path $CacheRoot 'registry.terraform.io-hashicorp-null' '3.2.3.json.gz')
        $back = InModuleScope TerraformGraph -Parameters @{ P = $path } { param($P) Read-TerraformSchemaCache -Path $P }
        ($back | ConvertTo-TerraformJson -Compress) | Should -BeExactly ($document | ConvertTo-TerraformJson -Compress)
        @(Get-ChildItem -LiteralPath (Split-Path $path -Parent) -Force).Name | Should -Be @('3.2.3.json.gz')
    }

    It "downloads a pack from a directory Source, then reports Cached, then Updated with -Force" {
        $entry = $PackEntries | Where-Object version -eq '3.2.3'
        $first = Get-TerraformSchemaPack -Provider null -Source $PackDir -PassThru -ErrorAction Stop
        $first.Status | Should -Be 'Downloaded'
        $first.ProviderAddress | Should -Be 'registry.terraform.io/hashicorp/null'
        $first.Version | Should -Be '3.2.3'
        $first.Path | Should -Be (Join-Path $CacheRoot 'registry.terraform.io-hashicorp-null' '3.2.3.json.gz')
        (Get-FileHash -LiteralPath $first.Path -Algorithm SHA256).Hash | Should -Be $entry.sha256
        $first.Bytes | Should -Be $entry.bytes

        (Get-TerraformSchemaPack -Provider null -Source $PackDir -PassThru -ErrorAction Stop).Status | Should -Be 'Cached'
        (Get-TerraformSchemaPack -Provider null -Source $PackDir -Force -PassThru -ErrorAction Stop).Status | Should -Be 'Updated'
        @(Get-ChildItem -LiteralPath (Split-Path $first.Path -Parent) -Force).Name | Should -Be @('3.2.3.json.gz')
    }

    It "downloads every pack in the manifest when -Provider is omitted" {
        $results = @(Get-TerraformSchemaPack -Source $PackDir -PassThru -ErrorAction Stop)
        $results.ProviderAddress | Should -Be @($PackEntries | ForEach-Object { $_.address })
        @($results | Where-Object Status -ne 'Downloaded').Count | Should -Be 0
    }

    It "throws on a sha256 mismatch and leaves nothing in the cache" {
        $bad = Join-Path $TestDrive "packs-bad-$([guid]::NewGuid().ToString('n'))"
        Copy-Item -LiteralPath $PackDir -Destination $bad -Recurse
        $manifest = Get-Content -LiteralPath (Join-Path $bad 'manifest.json') -Raw | ConvertFrom-TerraformJson
        $manifest.packs[0].sha256 = '0' * 64
        $manifest | ConvertTo-TerraformJson | Set-Content -LiteralPath (Join-Path $bad 'manifest.json')

        { Get-TerraformSchemaPack -Provider null -Source $bad -ErrorAction Stop } | Should -Throw '*sha256 mismatch*Nothing was written to the cache.'
        @(Get-ChildItem -LiteralPath $CacheRoot -Recurse -File -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "throws for a provider with no manifest entry and names Get-TerraformSchemaPack and Get-TerraformProviderSchema -SaveToCache" {
        { Get-TerraformSchemaPack -Provider hashicorp/azurerm -Source $PackDir -ErrorAction Stop } |
            Should -Throw "Get-TerraformSchemaPack found no pack for registry.terraform.io/hashicorp/azurerm in*Get-TerraformProviderSchema -Provider hashicorp/azurerm -SaveToCache."
        @(Get-ChildItem -LiteralPath $CacheRoot -Recurse -File -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "lists cached schemas with Get-TerraformSchemaCache" {
        Get-TerraformSchemaPack -Source $PackDir -ErrorAction Stop
        $all = @(Get-TerraformSchemaCache -ErrorAction Stop)
        $all.ProviderAddress | Should -Be @('registry.terraform.io/hashicorp/local', 'registry.terraform.io/hashicorp/null', 'terraform.io/builtin/terraform')
        $null3 = Get-TerraformSchemaCache -Provider null
        $null3.Version | Should -Be '3.2.3'
        $null3.Bytes | Should -Be ($PackEntries | Where-Object version -eq '3.2.3').bytes
        $null3.CachedOn | Should -BeOfType [datetime]
        @(Get-TerraformSchemaCache -Provider 'hashicorp/*').Count | Should -Be 2
        (Get-TypeData TerraformGraph.CachedSchema).DefaultDisplayPropertySet.ReferencedProperties |
            Should -Be @('ProviderAddress', 'Version', 'Bytes', 'CachedOn')
    }

    It "builds the same graph from ConvertTo-TerraformSchemaGraph -Provider null as from the piped document" {
        Get-TerraformSchemaPack -Provider null -Source $PackDir -ErrorAction Stop
        $cached = ConvertTo-TerraformSchemaGraph -Provider null -ErrorAction Stop
        $piped = $Documents['registry.terraform.io/hashicorp/null'].Document | ConvertTo-TerraformSchemaGraph -ErrorAction Stop
        $cached.NodeCount | Should -Be $piped.NodeCount
        $cached.EdgeCount | Should -Be $piped.EdgeCount
        $cached.Nodes[0].Id | Should -Be $piped.Nodes[0].Id
        $cached.Nodes[-1].Id | Should -Be $piped.Nodes[-1].Id
        $cached.Providers | Should -Be @('registry.terraform.io/hashicorp/null')
    }

    It "throws for an uncached ConvertTo-TerraformSchemaGraph -Provider and names both ways to fill the cache" {
        { ConvertTo-TerraformSchemaGraph -Provider azurerm -ErrorAction Stop } |
            Should -Throw "No cached schema matches 'azurerm'. Download a schema pack with Get-TerraformSchemaPack -Provider azurerm, or harvest it locally with Get-TerraformProviderSchema -Provider azurerm -SaveToCache."
    }

    It "matches the same 5 infra nodes with ConvertTo-TerraformResourceGraph -Provider null,local,terraform as with -SchemaGraph" {
        Get-TerraformSchemaPack -Source $PackDir -ErrorAction Stop
        $moduleGraph = Get-TerraformModuleGraph -Path $Infra -Recurse -ErrorAction Stop
        $schemas = @(foreach ($address in $Documents.Keys) { $Documents[$address].Document | ConvertTo-TerraformSchemaGraph -ErrorAction Stop })
        $viaSchemaGraph = $moduleGraph | ConvertTo-TerraformResourceGraph -SchemaGraph $schemas -ErrorAction Stop
        $viaProvider = $moduleGraph | ConvertTo-TerraformResourceGraph -Provider null, local, terraform -ErrorAction Stop

        $viaProvider.MatchedCount | Should -Be 5
        $viaSchemaGraph.MatchedCount | Should -Be 5
        @($viaProvider.Edges | ForEach-Object { "$($_.From)>$($_.To)" }) | Should -Be @($viaSchemaGraph.Edges | ForEach-Object { "$($_.From)>$($_.To)" })
    }

    It "loads every cached provider with -AutoSchema" {
        Get-TerraformSchemaPack -Source $PackDir -ErrorAction Stop
        $graph = Get-TerraformModuleGraph -Path $Infra -Recurse -ErrorAction Stop | ConvertTo-TerraformResourceGraph -AutoSchema -ErrorAction Stop
        $graph.MatchedCount | Should -Be 5
    }

    It "matches nothing with -AutoSchema and an empty cache, marks every node ProviderNotInSchemaGraph, and never downloads" {
        Mock -ModuleName TerraformGraph Save-TerraformSchemaPackFile { throw 'must not download' }
        Mock -ModuleName TerraformGraph Invoke-WebRequest { throw 'must not download' }
        $graph = Get-TerraformModuleGraph -Path $Infra -Recurse -ErrorAction Stop | ConvertTo-TerraformResourceGraph -AutoSchema -ErrorAction Stop
        $graph.NodeCount | Should -Be 5
        $graph.MatchedCount | Should -Be 0
        @($graph.Nodes | Where-Object Reason -ne 'ProviderNotInSchemaGraph').Count | Should -Be 0
        Should -Invoke -ModuleName TerraformGraph Save-TerraformSchemaPackFile -Times 0 -Exactly
        Should -Invoke -ModuleName TerraformGraph Invoke-WebRequest -Times 0 -Exactly
    }

    Context "-SaveToCache (registry)" -Skip:(-not (Test-Connection registry.terraform.io -Count 1 -Quiet)) {

        It "writes one file into the redirected cache for hashicorp/null 3.2.3" {
            $dir = Join-Path $TestDrive 'save-to-cache-null'
            $schema = Get-TerraformProviderSchema -Provider hashicorp/null -Version 3.2.3 -SaveToCache -WorkingDirectory $dir -Cleanup -ErrorAction Stop
            $schema['provider_schemas'].Keys | Should -Contain 'registry.terraform.io/hashicorp/null'
            $files = @(Get-ChildItem -LiteralPath $CacheRoot -Recurse -File -Force)
            $files.Count | Should -Be 1
            $files[0].FullName | Should -Be (Join-Path $CacheRoot 'registry.terraform.io-hashicorp-null' '3.2.3.json.gz')
            (Get-TerraformSchemaCache -Provider null).Version | Should -Be '3.2.3'
        }
    }
}

# Both cache roots are module-scoped paths. Every test points them at TestDrive, so the real
# LOCALAPPDATA caches are never read or written. tests/fixtures/docs holds real harvests of
# hashicorp/null 3.2.3 and hashicorp/local 2.5.2 (Update-TerraformProviderDocCache against
# the schema fixtures), decompressed.
Describe "Provider docs" {

    BeforeAll {
        $useRoots = {
            param([string]$Root)
            InModuleScope TerraformGraph -Parameters @{ Root = $Root } {
                param($Root)
                $script:TerraformSchemaCacheRoot = Join-Path $Root 'schemas'
                $script:TerraformDocCacheRoot = Join-Path $Root 'docs'
            }
        }
        Set-Variable -Name UseRoots -Scope Script -Value $useRoots
        Set-Variable -Name SavedRoots -Scope Script -Value (InModuleScope TerraformGraph { @{ Schema = $script:TerraformSchemaCacheRoot; Docs = $script:TerraformDocCacheRoot } })
        Set-Variable -Name Infra -Scope Script -Value (Join-Path (Split-Path $PSScriptRoot -Parent) 'infra')

        $schemaFixtures = Join-Path $PSScriptRoot 'fixtures' 'schemas'
        $docFixtures = Join-Path $PSScriptRoot 'fixtures' 'docs'
        $fixtures = [ordered]@{
            'registry.terraform.io/hashicorp/null'  = @{ Version = '3.2.3'; Schema = [System.IO.File]::ReadAllText((Join-Path $schemaFixtures 'null-3.2.3.json')); Docs = [System.IO.File]::ReadAllText((Join-Path $docFixtures 'null-3.2.3.json')) }
            'registry.terraform.io/hashicorp/local' = @{ Version = '2.5.2'; Schema = [System.IO.File]::ReadAllText((Join-Path $schemaFixtures 'local-2.5.2.json')); Docs = [System.IO.File]::ReadAllText((Join-Path $docFixtures 'local-2.5.2.json')) }
        }
        Set-Variable -Name Fixtures -Scope Script -Value $fixtures

        # Seed the current roots with the schema and docs fixtures.
        $seed = {
            param([switch]$NoDocs)
            foreach ($address in $Fixtures.Keys) {
                $item = $Fixtures[$address]
                InModuleScope TerraformGraph -Parameters @{ A = $address; I = $item; NoDocs = [bool]$NoDocs } {
                    param($A, $I, $NoDocs)
                    $null = Write-TerraformSchemaCache -Provider $A -Version $I.Version -Document $I.Schema
                    if (-not $NoDocs) { $null = Write-TerraformSchemaCache -Provider $A -Version $I.Version -Document $I.Docs -Kind Docs }
                }
            }
        }
        Set-Variable -Name Seed -Scope Script -Value $seed

        # A pack source with a schema entry and a docs entry for null, both written through
        # the cache writer and listed with their real sha256.
        $packDir = Join-Path $TestDrive 'doc-packs'
        New-Item -ItemType Directory -Path $packDir | Out-Null
        & $useRoots (Join-Path $TestDrive 'doc-pack-staging')
        $null3 = $fixtures['registry.terraform.io/hashicorp/null']
        $paths = InModuleScope TerraformGraph -Parameters @{ I = $null3 } {
            param($I)
            @{
                Schema = Write-TerraformSchemaCache -Provider hashicorp/null -Version $I.Version -Document $I.Schema
                Docs   = Write-TerraformSchemaCache -Provider hashicorp/null -Version $I.Version -Document $I.Docs -Kind Docs
            }
        }
        $entries = foreach ($kind in 'schema', 'docs') {
            $file = if ($kind -eq 'docs') { 'docs.registry.terraform.io-hashicorp-null.3.2.3.json.gz' } else { 'registry.terraform.io-hashicorp-null.3.2.3.json.gz' }
            Copy-Item -LiteralPath ($kind -eq 'docs' ? $paths.Docs : $paths.Schema) -Destination (Join-Path $packDir $file)
            [ordered]@{
                kind    = $kind
                address = 'registry.terraform.io/hashicorp/null'
                version = '3.2.3'
                file    = $file
                sha256  = (Get-FileHash -LiteralPath (Join-Path $packDir $file) -Algorithm SHA256).Hash.ToLowerInvariant()
                bytes   = (Get-Item -LiteralPath (Join-Path $packDir $file)).Length
            }
        }
        [ordered]@{ builtOn = '2026-10-06T00:00:00Z'; packs = [object[]]@($entries) } |
            ConvertTo-TerraformJson | Set-Content -LiteralPath (Join-Path $packDir 'manifest.json')
        Set-Variable -Name DocPackDir -Scope Script -Value $packDir
        Set-Variable -Name DocPackEntries -Scope Script -Value @($entries)

        Set-Variable -Name SavedTokens -Scope Script -Value @{ GH_TOKEN = $env:GH_TOKEN; GITHUB_TOKEN = $env:GITHUB_TOKEN }
    }

    AfterAll {
        InModuleScope TerraformGraph -Parameters @{ S = $SavedRoots } {
            param($S)
            $script:TerraformSchemaCacheRoot = $S.Schema
            $script:TerraformDocCacheRoot = $S.Docs
        }
        $env:GH_TOKEN = $SavedTokens.GH_TOKEN
        $env:GITHUB_TOKEN = $SavedTokens.GITHUB_TOKEN
    }

    BeforeEach {
        # New, empty cache roots per test.
        $root = Join-Path $TestDrive "docs-$([guid]::NewGuid().ToString('n'))"
        & $UseRoots $root
        Set-Variable -Name CacheRoot -Scope Script -Value $root
    }

    It "exports the four docs commands from TerraformGraph" {
        foreach ($name in 'Update-TerraformProviderDocCache', 'Get-TerraformProviderDoc', 'Get-TerraformDocPack', 'Get-TerraformDocCache') {
            (Get-Command $name -ErrorAction Stop).Module.Name | Should -Be 'TerraformGraph'
        }
        (Get-TypeData TerraformGraph.ProviderDoc).DefaultDisplayPropertySet.ReferencedProperties | Should -Be @('Id', 'Category', 'Title', 'Subcategory')
    }

    It "reconstructs doc Ids for resources, data sources, overview, guides and an unmatched slug" {
        $results = InModuleScope TerraformGraph {
            $address = 'registry.terraform.io/vmware/vsphere'
            $index = [pscustomobject]@{
                SchemaVersion = '2.17.1'
                Prefix        = 'vsphere'
                Resource      = [System.Collections.Generic.HashSet[string]]::new([string[]]@('vsphere_resource_pool', 'vsphere_sso_group'))
                Data          = [System.Collections.Generic.HashSet[string]]::new([string[]]@('vsphere_datacenter'))
            }
            [ordered]@{
                Resource  = Resolve-TerraformProviderDocId -Address $address -Category resources -Slug resource_pool -Index $index -Prefix vsphere
                Prefixed  = Resolve-TerraformProviderDocId -Address $address -Category resources -Slug vsphere_sso_group -Index $index -Prefix vsphere
                Data      = Resolve-TerraformProviderDocId -Address $address -Category data-sources -Slug datacenter -Index $index -Prefix vsphere
                Overview  = Resolve-TerraformProviderDocId -Address $address -Category overview -Slug index -Index $index -Prefix vsphere
                Guide     = Resolve-TerraformProviderDocId -Address $address -Category guides -Slug getting-started -Index $index -Prefix vsphere
                Unmatched = Resolve-TerraformProviderDocId -Address $address -Category resources -Slug no_such_thing -Index $index -Prefix vsphere
                DataAsRes = Resolve-TerraformProviderDocId -Address $address -Category data-sources -Slug resource_pool -Index $index -Prefix vsphere
                NoSchema  = Resolve-TerraformProviderDocId -Address $address -Category resources -Slug resource_pool -Index $null -Prefix vsphere
            }
        }
        $results.Resource.Id | Should -Be 'registry.terraform.io/vmware/vsphere/resource/vsphere_resource_pool'
        $results.Resource.Type | Should -Be 'vsphere_resource_pool'
        $results.Resource.Matched | Should -BeTrue
        $results.Prefixed.Id | Should -Be 'registry.terraform.io/vmware/vsphere/resource/vsphere_sso_group'
        $results.Data.Id | Should -Be 'registry.terraform.io/vmware/vsphere/data/vsphere_datacenter'
        $results.Overview.Id | Should -Be 'registry.terraform.io/vmware/vsphere'
        $results.Guide.Id | Should -Be 'registry.terraform.io/vmware/vsphere/guide/getting-started'
        $results.Unmatched.Id | Should -Be 'registry.terraform.io/vmware/vsphere/unmatched/resources/no_such_thing'
        $results.Unmatched.Matched | Should -BeFalse
        $results.Unmatched.Type | Should -BeNullOrEmpty
        $results.DataAsRes.Id | Should -Be 'registry.terraform.io/vmware/vsphere/unmatched/data-sources/resource_pool'
        $results.NoSchema.Id | Should -Be 'registry.terraform.io/vmware/vsphere/resource/vsphere_resource_pool'
        $results.NoSchema.Matched | Should -BeNullOrEmpty
    }

    It "counts unmatched docs in the document and derives the prefix from the cached schema" {
        & $Seed -NoDocs
        $document = InModuleScope TerraformGraph {
            $index = Get-TerraformProviderDocSchemaIndex -Address 'registry.terraform.io/hashicorp/null' -Version '3.2.3'
            $docs = @(
                [pscustomobject]@{ Category = 'resources'; Title = 'resource'; Subcategory = $null; Slug = 'resource'; Content = 'r' }
                [pscustomobject]@{ Category = 'resources'; Title = 'gone'; Subcategory = $null; Slug = 'gone'; Content = 'g' }
                [pscustomobject]@{ Category = 'overview'; Title = 'overview'; Subcategory = $null; Slug = 'index'; Content = 'o' }
            )
            @{ Index = $index; Document = ConvertTo-TerraformProviderDocDocument -Address 'registry.terraform.io/hashicorp/null' -Version '3.2.3' -Docs $docs -Index $index -Prefix $index.Prefix }
        }
        $document.Index.Prefix | Should -Be 'null'
        $document.Document.docCount | Should -Be 3
        $document.Document.unmatchedCount | Should -Be 1
        $document.Document.schemaVersion | Should -Be '3.2.3'
        @($document.Document.docs | ForEach-Object { $_.id }) | Should -Be @(
            'registry.terraform.io/hashicorp/null'
            'registry.terraform.io/hashicorp/null/unmatched/resources/gone'
            'registry.terraform.io/hashicorp/null/resource/null_resource'
        )
    }

    It "round-trips the null fixture through the docs cache and lists it with Get-TerraformDocCache" {
        $item = $Fixtures['registry.terraform.io/hashicorp/null']
        $path = InModuleScope TerraformGraph -Parameters @{ I = $item } {
            param($I)
            Write-TerraformSchemaCache -Provider hashicorp/null -Version 3.2.3 -Document $I.Docs -Kind Docs
        }
        $path | Should -Be (Join-Path $CacheRoot 'docs' 'registry.terraform.io-hashicorp-null' '3.2.3.json.gz')
        $back = InModuleScope TerraformGraph -Parameters @{ P = $path } { param($P) Read-TerraformSchemaCache -Path $P }
        ($back | ConvertTo-TerraformJson -Compress) | Should -BeExactly ($item.Docs | ConvertFrom-TerraformJson -AsHashtable | ConvertTo-TerraformJson -Compress)

        $listed = Get-TerraformDocCache -Provider null
        $listed.ProviderAddress | Should -Be 'registry.terraform.io/hashicorp/null'
        $listed.Version | Should -Be '3.2.3'
        $listed.DocCount | Should -Be 4
        $listed.UnmatchedCount | Should -Be 0
        $listed.PSObject.TypeNames[0] | Should -Be 'TerraformGraph.CachedDoc'
        @(Get-TerraformSchemaCache).Count | Should -Be 0
    }

    It "gets docs by -Id, -Type wildcard and -Category" {
        & $Seed
        $byId = @(Get-TerraformProviderDoc -Id 'registry.terraform.io/hashicorp/null/resource/null_resource' -ErrorAction Stop)
        $byId.Count | Should -Be 1
        $byId[0].Type | Should -Be 'null_resource'
        $byId[0].Version | Should -Be '3.2.3'
        $byId[0].Content | Should -Match 'null_resource'

        $byType = @(Get-TerraformProviderDoc -Type 'local_*' -ErrorAction Stop)
        @($byType | ForEach-Object Id) | Should -Be @(
            'registry.terraform.io/hashicorp/local/resource/local_file'
            'registry.terraform.io/hashicorp/local/resource/local_sensitive_file'
            'registry.terraform.io/hashicorp/local/data/local_file'
            'registry.terraform.io/hashicorp/local/data/local_sensitive_file'
        )
        @(Get-TerraformProviderDoc -Provider local -Type '*_sensitive_*' -Category data-sources -ErrorAction Stop).Id |
            Should -Be 'registry.terraform.io/hashicorp/local/data/local_sensitive_file'

        $guides = @(Get-TerraformProviderDoc -Provider null -Category guides -ErrorAction Stop)
        $guides.Id | Should -Be 'registry.terraform.io/hashicorp/null/guide/terraform-migration'
        $guides.Type | Should -BeNullOrEmpty
        @(Get-TerraformProviderDoc -Category overview -ErrorAction Stop).Id | Should -Be @('registry.terraform.io/hashicorp/local', 'registry.terraform.io/hashicorp/null')
        @(Get-TerraformProviderDoc -Provider 'hashicorp/n*' -ErrorAction Stop).Count | Should -Be 4
    }

    It "returns only hcl and terraform code blocks with -Examples" {
        $content = @(
            '# Example', '', '```hcl', 'resource "a" "b" {}', '```', '', '```shell', 'terraform import a.b id', '```', '',
            '```terraform', 'data "c" "d" {}', '```', '', '```json', '{ "x": 1 }', '```', '', '```', 'untagged', '```'
        ) -join "`n"
        $document = [ordered]@{
            address = 'registry.terraform.io/hashicorp/null'; version = '9.9.9'; harvestedOn = '2026-10-06T00:00:00Z'
            schemaVersion = $null; docCount = 1; unmatchedCount = $null
            docs = [object[]]@([ordered]@{ id = 'registry.terraform.io/hashicorp/null/resource/null_resource'; category = 'resources'; title = 'resource'; subcategory = $null; slug = 'resource'; content = $content })
        }
        InModuleScope TerraformGraph -Parameters @{ D = $document } {
            param($D)
            $null = Write-TerraformSchemaCache -Provider hashicorp/null -Version 9.9.9 -Document $D -Kind Docs
        }
        $doc = Get-TerraformProviderDoc -Provider null -Examples -ErrorAction Stop
        $doc.ExampleCount | Should -Be 2
        $doc.Content | Should -BeExactly "resource `"a`" `"b`" {}`n`ndata `"c`" `"d`" {}"

        $plain = Get-TerraformProviderDoc -Provider null -ErrorAction Stop
        $plain.ExampleCount | Should -BeNullOrEmpty
        $plain.Content | Should -BeExactly $content
    }

    It "returns one doc per distinct matched null/local schema type for a ResourceGraph of infra piped in" {
        & $Seed
        $graph = Get-TerraformModuleGraph -Path $Infra -Recurse -ErrorAction Stop | ConvertTo-TerraformResourceGraph -AutoSchema -ErrorAction Stop
        $matched = @($graph.Nodes | Where-Object { $_.SchemaMatched -and $_.ProviderAddress -match '/hashicorp/(null|local)$' })
        $matched.Count | Should -Be 3
        $expected = @($matched | ForEach-Object SchemaId | Select-Object -Unique)

        $docs = @($graph | Select-Object -ExpandProperty Nodes | Get-TerraformProviderDoc -WarningVariable warnings -ErrorAction Stop)
        @($docs | ForEach-Object Id) | Should -Be $expected
        @($docs | ForEach-Object Id) | Should -Be @('registry.terraform.io/hashicorp/null/resource/null_resource', 'registry.terraform.io/hashicorp/local/data/local_file')
        $warnings.Count | Should -Be 0
    }

    It "maps piped SchemaNodes to their resource, data source or overview page" {
        & $Seed
        $schema = ConvertTo-TerraformSchemaGraph -Provider null -ErrorAction Stop
        $docs = @($schema.Nodes | Get-TerraformProviderDoc -ErrorAction Stop)
        @($docs | ForEach-Object Id) | Should -Be @(
            'registry.terraform.io/hashicorp/null'
            'registry.terraform.io/hashicorp/null/resource/null_resource'
            'registry.terraform.io/hashicorp/null/data/null_data_source'
        )
        $attribute = $schema.Nodes | Where-Object Id -eq 'registry.terraform.io/hashicorp/null/resource/null_resource/triggers'
        ($attribute | Get-TerraformProviderDoc -ErrorAction Stop).Id | Should -Be 'registry.terraform.io/hashicorp/null/resource/null_resource'
    }

    It "throws when docs are not cached and names Get-TerraformDocPack and Update-TerraformProviderDocCache" {
        { Get-TerraformProviderDoc -Provider azurerm -ErrorAction Stop } |
            Should -Throw "No cached provider docs match 'azurerm'. Download a docs pack with Get-TerraformDocPack -Provider azurerm, or harvest them from the registry with Update-TerraformProviderDocCache -Provider azurerm."
        { Get-TerraformProviderDoc -ErrorAction Stop } | Should -Throw '*Get-TerraformDocPack*Update-TerraformProviderDocCache*'
        & $Seed
        { Get-TerraformProviderDoc -Provider null -Version 1.0.0 -ErrorAction Stop } | Should -Throw '*Get-TerraformDocPack -Provider registry.terraform.io/hashicorp/null -Version 1.0.0*Update-TerraformProviderDocCache*'
    }

    It "warns once per uncached provider in the pipeline and never downloads" {
        & $Seed -NoDocs
        Mock -ModuleName TerraformGraph Invoke-WebRequest { throw 'must not download' }
        Mock -ModuleName TerraformGraph Invoke-RestMethod { throw 'must not download' }
        $graph = Get-TerraformModuleGraph -Path $Infra -Recurse -ErrorAction Stop | ConvertTo-TerraformResourceGraph -AutoSchema -ErrorAction Stop
        $docs = @($graph.Nodes | Get-TerraformProviderDoc -WarningVariable warnings -WarningAction SilentlyContinue)
        $docs.Count | Should -Be 0
        @($warnings | ForEach-Object { "$_" }) | Should -Be @(
            'No cached docs for registry.terraform.io/hashicorp/null. Download a docs pack with Get-TerraformDocPack -Provider hashicorp/null, or harvest them with Update-TerraformProviderDocCache -Provider hashicorp/null.'
            'No cached docs for registry.terraform.io/hashicorp/local. Download a docs pack with Get-TerraformDocPack -Provider hashicorp/local, or harvest them with Update-TerraformProviderDocCache -Provider hashicorp/local.'
        )
        Should -Invoke -ModuleName TerraformGraph Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke -ModuleName TerraformGraph Invoke-RestMethod -Times 0 -Exactly
    }

    It "downloads only the docs entry with Get-TerraformDocPack from a manifest with both kinds" {
        $results = @(Get-TerraformDocPack -Source $DocPackDir -PassThru -ErrorAction Stop)
        $results.Count | Should -Be 1
        $results[0].PSObject.TypeNames[0] | Should -Be 'TerraformGraph.DocPack'
        $results[0].Status | Should -Be 'Downloaded'
        $results[0].Path | Should -Be (Join-Path $CacheRoot 'docs' 'registry.terraform.io-hashicorp-null' '3.2.3.json.gz')
        (Get-FileHash -LiteralPath $results[0].Path -Algorithm SHA256).Hash | Should -Be ($DocPackEntries | Where-Object kind -eq 'docs').sha256
        Test-Path -LiteralPath (Join-Path $CacheRoot 'schemas') | Should -BeFalse
        (Get-TerraformDocPack -Provider null -Source $DocPackDir -PassThru -ErrorAction Stop).Status | Should -Be 'Cached'
        (Get-TerraformProviderDoc -Provider null -Category overview -ErrorAction Stop).Id | Should -Be 'registry.terraform.io/hashicorp/null'
    }

    It "ignores docs entries in Get-TerraformSchemaPack" {
        $results = @(Get-TerraformSchemaPack -Source $DocPackDir -PassThru -ErrorAction Stop)
        $results.Count | Should -Be 1
        $results[0].Path | Should -Be (Join-Path $CacheRoot 'schemas' 'registry.terraform.io-hashicorp-null' '3.2.3.json.gz')
        (Get-FileHash -LiteralPath $results[0].Path -Algorithm SHA256).Hash | Should -Be ($DocPackEntries | Where-Object kind -eq 'schema').sha256
        Test-Path -LiteralPath (Join-Path $CacheRoot 'docs') | Should -BeFalse
    }

    It "throws for Get-TerraformDocPack with no docs entry and names Update-TerraformProviderDocCache" {
        { Get-TerraformDocPack -Provider hashicorp/local -Source $DocPackDir -ErrorAction Stop } |
            Should -Throw "Get-TerraformDocPack found no docs pack for registry.terraform.io/hashicorp/local in*Harvest them from the registry instead with Update-TerraformProviderDocCache -Provider hashicorp/local."
    }

    Context "GitHub release downloads" {

        BeforeEach {
            $env:GH_TOKEN = $null
            $env:GITHUB_TOKEN = $null
        }

        It "uses the releases API with a Bearer token when GH_TOKEN is set" {
            $env:GH_TOKEN = 'test-token'
            Mock -ModuleName TerraformGraph Invoke-RestMethod {
                [pscustomobject]@{
                    tag_name = 'v0.11.0'
                    assets   = @(
                        [pscustomobject]@{ name = 'manifest.json'; url = 'https://api.github.com/repos/o/r/releases/assets/1' }
                        [pscustomobject]@{ name = 'docs.registry.terraform.io-hashicorp-null.3.2.3.json.gz'; url = 'https://api.github.com/repos/o/r/releases/assets/2' }
                    )
                }
            }
            Mock -ModuleName TerraformGraph Invoke-WebRequest {
                $name = if ($Uri -like '*/assets/1') { 'manifest.json' } else { 'docs.registry.terraform.io-hashicorp-null.3.2.3.json.gz' }
                Copy-Item -LiteralPath (Join-Path $DocPackDir $name) -Destination $OutFile
            }

            $result = Get-TerraformDocPack -Provider null -Source 'https://github.com/o/r/releases/latest/download' -PassThru -ErrorAction Stop
            $result.Status | Should -Be 'Downloaded'
            Should -Invoke -ModuleName TerraformGraph Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/o/r/releases/latest' -and $Headers.Authorization -eq 'Bearer test-token'
            }
            Should -Invoke -ModuleName TerraformGraph Invoke-WebRequest -Times 2 -Exactly -ParameterFilter {
                $Uri -like 'https://api.github.com/repos/o/r/releases/assets/*' -and $Headers.Authorization -eq 'Bearer test-token' -and $Headers.Accept -eq 'application/octet-stream'
            }
        }

        It "looks up a tagged release with GITHUB_TOKEN" {
            $env:GITHUB_TOKEN = 'other-token'
            Mock -ModuleName TerraformGraph Invoke-RestMethod {
                [pscustomobject]@{ tag_name = 'v0.11.0'; assets = @([pscustomobject]@{ name = 'manifest.json'; url = 'https://api.github.com/repos/o/r/releases/assets/1' }) }
            }
            Mock -ModuleName TerraformGraph Invoke-WebRequest { Copy-Item -LiteralPath (Join-Path $DocPackDir 'manifest.json') -Destination $OutFile }
            { Get-TerraformDocPack -Provider null -Source 'https://github.com/o/r/releases/download/v0.11.0' -ErrorAction Stop } |
                Should -Throw '*Release v0.11.0 of o/r has no asset named docs.registry.terraform.io-hashicorp-null.3.2.3.json.gz*'
            Should -Invoke -ModuleName TerraformGraph Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/o/r/releases/tags/v0.11.0' -and $Headers.Authorization -eq 'Bearer other-token'
            }
        }

        It "uses the anonymous download URL when no token is set" {
            Mock -ModuleName TerraformGraph Invoke-RestMethod { throw 'must not call the API' }
            Mock -ModuleName TerraformGraph Invoke-WebRequest {
                Copy-Item -LiteralPath (Join-Path $DocPackDir ($Uri -split '/')[-1]) -Destination $OutFile
            }
            $result = Get-TerraformSchemaPack -Provider null -Source 'https://github.com/o/r/releases/latest/download' -PassThru -ErrorAction Stop
            $result.Status | Should -Be 'Downloaded'
            Should -Invoke -ModuleName TerraformGraph Invoke-RestMethod -Times 0 -Exactly
            Should -Invoke -ModuleName TerraformGraph Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://github.com/o/r/releases/latest/download/manifest.json' -and -not $Headers
            }
            Should -Invoke -ModuleName TerraformGraph Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://github.com/o/r/releases/latest/download/registry.terraform.io-hashicorp-null.3.2.3.json.gz' -and -not $Headers
            }
        }

        It "says the repository may be private and names GH_TOKEN on a 404 without a token" {
            Mock -ModuleName TerraformGraph Invoke-WebRequest {
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::NotFound))
            }
            { Get-TerraformSchemaPack -Provider null -Source 'https://github.com/o/r/releases/latest/download' -ErrorAction Stop } |
                Should -Throw '*manifest.json was not found at https://github.com/o/r/releases/latest/download (404). The repository may be private: set $env:GH_TOKEN*'
        }
    }

    Context "live harvest (registry)" -Skip:(-not (Test-Connection registry.terraform.io -Count 1 -Quiet)) {

        It "harvests hashicorp/null 3.2.3 into the redirected docs cache" {
            & $Seed -NoDocs
            $result = Update-TerraformProviderDocCache -Provider hashicorp/null -Version 3.2.3 -PassThru -ErrorAction Stop
            $result.DocCount | Should -BeGreaterThan 0
            $result.UnmatchedCount | Should -Be 0
            $result.Status | Should -Be 'Harvested'
            $result.Path | Should -Be (Join-Path $CacheRoot 'docs' 'registry.terraform.io-hashicorp-null' '3.2.3.json.gz')
            (Update-TerraformProviderDocCache -Provider hashicorp/null -Version 3.2.3 -PassThru -ErrorAction Stop).Status | Should -Be 'Cached'
            (Get-TerraformProviderDoc -Provider null -Type null_resource -ErrorAction Stop).Id | Should -Be 'registry.terraform.io/hashicorp/null/resource/null_resource'
        }
    }
}
