FROM quay.io/jupyterhub/jupyterhub:6.0.1

RUN python -m pip install --no-cache-dir       "jupyterlab>=4,<5"     && printf '%s\n'       '#!/usr/bin/env bash'       'set -euo pipefail'       'export HOME="/home/research/${JUPYTERHUB_USER}"'       'mkdir -p "${HOME}"'       'cd "${HOME}"'       'exec jupyterhub-singleuser "$@"'       > /usr/local/bin/start-workbench     && chmod 0755 /usr/local/bin/start-workbench

USER root
