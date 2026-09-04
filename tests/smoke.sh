#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devdash-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

make_command() {
  local name="$1"
  cat > "$TEST_DIR/bin/$name" <<EOF
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$TEST_DIR/bin/$name"
}

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home" "$TEST_DIR/project"

for name in git lazygit yazi codex claude devdash brew sudo apt-get; do
  make_command "$name"
done

cat > "$TEST_DIR/bin/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DEVDASH_TMUX_LOG"
case "$1" in
  has-session)
    exit 1
    ;;
  new-session)
    printf '%%1\n'
    ;;
  split-window)
    count_file="${DEVDASH_TMUX_LOG}.count"
    count=1
    [[ -f "$count_file" ]] && count="$(cat "$count_file")"
    count=$((count + 1))
    printf '%s' "$count" > "$count_file"
    printf '%%%s\n' "$count"
    ;;
esac
EOF
chmod +x "$TEST_DIR/bin/tmux"

cat > "$TEST_DIR/bin/tput" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  cols) printf '160\n' ;;
  lines) printf '45\n' ;;
esac
EOF
chmod +x "$TEST_DIR/bin/tput"

bash -n "$ROOT_DIR/bin/devdash"
bash -n "$ROOT_DIR/install.sh"

help_output="$("$ROOT_DIR/bin/devdash" --help)"
[[ "$help_output" == *'Usage: devdash [PROJECT]'* ]] || fail 'devdash help is missing'

export DEVDASH_TMUX_LOG="$TEST_DIR/tmux.log"
TMUX= PATH="$TEST_DIR/bin:/usr/bin:/bin" "$ROOT_DIR/bin/devdash" "$TEST_DIR/project"
grep -q 'new-session' "$DEVDASH_TMUX_LOG" || fail 'tmux session was not created'
grep -q 'attach-session' "$DEVDASH_TMUX_LOG" || fail 'tmux session was not attached'

printf '{"scripts":{"dev":"vite"}}\n' > "$TEST_DIR/project/package.json"
touch "$TEST_DIR/project/pnpm-lock.yaml"
: > "$DEVDASH_TMUX_LOG"
TMUX= PATH="$TEST_DIR/bin:/usr/bin:/bin" "$ROOT_DIR/bin/devdash" "$TEST_DIR/project"
grep -q 'pnpm dev' "$DEVDASH_TMUX_LOG" || fail 'pnpm project was not detected'

cat > "$TEST_DIR/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${TEST_UNAME:-Darwin}"
EOF
chmod +x "$TEST_DIR/bin/uname"

mac_output="$(HOME="$TEST_DIR/home" TEST_UNAME=Darwin PATH="$TEST_DIR/bin:/usr/bin:/bin" "$ROOT_DIR/install.sh" --check)"
[[ "$mac_output" == *'Platform: macos'* ]] || fail 'macOS detection failed'

wsl_output="$(HOME="$TEST_DIR/home" TEST_UNAME=Linux WSL_DISTRO_NAME=Ubuntu PATH="$TEST_DIR/bin:/usr/bin:/bin" "$ROOT_DIR/install.sh" --check)"
[[ "$wsl_output" == *'Platform: wsl'* ]] || fail 'WSL detection failed'

HOME="$TEST_DIR/home" \
TEST_UNAME=Darwin \
DEVDASH_INSTALL_DIR="$TEST_DIR/mac-bin" \
PATH="$TEST_DIR/bin:/usr/bin:/bin" \
  "$ROOT_DIR/install.sh" >/dev/null
[[ -x "$TEST_DIR/mac-bin/devdash" ]] || fail 'macOS install did not create devdash'
grep -q "$TEST_DIR/mac-bin" "$TEST_DIR/home/.zprofile" || fail 'macOS PATH was not configured'

HOME="$TEST_DIR/home" \
TEST_UNAME=Linux \
WSL_DISTRO_NAME=Ubuntu \
DEVDASH_INSTALL_DIR="$TEST_DIR/wsl-bin" \
PATH="$TEST_DIR/bin:/usr/bin:/bin" \
  "$ROOT_DIR/install.sh" >/dev/null
[[ -x "$TEST_DIR/wsl-bin/devdash" ]] || fail 'WSL install did not create devdash'
grep -q "$TEST_DIR/wsl-bin" "$TEST_DIR/home/.bashrc" || fail 'WSL PATH was not configured'

printf 'All smoke tests passed.\n'
