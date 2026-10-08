#!/usr/bin/env bash
# Recommended (Bash or zsh): source ./install.sh
# Installation runs in a separate Bash process; only PATH setup is sourced.

# Keep strict mode, traps, variables and functions out of the calling shell.
# This small entry point is compatible with both Bash and zsh.
if [ -n "${ZSH_VERSION:-}" ] || [ "${BASH_SOURCE[0]}" != "$0" ]; then
  _devdash_installer_source_entry() {
    local devdash_script devdash_status=0
    local devdash_config="${XDG_CONFIG_HOME:-$HOME/.config}/devdash"
    if [ -n "${ZSH_VERSION:-}" ]; then
      eval 'devdash_script=${(%):-%x}'
    else
      devdash_script="${BASH_SOURCE[0]}"
    fi

    DEVDASH_SOURCED=1 DEVDASH_ZDOTDIR="${ZDOTDIR:-$HOME}" \
      DEVDASH_CONFIG_DIR="$devdash_config" \
      command bash "$devdash_script" "$@" || devdash_status=$?

    if [ "$devdash_status" -eq 0 ] && [ "$#" -eq 0 ]; then
      if . "$devdash_config/env.sh"; then
        hash -r 2>/dev/null || :
        printf '\nPATH refreshed in this terminal. Run: devdash\n'
      else
        devdash_status=$?
      fi
    fi
    unset -f _devdash_installer_source_entry
    return "$devdash_status"
  }
  _devdash_installer_source_entry "$@"
  return $?
fi

set -Eeuo pipefail

REPO_URL="${DEVDASH_REPO_URL:-https://github.com/ChitrakshKataria/AI-Driven-dev-dashbord.git}"
INSTALL_DIR="${DEVDASH_INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${DEVDASH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/devdash}"
ENV_FILE="$CONFIG_DIR/env.sh"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TEMP_DIR=''
BREW_BIN=''
STEP='starting'

usage() {
  cat <<'EOF'
Usage:
  source ./install.sh       Install and refresh this terminal (Bash/zsh)
  bash ./install.sh         Install; print the command to refresh PATH
  bash ./install.sh --check Check commands without installing or editing files
  bash ./install.sh --help  Show this help

Supports macOS and Homebrew-compatible Linux, including WSL2.
Linux bootstrap: Debian/Ubuntu, Fedora/RHEL, Arch and openSUSE.
Other glibc-based distributions need Homebrew's prerequisites preinstalled.
Requires a normal user account; sudo may be requested for system packages.

DevDash: ~/.local/bin (override with exported DEVDASH_INSTALL_DIR).
Codex: npm package under ~/.local; Node.js is installed if needed.
Claude: official native installer. Neither assistant is launched during setup.
Shell integration: Bash and zsh; existing startup files are preserved.
EOF
}

log() { printf '\n==> %s\n' "$1"; }
die() { printf 'Error: %s\n' "$1" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}

on_error() {
  local status="$1" line="$2"
  trap - ERR
  printf '\nFailed while %s (line %s, exit %s).\n' "$STEP" "$line" "$status" >&2
  printf 'Fix the error above, then rerun. Completed dependencies will be reused.\n' >&2
  exit "$status"
}

trap cleanup EXIT
trap 'on_error "$?" "$LINENO"' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

prepend_path() {
  case ":${PATH:-}:" in
    *":$1:"*) ;;
    *) export PATH="$1${PATH:+:$PATH}" ;;
  esac
}

refresh_path() {
  prepend_path "$HOME/.local/bin"
  prepend_path "$INSTALL_DIR"
  hash -r
}

detect_platform() {
  case "$(uname -s)" in
    Darwin) PLATFORM=macos ;;
    Linux)
      PLATFORM=linux
      if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
        PLATFORM=wsl
      fi
      ;;
    *) die "Unsupported operating system: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64|arm64|aarch64) ;;
    *) die 'This installer requires 64-bit Intel/AMD or ARM.' ;;
  esac
}

load_brew() {
  local candidate
  if have brew; then
    BREW_BIN="$(command -v brew)"
  else
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew \
      /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
      if [[ -x "$candidate" ]]; then
        BREW_BIN="$candidate"
        break
      fi
    done
  fi
  if [[ -n "$BREW_BIN" ]]; then
    local brew_env
    brew_env="$("$BREW_BIN" shellenv bash)"
    eval "$brew_env"
  fi
  refresh_path
}

run_as_root() {
  have sudo || die 'Install sudo or ask an administrator to install the system prerequisites.'
  sudo "$@"
}

install_base_tools() {
  local tool missing=0
  if [[ "$PLATFORM" == macos ]]; then
    have curl || die 'curl is required. Install the Xcode Command Line Tools: xcode-select --install'
    return 0
  fi
  if have apk; then
    die 'Alpine/musl Linux is not supported by this Homebrew-based installer.'
  fi
  for tool in cc c++ make curl file git ps patch tar gzip; do
    have "$tool" || missing=1
  done
  if [[ "$missing" -eq 0 ]]; then
    return 0
  fi

  log 'Installing Linux prerequisites (sudo may request your password)'
  if have apt-get; then
    run_as_root apt-get update
    run_as_root apt-get install -y build-essential procps curl file git ca-certificates patch tar gzip
  elif have dnf; then
    run_as_root dnf install -y gcc gcc-c++ make procps-ng curl file git ca-certificates patch tar gzip
  elif have pacman; then
    # Use the existing package database; do not perform a system-wide upgrade
    # or refresh it alone (which could cause an Arch partial upgrade).
    run_as_root pacman -S --needed --noconfirm base-devel procps-ng curl file git ca-certificates
  elif have zypper; then
    run_as_root zypper --non-interactive install gcc gcc-c++ make procps curl file git ca-certificates patch tar gzip
  else
    die 'Install a C/C++ compiler, make, curl, file, Git, procps, patch, tar, gzip and CA certificates, then rerun.'
  fi
}

download() {
  curl --fail --location --show-error --silent \
    --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 300 \
    "$1" --output "$2"
  [[ -s "$2" ]] || die "Empty download: $1"
}

install_homebrew() {
  load_brew
  if [[ -z "$BREW_BIN" ]]; then
    log 'Installing Homebrew'
    # Cache sudo credentials before Homebrew's noninteractive install.
    if have sudo; then sudo -v; fi
    download 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' "$TEMP_DIR/homebrew.sh"
    NONINTERACTIVE=1 /bin/bash "$TEMP_DIR/homebrew.sh" </dev/null
    load_brew
  fi
  [[ -n "$BREW_BIN" ]] || die 'Homebrew was not found after installation.'
}

install_dependencies() {
  local name
  local packages=()
  for name in tmux git lazygit yazi; do
    if have "$name"; then
      printf 'Keeping existing %s: %s\n' "$name" "$(command -v "$name")"
    else
      packages+=("$name")
    fi
  done
  if [[ ${#packages[@]} -gt 0 ]]; then
    log 'Installing missing dashboard tools'
    brew install "${packages[@]}"
  fi

  STEP='installing Codex CLI'
  if have codex; then
    printf 'Keeping existing Codex CLI: %s\n' "$(command -v codex)"
  else
    log 'Installing Codex CLI without launching it'
    if ! have node || ! have npm || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' >/dev/null 2>&1; then
      brew install node
      load_brew
      if ! have npm || ! have node || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' >/dev/null 2>&1; then
        die 'Node.js 22+ and npm are needed. Check the Homebrew output for a linking conflict, resolve it, then rerun.'
      fi
    fi
    # Official npm package avoids the standalone installer's launch prompt.
    # Explicit --prefix avoids sudo and does not change the user's npm config.
    CI=1 npm install --global --prefix "$HOME/.local" \
      --no-audit --no-fund --include=optional '@openai/codex@latest' </dev/null
    refresh_path
    have codex || die 'Codex installation completed, but codex is missing from PATH.'
  fi

  STEP='installing Claude Code'
  if have claude; then
    printf 'Keeping existing Claude Code: %s\n' "$(command -v claude)"
  else
    log 'Installing Claude Code'
    download 'https://claude.ai/install.sh' "$TEMP_DIR/claude.sh"
    CI=1 bash "$TEMP_DIR/claude.sh" </dev/null
    refresh_path
    have claude || die 'Claude installation completed, but claude is missing from PATH.'
  fi
}

# Literal single-quoted shell string, including paths containing apostrophes.
shell_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

add_line_once() {
  local line="$1" file="$2"
  mkdir -p -- "$(dirname -- "$file")"
  touch -- "$file"
  if ! grep -Fqx -- "$line" "$file"; then
    # Leading newline also handles a preexisting file without a final newline.
    printf '\n%s\n' "$line" >> "$file"
  fi
}

configure_shell() {
  local quoted_env line zdotdir
  mkdir -p -- "$CONFIG_DIR"
  {
    printf '# Generated by DevDash. Source this file in Bash or zsh.\n'
    printf 'if [ -x %s ]; then\n' "$(shell_quote "$BREW_BIN")"
    printf '  eval "$(%s shellenv bash)"\nfi\n' "$(shell_quote "$BREW_BIN")"
    cat <<'EOF'
_devdash_add_path() {
  case ":${PATH:-}:" in
    *":$1:"*) ;;
    *) PATH="$1${PATH:+:$PATH}" ;;
  esac
}
EOF
    printf '_devdash_add_path %s\n' "$(shell_quote "$HOME/.local/bin")"
    printf '_devdash_add_path %s\n' "$(shell_quote "$INSTALL_DIR")"
    printf 'export PATH\nunset -f _devdash_add_path\n'
  } > "$TEMP_DIR/env.sh"
  install -m 644 "$TEMP_DIR/env.sh" "$ENV_FILE"

  quoted_env="$(shell_quote "$ENV_FILE")"
  line="if [ -r $quoted_env ]; then . $quoted_env; fi # DevDash"
  add_line_once "$line" "$HOME/.bashrc"
  add_line_once "$line" "$HOME/.profile"
  # Bash reads only the first existing login file. Do not create a new
  # .bash_profile that would prevent an existing .profile from being read.
  if [[ -f "$HOME/.bash_profile" ]]; then
    add_line_once "$line" "$HOME/.bash_profile"
  elif [[ -f "$HOME/.bash_login" ]]; then
    add_line_once "$line" "$HOME/.bash_login"
  fi
  zdotdir="${DEVDASH_ZDOTDIR:-${ZDOTDIR:-$HOME}}"
  add_line_once "$line" "$zdotdir/.zprofile"
  add_line_once "$line" "$zdotdir/.zshrc"
}

install_devdash() {
  log "Installing DevDash in $INSTALL_DIR"
  mkdir -p -- "$INSTALL_DIR"
  install -m 755 "$SOURCE_DIR/bin/devdash" "$INSTALL_DIR/devdash"
  refresh_path
}

check_installation() {
  local failed=0 name
  printf '\nPlatform: %s (%s)\n' "$PLATFORM" "$(uname -m)"
  for name in git tmux lazygit yazi codex claude devdash; do
    if ! have "$name"; then
      printf 'MISSING  %s\n' "$name"
      failed=1
      continue
    fi
    # Version checks do not launch the interactive assistants or require login.
    # DevDash has no assumed --version flag; only check its executable here.
    case "$name" in
      devdash) printf 'OK       %-8s %s\n' "$name" "$(command -v "$name")"; continue ;;
      tmux) set -- "$name" -V ;;
      *) set -- "$name" --version ;;
    esac
    if "$@" >/dev/null 2>&1; then
      printf 'OK       %-8s %s\n' "$name" "$(command -v "$name")"
    else
      printf 'BROKEN   %-8s Try: %s\n' "$name" "$*"
      failed=1
    fi
  done
  return "$failed"
}

main() {
  [[ $# -le 1 ]] || { usage >&2; exit 2; }
  case "${1:-}" in
    -h|--help) usage; return 0 ;;
    --check)
      detect_platform
      load_brew
      check_installation
      return
      ;;
    '') ;;
    *) usage >&2; exit 2 ;;
  esac

  detect_platform
  [[ -f "$SOURCE_DIR/bin/devdash" ]] || die "bin/devdash was not found. Put install.sh in the checkout of $REPO_URL, alongside the bin directory."
  [[ "$(id -u)" != 0 ]] || die 'Run as your normal user, without sudo. Only system package commands use sudo.'
  case "$INSTALL_DIR" in
    /*) ;;
    *) die 'DEVDASH_INSTALL_DIR must be an absolute path.' ;;
  esac
  case "$INSTALL_DIR$CONFIG_DIR" in
    *:*|*$'\n'*) die 'Installation/configuration paths cannot contain colons or newlines.' ;;
  esac
  [[ "$CONFIG_DIR" == /* ]] || die 'XDG_CONFIG_HOME must be an absolute path.'

  printf 'Detected %s (%s).\n' "$PLATFORM" "$(uname -m)"
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devdash-install.XXXXXX")"
  refresh_path
  STEP='installing system prerequisites'
  install_base_tools
  STEP='installing Homebrew'
  install_homebrew
  STEP='installing dashboard dependencies'
  install_dependencies
  STEP='installing DevDash'
  install_devdash
  STEP='configuring the shell'
  configure_shell
  STEP='checking the installation'
  check_installation

  printf '\nInstallation complete. No assistant was launched.\n'
  if [[ "${DEVDASH_SOURCED:-0}" != 1 ]]; then
    printf 'Refresh this terminal (Bash/zsh), then run devdash inside a project:\n  source %s\n' "$(shell_quote "$ENV_FILE")"
    printf '\nNext time, use: source ./install.sh\n'
  fi
}

main "$@"
