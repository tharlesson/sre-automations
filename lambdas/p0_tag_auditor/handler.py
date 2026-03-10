import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict, List

import boto3
from botocore.exceptions import ClientError


LOGGER = logging.getLogger()
LOGGER.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

DRY_RUN = os.getenv("DRY_RUN", "true").lower() == "true"
AUTO_REMEDIATE = os.getenv("AUTO_REMEDIATE", "false").lower() == "true"
REQUIRED_TAGS = json.loads(
    os.getenv("REQUIRED_TAGS_JSON", '["Environment","Application","Owner","CostCenter","ManagedBy"]')
)
DEFAULT_TAG_VALUES = json.loads(os.getenv("DEFAULT_TAG_VALUES_JSON", "{}"))
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "")

TAGGING = boto3.client("resourcegroupstaggingapi")
SNS = boto3.client("sns")


def _log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
        "dry_run": DRY_RUN,
        "auto_remediate": AUTO_REMEDIATE,
    }
    payload.update(fields)
    LOGGER.info(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    _log("tag_auditor_started", event=event)

    findings: List[Dict[str, Any]] = []
    remediated = 0

    paginator = TAGGING.get_paginator("get_resources")
    for page in paginator.paginate(ResourcesPerPage=100):
        for mapping in page.get("ResourceTagMappingList", []):
            resource_arn = mapping.get("ResourceARN", "")
            tags = {item.get("Key", ""): str(item.get("Value", "")) for item in mapping.get("Tags", [])}
            missing_tags = [tag for tag in REQUIRED_TAGS if not str(tags.get(tag, "")).strip()]
            if not missing_tags:
                continue

            finding = {
                "resource_arn": resource_arn,
                "missing_tags": missing_tags,
                "current_tags": tags,
            }
            findings.append(finding)

            if AUTO_REMEDIATE:
                tags_to_apply = _build_remediation_tags(missing_tags)
                if tags_to_apply:
                    _apply_tags(resource_arn, tags_to_apply)
                    remediated += 1

    payload = {
        "automation": "tag_auditor",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "dry_run": DRY_RUN,
        "auto_remediate": AUTO_REMEDIATE,
        "required_tags": REQUIRED_TAGS,
        "non_compliant_resources": len(findings),
        "remediated_resources": remediated,
        "findings": findings,
    }

    _notify(payload)
    _log(
        "tag_auditor_finished",
        non_compliant_resources=len(findings),
        remediated_resources=remediated,
    )
    return payload


def _build_remediation_tags(missing_tags: List[str]) -> Dict[str, str]:
    tags_to_apply: Dict[str, str] = {}
    for tag_key in missing_tags:
        if tag_key in DEFAULT_TAG_VALUES:
            tags_to_apply[tag_key] = str(DEFAULT_TAG_VALUES[tag_key])
        elif tag_key == "ManagedBy":
            tags_to_apply[tag_key] = "Terraform"
    return tags_to_apply


def _apply_tags(resource_arn: str, tags: Dict[str, str]) -> None:
    _log("tag_remediation", resource_arn=resource_arn, tags=tags)
    if DRY_RUN:
        return

    try:
        TAGGING.tag_resources(ResourceARNList=[resource_arn], Tags=tags)
    except ClientError as exc:
        _log("tag_remediation_failed", resource_arn=resource_arn, error=str(exc))


def _notify(payload: Dict[str, Any]) -> None:
    if not SNS_TOPIC_ARN:
        _log("sns_topic_missing", message="SNS_TOPIC_ARN not set, skipping notification")
        return

    message = json.dumps(payload, default=str)
    subject = f"[SRE][TagAuditor] {payload['non_compliant_resources']} recursos nao conformes"

    if DRY_RUN:
        _log("sns_publish_dry_run", subject=subject)
        return

    SNS.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)