"""Executor: holds the Kubernetes identity, never touches AWS.

POST /execute -> independently validates the tool intent against its own allowlist,
then calls the Kubernetes API using the in-cluster ServiceAccount token. RBAC decides
what actually succeeds. Kubernetes error responses (403s in particular) are surfaced
verbatim rather than reformatted - see BUILD_SPEC.md.
"""

import json
import logging
import os
import sys

from fastapi import FastAPI, HTTPException
from kubernetes import config
from kubernetes.client.exceptions import ApiException
from pydantic import BaseModel

# In-cluster only, deliberately - this process has no kubeconfig and is never run
# outside a pod with a projected ServiceAccount token. Must run before importing
# k8s_tools: it instantiates CoreV1Api() at module import time, which captures
# whatever the default Configuration is *at that moment* - importing it before the
# in-cluster config is loaded silently binds it to an empty (hostless) config.
config.load_incluster_config()

from allowlist import validate_tool_intent
from k8s_tools import TOOL_FUNCTIONS

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("executor")

app = FastAPI(title="k8s-troubleshooting-executor")


class ExecuteRequest(BaseModel):
    tool: str
    params: dict = {}


def _api_exception_message(exc: ApiException) -> str:
    if not exc.body:
        return exc.reason or str(exc)
    try:
        return json.loads(exc.body).get("message", exc.reason)
    except (ValueError, AttributeError):
        return exc.body


@app.post("/execute")
def execute(request: ExecuteRequest) -> dict:
    is_valid, reason = validate_tool_intent(request.tool, request.params)
    log.info(
        "execute_request tool=%s params=%s valid=%s reason=%s",
        request.tool, request.params, is_valid, reason,
    )

    if not is_valid:
        raise HTTPException(status_code=400, detail=f"rejected by executor allowlist: {reason}")

    try:
        return TOOL_FUNCTIONS[request.tool](request.params)
    except ApiException as exc:
        message = _api_exception_message(exc)
        log.warning(
            "kubernetes_api_error tool=%s namespace=%s status=%s reason=%s message=%s",
            request.tool, request.params.get("namespace"), exc.status, exc.reason, message,
        )
        # Same status code and message the API server returned - not remapped to a
        # generic 500, not swallowed into a success response.
        raise HTTPException(
            status_code=exc.status,
            detail={"kubernetes_reason": exc.reason, "kubernetes_message": message},
        )


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}
