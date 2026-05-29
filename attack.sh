#!/bin/bash

FILE="working_dns.txt"
MAX_JOBS=10000

while IFS= read -r ip || [[ -n "$ip" ]]; do
(
    echo "Sending to: $ip"

sudo nping --udp \
  --dest-ip "$ip" \
  --source-port 5353 \
  --dest-port 53 \
  --data 12340100000100000000000006766f726d6f7802696e0000100001 \
  -c 1 >/dev/null 2>&1
) &

while [ "$(jobs -r | wc -l)" -ge "$MAX_JOBS" ]; do
    sleep 0.1
done

done < "$FILE"

wait
echo "Done"
