#!/bin/sh
# Snapparazzi installer
#
#   curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh | sh
#
# Environment overrides:
#   SNAPPARAZZI_BIN=<dir>  install location (default: $HOME/.local/bin)
#   SNAPPARAZZI_REF=<ref>  git branch, tag, or commit to install (default: main)

set -eu

REPO="RayChang/snapparazzi"
REF="${SNAPPARAZZI_REF:-main}"
BIN_DIR="${SNAPPARAZZI_BIN:-$HOME/.local/bin}"
ARCHIVE_URL="https://codeload.github.com/$REPO/tar.gz/$REF"
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

# Branch, tag, or SHA characters only; it becomes part of the download URL.
valid_ref() {
  case "$1" in
    "" | -* | /* | */ | *//* | *..*) return 1 ;;
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  return 0
}

trap cleanup EXIT HUP INT TERM

[ "$(uname -s)" = "Darwin" ] || fail "Snapparazzi requires macOS / Snapparazzi 僅支援 macOS"
valid_ref "$REF" || fail "invalid SNAPPARAZZI_REF: $REF / SNAPPARAZZI_REF 格式無效"
have curl || fail "curl is required / 需要 curl"
have tar || fail "tar is required / 需要 tar"
have make || fail "make is required. Run 'xcode-select --install' first. / 需要 make，請先執行 'xcode-select --install'。"
have install || fail "install is required / 需要 install"

if have xcrun && xcrun -f swiftc >/dev/null 2>&1; then
  swift_compiler="xcrun -sdk macosx swiftc"
elif have swiftc; then
  swift_compiler="$(command -v swiftc)"
else
  fail "Swift compiler not found. Run 'xcode-select --install' first. / 找不到 Swift compiler，請先執行 'xcode-select --install'。"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/snapparazzi.XXXXXX")" || fail "cannot create temporary directory"
archive="$tmp_dir/source.tar.gz"
source_dir="$tmp_dir/source"
built_binary="$source_dir/.build/snapparazzi"

say "Downloading Snapparazzi source ($REF)…"
curl -fsSL "$ARCHIVE_URL" -o "$archive" || \
  fail "cannot download $ARCHIVE_URL (bad SNAPPARAZZI_REF?) / 無法下載原始碼"
members="$(tar -tzf "$archive")" || fail "downloaded archive is not readable / 原始碼壓縮檔無法讀取"
if printf '%s\n' "$members" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  fail "archive contains unsafe paths / 原始碼壓縮檔含有不安全的路徑"
fi
mkdir "$source_dir"
tar -xzf "$archive" -C "$source_dir" --strip-components 1 || fail "cannot extract source archive / 無法解壓原始碼"
[ -f "$source_dir/Makefile" ] && [ -f "$source_dir/Sources/Snapparazzi/main.swift" ] || \
  fail "downloaded source does not look like Snapparazzi (bad SNAPPARAZZI_REF?)"

say "Building native macOS executable…"
make -C "$source_dir" build SWIFTC="$swift_compiler" >/dev/null || \
  fail "build failed / 編譯失敗"
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
