#!/bin/sh
# Add the test subscriber via the local free5GC web console.
# Uses the web console's built-in default test login (local testbed only).
set -e
cd "$(dirname "$0")"
TOKEN=$(curl -s -X POST http://127.0.0.1:5000/api/login -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"free5gc"}' | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] || { echo "login failed"; exit 1; }
curl -s -o /dev/null -w "POST subscriber: %{http_code}\n" -X POST \
  http://127.0.0.1:5000/api/subscriber/imsi-208930000000001/20893 \
  -H "Token: $TOKEN" -H 'Content-Type: application/json' --data @${SUBSCRIBER:-subscriber.json}
