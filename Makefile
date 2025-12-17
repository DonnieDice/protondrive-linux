.PHONY: help setup dev build build-web build-linux build-appimage build-deb build-rpm clean test fmt lint

help:
	@echo "Proton Drive Tauri - Available commands:"
	@echo ""
	@echo "Setup & Development:"
	@echo "  make setup       - Install dependencies and initialize project"
	@echo "  make dev         - Start development server with hot-reload"
	@echo ""
	@echo "Building:"
	@echo "  make build       - Build all distributions (Linux)"
	@echo "  make build-web   - Build web app only"
	@echo "  make build-linux - Build Linux distributions (AppImage, DEB, RPM)"
	@echo "  make build-appimage - Build AppImage only"
	@echo "  make build-deb   - Build DEB package only"
	@echo "  make build-rpm   - Build RPM package only"
	@echo ""
	@echo "Development:"
	@echo "  make fmt         - Format code (Rust)"
	@echo "  make lint        - Lint code (Rust)"
	@echo "  make test        - Run tests"
	@echo "  make clean       - Clean build artifacts"

setup:
	bash scripts/setup.sh

dev:
	npm run dev

build: build-web
	npm run build

build-web:
	npm run build:web

build-linux: build-web
	npm run build

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

test:
	cd WebClients/applications/drive && npm test

clean:
	rm -rf src-tauri/target
	rm -rf WebClients/applications/drive/build
	rm -rf node_modules
