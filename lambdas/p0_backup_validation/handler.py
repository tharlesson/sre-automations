import json
import os
import uuid
from datetime import datetime, timezone
from typing import Any, Dict

import boto3


EVIDENCE_BUCKET = os.getenv("EVIDENCE_BUCKET", "")
EVIDENCE_PREFIX = os.getenv("EVIDENCE_PREFIX", "backup-validation")
SNAPSHOT_MAX_AGE_DAYS = int(os.getenv("SNAPSHOT_MAX_AGE_DAYS", "7"))
DRY_RUN = os.getenv("DRY_RUN", "true").lower() == "true"
ALLOW_RESTORE = os.getenv("ALLOW_RESTORE", "false").lower() == "true"
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "")

EC2 = boto3.client("ec2")
RDS = boto3.client("rds")
S3 = boto3.client("s3")
SNS = boto3.client("sns")


def _log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
        "dry_run": DRY_RUN,
        "allow_restore": ALLOW_RESTORE,
    }
    payload.update(fields)
    print(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    action = str(event.get("action", "")).strip().lower()
    _log("backup_validation_worker_started", action=action, event=event)

    if action == "discover":
        return _discover_snapshot()
    if action == "restore":
        snapshot_id = event.get("snapshot_id")
        if not snapshot_id:
            raise ValueError("snapshot_id is required for restore action")
        return _restore_snapshot(snapshot_id)
    if action == "smoke_test":
        return _smoke_test(event)
    if action == "cleanup":
        return _cleanup(event)
    if action == "persist_evidence":
        return _persist_evidence(event)

    raise ValueError(f"Unsupported action: {action}")


def _discover_snapshot() -> Dict[str, Any]:
    snapshots = EC2.describe_snapshots(OwnerIds=["self"]).get("Snapshots", [])
    if not snapshots:
        raise RuntimeError("No EBS snapshots found for this account")

    snapshots.sort(key=lambda item: item.get("StartTime", datetime(1970, 1, 1, tzinfo=timezone.utc)), reverse=True)
    latest = snapshots[0]
    latest_time = latest["StartTime"]
    age_days = max((datetime.now(timezone.utc) - latest_time).days, 0)

    result = {
        "snapshot_id": latest["SnapshotId"],
        "snapshot_time": latest_time.isoformat(),
        "snapshot_age_days": age_days,
        "snapshot_compliant": age_days <= SNAPSHOT_MAX_AGE_DAYS,
        "max_allowed_age_days": SNAPSHOT_MAX_AGE_DAYS,
    }
    _log("snapshot_discovered", **result)
    return result


def _restore_snapshot(snapshot_id: str) -> Dict[str, Any]:
    if DRY_RUN or not ALLOW_RESTORE:
        return {
            "snapshot_id": snapshot_id,
            "restore_performed": False,
            "simulated": True,
            "reason": "dry_run_enabled_or_restore_not_allowed",
        }

    availability_zone = _first_available_az()
    response = EC2.create_volume(
        SnapshotId=snapshot_id,
        AvailabilityZone=availability_zone,
        VolumeType="gp3",
        TagSpecifications=[
            {
                "ResourceType": "volume",
                "Tags": [{"Key": "Name", "Value": f"temp-restore-{snapshot_id[:8]}"}],
            }
        ],
    )

    volume_id = response["VolumeId"]
    _log("temporary_volume_created", volume_id=volume_id, snapshot_id=snapshot_id)

    return {
        "snapshot_id": snapshot_id,
        "restore_performed": True,
        "simulated": False,
        "temporary_volume_id": volume_id,
        "availability_zone": availability_zone,
    }


def _smoke_test(event: Dict[str, Any]) -> Dict[str, Any]:
    volume_id = event.get("temporary_volume_id")
    simulated = bool(event.get("simulated"))

    if simulated or not volume_id:
        return {
            "smoke_test_passed": True,
            "simulated": True,
            "details": "Smoke test simulated because restore was not performed",
        }

    volume = EC2.describe_volumes(VolumeIds=[volume_id]).get("Volumes", [])[0]
    state = volume.get("State")
    passed = state in {"available", "in-use"}

    result = {
        "temporary_volume_id": volume_id,
        "smoke_test_passed": passed,
        "simulated": False,
        "volume_state": state,
    }
    if not passed:
        raise RuntimeError(json.dumps(result))
    return result


def _cleanup(event: Dict[str, Any]) -> Dict[str, Any]:
    volume_id = event.get("temporary_volume_id")
    simulated = bool(event.get("simulated"))

    if simulated or not volume_id:
        return {
            "cleanup_performed": False,
            "simulated": True,
            "details": "No temporary resource to cleanup",
        }

    EC2.delete_volume(VolumeId=volume_id)
    _log("temporary_volume_deleted", volume_id=volume_id)
    return {
        "cleanup_performed": True,
        "simulated": False,
        "temporary_volume_id": volume_id,
    }


def _persist_evidence(event: Dict[str, Any]) -> Dict[str, Any]:
    if not EVIDENCE_BUCKET:
        raise ValueError("EVIDENCE_BUCKET is required")

    execution_id = event.get("execution_id") or uuid.uuid4().hex
    now = datetime.now(timezone.utc)
    key = f"{EVIDENCE_PREFIX}/{now.strftime('%Y/%m/%d')}/backup-validation-{execution_id}.json"

    evidence = {
        "automation": "backup_validation",
        "timestamp": now.isoformat(),
        "dry_run": DRY_RUN,
        "allow_restore": ALLOW_RESTORE,
        "execution_id": execution_id,
        "details": event,
    }

    S3.put_object(
        Bucket=EVIDENCE_BUCKET,
        Key=key,
        Body=json.dumps(evidence, default=str).encode("utf-8"),
        ContentType="application/json",
    )

    evidence_uri = f"s3://{EVIDENCE_BUCKET}/{key}"
    _publish_notification(evidence_uri)

    return {
        "evidence_s3_uri": evidence_uri,
        "evidence_key": key,
    }


def _publish_notification(evidence_uri: str) -> None:
    if not SNS_TOPIC_ARN:
        return

    SNS.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="[SRE][BackupValidation] Evidence generated",
        Message=json.dumps({"evidence_s3_uri": evidence_uri}),
    )


def _first_available_az() -> str:
    zones = EC2.describe_availability_zones(Filters=[{"Name": "state", "Values": ["available"]}]).get(
        "AvailabilityZones", []
    )
    if not zones:
        raise RuntimeError("No available AZ found")
    return zones[0]["ZoneName"]