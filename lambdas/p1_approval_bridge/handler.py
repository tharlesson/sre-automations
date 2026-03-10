import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, List

import urllib3


CHATOPS_WEBHOOK_URL = os.getenv("CHATOPS_WEBHOOK_URL", "")
ITSM_WEBHOOK_URL = os.getenv("ITSM_WEBHOOK_URL", "")
FORWARD_ONLY_APPROVAL_MESSAGES = os.getenv("FORWARD_ONLY_APPROVAL_MESSAGES", "true").lower() == "true"
HTTP_TIMEOUT_SECONDS = int(os.getenv("HTTP_TIMEOUT_SECONDS", "10"))

HTTP = urllib3.PoolManager()


def _log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
    }
    payload.update(fields)
    print(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    records = event.get("Records", []) if isinstance(event, dict) else []

    forwarded = 0
    skipped = 0
    errors: List[Dict[str, str]] = []

    for record in records:
        sns_payload = (record.get("Sns") or {})
        subject = str(sns_payload.get("Subject", ""))
        message = str(sns_payload.get("Message", ""))

        if FORWARD_ONLY_APPROVAL_MESSAGES and not _is_approval_message(subject, message):
            skipped += 1
            continue

        normalized_message = _normalize_message(message)
        payload = {
            "subject": subject,
            "message": normalized_message,
            "raw": message,
        }

        for target_name, webhook_url in (("chatops", CHATOPS_WEBHOOK_URL), ("itsm", ITSM_WEBHOOK_URL)):
            if not webhook_url:
                continue
            try:
                _post_webhook(webhook_url, payload)
                forwarded += 1
            except Exception as exc:  # noqa: BLE001
                errors.append({"target": target_name, "error": str(exc)})

    result = {
        "records": len(records),
        "forwarded": forwarded,
        "skipped": skipped,
        "errors": errors,
    }
    _log("approval_bridge_finished", **result)
    return result


def _is_approval_message(subject: str, message: str) -> bool:
    text = f"{subject} {message}".lower()
    keywords = ["approval", "aprovacao", "approved", "pending_approval", "sgremediation", "ssmrunbooks"]
    return any(keyword in text for keyword in keywords)


def _normalize_message(raw_message: str) -> Dict[str, Any] | str:
    try:
        return json.loads(raw_message)
    except Exception:  # noqa: BLE001
        return raw_message


def _post_webhook(webhook_url: str, payload: Dict[str, Any]) -> None:
    response = HTTP.request(
        method="POST",
        url=webhook_url,
        headers={"Content-Type": "application/json"},
        body=json.dumps(payload).encode("utf-8"),
        timeout=urllib3.Timeout(connect=HTTP_TIMEOUT_SECONDS, read=HTTP_TIMEOUT_SECONDS),
    )

    if response.status >= 400:
        raise RuntimeError(f"Webhook call failed status={response.status}")