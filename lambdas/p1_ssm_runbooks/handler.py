import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List

import boto3


DRY_RUN = os.getenv("DRY_RUN", "true").lower() == "true"
REQUIRE_MANUAL_APPROVAL = os.getenv("REQUIRE_MANUAL_APPROVAL", "false").lower() == "true"
PATCHING_DOCUMENT_NAME = os.getenv("PATCHING_DOCUMENT_NAME", "")
RUNBOOK_DOCUMENT_NAME = os.getenv("RUNBOOK_DOCUMENT_NAME", "")
TARGET_TAG_SELECTOR = json.loads(os.getenv("TARGET_TAG_SELECTOR_JSON", "{}"))
PATCH_OPERATION = os.getenv("PATCH_OPERATION", "Scan")
RUNBOOK_PARAMETERS = json.loads(os.getenv("RUNBOOK_PARAMETERS_JSON", "{}"))
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "")
APPROVAL_SNS_TOPIC_ARN = os.getenv("APPROVAL_SNS_TOPIC_ARN", "")

EC2 = boto3.client("ec2")
SSM = boto3.client("ssm")
SNS = boto3.client("sns")


def _log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
        "dry_run": DRY_RUN,
        "require_manual_approval": REQUIRE_MANUAL_APPROVAL,
    }
    payload.update(fields)
    print(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    action = str((event or {}).get("action", "runbook")).strip().lower()
    approved = bool((event or {}).get("approved", False))

    if action not in {"patching", "runbook"}:
        raise ValueError("action must be patching or runbook")

    document_name = PATCHING_DOCUMENT_NAME if action == "patching" else RUNBOOK_DOCUMENT_NAME
    if not document_name:
        raise ValueError(f"Document not configured for action={action}")

    target_ids = _find_target_instances()
    if not target_ids:
        result = {
            "status": "no_targets",
            "action": action,
            "document_name": document_name,
            "target_count": 0,
        }
        _notify(SNS_TOPIC_ARN, f"[SRE][SSMRunbooks] no targets for {action}", result)
        return result

    parameters = _build_parameters(action)

    if REQUIRE_MANUAL_APPROVAL and not approved:
        approval_payload = {
            "status": "pending_approval",
            "action": action,
            "document_name": document_name,
            "target_count": len(target_ids),
            "target_ids": target_ids,
            "parameters": parameters,
            "approval_hint": {
                "invoke_payload": {
                    "action": action,
                    "approved": True,
                }
            },
        }
        _notify(
            APPROVAL_SNS_TOPIC_ARN or SNS_TOPIC_ARN,
            f"[SRE][SSMRunbooks] approval required for {action}",
            approval_payload,
        )
        return approval_payload

    if DRY_RUN:
        dry_result = {
            "status": "dry_run",
            "action": action,
            "document_name": document_name,
            "target_count": len(target_ids),
            "target_ids": target_ids,
            "parameters": parameters,
        }
        _notify(SNS_TOPIC_ARN, f"[SRE][SSMRunbooks] dry-run {action}", dry_result)
        return dry_result

    command_id = _send_commands(document_name=document_name, instance_ids=target_ids, parameters=parameters)
    result = {
        "status": "submitted",
        "action": action,
        "document_name": document_name,
        "target_count": len(target_ids),
        "command_id": command_id,
    }
    _notify(SNS_TOPIC_ARN, f"[SRE][SSMRunbooks] command submitted ({action})", result)
    return result


def _find_target_instances() -> List[str]:
    filters = [{"Name": "instance-state-name", "Values": ["running"]}]
    for key, value in TARGET_TAG_SELECTOR.items():
        filters.append({"Name": f"tag:{key}", "Values": [str(value)]})

    instance_ids: List[str] = []
    paginator = EC2.get_paginator("describe_instances")
    for page in paginator.paginate(Filters=filters):
        for reservation in page.get("Reservations", []):
            for instance in reservation.get("Instances", []):
                instance_ids.append(instance["InstanceId"])

    _log("ssm_targets_discovered", target_count=len(instance_ids), selector=TARGET_TAG_SELECTOR)
    return instance_ids


def _build_parameters(action: str) -> Dict[str, List[str]]:
    if action == "patching":
        return {"Operation": [PATCH_OPERATION]}
    return RUNBOOK_PARAMETERS


def _send_commands(document_name: str, instance_ids: List[str], parameters: Dict[str, List[str]]) -> str:
    command_id = ""
    for chunk in _chunk(instance_ids, 50):
        response = SSM.send_command(
            InstanceIds=chunk,
            DocumentName=document_name,
            Parameters=parameters,
            Comment="SRE automation runbook execution",
        )
        command_id = response["Command"]["CommandId"]
        _log("ssm_command_sent", command_id=command_id, document_name=document_name, target_count=len(chunk))
    return command_id


def _notify(topic_arn: str, subject: str, payload: Dict[str, Any]) -> None:
    if not topic_arn:
        _log("sns_skipped", reason="topic_missing", subject=subject)
        return
    SNS.publish(TopicArn=topic_arn, Subject=subject[:100], Message=json.dumps(payload, default=str))


def _chunk(items: List[str], size: int) -> Iterable[List[str]]:
    for idx in range(0, len(items), size):
        yield items[idx : idx + size]