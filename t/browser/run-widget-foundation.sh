#!/bin/sh
# Install the dev-only Foundation widget fixture for this browser test, then
# remove it again so no test route is present in the tracked application tree.
set -eu

fixture_dir="$LJHOME/t/browser/fixtures"
controller_dir="$LJHOME/cgi-bin/DW/Controller/Test"
template_dir="$LJHOME/views/test"
controller="$controller_dir/WidgetFoundation.pm"
template="$template_dir/widget-foundation.tt"

# The runner owns only files it creates. Refuse to touch a pre-existing fixture
# destination, which might belong to another developer or test process.
if [ -e "$controller" ] || [ -L "$controller" ] || [ -e "$template" ] || [ -L "$template" ]; then
    echo "widget Foundation fixture destination already exists" >&2
    exit 1
fi

cleanup() {
    rm -f "$controller" "$template"
    rmdir "$controller_dir" "$template_dir" 2>/dev/null || true
    pkill starman || true
    bash "$LJHOME/.devcontainer/start.sh"
}
trap cleanup EXIT INT TERM

mkdir -p "$controller_dir" "$template_dir"
cp "$fixture_dir/WidgetFoundation.pm" "$controller"
cp "$fixture_dir/widget-foundation.tt" "$template"
pkill starman || true
bash "$LJHOME/.devcontainer/start.sh"
node "$LJHOME/t/browser/widget-foundation.js"
