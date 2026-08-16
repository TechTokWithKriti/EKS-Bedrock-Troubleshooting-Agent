"""The five read-only Kubernetes operations the executor is allowed to perform.

Every function here takes the tool's `params` dict and returns a JSON-serializable
dict. `kubernetes.client.exceptions.ApiException` is allowed to propagate out of these
- main.py is responsible for turning it into an HTTP response that preserves the
original status code and message rather than swallowing it.
"""

from kubernetes import client

core_v1 = client.CoreV1Api()


def _pod_summary(pod) -> dict:
    container_statuses = pod.status.container_statuses or []
    return {
        "name": pod.metadata.name,
        "phase": pod.status.phase,
        "restart_count": sum(cs.restart_count for cs in container_statuses),
    }


def _container_status_detail(cs) -> dict:
    detail = {"name": cs.name, "ready": cs.ready, "restart_count": cs.restart_count}
    state = cs.state
    if state.waiting:
        detail.update(state="waiting", reason=state.waiting.reason, message=state.waiting.message)
    elif state.terminated:
        detail.update(
            state="terminated",
            reason=state.terminated.reason,
            exit_code=state.terminated.exit_code,
            message=state.terminated.message,
        )
    elif state.running:
        detail.update(state="running")
    return detail


def list_namespaces(params: dict) -> dict:
    result = core_v1.list_namespace()
    return {"namespaces": [ns.metadata.name for ns in result.items]}


def list_pods(params: dict) -> dict:
    result = core_v1.list_namespaced_pod(namespace=params["namespace"])
    return {"pods": [_pod_summary(pod) for pod in result.items]}


def describe_pod(params: dict) -> dict:
    pod = core_v1.read_namespaced_pod(name=params["pod_name"], namespace=params["namespace"])
    return {
        "name": pod.metadata.name,
        "phase": pod.status.phase,
        "containers": [_container_status_detail(cs) for cs in (pod.status.container_statuses or [])],
    }


def get_pod_events(params: dict) -> dict:
    result = core_v1.list_namespaced_event(namespace=params["namespace"])
    events = sorted(result.items, key=lambda e: str(e.last_timestamp or e.event_time or ""))
    return {
        "events": [
            {
                "type": event.type,
                "reason": event.reason,
                "message": event.message,
                "involved_object": event.involved_object.name,
                "count": event.count,
            }
            for event in events[-50:]
        ]
    }


def get_secret(params: dict) -> dict:
    # Expected to be denied by RBAC (no `secrets` rule on the executor's
    # ClusterRole) - that denial is the point, see BUILD_SPEC.md. If this ever
    # succeeds, the RBAC scoping has regressed.
    secret = core_v1.read_namespaced_secret(name=params["secret_name"], namespace=params["namespace"])
    return {"secret_name": secret.metadata.name, "keys": sorted((secret.data or {}).keys())}


TOOL_FUNCTIONS = {
    "list_namespaces": list_namespaces,
    "list_pods": list_pods,
    "describe_pod": describe_pod,
    "get_pod_events": get_pod_events,
    "get_secret": get_secret,
}
