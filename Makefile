dev_build_version=$(shell git describe --tags --always --dirty)

export PATH := $(shell pwd)/.tmp/protoc/bin:$(PATH)
export PROTOC_VERSION := 22.0
# Disable CGO for improved compatibility across distros
export CGO_ENABLED=0
export GOFLAGS=-trimpath
export GOWORK=off

# TODO: run golint and errcheck, but only to catch *new* violations and
# decide whether to change code or not (e.g. we need to be able to whitelist
# violations already in the code). They can be useful to catch errors, but
# they are just too noisy to be a requirement for a CI -- we don't even *want*
# to fix some of the things they consider to be violations.
.PHONY: ci
ci: deps checkgofmt checkgenerate vet staticcheck ineffassign predeclared test

.PHONY: deps
deps:
	go get -d -v -t ./...
	go mod tidy

.PHONY: updatedeps
updatedeps:
	go get -d -v -t -u -f ./...
	go mod tidy

.PHONY: install
install:
	go install -ldflags '-X "main.version=dev build $(dev_build_version)"' ./...

.PHONY: release
release:
	@go install github.com/goreleaser/goreleaser@v1.21.0
	goreleaser release --clean

.PHONY: docker
docker:
	@echo $(dev_build_version) > VERSION
	docker build -t fullstorydev/grpcurl:$(dev_build_version) .
	@rm VERSION

.PHONY: generate
generate: .tmp/protoc/bin/protoc
	@go install google.golang.org/protobuf/cmd/protoc-gen-go@a709e31e5d12
	@go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.1.0
	@go install github.com/jhump/protoreflect/desc/sourceinfo/cmd/protoc-gen-gosrcinfo@v1.14.1
	go generate ./...
	go mod tidy

.PHONY: checkgenerate
checkgenerate: generate
	git status --porcelain -- '**/*.go'
	@if [ -n "$$(git status --porcelain -- '**/*.go')" ]; then \
		git diff -- '**/*.go'; \
		exit 1; \
	fi

.PHONY: checkgofmt
checkgofmt:
	gofmt -s -l .
	@if [ -n "$$(gofmt -s -l .)" ]; then \
		exit 1; \
	fi

.PHONY: vet
vet:
	go vet ./...

.PHONY: staticcheck
staticcheck:
	@go install honnef.co/go/tools/cmd/staticcheck@2025.1.1
	staticcheck -checks "inherit,-SA1019" ./...

.PHONY: ineffassign
ineffassign:
	@go install github.com/gordonklaus/ineffassign@7953dde2c7bf
	ineffassign .

.PHONY: predeclared
predeclared:
	@go install github.com/nishanths/predeclared@51e8c974458a0f93dc03fe356f91ae1a6d791e6f
	predeclared ./...

# Intentionally omitted from CI, but target here for ad-hoc reports.
.PHONY: golint
golint:
	@go install golang.org/x/lint/golint@v0.0.0-20210508222113-6edffad5e616
	golint -min_confidence 0.9 -set_exit_status ./...

# Intentionally omitted from CI, but target here for ad-hoc reports.
.PHONY: errcheck
errcheck:
	@go install github.com/kisielk/errcheck@v1.2.0
	errcheck ./...

.PHONY: test
test: deps
	CGO_ENABLED=1 go test -race ./...

.tmp/protoc/bin/protoc: ./Makefile ./download_protoc.sh
	./download_protoc.sh

