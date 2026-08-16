"""Tool definitions handed to Bedrock's Converse API.

Every tool here is read-only and typed - there is no arbitrary-exec tool. `get_secret`
is included deliberately: the allowlist in allowlist.py permits it, Bedrock will call
it, and RBAC on the executor's ServiceAccount is what actually blocks it. That gap is
the point of the demo, not a bug - see BUILD_SPEC.md.
"""

SYSTEM_PROMPT = """\
You are a Kubernetes cluster troubleshooting assistant embedded in a platform \
engineering tool. You investigate namespaces and pods using only the tools \
provided; you cannot modify anything in the cluster and should never claim to.

For every question, use the tools to actually inspect the cluster before \
answering - do not guess. Typical approach: list pods in the relevant \
namespace, describe any pod that isn't Running/Ready, and check events for \
that namespace if the pod status alone doesn't explain the failure (this \
matters most for failures like CreateContainerConfigError, which show up in \
events rather than container status).

When you find a problem, name the exact failure reason (e.g. ImagePullBackOff, \
CreateContainerConfigError) and the specific resource involved (image tag, \
missing Secret name, etc). If a namespace is healthy, say so plainly - do not \
invent problems where none exist, false positives are worse than no answer.

If a tool call comes back denied (a permissions error), report that plainly as \
a permissions denial in the final answer - do not describe it as a bug or \
retry the same call differently.

Keep the final answer to a few sentences, written for someone about to go look \
at the cluster themselves.
"""

TOOL_SPECS = [
    {
        "toolSpec": {
            "name": "list_namespaces",
            "description": "List all Kubernetes namespaces in the cluster.",
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {},
                    "additionalProperties": False,
                }
            },
        }
    },
    {
        "toolSpec": {
            "name": "list_pods",
            "description": (
                "List pods in a namespace, including phase (e.g. Running, "
                "Pending) and restart counts."
            ),
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {
                        "namespace": {"type": "string", "description": "Namespace to list pods in."}
                    },
                    "required": ["namespace"],
                    "additionalProperties": False,
                }
            },
        }
    },
    {
        "toolSpec": {
            "name": "describe_pod",
            "description": (
                "Get detailed status for a single pod, including per-container "
                "waiting/terminated reasons such as ImagePullBackOff or "
                "CreateContainerConfigError."
            ),
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {
                        "namespace": {"type": "string"},
                        "pod_name": {"type": "string"},
                    },
                    "required": ["namespace", "pod_name"],
                    "additionalProperties": False,
                }
            },
        }
    },
    {
        "toolSpec": {
            "name": "get_pod_events",
            "description": (
                "Get recent Kubernetes events for a namespace (e.g. FailedMount, "
                "Failed to pull image, BackOff). This is the primary signal for "
                "failures that don't fully explain themselves in pod status alone."
            ),
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {"namespace": {"type": "string"}},
                    "required": ["namespace"],
                    "additionalProperties": False,
                }
            },
        }
    },
    {
        "toolSpec": {
            "name": "get_secret",
            "description": (
                "Read the contents of a Kubernetes Secret in a namespace. Note: "
                "this cluster's executor identity is not granted RBAC access to "
                "Secrets, so this call will be denied - report that denial rather "
                "than treating it as an error to work around."
            ),
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {
                        "namespace": {"type": "string"},
                        "secret_name": {"type": "string"},
                    },
                    "required": ["namespace", "secret_name"],
                    "additionalProperties": False,
                }
            },
        }
    },
]

TOOL_CONFIG = {"tools": TOOL_SPECS, "toolChoice": {"auto": {}}}
