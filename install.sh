#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${DEVDASH_REPO_URL:-https://github.com/ChitrakshKataria/AI-Driven-vibecoding-dev-dashbord.git}"
INSTALL_DIR="${DEVDASH_INSTALL_DIR:-$HOME/.local/bin}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--check]

Install DevDash and its command-line dependencies on macOS or WSL.

  --check   Check an existing installation without changing anything
  -h        Show this help

The command is installed in ~/.local/bin by default. Set
DEVDASH_INSTALL_DIR to use a different directory.
EOF
}

log() {
  printf '\n%s\n' "$1"
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

detect_platform() {
  case "$(uname -s)" in
    Darwin)
      PLATFORM=macos
      ;;
    Linux)
      if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
        PLATFORM=wsl
      else
        die 'this installer currently supports macOS and WSL only'
      fi
      ;;
    *)
      die "unsupported operating system: $(uname -s)"
      ;;
  esac
}

load_brew() {
  local candidate
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  for candidate in \
    /opt/homebrew/bin/brew \
    /usr/local/bin/brew \
    /home/linuxbrew/.linuxbrew/bin/brew
  do
    if [[ -x "$candidate" ]]; then
      eval "$("$candidate" shellenv)"
      return
    fi
  done
}

add_line_once() {
  local line="$1"
  local file="$2"
  touch "$file"
  if ! grep -Fqx "$line" "$file"; then
    printf '%s\n' "$line" >> "$file"
  fi
}

add_shell_line() {
  local line="$1"
  if [[ "$PLATFORM" == macos ]]; then
    add_line_once "$line" "$HOME/.zprofile"
    add_line_once "$line" "$HOME/.bash_profile"
  else
    add_line_once "$line" "$HOME/.profile"
    add_line_once "$line" "$HOME/.bashrc"
    add_line_once "$line" "$HOME/.bash_profile"
  fi
}

run_as_root() {
  if [[ "$(id -u)" == 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "sudo is required to install WSL system packages"
  fi
}

install_base_tools() {
  if [[ "$PLATFORM" == wsl ]]; then
    command -v apt-get >/dev/null 2>&1 || die 'WSL must use an Ubuntu or Debian based distribution with apt-get'
    log 'Installing WSL system packages'
    run_as_root apt-get update
    run_as_root apt-get install -y build-essential procps curl file git ca-certificates
  elif ! command -v curl >/dev/null 2>&1; then
    die 'curl is required. Install the Xcode Command Line Tools with: xcode-select --install'
  fi
}

install_homebrew() {
  load_brew
  if ! command -v brew >/dev/null 2>&1; then
    log 'Installing Homebrew'
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew
  fi
  command -v brew >/dev/null 2>&1 || die 'Homebrew installed but could not be added to PATH'

  local brew_path
  brew_path="$(command -v brew)"
  add_shell_line "eval \"\$($brew_path shellenv)\""
}

install_dependencies() {
  log 'Installing tmux, Git, lazygit and yazi'
  brew install tmux git lazygit yazi

  if ! command -v codex >/dev/null 2>&1; then
    log 'Installing Codex CLI'
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
  else
    printf 'Codex CLI is already installed.\n'
  fi

  if ! command -v claude >/dev/null 2>&1; then
    log 'Installing Claude Code'
    curl -fsSL https://claude.ai/install.sh | bash
  else
    printf 'Claude Code is already installed.\n'
  fi
}

install_devdash() {
  local source_file="$SOURCE_DIR/bin/devdash"
  if [[ ! -f "$source_file" ]]; then
    die "bin/devdash was not found. Clone $REPO_URL and run ./install.sh from that checkout"
  fi

  log "Installing devdash in $INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  install -m 755 "$source_file" "$INSTALL_DIR/devdash"
  if [[ "$INSTALL_DIR" == "$HOME/.local/bin" ]]; then
    add_shell_line 'export PATH="$HOME/.local/bin:$PATH"'
  else
    add_shell_line "export PATH=\"$INSTALL_DIR:\$PATH\""
  fi
  export PATH="$INSTALL_DIR:$HOME/.local/bin:$PATH"
}

check_installation() {
  local failed=0
  local command_name

  printf 'Platform: %s\n' "$PLATFORM"
  for command_name in git tmux lazygit yazi codex claude devdash; do
    if command -v "$command_name" >/dev/null 2>&1; then
      printf 'OK       %s\n' "$command_name"
    else
      printf 'MISSING  %s\n' "$command_name"
      failed=1
    fi
  done
  return "$failed"
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return
      ;;
    --check)
      detect_platform
      load_brew
      export PATH="$INSTALL_DIR:$HOME/.local/bin:$PATH"
      check_installation
      return
      ;;
    '')
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac

  detect_platform
  printf 'Detected %s.\n' "$PLATFORM"
  export PATH="$INSTALL_DIR:$HOME/.local/bin:$PATH"
  install_base_tools
  install_homebrew
  install_dependencies
  install_devdash

  log 'Checking the installation'
  check_installation
  printf '\nInstallation complete. Restart your terminal, then run devdash inside a project.\n'
}

main "$@"
