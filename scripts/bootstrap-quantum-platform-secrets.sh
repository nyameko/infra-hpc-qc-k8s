#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-quantum-platform}"

if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
  echo "POSTGRES_PASSWORD is required." >&2
  exit 1
fi

if [[ -z "${DJANGO_SECRET_KEY:-}" ]]; then
  echo "DJANGO_SECRET_KEY is required." >&2
  exit 1
fi

kubectl create namespace "${NAMESPACE}" \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic quantum-platform-secrets \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=DJANGO_SECRET_KEY="${DJANGO_SECRET_KEY}" \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

if [[ -n "${TLS_CERT:-}" && -n "${TLS_KEY:-}" ]]; then
  kubectl -n "${NAMESPACE}" create secret tls quantum-platform-tls \
    --cert="${TLS_CERT}" \
    --key="${TLS_KEY}" \
    --dry-run=client \
    -o yaml \
    | kubectl apply -f -
else
  echo
  echo "TLS_CERT/TLS_KEY were not supplied."
  echo "Create the quantum-platform-tls secret before browser acceptance testing."
fi
