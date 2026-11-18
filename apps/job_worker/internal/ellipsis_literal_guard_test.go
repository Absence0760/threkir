package internal

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// Every string a person reads writes the one-character ellipsis "…" (U+2026),
// never three full stops, which can wrap between the dots and read as three
// sentences to a screen reader (decisions § 2539, § 2556, § 2571). The worker
// renders the email, SMS, web-push and native-push copy, so this guard parses
// every non-test .go file in the module and fails a string literal holding
// "...". It reads literals, not lines, so a variadic spread (`chunk...`) and a
// comment never match.
//
// Excused, because no reader sees them:
//   - struct field tags;
//   - literals inside fmt.Errorf / errors.New, which reach logs, never copy;
//   - literals inside a logger call (.Debug / .Info / .Warn / .Error and their
//     Context forms).

var ellipsisExcusedCalls = map[string]bool{
	"Errorf": true, "New": true,
	"Debug": true, "Info": true, "Warn": true, "Error": true,
	"DebugContext": true, "InfoContext": true, "WarnContext": true, "ErrorContext": true,
}

func ellipsisOffenders(t *testing.T, fset *token.FileSet, file *ast.File) []string {
	t.Helper()
	var out []string
	var walk func(n ast.Node) bool
	walk = func(n ast.Node) bool {
		switch v := n.(type) {
		case *ast.Field:
			if v.Tag != nil {
				ast.Inspect(v.Type, walk)
				return false
			}
		case *ast.ImportSpec:
			return false
		case *ast.CallExpr:
			if sel, ok := v.Fun.(*ast.SelectorExpr); ok && ellipsisExcusedCalls[sel.Sel.Name] {
				return false
			}
		case *ast.BasicLit:
			if v.Kind != token.STRING {
				return true
			}
			s, err := strconv.Unquote(v.Value)
			if err != nil {
				s = v.Value
			}
			if strings.Contains(s, "...") {
				out = append(out, fset.Position(v.Pos()).String()+": "+v.Value)
			}
		}
		return true
	}
	ast.Inspect(file, walk)
	return out
}

func ellipsisOffendersInSource(t *testing.T, src string) []string {
	t.Helper()
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "planted.go", src, 0)
	if err != nil {
		t.Fatalf("parse planted source: %v", err)
	}
	return ellipsisOffenders(t, fset, f)
}

func TestUserFacingLiterals_WriteTheOneCharacterEllipsis(t *testing.T) {
	fset := token.NewFileSet()
	files := 0
	var offenders []string
	err := filepath.WalkDir("..", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		f, err := parser.ParseFile(fset, path, nil, 0)
		if err != nil {
			return err
		}
		files++
		offenders = append(offenders, ellipsisOffenders(t, fset, f)...)
		return nil
	})
	if err != nil {
		t.Fatalf("walk the module: %v", err)
	}
	if files < 50 {
		t.Fatalf("found only %d .go files; the walk is not reading the module", files)
	}
	for _, o := range offenders {
		t.Errorf("write \"…\", not three full stops: %s", o)
	}
}

func TestEllipsisGuard_CatchesTheSlipsItExistsFor(t *testing.T) {
	cases := []struct {
		src  string
		want int
	}{
		{`package p; var s = "Loading..."`, 1},
		{"package p; var s = `読み込み中...`", 1},
		{`package p; var s = map[string]string{"ja": "送信中..."}`, 1},
		{`package p; var s = "Loading…"`, 0},
		{`package p; func f(a []int, b []int) { _ = append(a, b...) }`, 0},
		{`package p; // see the docs...` + "\nvar s = 1", 0},
		{`package p; import "errors"; var e = errors.New("bad input...")`, 0},
		{`package p; import "fmt"; func f() error { return fmt.Errorf("read %s...", "x") }`, 0},
		{`package p; func f(l interface{ Info(string, ...any) }) { l.Info("draining...") }`, 0},
		{"package p; type T struct { A string `json:\"a,omitempty\" x:\"...\"` }", 0},
	}
	for _, c := range cases {
		if got := len(ellipsisOffendersInSource(t, c.src)); got != c.want {
			t.Errorf("%d offenders, want %d, in %s", got, c.want, c.src)
		}
	}
}
