#!/usr/bin/env bash
set -euo pipefail
hosts=(10.50.0.10 10.50.0.11 10.50.0.12 10.50.0.20 10.50.0.21 10.50.0.30 10.50.0.31 10.51.0.11 10.51.0.12 10.51.0.13 10.51.0.21 10.51.0.22 10.51.0.23)
for h in "${hosts[@]}"; do
  printf '%-15s ' "$h"
  if timeout 2 bash -c "</dev/tcp/$h/22" 2>/dev/null; then echo SSH-OPEN; else echo NO-SSH; fi
done
