FROM quay.io/jupyterhub/jupyterhub:5.4.2

RUN python -m pip install --no-cache-dir batchspawner==1.3.0 \
    && apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/*

USER root
