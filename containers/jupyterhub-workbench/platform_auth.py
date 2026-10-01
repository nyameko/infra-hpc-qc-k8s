"""Short-lived Quantum Platform launch assertions for JupyterHub."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time

from jupyterhub.auth import Authenticator
from jupyterhub.handlers.base import BaseHandler
from jupyterhub.utils import url_path_join
from tornado import web


def _b64url_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def decode_launch_assertion(token: str, signing_key: str) -> dict:
    try:
        encoded, supplied_signature = token.split(".", 1)
    except ValueError as exc:
        raise web.HTTPError(403, "Malformed workbench launch assertion.") from exc

    expected_signature = base64.urlsafe_b64encode(
        hmac.new(
            signing_key.encode("utf-8"),
            encoded.encode("ascii"),
            hashlib.sha256,
        ).digest()
    ).decode("ascii").rstrip("=")

    if not hmac.compare_digest(supplied_signature, expected_signature):
        raise web.HTTPError(403, "Invalid workbench launch assertion.")

    try:
        claims = json.loads(_b64url_decode(encoded))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise web.HTTPError(403, "Invalid workbench launch assertion payload.") from exc

    now = int(time.time())
    if claims.get("aud") != "jupyterhub-workbench":
        raise web.HTTPError(403, "Workbench assertion audience mismatch.")
    if int(claims.get("exp", 0)) < now:
        raise web.HTTPError(403, "Workbench launch assertion has expired.")
    if int(claims.get("iat", now)) > now + 30:
        raise web.HTTPError(403, "Workbench launch assertion is not yet valid.")

    jti = str(claims.get("jti", "")).strip()
    if not jti:
        raise web.HTTPError(403, "Workbench launch assertion has no nonce.")

    username = str(claims.get("sub", "")).strip()
    if not username:
        raise web.HTTPError(403, "Workbench launch assertion has no user.")

    try:
        uid = int(claims["uid"])
        gid = int(claims["gid"])
    except (KeyError, TypeError, ValueError) as exc:
        raise web.HTTPError(403, "Workbench assertion has no POSIX identity.") from exc

    if uid <= 0 or gid <= 0:
        raise web.HTTPError(403, "Workbench assertion has invalid POSIX identity.")

    theme = str(claims.get("theme", "dark")).strip().lower()
    if theme not in {"light", "dark"}:
        theme = "dark"

    return {
        "name": username,
        "auth_state": {
            "uid": uid,
            "gid": gid,
            "theme": theme,
            "assertion_exp": int(claims["exp"]),
            "assertion_jti": jti,
        },
    }


class PlatformLaunchHandler(BaseHandler):
    async def get(self):
        token = self.get_argument("token", default="").strip()
        if not token:
            self.redirect(os.environ["QUANTUM_PLATFORM_WORKBENCH_URL"])
            return

        user = await self.login_user({"launch_token": token})
        if user is None:
            raise web.HTTPError(403, "Quantum Platform workbench login failed.")

        # Never preserve the assertion token in the redirect URL.
        target = (
            user.url
            if user.spawner.active
            else url_path_join(self.hub.base_url, "spawn")
        )
        self.redirect(target)


class PlatformLaunchAuthenticator(Authenticator):
    login_service = "Quantum Platform"

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._used_assertions = {}

    def login_url(self, base_url):
        return url_path_join(base_url, "platform-login")

    def get_handlers(self, app):
        return [(r"/platform-login", PlatformLaunchHandler)]

    async def authenticate(self, handler, data):
        token = str((data or {}).get("launch_token", "")).strip()
        if not token:
            return None
        signing_key = os.environ["JUPYTERHUB_PLATFORM_SIGNING_KEY"]
        identity = decode_launch_assertion(token, signing_key)

        now = int(time.time())
        self._used_assertions = {
            nonce: expiry
            for nonce, expiry in self._used_assertions.items()
            if expiry >= now
        }
        nonce = identity["auth_state"]["assertion_jti"]
        if nonce in self._used_assertions:
            raise web.HTTPError(403, "Workbench launch assertion was already used.")

        self._used_assertions[nonce] = identity["auth_state"]["assertion_exp"]
        return identity
