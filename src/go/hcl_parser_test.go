package main

import (
	"encoding/json"
	"testing"
)

// parseAttr parses src and returns the decoded Expr of the top-level attribute name.
func parseAttr(t *testing.T, src, name string) map[string]interface{} {
	t.Helper()
	out, err := parseToJSON([]byte(src), "test.tf")
	if err != nil {
		t.Fatalf("parseToJSON: %v", err)
	}
	var doc struct {
		Body struct {
			Attributes map[string]struct {
				Expr map[string]interface{}
			}
		}
	}
	if err := json.Unmarshal(out, &doc); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	attr, ok := doc.Body.Attributes[name]
	if !ok {
		t.Fatalf("attribute %q not found in %s", name, out)
	}
	return attr.Expr
}

func assertKindRaw(t *testing.T, expr map[string]interface{}, kind, raw string) {
	t.Helper()
	if expr["Kind"] != kind {
		t.Errorf("Kind = %v, want %v", expr["Kind"], kind)
	}
	if expr["Raw"] != raw {
		t.Errorf("Raw = %q, want %q", expr["Raw"], raw)
	}
	if _, ok := expr["SrcRange"]; !ok {
		t.Errorf("SrcRange missing")
	}
}

func child(t *testing.T, expr map[string]interface{}, key string) map[string]interface{} {
	t.Helper()
	m, ok := expr[key].(map[string]interface{})
	if !ok {
		t.Fatalf("%s is %T, want object", key, expr[key])
	}
	return m
}

func list(t *testing.T, expr map[string]interface{}, key string) []interface{} {
	t.Helper()
	l, ok := expr[key].([]interface{})
	if !ok {
		t.Fatalf("%s is %T, want array", key, expr[key])
	}
	return l
}

func TestStringLiteral(t *testing.T) {
	e := parseAttr(t, `source = "./modules/network"`, "source")
	assertKindRaw(t, e, "TemplateExpr", `"./modules/network"`)
	if e["IsLiteral"] != true {
		t.Errorf("IsLiteral = %v, want true", e["IsLiteral"])
	}
	if e["Value"] != "./modules/network" {
		t.Errorf("Value = %v", e["Value"])
	}
	part := list(t, e, "Parts")[0].(map[string]interface{})
	assertKindRaw(t, part, "LiteralValueExpr", "./modules/network")
	if part["Value"] != "./modules/network" || part["ValueType"] != "string" {
		t.Errorf("part Value/ValueType = %v/%v", part["Value"], part["ValueType"])
	}
}

func TestNumberAndBoolLiterals(t *testing.T) {
	e := parseAttr(t, "n = 2\nb = false\nz = null", "n")
	assertKindRaw(t, e, "LiteralValueExpr", "2")
	if e["Value"] != float64(2) || e["ValueType"] != "number" {
		t.Errorf("Value/ValueType = %v/%v", e["Value"], e["ValueType"])
	}
	e = parseAttr(t, "b = false", "b")
	if e["Value"] != false || e["ValueType"] != "bool" {
		t.Errorf("Value/ValueType = %v/%v", e["Value"], e["ValueType"])
	}
	e = parseAttr(t, "z = null", "z")
	if v, ok := e["Value"]; !ok || v != nil {
		t.Errorf("Value = %v (present %v), want null", v, ok)
	}
}

func TestTemplateInterpolation(t *testing.T) {
	e := parseAttr(t, `filename = "${path.module}/../README.md"`, "filename")
	assertKindRaw(t, e, "TemplateExpr", `"${path.module}/../README.md"`)
	if e["IsLiteral"] != false {
		t.Errorf("IsLiteral = %v, want false", e["IsLiteral"])
	}
	if _, ok := e["Value"]; ok {
		t.Errorf("Value present on non-literal template")
	}
	parts := list(t, e, "Parts")
	if len(parts) != 2 {
		t.Fatalf("len(Parts) = %d, want 2", len(parts))
	}
	first := parts[0].(map[string]interface{})
	assertKindRaw(t, first, "ScopeTraversalExpr", "path.module")
	if first["Traversal"] != "path.module" {
		t.Errorf("Traversal = %v", first["Traversal"])
	}
}

func TestTemplateWrap(t *testing.T) {
	e := parseAttr(t, `x = "${var.a}"`, "x")
	assertKindRaw(t, e, "TemplateWrapExpr", `"${var.a}"`)
	if child(t, e, "Wrapped")["Traversal"] != "var.a" {
		t.Errorf("Wrapped = %v", e["Wrapped"])
	}
}

func TestScopeTraversal(t *testing.T) {
	cases := map[string]string{
		"var.region":                 "var.region",
		"module.network.subnet_id":   "module.network.subnet_id",
		"aws_instance.web[0].id":     "aws_instance.web[0].id",
		`aws_instance.web["a"].arn`: `aws_instance.web["a"].arn`,
	}
	for src, want := range cases {
		e := parseAttr(t, "x = "+src, "x")
		assertKindRaw(t, e, "ScopeTraversalExpr", src)
		if e["Traversal"] != want {
			t.Errorf("Traversal = %v, want %v", e["Traversal"], want)
		}
	}
}

func TestFunctionCall(t *testing.T) {
	e := parseAttr(t, `x = concat(var.a, ["b"]...)`, "x")
	assertKindRaw(t, e, "FunctionCallExpr", `concat(var.a, ["b"]...)`)
	if e["Name"] != "concat" {
		t.Errorf("Name = %v", e["Name"])
	}
	if e["ExpandFinal"] != true {
		t.Errorf("ExpandFinal = %v, want true", e["ExpandFinal"])
	}
	args := list(t, e, "Args")
	if len(args) != 2 {
		t.Fatalf("len(Args) = %d, want 2", len(args))
	}
	assertKindRaw(t, args[0].(map[string]interface{}), "ScopeTraversalExpr", "var.a")
	assertKindRaw(t, args[1].(map[string]interface{}), "TupleConsExpr", `["b"]`)
}

func TestObjectCons(t *testing.T) {
	e := parseAttr(t, "x = {\n  region = var.aws_region\n}", "x")
	assertKindRaw(t, e, "ObjectConsExpr", "{\n  region = var.aws_region\n}")
	items := list(t, e, "Items")
	if len(items) != 1 {
		t.Fatalf("len(Items) = %d, want 1", len(items))
	}
	item := items[0].(map[string]interface{})
	if child(t, item, "Key")["Raw"] != "region" {
		t.Errorf("Key = %v", item["Key"])
	}
	value := child(t, item, "Value")
	assertKindRaw(t, value, "ScopeTraversalExpr", "var.aws_region")
	if value["Traversal"] != "var.aws_region" {
		t.Errorf("Traversal = %v", value["Traversal"])
	}
}

func TestTupleCons(t *testing.T) {
	e := parseAttr(t, `x = ["us-east-1a", "us-east-1b"]`, "x")
	assertKindRaw(t, e, "TupleConsExpr", `["us-east-1a", "us-east-1b"]`)
	exprs := list(t, e, "Exprs")
	if len(exprs) != 2 {
		t.Fatalf("len(Exprs) = %d, want 2", len(exprs))
	}
	if exprs[1].(map[string]interface{})["Value"] != "us-east-1b" {
		t.Errorf("Exprs[1] = %v", exprs[1])
	}
}

func TestConditional(t *testing.T) {
	e := parseAttr(t, `x = var.on ? 1 : length(var.list) > 0`, "x")
	assertKindRaw(t, e, "ConditionalExpr", `var.on ? 1 : length(var.list) > 0`)
	assertKindRaw(t, child(t, e, "Condition"), "ScopeTraversalExpr", "var.on")
	assertKindRaw(t, child(t, e, "TrueResult"), "LiteralValueExpr", "1")
	f := child(t, e, "FalseResult")
	assertKindRaw(t, f, "BinaryOpExpr", "length(var.list) > 0")
	if f["Op"] != ">" {
		t.Errorf("Op = %v, want >", f["Op"])
	}
}

func TestForExpr(t *testing.T) {
	src := `x = { for k, v in var.tags : upper(k) => v if v != "" }`
	e := parseAttr(t, src, "x")
	assertKindRaw(t, e, "ForExpr", `{ for k, v in var.tags : upper(k) => v if v != "" }`)
	if e["KeyVar"] != "k" || e["ValVar"] != "v" {
		t.Errorf("KeyVar/ValVar = %v/%v", e["KeyVar"], e["ValVar"])
	}
	if e["Group"] != false {
		t.Errorf("Group = %v", e["Group"])
	}
	if child(t, e, "CollExpr")["Traversal"] != "var.tags" {
		t.Errorf("CollExpr = %v", e["CollExpr"])
	}
	assertKindRaw(t, child(t, e, "KeyExpr"), "FunctionCallExpr", "upper(k)")
	assertKindRaw(t, child(t, e, "ValExpr"), "ScopeTraversalExpr", "v")
	cond := child(t, e, "CondExpr")
	assertKindRaw(t, cond, "BinaryOpExpr", `v != ""`)
	if cond["Op"] != "!=" {
		t.Errorf("Op = %v", cond["Op"])
	}

	// List form has no key expression.
	e = parseAttr(t, `y = [for s in var.list : s]`, "y")
	if e["KeyExpr"] != nil || e["KeyVar"] != "" {
		t.Errorf("KeyExpr/KeyVar = %v/%v, want null/empty", e["KeyExpr"], e["KeyVar"])
	}
}

func TestBlocksKeepShape(t *testing.T) {
	out, err := parseToJSON([]byte("module \"network\" {\n  source = \"./x\"\n}\n"), "test.tf")
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		Body struct {
			Blocks []struct {
				Type   string
				Labels []string
				Body   struct {
					Attributes map[string]struct{ Name string }
				}
				TypeRange struct{ Start struct{ Line int } }
			}
		}
	}
	if err := json.Unmarshal(out, &doc); err != nil {
		t.Fatal(err)
	}
	b := doc.Body.Blocks[0]
	if b.Type != "module" || b.Labels[0] != "network" || b.Body.Attributes["source"].Name != "source" || b.TypeRange.Start.Line != 1 {
		t.Errorf("block = %+v", b)
	}
}

func TestParseErrorPrefix(t *testing.T) {
	_, err := parseToJSON([]byte("x = "), "bad.tf")
	if err == nil || err.Error()[:6] != "Error " {
		t.Errorf("err = %v, want Error prefix", err)
	}
}
