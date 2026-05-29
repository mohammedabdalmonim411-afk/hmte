# Contributing to HTE (Hermes Team Engine)

Thank you for your interest in contributing to HTE (Hermes Team Engine)! We welcome contributions from the community.

## How to Contribute

### Reporting Bugs

If you find a bug, please open an issue on GitHub with:
- A clear, descriptive title
- Steps to reproduce the issue
- Expected behavior vs actual behavior
- Your environment (OS, Python version, Bash version, etc.)
- Any relevant logs or screenshots

### Suggesting Enhancements

We welcome feature requests! Please open an issue with:
- A clear description of the feature
- Use cases and benefits
- Any implementation ideas you have

### Submitting Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** following our code standards
3. **Test your changes** thoroughly
4. **Update documentation** if needed
5. **Commit your changes** with clear, descriptive messages
6. **Push to your fork** and submit a pull request

#### Pull Request Guidelines

- Keep PRs focused on a single feature or fix
- Write clear commit messages
- Include tests for new functionality
- Update relevant documentation
- Ensure all tests pass
- Follow the existing code style

## Code Standards

### Shell Scripts
- Follow POSIX shell conventions where possible
- Use `set -euo pipefail` for error handling
- Add comments for complex logic
- Use meaningful variable names (UPPER_CASE for constants)
- Test scripts on both Linux and macOS

### Python Scripts
- Follow PEP 8 style guide
- Use type hints where appropriate
- Add docstrings for functions
- Handle errors gracefully
- Use `filelock` for cross-platform file locking

### Documentation
- Use clear, concise language
- Include code examples
- Keep README.md up to date
- Document breaking changes in CHANGELOG.md

## Development Setup

```bash
# Clone the repository
git clone https://github.com/mohammedabdalmonim411-afk/hmte.git
cd hmte

# Install Python dependencies
pip install -r requirements.txt

# Run the installation script
./install-to-hermes.sh

# Run core workflow tests
bash scripts/e2e-core-workflow-test.sh

# Run anti-fake guarantee tests
bash scripts/e2e-anti-fake-test.sh
```

## Testing

```bash
# Run core workflow tests
bash scripts/e2e-core-workflow-test.sh

# Run anti-fake guarantee tests
bash scripts/e2e-anti-fake-test.sh

# Test individual scripts
bash -n scripts/hmte-start.sh  # Syntax check
python -m py_compile src/skills/hmte/scripts/write_state.py

# Test installation
./install-to-hermes.sh --force
```

## Code Review Process

All submissions require review. We use GitHub pull requests for this purpose. The maintainers will review your PR and may request changes before merging.

## Community

- Be respectful and inclusive
- Follow our [Code of Conduct](CODE_OF_CONDUCT.md)
- Help others in discussions and issues

## Questions?

Feel free to open an issue for any questions about contributing!

Thank you for contributing to HTE! 🚀
