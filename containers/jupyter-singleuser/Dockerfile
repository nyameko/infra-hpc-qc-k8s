FROM quay.io/jupyterhub/jupyterhub:5.4.2

RUN python -m pip install --no-cache-dir \
      batchspawner==1.3.0 \
      "jupyterlab>=4,<5"

# Apptainer runs this image as the Slurm/POSIX user. The image deliberately
# contains no facility credentials and no user-specific state.
