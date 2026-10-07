# The Go HCL parser as a Windows x64 c-shared DLL, cross-compiled with mingw.
# The Go toolchain is the golang image whose version matches go.mod's `go` line (1.24); keep the
# two in step. go.mod and go.sum are used as committed: nothing rewrites them in the build.
FROM golang:1.24-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends gcc-mingw-w64-x86-64 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app/src/go
COPY src/go/go.mod src/go/go.sum ./
RUN go mod download
COPY src/go/ ./

ENV CGO_ENABLED=1 \
    GOOS=windows \
    GOARCH=amd64 \
    CC=x86_64-w64-mingw32-gcc

# -buildmode=c-shared also writes TerraformGraph.h, generated from the //export lines, beside
# the DLL; BuildDLL copies both out (the header is never tracked by hand).
RUN mkdir -p /out && \
    go build -trimpath -buildmode=c-shared -o /out/TerraformGraph.dll .

# Only the two files, for `docker create` + `docker cp` in Invoke-Build BuildDLL.
FROM scratch
COPY --from=builder /out/TerraformGraph.dll /out/TerraformGraph.h /
CMD ["/TerraformGraph.dll"]
