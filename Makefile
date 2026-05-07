.PHONY: help dev build build-web build-appimage build-deb build-rpm clean fmt lint

help:
	@echo "Proton Drive Linux - Available commands:"
	@echo ""
	@echo "Building:"
	@echo " make build          - Build all distributions"
	@echo " make build-web      - Build web app only"
	@echo " make build-appimage - Build AppImage only"
	@echo " make build-deb      - Build DEB package only"
	@echo " make build-rpm      - Build RPM package only"
	@echo ""
	@echo "Development:"
	@echo " make dev  - Start development server"
	@echo " make fmt  - Format code (Rust)"
	@echo " make lint - Lint code (Rust)"
	@echo " make clean - Clean build artifacts"

dev:
	npm run dev

build: build-web
	npm run build

build-web:
	npm run build:web

build-appimage: build-web
	npm run build:appimage

build-deb: build-web
	npm run build:deb

build-rpm: build-web
	npm run build:rpm

fmt:
	cd src-tauri && cargo fmt

lint:
	cd src-tauri && cargo clippy -- -D warnings

clean:
	rm -rf src-tauri/target
	rm -rf WebClients
	rm -rf node_modules
