#!/bin/sh
set -eu

ZIG_CHANNEL="${ZIG_CHANNEL:-master}"
ZIG_TARGET="${ZIG_TARGET:-aarch64-linux}"
ZIG_INSTALL_DIR="${ZIG_INSTALL_DIR:-/opt/zig}"
ZIG_SOURCE="${ZIG_SOURCE:-iridoporth-docker-build}"
ZIG_INDEX_URL="${ZIG_INDEX_URL:-https://ziglang.org/download/index.json}"
ZIG_MIRRORS_URL="${ZIG_MIRRORS_URL:-https://ziglang.org/download/community-mirrors.txt}"
ZIG_CURL_CONNECT_TIMEOUT="${ZIG_CURL_CONNECT_TIMEOUT:-10}"
ZIG_CURL_MAX_TIME="${ZIG_CURL_MAX_TIME:-90}"
ZIG_CURL_RETRIES="${ZIG_CURL_RETRIES:-1}"
ZIG_ONLY_MIRROR="${ZIG_ONLY_MIRROR:-}"

# ZSF minisign public key from https://ziglang.org/download/.
ZIG_MINISIGN_PUBKEY="${ZIG_MINISIGN_PUBKEY:-RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U}"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "missing required command: $1" >&2
        exit 1
    fi
}

need_cmd curl
need_cmd jq
need_cmd minisign
need_cmd tar
need_cmd awk
need_cmd sed

curl_get() {
    url="$1"
    output="$2"
    curl -fsSL \
        --connect-timeout "$ZIG_CURL_CONNECT_TIMEOUT" \
        --max-time "$ZIG_CURL_MAX_TIME" \
        --retry "$ZIG_CURL_RETRIES" \
        --retry-delay 1 \
        "$url" \
        -o "$output"
}

index_json="$tmp_dir/index.json"
mirrors_txt="$tmp_dir/community-mirrors.txt"
shuffled_mirrors="$tmp_dir/community-mirrors.shuffled.txt"
tarball="$tmp_dir/zig.tar.xz"
signature="$tmp_dir/zig.tar.xz.minisig"
verify_log="$tmp_dir/minisign.log"

echo "Fetching Zig download index: $ZIG_INDEX_URL"
curl_get "$ZIG_INDEX_URL" "$index_json"

zig_version="$(jq -r --arg channel "$ZIG_CHANNEL" '.[$channel].version // empty' "$index_json" | tr -d '\r\n')"
tarball_url="$(jq -r --arg channel "$ZIG_CHANNEL" --arg target "$ZIG_TARGET" '.[$channel][$target].tarball // empty' "$index_json" | tr -d '\r\n')"

if [ -z "$zig_version" ] || [ -z "$tarball_url" ]; then
    echo "unable to resolve Zig channel '$ZIG_CHANNEL' for target '$ZIG_TARGET'" >&2
    echo "available targets for this channel:" >&2
    jq -r --arg channel "$ZIG_CHANNEL" '.[$channel] | keys[]' "$index_json" >&2
    exit 1
fi

tarball_name="$(basename "$tarball_url" | tr -d '\r\n')"

echo "Resolved Zig $zig_version for $ZIG_TARGET"
echo "Tarball: $tarball_name"

echo "Fetching Zig community mirror list: $ZIG_MIRRORS_URL"
if [ -n "$ZIG_ONLY_MIRROR" ]; then
    printf '%s\n' "$ZIG_ONLY_MIRROR" > "$mirrors_txt"
else
    curl_get "$ZIG_MIRRORS_URL" "$mirrors_txt"
fi

# Shuffle mirrors to avoid concentrating automated traffic on the first entry.
awk 'BEGIN { srand() } { print rand() "\t" $0 }' "$mirrors_txt" \
    | sort -n \
    | sed 's/^[^\t]*\t//' > "$shuffled_mirrors"

try_download_and_verify() {
    mirror="$1"
    base_url="${mirror%/}"
    tarball_download_url="$base_url/$tarball_name?source=$ZIG_SOURCE"
    signature_download_url="$base_url/$tarball_name.minisig?source=$ZIG_SOURCE"

    echo "Trying mirror: $base_url"

    rm -f "$tarball" "$signature" "$verify_log"

    if ! curl_get "$tarball_download_url" "$tarball"; then
        echo "  tarball download failed" >&2
        return 1
    fi

    if ! curl_get "$signature_download_url" "$signature"; then
        echo "  signature download failed" >&2
        return 1
    fi

    if ! minisign -Vm "$tarball" -x "$signature" -P "$ZIG_MINISIGN_PUBKEY" >"$verify_log" 2>&1; then
        echo "  minisign verification failed" >&2
        sed 's/^/    /' "$verify_log" >&2
        return 1
    fi

    trusted_comment="$(sed -n 's/^Trusted comment: //p' "$verify_log" | tail -n 1)"
    actual_file="$(printf '%s\n' "$trusted_comment" | sed -n 's/^.*file://; s/[[:space:]]*hashed.*$//p' | tr -d '\r\n')"

    if [ "$actual_file" != "$tarball_name" ]; then
        echo "  trusted comment file mismatch: expected '$tarball_name', got '${actual_file:-<missing>}'" >&2
        sed 's/^/    /' "$verify_log" >&2
        return 1
    fi

    echo "  verified"
    return 0
}

success=0
while IFS= read -r mirror; do
    if [ -z "$mirror" ]; then
        continue
    fi

    if try_download_and_verify "$mirror"; then
        success=1
        break
    fi
done < "$shuffled_mirrors"

if [ "$success" -ne 1 ]; then
    echo "all mirrors failed; trying ziglang.org as final fallback" >&2
    zig_base_url="$(dirname "$tarball_url")"
    if ! try_download_and_verify "$zig_base_url"; then
        echo "failed to download and verify Zig $zig_version for $ZIG_TARGET" >&2
        exit 1
    fi
fi

rm -rf "$ZIG_INSTALL_DIR"
mkdir -p "$ZIG_INSTALL_DIR"
tar -xf "$tarball" -C "$ZIG_INSTALL_DIR" --strip-components=1

echo "Installed Zig to $ZIG_INSTALL_DIR"
"$ZIG_INSTALL_DIR/zig" version
