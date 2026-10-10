module github.com/Absence0760/threkir/apps/job_worker

// Patch-level floor, not a bare `go 1.27`: the stdlib CVEs Trivy raised
// against 1.27.1 (CVE-2026-78667, -78669, -97031 and ten more) are fixed in
// 1.27.2, and CI resolves its toolchain from this line. Each module's
// Dockerfile builder must name this exact version — check_toolchain_pins.mjs
// fails the PR otherwise, so the shipped binary and the tested one agree.
go 1.27.2

require (
	github.com/alicebob/miniredis/v2 v2.39.0
	github.com/coder/websocket v1.8.15
	github.com/golang-jwt/jwt/v5 v5.3.1
	github.com/redis/go-redis/v9 v9.22.0
	golang.org/x/image v0.46.0
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/yuin/gopher-lua v1.1.1 // indirect
	go.uber.org/atomic v1.11.0 // indirect
	golang.org/x/sys v0.48.0 // indirect
)
