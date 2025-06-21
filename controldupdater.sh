#!/usr/bin/env bash

set -euo pipefail

# Check arguments
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <API_TOKEN> <DEVICE_ID>"
  exit 1
fi

API_TOKEN="$1"
DEVICE_ID="$2"

# 1) Get public IP
CURRENT_IP=$(curl -s https://api.ipify.org)

# 2) List all authorized IPs
resp_list=$(curl -sS -w "\n%{http_code}" -G \
  --url https://api.controld.com/access \
  --header "accept: application/json" \
  --header "authorization: Bearer $API_TOKEN" \
  --data-urlencode "device_id=$DEVICE_ID")

body_list=$(echo "$resp_list" | sed '$d')
code_list=$(echo "$resp_list" | tail -n1)

if [[ ! "$code_list" =~ ^2 ]]; then
  echo "❌ Error $code_list listing authorized IPs"
  echo "$body_list" | jq . || echo "$body_list"
  exit 1
fi

# 3) Extract the IP with the highest timestamp
OLD_IP=$(echo "$body_list" | jq -r '.body.ips | max_by(.ts) | .ip')

echo "Most recent authorized IP: $OLD_IP"
echo "My current public IP:      $CURRENT_IP"

# 4) If it hasn’t changed, exit
if [[ "$CURRENT_IP" == "$OLD_IP" ]]; then
  echo "✅ IP hasn’t changed. Nothing to do."
  exit 0
fi

# 5) Delete the old IP
resp_del=$(curl -sS -w "\n%{http_code}" --request DELETE \
  --url https://api.controld.com/access \
  --header "accept: application/json" \
  --header "authorization: Bearer $API_TOKEN" \
  --header "content-type: application/x-www-form-urlencoded" \
  --data-urlencode "device_id=$DEVICE_ID" \
  --data-urlencode "ips[]=$OLD_IP")

body_del=$(echo "$resp_del" | sed '$d')
code_del=$(echo "$resp_del" | tail -n1)

if [[ ! "$code_del" =~ ^2 ]]; then
  echo "❌ Error $code_del deleting old IP $OLD_IP"
  echo "$body_del" | jq . || echo "$body_del"
  exit 1
fi

echo "🗑️  Old IP $OLD_IP deleted."

# 6) Add the new IP
resp_add=$(curl -sS -w "\n%{http_code}" --request POST \
  --url https://api.controld.com/access \
  --header "accept: application/json" \
  --header "authorization: Bearer $API_TOKEN" \
  --header "content-type: application/x-www-form-urlencoded" \
  --data-urlencode "device_id=$DEVICE_ID" \
  --data-urlencode "ips[]=$CURRENT_IP")

body_add=$(echo "$resp_add" | sed '$d')
code_add=$(echo "$resp_add" | tail -n1)

if [[ "$code_add" =~ ^2 ]]; then
  echo "✅ New IP $CURRENT_IP authorized successfully."
  echo "$body_add" | jq .
else
  echo "❌ Error $code_add authorizing new IP $CURRENT_IP"
  echo "$body_add" | jq . || echo "$body_add"
  exit 1
fi
