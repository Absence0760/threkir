# Multi-stage build for the graph_cycle map sidecar. Final image is distroless
# static — no shell, no package manager, just the binary — exactly like
# job_worker. CGO is off so the build is fully static.
#
# Unlike the GraphHopper app next door, there is NO Caddy sidecar: this Go
# server enforces the X-Engine-Key guard in-process (internal/api/guard.go), so
# it binds the public Fly port (8989) directly and the image stays single-binary.
#
# The OSM PBF is NOT baked into the image; it lives on the mounted volume at
# /data/region.osm.pbf (operator-uploaded, the SAME extract OSRM/GraphHopper
# use) and is parsed into an in-memory foot graph on boot.

# Pinned by digest (in addition to tag) to satisfy OpenSSF Scorecard
# PinnedDependenciesID — resolve a new digest with
# `docker manifest inspect golang:<tag>` when bumping. The tag names the exact
# patch, equal to go.mod's `go` directive — scripts/check_toolchain_pins.mjs
# holds every Go module's builder to it, which is what keeps this identical to
# apps/job_worker/Dockerfile (a comment saying so did not: this file sat on
# 1.26 while that one moved to 1.27).
FROM golang:1.27.2-alpine@sha256:f92b6ef800e499660581efdabdf25d9d817a9d124eaf900924f0504e7e27e12d AS build
WORKDIR /src

# Cache go.mod / go.sum first so dependency-only changes don't invalidate the
# source layer.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/graph_cycle .

# Debian 13, not 12: bookworm is in LTS, and its data packages trail
# trixie's — on 2026-09-28 the newest static-debian12 still shipped tzdata
# 2026b (Trivy DLA-4792-1) while static-debian13 carried 2026c. The binary
# is static, so the base supplies only ca-certificates, tzdata and the
# nonroot user.
FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3
COPY --from=build /out/graph_cycle /graph_cycle

# Public guarded port (the Go server binds it; Fly's http_service forwards here).
# Health is checked by Fly over HTTP — distroless has no shell for an in-image
# HEALTHCHECK, same as job_worker.
EXPOSE 8989
USER nonroot:nonroot
ENTRYPOINT ["/graph_cycle"]
