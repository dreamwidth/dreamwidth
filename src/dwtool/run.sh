#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BINARY="$SCRIPT_DIR/dwtool"
MIN_GO_VERSION="1.23"

# --- Dependency checks ---

check_go() {
    if ! command -v go &>/dev/null; then
        echo "ERROR: Go is not installed."
        echo "  Install: https://go.dev/dl/ or 'brew install go'"
        return 1
    fi

    local ver
    ver=$(go version | grep -oE 'go[0-9]+\.[0-9]+' | sed 's/go//')
    local major minor
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)

    if (( major < 1 || (major == 1 && minor < 23) )); then
        echo "ERROR: Go >= $MIN_GO_VERSION required (found $ver)"
        return 1
    fi
}

check_gh() {
    if ! command -v gh &>/dev/null; then
        echo "WARNING: 'gh' CLI not found. Deploy functionality will not work."
        echo "  Install: https://cli.github.com/"
        return 0
    fi
    if ! gh auth status &>/dev/null; then
        echo "WARNING: 'gh' CLI not authenticated. Run 'gh auth login' for deploy support."
    fi
}

check_session_manager() {
    if ! command -v session-manager-plugin &>/dev/null; then
        echo "WARNING: 'session-manager-plugin' not found. Shell access will not work."
        echo "  Install: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
    fi
}

check_aws_creds() {
    if ! aws sts get-caller-identity &>/dev/null 2>&1; then
        if [[ -z "${AWS_ACCESS_KEY_ID:-}" && -z "${AWS_PROFILE:-}" && ! -f "${HOME}/.aws/credentials" ]]; then
            echo "WARNING: No AWS credentials detected. Configure via env vars, ~/.aws/credentials, or 'aws sso login'."
        fi
    fi
}

# --- Main ---

errors=0

check_go || errors=1

if (( errors )); then
    echo "Fix required dependencies above and retry."
    exit 1
fi

check_gh
check_session_manager
check_aws_creds

# Build
echo "Building dwtool..."
go build -o "$BINARY" .
echo "Build OK"

# Run, passing all arguments through
exec "$BINARY" "$@"
