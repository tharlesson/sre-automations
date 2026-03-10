import json
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

import boto3


LOGGER = logging.getLogger()
LOGGER.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

DRY_RUN = os.getenv("DRY_RUN", "true").lower() == "true"
ACM_THRESHOLD_DAYS = int(os.getenv("ACM_EXPIRY_THRESHOLD_DAYS", "30"))
SECRET_THRESHOLD_DAYS = int(os.getenv("SECRET_ROTATION_THRESHOLD_DAYS", "30"))
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "")

ACM = boto3.client("acm")
SECRETS = boto3.client("secretsmanager")
SNS = boto3.client("sns")


def _log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
        "dry_run": DRY_RUN,
    }
    payload.update(fields)
    LOGGER.info(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    _log("cert_secret_monitor_started", event=event)

    acm_findings = _find_expiring_certificates()
    secret_findings = _find_expiring_or_due_secrets()

    payload = {
        "automation": "cert_secret_monitor",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "dry_run": DRY_RUN,
        "acm_threshold_days": ACM_THRESHOLD_DAYS,
        "secret_threshold_days": SECRET_THRESHOLD_DAYS,
        "acm_findings": acm_findings,
        "secret_findings": secret_findings,
        "total_findings": len(acm_findings) + len(secret_findings),
    }

    _notify(payload)
    _log("cert_secret_monitor_finished", total_findings=payload["total_findings"])
    return payload


def _find_expiring_certificates() -> List[Dict[str, Any]]:
    findings: List[Dict[str, Any]] = []
    deadline = datetime.now(timezone.utc) + timedelta(days=ACM_THRESHOLD_DAYS)

    paginator = ACM.get_paginator("list_certificates")
    for page in paginator.paginate(CertificateStatuses=["ISSUED"]):
        for summary in page.get("CertificateSummaryList", []):
            arn = summary["CertificateArn"]
            details = ACM.describe_certificate(CertificateArn=arn).get("Certificate", {})
            not_after = details.get("NotAfter")
            if not not_after:
                continue
            if not_after <= deadline:
                findings.append(
                    {
                        "certificate_arn": arn,
                        "domain_name": details.get("DomainName"),
                        "not_after": not_after.isoformat(),
                        "days_to_expire": max((not_after - datetime.now(timezone.utc)).days, 0),
                    }
                )

    return findings


def _find_expiring_or_due_secrets() -> List[Dict[str, Any]]:
    findings: List[Dict[str, Any]] = []
    deadline = datetime.now(timezone.utc) + timedelta(days=SECRET_THRESHOLD_DAYS)

    paginator = SECRETS.get_paginator("list_secrets")
    for page in paginator.paginate():
        for secret in page.get("SecretList", []):
            secret_id = secret.get("ARN")
            if not secret_id:
                continue

            details = SECRETS.describe_secret(SecretId=secret_id)
            next_rotation = details.get("NextRotationDate")
            if details.get("RotationEnabled") and next_rotation and next_rotation <= deadline:
                findings.append(
                    {
                        "secret_arn": secret_id,
                        "name": details.get("Name"),
                        "finding_type": "rotation_due",
                        "next_rotation_date": next_rotation.isoformat(),
                        "days_to_rotation": max((next_rotation - datetime.now(timezone.utc)).days, 0),
                    }
                )
                continue

            deleted_date = details.get("DeletedDate")
            if deleted_date:
                findings.append(
                    {
                        "secret_arn": secret_id,
                        "name": details.get("Name"),
                        "finding_type": "secret_scheduled_for_deletion",
                        "deleted_date": deleted_date.isoformat(),
                    }
                )

    return findings


def _notify(payload: Dict[str, Any]) -> None:
    if not SNS_TOPIC_ARN:
        _log("sns_topic_missing", message="SNS_TOPIC_ARN not set, skipping notification")
        return

    if payload.get("total_findings", 0) == 0:
        _log("no_findings", message="No expiring certificates/secrets detected")
        return

    subject = f"[SRE][CertSecretMonitor] {payload['total_findings']} achados"
    message = json.dumps(payload, default=str)

    if DRY_RUN:
        _log("sns_publish_dry_run", subject=subject)
        return

    SNS.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)