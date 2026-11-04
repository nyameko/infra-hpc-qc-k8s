#!/usr/bin/env bash
# M4 read-only operator evidence. Run on k8s-cp-01 only.
# This script NEVER performs kubectl apply/sync/patch/delete, SQL DML,
# privileged migrations, restarts, backup/restore, or user impersonation.
set -euo pipefail

command -v kubectl >/dev/null || { echo "kubectl missing" >&2; exit 1; }

printf '\n== M4 ArgoCD status (not functional acceptance) ==\n'
kubectl -n argocd get applications \
  quantum-platform agent-control-plane agent-control-plane-personal-worker

printf '\n== ACP desired-to-live resource drift ==\n'
kubectl -n argocd get application agent-control-plane \
  -o jsonpath='{range .status.resources[*]}{.kind}{" "}{.namespace}{"/"}{.name}{" "}{.status}{"\n"}{end}'

printf '\n== ACP running Pods and immutable image identities ==\n'
kubectl -n agent-control-plane get pods \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.name}{"="}{.imageID}{" "}{end}{"\n"}{end}'

printf '\n== Quantum Platform running Pods and immutable image identities ==\n'
kubectl -n quantum-platform get pods \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.name}{"="}{.imageID}{" "}{end}{"\n"}{end}'

printf '\n== ACP migration inventory and app-role permissions (READ ONLY) ==\n'
read -r -d '' ACP_READONLY_PY <<'PY' || true
import os
import psycopg

# Never print DSN or credentials, even when a failure occurs.
try:
    with psycopg.connect(
        os.environ["ACP_DATABASE_URL"],
        connect_timeout=5,
        options="-c default_transaction_read_only=on",
    ) as conn:
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT version, left(checksum, 12) "
                "FROM acp1.schema_version ORDER BY version"
            )
            versions = cursor.fetchall()
            print("schema version/checksum-prefix:", versions)
            cursor.execute(
                "SELECT to_regclass('acp1.programme_conversation')::text, "
                "to_regclass('acp1.personal_profile')::text"
            )
            print("required tables:", cursor.fetchone())
            cursor.execute(
                "SELECT rolname, rolsuper, rolbypassrls "
                "FROM pg_roles WHERE rolname=current_user"
            )
            print("application role flags:", cursor.fetchone())
            cursor.execute(
                "SELECT has_table_privilege(current_user,'acp1.message','DELETE'), "
                "has_table_privilege(current_user,'acp1.conversation','DELETE')"
            )
            print("DELETE message / conversation:", cursor.fetchone())
except Exception as exc:
    # Report exception *type only* to avoid leaking credentials in messages.
    print("ACP read-only database query failed:", type(exc).__name__)
    raise SystemExit(1)
PY
kubectl -n agent-control-plane exec deployment/agent-control-plane-api -- \
  python -c "$ACP_READONLY_PY"

printf '\nRead-only snapshot complete. No migration, rollback, or restart was performed.\n'
printf 'See docs/M4-LIVE-ACCEPTANCE.md for expected image digests and separate human tests.\n'
