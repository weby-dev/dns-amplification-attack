#!/usr/bin/env bash
#
# dns-check.sh — check which DNS servers from a list actually resolve.
#
# Usage:
#   ./dns-check.sh                          # downloads the public-dns.info list
#   ./dns-check.sh nameservers.txt          # use a local file you already have
#   PARALLEL=500 TIMEOUT=2 ./dns-check.sh
#
set -uo pipefail

LISTURL="https://public-dns.info/nameservers.txt"
INFILE="${1:-}"                  # optional local file; if empty we download
TEST_DOMAIN="${TEST_DOMAIN:-google.com}"
OUTFILE="${OUTFILE:-working_dns.txt}"
TIMEOUT="${TIMEOUT:-2}"
PARALLEL="${PARALLEL:-300}"

command -v dig >/dev/null 2>&1 || { echo "Install 'dig' (dnsutils / bind-utils) first."; exit 1; }

# --- get the list: local file if given, else download ---
TMPLIST=""
if [[ -n "$INFILE" ]]; then
    [[ -f "$INFILE" ]] || { echo "File not found: $INFILE"; exit 1; }
    SRC="$INFILE"
    echo "Using local list: $INFILE"
else
    command -v curl >/dev/null 2>&1 || { echo "Need 'curl' to download (or pass a local file)."; exit 1; }
    TMPLIST=$(mktemp)
    echo "Downloading list from $LISTURL ..."
    curl -fsSL "$LISTURL" -o "$TMPLIST" || { echo "Download failed."; exit 1; }
    SRC="$TMPLIST"
fi

# keep only valid-looking IPv4 lines (the file has one IP per line, some IPv6)
TOTAL=$(grep -cE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' "$SRC")
echo "Loaded $TOTAL IPv4 servers to test (domain: $TEST_DOMAIN, $PARALLEL parallel, ${TIMEOUT}s timeout)."
echo

check_dns() {
    local ip="$1"
    if dig +short +time="$TIMEOUT" +tries=1 "@$ip" "$TEST_DOMAIN" 2>/dev/null | grep -qE '^[0-9]'; then
        printf 'WORKING  %s\n' "$ip"
        echo "$ip" >> "$OUTFILE"
    fi
}
export -f check_dns
export TEST_DOMAIN TIMEOUT OUTFILE

: > "$OUTFILE"
SECONDS=0

grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' "$SRC" \
    | xargs -P "$PARALLEL" -I{} bash -c 'check_dns "$@"' _ {}

[[ -n "$TMPLIST" ]] && rm -f "$TMPLIST"

echo
echo "Done in ${SECONDS}s. $(wc -l < "$OUTFILE") of $TOTAL servers are working."
echo "Saved to $OUTFILE"
