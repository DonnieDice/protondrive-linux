# Development Setup Guide

This guide will help new contributors and developers set up their development environment for the ProtonDrive Linux Client.

## Table of Contents

*   [Prerequisites](#prerequisites)
*   [Getting the Code](#getting-the-code)
*   [Installing Dependencies](#installing-dependencies)
*   [Running in Development Mode](#running-in-development-mode)
*   [Running Tests](#running-tests)
*   [Building Packages](#building-packages)
*   [Code Standards and Linting](#code-standards-and-linting)
*   [Troubleshooting Development Issues](#troubleshooting-development-issues)

## Prerequisites

Before you begin, ensure you have the following installed on your system:

*   **Node.js**: Version 18 or 20 (LTS recommended).
    *   You can download it from [nodejs.org](https://nodejs.org/) or use a version manager like `nvm`.
*   **npm**: Version 9+ (usually comes with Node.js).
*   **Git**: For version control.
*   **Linux Operating System**: The application is specifically designed for Linux. Development on other OSes is not officially supported.

## Getting the Code

Clone the repository from GitHub:

```bash
git clone https://github.com/donniedice/protondrive-linux.git
cd protondrive-linux
```

## Installing Dependencies

Once you have cloned the repository and navigated into the project directory, install the project dependencies:

```bash
npm install
# Or, if you prefer a clean install based on package-lock.json:
# npm ci
```

## Running in Development Mode

To start the Electron application in development mode (with hot-reloading and developer tools enabled):

```bash
./scripts/run-command.sh "npm start"
```

This will launch the Electron main process and the React renderer process.

## Running Tests

The project uses Jest for unit tests and Playwright for End-to-End (E2E) tests.

### Unit Tests

```bash
# Run all unit tests
./scripts/run-command.sh "npm test"

# Run tests with coverage report
./scripts/run-command.sh "npm test -- --coverage"

# Run specific test file
./scripts/run-command.sh "npm test -- path/to/your/test.test.ts"
```

### End-to-End (E2E) Tests

```bash
# Run E2E tests
./scripts/run-command.sh "npm run test:e2e"
```

## Building Packages

To build distributable packages for Linux (AppImage, .deb, .rpm):

```bash
# Build all packages
./scripts/run-command.sh "npm run make"

# The generated packages will be located in the `out/make/` directory.
```

## Code Standards and Linting

The project enforces strict code quality and style guidelines.

*   **ESLint**: For static code analysis and identifying problematic patterns.
    ```bash
    npm run lint
    ```
*   **Prettier**: For consistent code formatting.
    ```bash
    npm run format
    ```
Please ensure your code passes linting and formatting checks before submitting a pull request.

## Troubleshooting Development Issues

(Common development issues and their solutions will be added here.)
