#!/bin/sh
# Clust installer for macOS and Linux (and Git Bash on Windows, which it hands to install.ps1).
#
#   curl -fsSL https://raw.githubusercontent.com/YuriAlvesBordin/clust-releases/main/install.sh | sh
#
# Downloads the newest signed release for this machine, checks its ed25519 signature with the
# same key `clust update` uses, installs it to ~/.local/bin and puts that folder on PATH.
#
# Settings (environment variables):
#   CLUST_VERSION       a release tag such as v0.1.4 (default: the latest release)
#   CLUST_INSTALL_DIR   where the binary goes (default: ~/.local/bin)
#   CLUST_NO_MODIFY_PATH=1   never edit shell profiles
set -eu

REPO="YuriAlvesBordin/clust-releases"
# Public half of the release signing key: the same 32 bytes as UPDATE_PUBLIC_KEY in clust.
PUBKEY_PEM="-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA2I6WyDrts1PYmDy5L8lbWF2+rHq+3+N4tVdO0/e0GeU=
-----END PUBLIC KEY-----"

say() { printf '%s\n' "clust: $*"; }
fail() {
    printf '%s\n' "clust: error: $*" >&2
    exit 1
}

download() {
    # $1 url, $2 output file
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        fail "needs curl or wget to download"
    fi
}

target() {
    os=$(uname -s)
    arch=$(uname -m)
    case "$arch" in
        x86_64 | amd64) arch=x86_64 ;;
        arm64 | aarch64) arch=aarch64 ;;
        *) fail "no build for this processor ($arch). Builds exist for x86_64 and arm64." ;;
    esac
    case "$os" in
        Darwin)
            # a shell running under Rosetta reports x86_64 on an Apple Silicon Mac
            if [ "$arch" = x86_64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
                arch=aarch64
            fi
            echo "$arch-apple-darwin"
            ;;
        Linux)
            if [ "$(uname -o 2>/dev/null || true)" = Android ]; then
                fail "no Android (Termux) build yet"
            fi
            if [ "$arch" = aarch64 ]; then
                echo "aarch64-unknown-linux-gnu"
            elif getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
                echo "x86_64-unknown-linux-gnu"
            else
                # Alpine and other systems without glibc get the static build
                echo "x86_64-unknown-linux-musl"
            fi
            ;;
        *) fail "no build for $os. On Windows, run in PowerShell: irm https://raw.githubusercontent.com/$REPO/main/install.ps1 | iex" ;;
    esac
}

# Returns 0 if the signature is good, 1 if it is bad, 2 if this machine cannot check it.
verify() {
    # $1 binary, $2 signature file (url-safe base64, no padding)
    command -v openssl >/dev/null 2>&1 || return 2
    # ed25519 needs OpenSSL 3; macOS ships LibreSSL, which cannot do it
    case "$(openssl version 2>/dev/null)" in
        "OpenSSL 3"* | "OpenSSL 4"*) ;;
        *) return 2 ;;
    esac
    printf '%s\n' "$PUBKEY_PEM" >"$tmp/key.pem"
    sig=$(tr -d ' \r\n' <"$2" | tr '_-' '/+')
    case $((${#sig} % 4)) in
        2) sig="$sig==" ;;
        3) sig="$sig=" ;;
    esac
    printf '%s' "$sig" | openssl base64 -d -A >"$tmp/sig.bin" 2>/dev/null || return 1
    if openssl pkeyutl -verify -pubin -inkey "$tmp/key.pem" -rawin -in "$1" -sigfile "$tmp/sig.bin" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# The shell profile to put the PATH line in, and the line itself.
profile_line() {
    dir=$1
    case "$(basename "${SHELL:-sh}")" in
        zsh) echo "${ZDOTDIR:-$HOME}/.zshrc|export PATH=\"$dir:\$PATH\"" ;;
        bash)
            if [ "$(uname -s)" = Darwin ]; then
                echo "$HOME/.bash_profile|export PATH=\"$dir:\$PATH\""
            else
                echo "$HOME/.bashrc|export PATH=\"$dir:\$PATH\""
            fi
            ;;
        fish) echo "$HOME/.config/fish/config.fish|fish_add_path $dir" ;;
        *) echo "$HOME/.profile|export PATH=\"$dir:\$PATH\"" ;;
    esac
}

main() {
    case "$(uname -s)" in
        MINGW* | MSYS* | CYGWIN*)
            say "Windows detected: installing with PowerShell"
            exec powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/$REPO/main/install.ps1 | iex"
            ;;
    esac

    t=$(target)
    file="clust-$t"
    if [ -n "${CLUST_VERSION:-}" ]; then
        base="https://github.com/$REPO/releases/download/$CLUST_VERSION"
    else
        base="https://github.com/$REPO/releases/latest/download"
    fi
    dir="${CLUST_INSTALL_DIR:-$HOME/.local/bin}"

    tmp=$(mktemp -d 2>/dev/null || mktemp -d -t clust)
    trap 'rm -rf "$tmp"' EXIT INT TERM

    say "downloading $file ${CLUST_VERSION:-(latest)}"
    download "$base/$file" "$tmp/clust" || fail "download failed: $base/$file"
    download "$base/$file.sig" "$tmp/clust.sig" || fail "download failed: $base/$file.sig"

    set +e
    verify "$tmp/clust" "$tmp/clust.sig"
    v=$?
    set -e
    case $v in
        0) say "signature verified" ;;
        1) fail "the signature does not match: the download is damaged or was tampered with. Nothing was installed." ;;
        *) say "warning: cannot check the signature here (needs OpenSSL 3); trusting the HTTPS download from GitHub" ;;
    esac

    chmod +x "$tmp/clust"
    mkdir -p "$dir"
    # move, not copy: replaces the file even while an older clust is running
    mv -f "$tmp/clust" "$dir/clust"
    say "installed $dir/clust"

    case ":$PATH:" in
        *":$dir:"*) ;;
        *)
            if [ "${CLUST_NO_MODIFY_PATH:-0}" = 1 ]; then
                say "add $dir to your PATH to run clust from anywhere"
            else
                pl=$(profile_line "$dir")
                profile=${pl%%|*}
                line=${pl#*|}
                mkdir -p "$(dirname "$profile")"
                if ! grep -qsF "$dir" "$profile"; then
                    printf '\n# added by the clust installer\n%s\n' "$line" >>"$profile"
                    say "added $dir to PATH in $profile (open a new terminal to use it)"
                fi
            fi
            ;;
    esac

    other=$(command -v clust 2>/dev/null || true)
    if [ -n "$other" ] && [ "$other" != "$dir/clust" ]; then
        say "note: another clust at $other comes first on your PATH"
    fi

    "$dir/clust" --version 2>/dev/null || true
    say "done. Run: clust login"
}

main "$@"
