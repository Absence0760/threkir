module github.com/Absence0760/threkir/apps/graph_cycle

// Patch-level floor, not a bare `go 1.27`: the stdlib CVEs Trivy raised
// against 1.27.1 (CVE-2026-78667, -78669, -97031 and ten more) are fixed in
// 1.27.2, and CI resolves its toolchain from this line. Each module's
// Dockerfile builder must name this exact version — check_toolchain_pins.mjs
// fails the PR otherwise, so the shipped binary and the tested one agree.
go 1.27.2

require github.com/paulmach/osm v0.9.0

require (
	github.com/DataDog/czlib v0.0.0-20240814115052-86a9592b3985 // indirect
	github.com/paulmach/orb v0.12.0 // indirect
	github.com/paulmach/protoscan v0.2.1 // indirect
	go.mongodb.org/mongo-driver v1.17.7 // indirect
	google.golang.org/protobuf v1.36.10 // indirect
)
