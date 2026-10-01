FROM quay.io/jupyterhub/jupyterhub:6.0.1

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends libnss-wrapper \
    && rm -rf /var/lib/apt/lists/* \
    && nss_wrapper_lib="$(find /usr/lib -name libnss_wrapper.so -print -quit)" \
    && test -n "$nss_wrapper_lib" \
    && ln -sf "$nss_wrapper_lib" /usr/local/lib/libnss_wrapper.so

RUN python -m pip install --no-cache-dir "jupyterlab>=4.6,<5"

# Follow the browser/OS light-dark preference by default while still allowing
# each researcher to override JupyterLab settings in their persistent home.
RUN mkdir -p /usr/local/etc/jupyter/labconfig \
    && cat > /usr/local/etc/jupyter/labconfig/default_setting_overrides.json <<'EOF'
{
  "@jupyterlab/apputils-extension:themes": {
    "adaptive-theme": true,
    "preferred-light-theme": "JupyterLab Light",
    "preferred-dark-theme": "JupyterLab Dark"
  },
  "@jupyterlab/terminal-extension:plugin": {
    "theme": "inherit"
  }
}
EOF

# Research users have authoritative numeric UID/GID values supplied by Quantum
# Platform. They are deliberately not baked into the image. nss_wrapper gives
# libc/Jupyter a runtime passwd/group view for that dynamic identity.
RUN cat > /usr/local/bin/start-workbench <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

username="${QUANTUM_PLATFORM_USERNAME:?Quantum Platform username is required}"
uid="${QUANTUM_PLATFORM_UID:-$(id -u)}"
gid="${QUANTUM_PLATFORM_GID:-$(id -g)}"
home="${HOME:-/home/research/${username}}"

export HOME="$home"
export USER="$username"
export LOGNAME="$username"
export JUPYTERHUB_USER="$username"

theme="${QUANTUM_PLATFORM_THEME:-dark}"
if [[ "$theme" != "light" && "$theme" != "dark" ]]; then
  theme="dark"
fi

if [[ ! -d "$home" ]]; then
  echo "Research home does not exist: $home" >&2
  exit 1
fi

nss_dir="/tmp/quantum-platform-nss"
passwd_file="$nss_dir/passwd"
group_file="$nss_dir/group"

mkdir -p "$nss_dir"
cp /etc/passwd "$passwd_file"
cp /etc/group "$group_file"

if ! awk -F: -v uid="$uid" '$3 == uid { found=1 } END { exit !found }' "$passwd_file"; then
  printf '%s:x:%s:%s:Quantum Platform research user:%s:/bin/bash\n' \
    "$username" "$uid" "$gid" "$home" >> "$passwd_file"
fi

if ! awk -F: -v gid="$gid" '$3 == gid { found=1 } END { exit !found }' "$group_file"; then
  printf '%s:x:%s:\n' "$username" "$gid" >> "$group_file"
fi

export NSS_WRAPPER_PASSWD="$passwd_file"
export NSS_WRAPPER_GROUP="$group_file"
export LD_PRELOAD="/usr/local/lib/libnss_wrapper.so"

theme_dir="$home/.jupyter/lab/user-settings/@jupyterlab/apputils-extension"
theme_file="$theme_dir/themes.jupyterlab-settings"
mkdir -p "$theme_dir"

if [[ "$theme" == "light" ]]; then
  selected_theme="JupyterLab Light"
else
  selected_theme="JupyterLab Dark"
fi

cat > "$theme_file" <<EOF_THEME
{
  "theme": "$selected_theme",
  "adaptive-theme": false,
  "preferred-light-theme": "JupyterLab Light",
  "preferred-dark-theme": "JupyterLab Dark"
}
EOF_THEME

cd "$home"
exec jupyterhub-singleuser "$@"
EOF

RUN chmod 0755 /usr/local/bin/start-workbench

USER root
