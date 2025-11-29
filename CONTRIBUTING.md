# Contributing to ProtonDrive Linux

First off, thank you for considering contributing to ProtonDrive Linux! It's people like you that make open source such a great community. Every contribution is appreciated, from reporting a bug to submitting a feature request or writing code.

## Code of Conduct

This project and everyone participating in it is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project's maintainers by opening an issue on GitHub.

## How Can I Contribute?

### Reporting Bugs

- **Ensure the bug was not already reported** by searching on GitHub under [Issues](https://github.com/gemini-testing/protondrive-linux/issues).
- If you're unable to find an open issue addressing the problem, [open a new one](https://github.com/gemini-testing/protondrive-linux/issues/new). Be sure to include a **title and clear description**, as much relevant information as possible, and a **code sample** or an **executable test case** demonstrating the expected behavior that is not occurring.

### Suggesting Enhancements

- Open a new issue to suggest an enhancement. Please provide a clear description of the enhancement and its potential benefits.

### Your First Code Contribution

Unsure where to begin contributing? You can start by looking through `good first issue` and `help wanted` issues:
- [Good first issues](https://github.com/gemini-testing/protondrive-linux/labels/good%20first%20issue) - issues which should only require a few lines of code, and a test or two.
- [Help wanted issues](https://github.com/gemini-testing/protondrive-linux/labels/help%20wanted) - issues which should be a bit more involved than `good first issue` issues.

### Pull Requests

1.  **Fork the repository** and create your branch from `main`.
2.  **Set up your development environment**:
    ```bash
    npm install
    ```
3.  **Make your changes**. Please adhere to the existing code style.
4.  **Add tests** for your changes. This is important so we don't break it in a future version.
5.  **Ensure the test suite passes**:
    ```bash
    ./scripts/run-command.sh "npm test"
    ```
6.  **Ensure your code lints and formats correctly**:
    ```bash
    npm run lint
    npm run format
    ```
7.  **Issue that pull request!**

## Styleguides

-   We use [Prettier](httpss://prettier.io/) for code formatting. Run `npm run format` to format your code.
-   We use [ESLint](httpss://eslint.org/) for linting. Run `npm run lint` to check for linting errors.

We look forward to your contributions!
