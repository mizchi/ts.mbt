# typescript.mbt justfile

# Default recipe
default: check

# Check for errors
check:
    moon check --deny-warn

# Run tests
test:
    moon test --target native

# Run tests with filter
test-filter filter:
    moon test --target native --filter '{{filter}}'

# Format code
fmt:
    moon fmt

# Generate type definitions
info:
    moon info

# Full CI check
ci: fmt check test

# Update dependencies
update:
    moon update

# Clean build artifacts
clean:
    rm -rf _build target
