package main

/*
#include <stdlib.h> // Include the C standard library for free()
*/
import "C"
import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"unsafe" // Add the unsafe package

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/zclconf/go-cty/cty"
	ctyjson "github.com/zclconf/go-cty/cty/json"
)

//export ParseHCL
func ParseHCL(filePath *C.char) *C.char {
	// Convert the C string to a Go string
	goFilePath := C.GoString(filePath)

	// Resolve the absolute path (cross-platform)
	absPath, err := filepath.Abs(goFilePath)
	if err != nil {
		log.Printf("Error resolving absolute path: %v", err)
		return C.CString(fmt.Sprintf("Error resolving absolute path: %v", err))
	}

	src, err := os.ReadFile(absPath)
	if err != nil {
		log.Printf("Error reading HCL file: %v", err)
		return C.CString(fmt.Sprintf("Error reading HCL file: %v", err))
	}

	astJson, err := parseToJSON(src, absPath)
	if err != nil {
		log.Printf("%v", err)
		return C.CString(err.Error())
	}

	// Return the JSON as a C string
	return C.CString(string(astJson))
}

//export FreeString
func FreeString(str *C.char) {
	C.free(unsafe.Pointer(str))
}

func main() {} // Required for `c-shared` build mode

// parseToJSON parses src as native HCL syntax and returns the AST as JSON.
// Errors are prefixed "Error " because the PowerShell side checks for that.
func parseToJSON(src []byte, filename string) ([]byte, error) {
	file, diags := hclsyntax.ParseConfig(src, filename, hcl.Pos{Line: 1, Column: 1, Byte: 0})
	if diags.HasErrors() {
		return nil, fmt.Errorf("Error parsing HCL file: %v", diags)
	}

	body, ok := file.Body.(*hclsyntax.Body)
	if !ok {
		return nil, fmt.Errorf("Error parsing HCL file: body is %T, not native syntax", file.Body)
	}

	w := walker{src: src}
	astJson, err := json.Marshal(fileNode{Body: w.body(body)})
	if err != nil {
		return nil, fmt.Errorf("Error marshaling AST to JSON: %v", err)
	}
	return astJson, nil
}

// Block and attribute shapes match the field names json.Marshal produced for
// hclsyntax types, so the PowerShell side reads them unchanged.

type fileNode struct {
	Body *bodyNode
}

type bodyNode struct {
	Attributes map[string]*attributeNode
	Blocks     []*blockNode
	SrcRange   hcl.Range
	EndRange   hcl.Range
}

type blockNode struct {
	Type            string
	Labels          []string
	Body            *bodyNode
	TypeRange       hcl.Range
	LabelRanges     []hcl.Range
	OpenBraceRange  hcl.Range
	CloseBraceRange hcl.Range
}

type attributeNode struct {
	Name        string
	Expr        node
	SrcRange    hcl.Range
	NameRange   hcl.Range
	EqualsRange hcl.Range
}

// node is a JSON object that keeps its keys in insertion order, so every
// expression starts with Kind, Raw, SrcRange.
type node []field

type field struct {
	Key   string
	Value interface{}
}

func (n node) MarshalJSON() ([]byte, error) {
	if n == nil {
		return []byte("null"), nil
	}
	var buf bytes.Buffer
	buf.WriteByte('{')
	for i, f := range n {
		if i > 0 {
			buf.WriteByte(',')
		}
		key, err := json.Marshal(f.Key)
		if err != nil {
			return nil, err
		}
		buf.Write(key)
		buf.WriteByte(':')
		val, err := json.Marshal(f.Value)
		if err != nil {
			return nil, err
		}
		buf.Write(val)
	}
	buf.WriteByte('}')
	return buf.Bytes(), nil
}

type walker struct {
	src []byte
}

func (w walker) body(b *hclsyntax.Body) *bodyNode {
	if b == nil {
		return nil
	}
	out := &bodyNode{
		Attributes: make(map[string]*attributeNode, len(b.Attributes)),
		SrcRange:   b.SrcRange,
		EndRange:   b.EndRange,
	}
	for name, attr := range b.Attributes {
		out.Attributes[name] = &attributeNode{
			Name:        attr.Name,
			Expr:        w.expr(attr.Expr),
			SrcRange:    attr.SrcRange,
			NameRange:   attr.NameRange,
			EqualsRange: attr.EqualsRange,
		}
	}
	for _, blk := range b.Blocks {
		out.Blocks = append(out.Blocks, &blockNode{
			Type:            blk.Type,
			Labels:          blk.Labels,
			Body:            w.body(blk.Body),
			TypeRange:       blk.TypeRange,
			LabelRanges:     blk.LabelRanges,
			OpenBraceRange:  blk.OpenBraceRange,
			CloseBraceRange: blk.CloseBraceRange,
		})
	}
	return out
}

func (w walker) raw(rng hcl.Range) string {
	start, end := rng.Start.Byte, rng.End.Byte
	if start < 0 || end > len(w.src) || start > end {
		return ""
	}
	return string(w.src[start:end])
}

func (w walker) exprs(list []hclsyntax.Expression) []node {
	out := make([]node, 0, len(list))
	for _, e := range list {
		out = append(out, w.expr(e))
	}
	return out
}

func (w walker) expr(e hclsyntax.Expression) node {
	if e == nil {
		return nil
	}

	rng := e.Range()
	kind := fmt.Sprintf("%T", e)
	kind = kind[strings.LastIndex(kind, ".")+1:]
	n := node{
		{"Kind", kind},
		{"Raw", w.raw(rng)},
		{"SrcRange", rng},
	}

	switch x := e.(type) {
	case *hclsyntax.LiteralValueExpr:
		n = append(n,
			field{"Value", literalValue(x.Val)},
			field{"ValueType", x.Val.Type().FriendlyName()},
		)

	case *hclsyntax.TemplateExpr:
		isLiteral := true
		var joined strings.Builder
		for _, part := range x.Parts {
			lit, ok := part.(*hclsyntax.LiteralValueExpr)
			if !ok || lit.Val.Type() != cty.String || !lit.Val.IsKnown() || lit.Val.IsNull() {
				isLiteral = false
				break
			}
			joined.WriteString(lit.Val.AsString())
		}
		n = append(n,
			field{"Parts", w.exprs(x.Parts)},
			field{"IsLiteral", isLiteral},
		)
		if isLiteral {
			n = append(n, field{"Value", joined.String()})
		}

	case *hclsyntax.ScopeTraversalExpr:
		n = append(n, field{"Traversal", traversalString(x.Traversal)})

	case *hclsyntax.RelativeTraversalExpr:
		n = append(n,
			field{"Source", w.expr(x.Source)},
			field{"Traversal", traversalString(x.Traversal)},
		)

	case *hclsyntax.FunctionCallExpr:
		n = append(n,
			field{"Name", x.Name},
			field{"Args", w.exprs(x.Args)},
			field{"ExpandFinal", x.ExpandFinal},
		)

	case *hclsyntax.ObjectConsExpr:
		items := make([]node, 0, len(x.Items))
		for _, item := range x.Items {
			items = append(items, node{
				{"Key", w.expr(item.KeyExpr)},
				{"Value", w.expr(item.ValueExpr)},
			})
		}
		n = append(n, field{"Items", items})

	case *hclsyntax.TupleConsExpr:
		n = append(n, field{"Exprs", w.exprs(x.Exprs)})

	case *hclsyntax.ConditionalExpr:
		n = append(n,
			field{"Condition", w.expr(x.Condition)},
			field{"TrueResult", w.expr(x.TrueResult)},
			field{"FalseResult", w.expr(x.FalseResult)},
		)

	case *hclsyntax.BinaryOpExpr:
		n = append(n,
			field{"Op", operatorSymbol(x.Op)},
			field{"LHS", w.expr(x.LHS)},
			field{"RHS", w.expr(x.RHS)},
		)

	case *hclsyntax.UnaryOpExpr:
		n = append(n,
			field{"Op", operatorSymbol(x.Op)},
			field{"Val", w.expr(x.Val)},
		)

	case *hclsyntax.IndexExpr:
		n = append(n,
			field{"Collection", w.expr(x.Collection)},
			field{"Key", w.expr(x.Key)},
		)

	case *hclsyntax.SplatExpr:
		n = append(n,
			field{"Source", w.expr(x.Source)},
			field{"Each", w.expr(x.Each)},
		)

	case *hclsyntax.ForExpr:
		n = append(n,
			field{"KeyVar", x.KeyVar},
			field{"ValVar", x.ValVar},
			field{"CollExpr", w.expr(x.CollExpr)},
			field{"KeyExpr", w.expr(x.KeyExpr)},
			field{"ValExpr", w.expr(x.ValExpr)},
			field{"CondExpr", w.expr(x.CondExpr)},
			field{"Group", x.Group},
		)

	case *hclsyntax.ParenthesesExpr:
		n = append(n, field{"Expression", w.expr(x.Expression)})

	case *hclsyntax.TemplateWrapExpr:
		n = append(n, field{"Wrapped", w.expr(x.Wrapped)})
	}

	return n
}

// literalValue returns the cty value as JSON, or null if it cannot be encoded.
func literalValue(val cty.Value) json.RawMessage {
	if val.IsNull() {
		return json.RawMessage("null")
	}
	b, err := ctyjson.Marshal(val, val.Type())
	if err != nil {
		return json.RawMessage("null")
	}
	return json.RawMessage(b)
}

// traversalString renders a traversal the way it is written in HCL,
// e.g. var.region, module.network.subnet_id, aws_instance.web[0].id.
func traversalString(t hcl.Traversal) string {
	var b strings.Builder
	for _, step := range t {
		switch s := step.(type) {
		case hcl.TraverseRoot:
			b.WriteString(s.Name)
		case hcl.TraverseAttr:
			b.WriteString(".")
			b.WriteString(s.Name)
		case hcl.TraverseIndex:
			b.WriteString("[")
			b.WriteString(indexKey(s.Key))
			b.WriteString("]")
		case hcl.TraverseSplat:
			b.WriteString("[*]")
		}
	}
	return b.String()
}

func indexKey(key cty.Value) string {
	if !key.IsKnown() || key.IsNull() {
		return "?"
	}
	switch key.Type() {
	case cty.String:
		return strconv.Quote(key.AsString())
	case cty.Number:
		return key.AsBigFloat().Text('f', -1)
	}
	b, err := ctyjson.Marshal(key, key.Type())
	if err != nil {
		return "?"
	}
	return string(b)
}

var operatorSymbols = map[*hclsyntax.Operation]string{
	hclsyntax.OpLogicalOr:          "||",
	hclsyntax.OpLogicalAnd:         "&&",
	hclsyntax.OpLogicalNot:         "!",
	hclsyntax.OpEqual:              "==",
	hclsyntax.OpNotEqual:           "!=",
	hclsyntax.OpGreaterThan:        ">",
	hclsyntax.OpGreaterThanOrEqual: ">=",
	hclsyntax.OpLessThan:           "<",
	hclsyntax.OpLessThanOrEqual:    "<=",
	hclsyntax.OpAdd:                "+",
	hclsyntax.OpSubtract:           "-",
	hclsyntax.OpMultiply:           "*",
	hclsyntax.OpDivide:             "/",
	hclsyntax.OpModulo:             "%",
	hclsyntax.OpNegate:             "-",
}

func operatorSymbol(op *hclsyntax.Operation) string {
	if s, ok := operatorSymbols[op]; ok {
		return s
	}
	return "?"
}
