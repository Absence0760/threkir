# Multi-stage build. Final image is distroless static so there's no
# shell, no package manager, no glibc — just the binary. CGO is off
# so the build is fully static and portable across distros.

# Pinned by digest (in addition to tag) to satisfy OpenSSF Scorecard
# PinnedDependenciesID — bumping the tag without re-pinning the
# digest no-ops the pin, so resolve the new digest with
# `docker manifest inspect golang:<tag>` when bumping.
FROM golang:1.27-alpine@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414 AS build
WORKDIR /src

# Cache go.mod / go.sum first so dependency-only changes don't
# invalidate the source layer.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/job_worker .

# Debian 13, not 12: bookworm is in LTS, and its data packages trail
# trixie's — on 2026-09-28 the newest static-debian12 still shipped tzdata
# 2026b (Trivy DLA-4792-1) while static-debian13 carried 2026c. The binary
# is static, so the base supplies only ca-certificates, tzdata and the
# nonroot user.
FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3
COPY --from=build /out/job_worker /job_worker

# slog JSON logs go to stdout. No HTTP listener — the worker is
# pure outbound, so no EXPOSE.
USER nonroot:nonroot
ENTRYPOINT ["/job_worker"]
