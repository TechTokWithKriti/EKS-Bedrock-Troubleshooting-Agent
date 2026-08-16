"""Orchestrator: holds the AWS identity, never touches the Kubernetes API directly.

POST /ask -> runs the Bedrock Converse tool-use loop, validating every tool intent
against the hardcoded allowlist before forwarding it to the executor over
cluster-internal HTTP. See BUILD_SPEC.md for the full request path.
"""

import logging
import os
import sys

import boto3
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from allowlist import validate_tool_intent
from executor_client import ExecutorCallError, call_executor
from tools import SYSTEM_PROMPT, TOOL_CONFIG

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
BEDROCK_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]  # inference profile ID, not the bare model ID
MAX_ITERATIONS = int(os.environ.get("MAX_ITERATIONS", "5"))

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("orchestrator")

app = FastAPI(title="k8s-troubleshooting-orchestrator")
bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)


class AskRequest(BaseModel):
    question: str


def _extract_text(message: dict) -> str:
    return " ".join(
        block["text"] for block in message.get("content", []) if "text" in block
    ).strip()


def _tool_result_block(tool_use_id: str, content: dict, is_error: bool) -> dict:
    return {
        "toolResult": {
            "toolUseId": tool_use_id,
            "content": [{"json": content}],
            "status": "error" if is_error else "success",
        }
    }


def _converse(messages: list, *, with_tools: bool) -> dict:
    kwargs = {
        "modelId": BEDROCK_MODEL_ID,
        "system": [{"text": SYSTEM_PROMPT}],
        "messages": messages,
        "inferenceConfig": {"maxTokens": 1024, "temperature": 0},
    }
    if with_tools:
        kwargs["toolConfig"] = TOOL_CONFIG
    return bedrock.converse(**kwargs)


def run_agent_loop(question: str) -> str:
    messages = [{"role": "user", "content": [{"text": question}]}]

    for iteration in range(1, MAX_ITERATIONS + 1):
        response = _converse(messages, with_tools=True)
        output_message = response["output"]["message"]
        messages.append(output_message)
        stop_reason = response["stopReason"]

        if stop_reason != "tool_use":
            return _extract_text(output_message)

        tool_result_blocks = []
        for block in output_message.get("content", []):
            if "toolUse" not in block:
                continue

            tool_use = block["toolUse"]
            name = tool_use["name"]
            params = tool_use.get("input") or {}
            tool_use_id = tool_use["toolUseId"]

            is_valid, reason = validate_tool_intent(name, params)
            log.info(
                "tool_intent iteration=%d name=%s params=%s valid=%s reason=%s",
                iteration, name, params, is_valid, reason,
            )

            if not is_valid:
                tool_result_blocks.append(
                    _tool_result_block(tool_use_id, {"error": f"rejected by allowlist: {reason}"}, is_error=True)
                )
                continue

            try:
                result, is_error = call_executor(name, params)
            except ExecutorCallError as exc:
                log.warning("executor_call_failed iteration=%d name=%s error=%s", iteration, name, exc)
                result, is_error = {"error": str(exc)}, True

            tool_result_blocks.append(_tool_result_block(tool_use_id, result, is_error))

        messages.append({"role": "user", "content": tool_result_blocks})

    log.info("iteration_cap_reached max_iterations=%d", MAX_ITERATIONS)
    final_response = _converse(messages, with_tools=False)
    return _extract_text(final_response["output"]["message"])


@app.post("/ask")
def ask(request: AskRequest) -> dict:
    if not request.question.strip():
        raise HTTPException(status_code=400, detail="question must not be empty")

    log.info("ask_received question=%r", request.question)
    try:
        answer = run_agent_loop(request.question)
    except Exception:
        log.exception("agent_loop_failed")
        raise HTTPException(status_code=502, detail="failed to get an answer from the agent loop")

    return {"answer": answer}


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}
