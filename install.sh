#!/bin/sh
# Snapparazzi installer
#
#   curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh | sh
#
# Environment overrides:
#   SNAPPARAZZI_BIN=<dir>  install location (default: $HOME/.local/bin)
#   SNAPPARAZZI_REF=<ref>  git branch or tag to install (default: main)

set -eu

REPO="RayChang/snapparazzi"
REF="${SNAPPARAZZI_REF:-main}"
BIN_DIR="${SNAPPARAZZI_BIN:-$HOME/.local/bin}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"
tmp_dir=""
staged_binary=""

say() {
  printf '%s\n' "$*"
}

fail() {
  printf 'install: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

cleanup() {
  if [ -n "$staged_binary" ] && [ -f "$staged_binary" ]; then
    rm -f "$staged_binary"
  fi
  if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
}

trap cleanup EXIT HUP INT TERM

[ "$(uname -s)" = "Darwin" ] || fail "Snapparazzi requires macOS / Snapparazzi 僅支援 macOS"
have curl || fail "curl is required / 需要 curl"
have install || fail "install is required / 需要 install"

use_xcrun=0
swiftc_path=""
if have xcrun && xcrun -f swiftc >/dev/null 2>&1; then
  use_xcrun=1
elif have swiftc; then
  swiftc_path="$(command -v swiftc)"
else
  fail "Swift compiler not found. Run 'xcode-select --install' first. / 找不到 Swift compiler，請先執行 'xcode-select --install'。"
fi

compile() {
  if [ "$use_xcrun" -eq 1 ]; then
    xcrun -sdk macosx swiftc "$@"
  else
    "$swiftc_path" "$@"
  fi
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/snapparazzi.XXXXXX")" || fail "cannot create temporary directory"
source_file="$tmp_dir/main.swift"
built_binary="$tmp_dir/snapparazzi"

say "Downloading Snapparazzi source ($REF)…"
curl -fsSL "$RAW/Sources/Snapparazzi/main.swift" -o "$source_file"
grep -q 'private let snapparazziVersion' "$source_file" || \
  fail "downloaded file does not look like Snapparazzi (bad SNAPPARAZZI_REF?)"

say "Building native macOS executable…"
compile \
  -emit-executable \
  -O \
  -whole-module-optimization \
  -warnings-as-errors \
  "$source_file" \
  -o "$built_binary"
"$built_binary" --version >/dev/null

mkdir -p "$BIN_DIR"
staged_binary="$BIN_DIR/.snapparazzi.install.$$"
install -m 0755 "$built_binary" "$staged_binary"
mv -f "$staged_binary" "$BIN_DIR/snapparazzi"
staged_binary=""

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    bin_display="$(printf '%s' "$BIN_DIR" | sed "s|^$HOME|\$HOME|")"
    case "$(basename "${SHELL:-sh}")" in
      zsh)
        rc_file="$HOME/.zshrc"
        path_line="export PATH=\"$bin_display:\$PATH\""
        ;;
      bash)
        rc_file="$HOME/.bash_profile"
        path_line="export PATH=\"$bin_display:\$PATH\""
        ;;
      fish)
        rc_file="$HOME/.config/fish/config.fish"
        path_line="set -gx PATH \"$bin_display\" \$PATH"
        ;;
      *)
        rc_file="$HOME/.profile"
        path_line="export PATH=\"$bin_display:\$PATH\""
        ;;
    esac

    mkdir -p "$(dirname "$rc_file")"
    if ! grep -qsF "$path_line" "$rc_file"; then
      printf '\n# added by Snapparazzi installer\n%s\n' "$path_line" >> "$rc_file"
    fi
    say "Added $bin_display to PATH in $rc_file; open a new terminal to use it."
    ;;
esac

say ""
say "Snapparazzi installed / 安裝完成: $BIN_DIR/snapparazzi"
say "Run / 執行: snapparazzi"
say "Help / 說明: snapparazzi --help"
