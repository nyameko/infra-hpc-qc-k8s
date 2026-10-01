FROM quay.io/jupyterhub/jupyterhub:6.0.1

RUN python -m pip install --no-cache-dir \
      "jupyterhub-kubespawner==7.1.0" \
      "jupyterhub-idle-culler==2.0.0" \
      "cryptography>=42,<47"

COPY platform_auth.py /opt/jupyterhub/platform_auth.py
ENV PYTHONPATH=/opt/jupyterhub

RUN python -m compileall -q /opt/jupyterhub/platform_auth.py

USER root
