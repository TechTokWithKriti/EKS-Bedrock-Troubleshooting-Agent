"""Executor's own tool allowlist.

Deliberately not shared code with the orchestrator's allowlist.py - the two services
hold separate identities and trust nothing about each other's validation, so each
checks independently. If this ever imports from the orchestrator package, that's a
sign the identity boundary in BUILD_SPEC.md has been collapsed; don't do it.
"""

import re

K8S_NAME_RE = re.compile(r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
NAMESPACE_MAX_LEN = 63
RESOURCE_NAME_MAX_LEN = 253

ALLOWED_TOOLS = {
    "list_namespaces": {},
    "list_pods": {"namespace": NAMESPACE_MAX_LEN},
    "describe_pod": {"namespace": NAMESPACE_MAX_LEN, "pod_name": RESOURCE_NAME_MAX_LEN},
    "get_pod_events": {"namespace": NAMESPACE_MAX_LEN},
    "get_secret": {"namespace": NAMESPACE_MAX_LEN, "secret_name": RESOURCE_NAME_MAX_LEN},
}


def validate_tool_intent(name: str, params: dict) -> tuple[bool, str]:
    if name not in ALLOWED_TOOLS:
        return False, f"'{name}' is not an allowed tool"

    expected_params = ALLOWED_TOOLS[name]

    if not isinstance(params, dict):
        return False, "params must be an object"

    if set(params.keys()) != set(expected_params.keys()):
        return False, (
            f"expected params {sorted(expected_params.keys())}, "
            f"got {sorted(params.keys())}"
        )

    for param_name, max_len in expected_params.items():
        value = params[param_name]
        if not isinstance(value, str) or not value:
            return False, f"'{param_name}' must be a non-empty string"
        if len(value) > max_len:
            return False, f"'{param_name}' exceeds max length {max_len}"
        if not K8S_NAME_RE.match(value):
            return False, f"'{param_name}' is not a valid Kubernetes resource name"

    return True, "ok"
