import json
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

import boto3
from botocore.exceptions import ClientError


LOGGER = logging.getLogger()
LOGGER.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

DRY_RUN = os.getenv("DRY_RUN", "true").lower() == "true"
ALLOW_DESTRUCTIVE_ACTIONS = os.getenv("ALLOW_DESTRUCTIVE_ACTIONS", "false").lower() == "true"
SNAPSHOT_RETENTION_DAYS = int(os.getenv("SNAPSHOT_RETENTION_DAYS", "30"))
LOG_GROUP_RETENTION_DAYS = int(os.getenv("LOG_GROUP_RETENTION_DAYS", "30"))
ECR_IMAGE_RETENTION_DAYS = int(os.getenv("ECR_IMAGE_RETENTION_DAYS", "30"))
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "")

EC2 = boto3.client("ec2")
ECR = boto3.client("ecr")
LOGS = boto3.client("logs")
SNS = boto3.client("sns")


def _log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
        "dry_run": DRY_RUN,
        "allow_destructive_actions": ALLOW_DESTRUCTIVE_ACTIONS,
    }
    payload.update(fields)
    LOGGER.info(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    _log("orphan_cleanup_started", event=event)

    if not DRY_RUN and not ALLOW_DESTRUCTIVE_ACTIONS:
        raise ValueError("Refusing execution: set ALLOW_DESTRUCTIVE_ACTIONS=true when DRY_RUN=false.")

    report = {
        "automation": "orphan_cleanup",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "dry_run": DRY_RUN,
        "mode": "report" if DRY_RUN else "execution",
        "snapshot_candidates": _find_old_snapshots(),
        "orphan_ebs_volumes": _find_orphan_ebs_volumes(),
        "orphan_enis": _find_orphan_enis(),
        "unused_eips": _find_unused_eips(),
        "old_ecr_images": _find_old_ecr_images(),
        "old_log_groups": _find_old_log_groups(),
        "actions_executed": [],
        "errors": [],
    }

    if not DRY_RUN:
        report["actions_executed"], report["errors"] = _execute_cleanup(report)

    _notify(report)
    _log(
        "orphan_cleanup_finished",
        mode=report["mode"],
        candidates={
            "snapshots": len(report["snapshot_candidates"]),
            "ebs_volumes": len(report["orphan_ebs_volumes"]),
            "enis": len(report["orphan_enis"]),
            "eips": len(report["unused_eips"]),
            "ecr_images": len(report["old_ecr_images"]),
            "log_groups": len(report["old_log_groups"]),
        },
    )
    return report


def _find_old_snapshots() -> List[Dict[str, Any]]:
    threshold = datetime.now(timezone.utc) - timedelta(days=SNAPSHOT_RETENTION_DAYS)
    snapshots: List[Dict[str, Any]] = []

    paginator = EC2.get_paginator("describe_snapshots")
    for page in paginator.paginate(OwnerIds=["self"]):
        for snapshot in page.get("Snapshots", []):
            start_time = snapshot.get("StartTime")
            if not start_time or start_time > threshold:
                continue

            tags = {item.get("Key", ""): str(item.get("Value", "")) for item in snapshot.get("Tags", [])}
            if tags.get("Keep", "").lower() == "true":
                continue

            snapshots.append(
                {
                    "snapshot_id": snapshot["SnapshotId"],
                    "start_time": start_time.isoformat(),
                    "description": snapshot.get("Description"),
                }
            )

    return snapshots


def _find_orphan_ebs_volumes() -> List[Dict[str, Any]]:
    volumes: List[Dict[str, Any]] = []
    paginator = EC2.get_paginator("describe_volumes")
    for page in paginator.paginate(Filters=[{"Name": "status", "Values": ["available"]}]):
        for volume in page.get("Volumes", []):
            volumes.append(
                {
                    "volume_id": volume["VolumeId"],
                    "size": volume.get("Size"),
                    "create_time": volume.get("CreateTime").isoformat() if volume.get("CreateTime") else None,
                }
            )
    return volumes


def _find_orphan_enis() -> List[Dict[str, Any]]:
    enis: List[Dict[str, Any]] = []
    paginator = EC2.get_paginator("describe_network_interfaces")
    for page in paginator.paginate(Filters=[{"Name": "status", "Values": ["available"]}]):
        for eni in page.get("NetworkInterfaces", []):
            if eni.get("Attachment"):
                continue
            enis.append(
                {
                    "network_interface_id": eni["NetworkInterfaceId"],
                    "interface_type": eni.get("InterfaceType"),
                    "description": eni.get("Description"),
                }
            )
    return enis


def _find_unused_eips() -> List[Dict[str, Any]]:
    eips: List[Dict[str, Any]] = []
    for address in EC2.describe_addresses().get("Addresses", []):
        if address.get("AssociationId") or address.get("InstanceId") or address.get("NetworkInterfaceId"):
            continue
        eips.append(
            {
                "allocation_id": address.get("AllocationId"),
                "public_ip": address.get("PublicIp"),
            }
        )
    return eips


def _find_old_ecr_images() -> List[Dict[str, Any]]:
    threshold = datetime.now(timezone.utc) - timedelta(days=ECR_IMAGE_RETENTION_DAYS)
    images: List[Dict[str, Any]] = []

    repo_paginator = ECR.get_paginator("describe_repositories")
    for repo_page in repo_paginator.paginate():
        for repo in repo_page.get("repositories", []):
            repository_name = repo["repositoryName"]
            img_paginator = ECR.get_paginator("describe_images")
            for img_page in img_paginator.paginate(repositoryName=repository_name):
                for image in img_page.get("imageDetails", []):
                    pushed_at = image.get("imagePushedAt")
                    tags = image.get("imageTags", [])
                    if tags:
                        continue
                    if not pushed_at or pushed_at > threshold:
                        continue

                    images.append(
                        {
                            "repository": repository_name,
                            "image_digest": image.get("imageDigest"),
                            "image_pushed_at": pushed_at.isoformat(),
                        }
                    )
    return images


def _find_old_log_groups() -> List[Dict[str, Any]]:
    threshold = datetime.now(timezone.utc) - timedelta(days=LOG_GROUP_RETENTION_DAYS)
    groups: List[Dict[str, Any]] = []

    paginator = LOGS.get_paginator("describe_log_groups")
    for page in paginator.paginate():
        for group in page.get("logGroups", []):
            creation_time_ms = group.get("creationTime")
            if not creation_time_ms:
                continue

            created_at = datetime.fromtimestamp(creation_time_ms / 1000, tz=timezone.utc)
            if created_at > threshold:
                continue

            groups.append(
                {
                    "log_group_name": group.get("logGroupName"),
                    "created_at": created_at.isoformat(),
                }
            )

    return groups


def _execute_cleanup(report: Dict[str, Any]) -> tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    actions: List[Dict[str, Any]] = []
    errors: List[Dict[str, Any]] = []

    for snapshot in report["snapshot_candidates"]:
        _try_delete(
            action="delete_snapshot",
            payload=snapshot,
            actions=actions,
            errors=errors,
            executor=lambda: EC2.delete_snapshot(SnapshotId=snapshot["snapshot_id"]),
        )

    for volume in report["orphan_ebs_volumes"]:
        _try_delete(
            action="delete_volume",
            payload=volume,
            actions=actions,
            errors=errors,
            executor=lambda: EC2.delete_volume(VolumeId=volume["volume_id"]),
        )

    for eni in report["orphan_enis"]:
        _try_delete(
            action="delete_network_interface",
            payload=eni,
            actions=actions,
            errors=errors,
            executor=lambda: EC2.delete_network_interface(NetworkInterfaceId=eni["network_interface_id"]),
        )

    for eip in report["unused_eips"]:
        allocation_id = eip.get("allocation_id")
        if not allocation_id:
            continue
        _try_delete(
            action="release_address",
            payload=eip,
            actions=actions,
            errors=errors,
            executor=lambda: EC2.release_address(AllocationId=allocation_id),
        )

    for image in report["old_ecr_images"]:
        _try_delete(
            action="batch_delete_ecr_image",
            payload=image,
            actions=actions,
            errors=errors,
            executor=lambda: ECR.batch_delete_image(
                repositoryName=image["repository"],
                imageIds=[{"imageDigest": image["image_digest"]}],
            ),
        )

    for group in report["old_log_groups"]:
        _try_delete(
            action="delete_log_group",
            payload=group,
            actions=actions,
            errors=errors,
            executor=lambda: LOGS.delete_log_group(logGroupName=group["log_group_name"]),
        )

    return actions, errors


def _try_delete(
    action: str,
    payload: Dict[str, Any],
    actions: List[Dict[str, Any]],
    errors: List[Dict[str, Any]],
    executor: Any,
) -> None:
    try:
        executor()
        actions.append({"action": action, "payload": payload})
    except ClientError as exc:
        error = {"action": action, "payload": payload, "error": str(exc)}
        errors.append(error)
        _log("cleanup_action_failed", **error)


def _notify(report: Dict[str, Any]) -> None:
    if not SNS_TOPIC_ARN:
        _log("sns_topic_missing", message="SNS_TOPIC_ARN not set, skipping notification")
        return

    summary = {
        "mode": report["mode"],
        "snapshot_candidates": len(report["snapshot_candidates"]),
        "orphan_ebs_volumes": len(report["orphan_ebs_volumes"]),
        "orphan_enis": len(report["orphan_enis"]),
        "unused_eips": len(report["unused_eips"]),
        "old_ecr_images": len(report["old_ecr_images"]),
        "old_log_groups": len(report["old_log_groups"]),
        "actions_executed": len(report["actions_executed"]),
        "errors": len(report["errors"]),
    }

    if DRY_RUN:
        _log("sns_publish_dry_run", summary=summary)
        return

    SNS.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[SRE][OrphanCleanup] mode={report['mode']} actions={len(report['actions_executed'])}",
        Message=json.dumps({"summary": summary, "report": report}, default=str),
    )