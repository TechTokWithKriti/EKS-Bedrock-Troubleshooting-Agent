"""Thin HTTP client for the executor's /execute endpoint.

Deliberately dumb: no retries, no circuit breaking, no caching. The executor is the
one enforcing RBAC; this just forwards a validated intent and reports back whatever
comes back, error responses included.
"""

import os

import httpx

EXECUTOR_URL = os.environ.get("EXECUTOR_URL", "http://executor.agent.svc.cluster.local")
EXECUTOR_TIMEOUT_SECONDS = float(os.environ.get("EXECUTOR_TIMEOUT_SECONDS", "10"))

_client = httpx.Client(timeout=EXECUTOR_TIMEOUT_SECONDS)


class ExecutorCallError(Exception):
    """Raised when the executor couldn't be reached or returned something unusable."""


def call_executor(tool: str, params: dict) -> dict:
    """Calls the executor. Returns (result_dict, is_error).

    On any non-2xx response the executor's own error body is passed through as the
    result and is_error is True - this is how a Kubernetes 403 on `get_secret`
    ultimately becomes the tool result Bedrock sees, rather than being swallowed here.
    """
    try:
        response = _client.post(
            f"{EXECUTOR_URL}/execute",
            json={"tool": tool, "params": params},
        )
    except httpx.HTTPError as exc:
        raise ExecutorCallError(f"could not reach executor: {exc}") from exc

    try:
        body = response.json()
    except ValueError:
        body = {"error": response.text or f"executor returned HTTP {response.status_code}"}

    is_error = response.status_code >= 400
    return body, is_error
