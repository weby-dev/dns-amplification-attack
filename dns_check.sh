#!/usr/bin/env bash
#
# dns_check.sh — check which DNS servers from a list actually resolve a domain,
#                and save the working ones to a file.
#
# Usage:
#   ./dns_check.sh                       # downloads the public-dns.info list
#   ./dns_check.sh nameservers.txt       # use a local file you already have
#   WORKERS=800 TIMEOUT=2 ./dns_check.sh nameservers.txt
#
set -uo pipefail

LISTURL="https://public-dns.info/nameservers.txt"
INFILE="${1:-}"                          # local file; if empty, download
DOMAIN="${DOMAIN:-google.com}"           # domain used to test resolution
OUTFILE="${OUTFILE:-working_dns.txt}"
TIMEOUT="${TIMEOUT:-2}"                   # seconds to wait per server
WORKERS="${WORKERS:-400}"                 # concurrent dig processes

command -v dig >/dev/null 2>&1 || {
    echo "'dig' not found. Install it:  sudo apt install dnsutils   (or bind-utils)"; exit 1; }

# --- get the list: local file if given, else download ---
TMPLIST=""
if [[ -n "$INFILE" ]]; then
    [[ -f "$INFILE" ]] || { echo "File not found: $INFILE"; exit 1; }
    SRC="$INFILE"
    echo "Using local list: $INFILE"
else
    command -v curl >/dev/null 2>&1 || { echo "Need 'curl' to download, or pass a local file."; exit 1; }
    TMPLIST=$(mktemp)
    echo "Downloading $LISTURL ..."
    curl -fsSL "$LISTURL" -o "$TMPLIST" || { echo "Download failed."; exit 1; }
    SRC="$TMPLIST"
fi

# keep only valid IPv4 lines (the file also contains IPv6)
IPV4_RE='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
TOTAL=$(grep -cE "$IPV4_RE" "$SRC")
echo "Loaded $TOTAL IPv4 servers. domain=$DOMAIN timeout=${TIMEOUT}s workers=$WORKERS"
echo

# --- check one server; validate it's a real, error-free answer ---
check_dns() {
    local ip="$1" out
    # +time/+tries cap the wait; require a status of NOERROR and a non-empty answer
    out=$(dig +time="$TIMEOUT" +tries=1 +noall +comments +answer "@$ip" "$DOMAIN" 2>/dev/null) || return 0
    if grep -q "status: NOERROR" <<<"$out" && grep -qE "[[:space:]]A[[:space:]]+[0-9]" <<<"$out"; then
        printf 'WORKING  %s\n' "$ip"
        echo "$ip" >> "$OUTFILE"
    fi
}
export -f check_dns
export DOMAIN TIMEOUT OUTFILE

: > "$OUTFILE"
SECONDS=0
trap 'echo; echo "Stopped. $(wc -l < "$OUTFILE") working so far in $OUTFILE"; exit 0' INT

grep -E "$IPV4_RE" "$SRC" \
    | xargs -P "$WORKERS" -I{} bash -c 'check_dns "$@"' _ {}

[[ -n "$TMPLIST" ]] && rm -f "$TMPLIST"

echo
echo "Done in ${SECONDS}s. $(wc -l < "$OUTFILE") of $TOTAL servers are working."
echo "Saved to $OUTFILE"
