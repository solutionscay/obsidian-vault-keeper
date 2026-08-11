#!/usr/bin/env bash
# Select the first eligible domain from an ordered candidate list.
# Usage: curator-domain-select.sh PREVIOUS_DOMAIN PRIOR_COUNT RENEWED_DOMAIN CANDIDATE...

set -euo pipefail

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 PREVIOUS_DOMAIN PRIOR_COUNT RENEWED_DOMAIN CANDIDATE..." >&2
    exit 2
fi

PREVIOUS_DOMAIN=$1
PRIOR_COUNT=$2
RENEWED_DOMAIN=$3
shift 3

if ! [[ "$PRIOR_COUNT" =~ ^[0-9]+$ ]]; then
    echo "Error: PRIOR_COUNT must be a nonnegative integer." >&2
    exit 2
fi

DECISION=continue
ROTATE=false
if [ "$PRIOR_COUNT" -ge 3 ] && [ "$RENEWED_DOMAIN" != "$PREVIOUS_DOMAIN" ]; then
    ROTATE=true
    DECISION=rotate-after-three
elif [ "$RENEWED_DOMAIN" = "$PREVIOUS_DOMAIN" ] && [ -n "$PREVIOUS_DOMAIN" ]; then
    DECISION=operator-renewal
fi

for domain in "$@"; do
    if [ "$ROTATE" = true ] && [ "$domain" = "$PREVIOUS_DOMAIN" ]; then
        continue
    fi

    printf 'Domain: %s\n' "$domain"
    printf 'Previous consecutive runs: %s\n' "$PRIOR_COUNT"
    printf 'Decision: %s\n' "$DECISION"
    exit 0
done

echo "Error: No eligible Curator domain." >&2
exit 1
