import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Tuple

import boto3
from botocore.exceptions import ClientError


CRITICAL_PORTS = [int(port) for port in json.loads(os.getenv("CRITICAL_PORTS_JSON", "[22,3389,3306,5432]"))]
EXCLUDED_SG_IDS = set(json.loads(os.getenv("EXCLUDED_SECURITY_GROUPS_JSON", "[]")))
DEFAULT_DRY_RUN = os.getenv("DRY_RUN", "true").lower() == "true"

EC2 = boto3.client("ec2")


def _log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
    }
    payload.update(fields)
    print(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    action = str((event or {}).get("action", "detect")).strip().lower()

    if action == "detect":
        return _detect_exposed_security_groups()
    if action == "remediate":
        dry_run = bool((event or {}).get("dry_run", DEFAULT_DRY_RUN))
        findings = (event or {}).get("findings", [])
        return _remediate(findings=findings, dry_run=dry_run)

    raise ValueError("action must be detect or remediate")


def _detect_exposed_security_groups() -> Dict[str, Any]:
    findings: List[Dict[str, Any]] = []

    paginator = EC2.get_paginator("describe_security_groups")
    for page in paginator.paginate():
        for sg in page.get("SecurityGroups", []):
            sg_id = sg.get("GroupId", "")
            if sg_id in EXCLUDED_SG_IDS:
                continue

            for permission in sg.get("IpPermissions", []):
                exposed_ranges = _world_ranges(permission)
                if not exposed_ranges:
                    continue

                exposed_ports = _critical_ports_in_permission(permission, CRITICAL_PORTS)
                if not exposed_ports:
                    continue

                findings.append(
                    {
                        "group_id": sg_id,
                        "group_name": sg.get("GroupName"),
                        "description": sg.get("Description"),
                        "exposed_ports": exposed_ports,
                        "offending_permission": _build_offending_permission(permission, exposed_ranges),
                    }
                )

    result = {
        "status": "detected",
        "critical_ports": CRITICAL_PORTS,
        "excluded_security_groups": sorted(EXCLUDED_SG_IDS),
        "findings_count": len(findings),
        "findings": findings,
    }
    _log("sg_exposure_detected", findings_count=len(findings))
    return result


def _remediate(findings: List[Dict[str, Any]], dry_run: bool) -> Dict[str, Any]:
    actions_planned: List[Dict[str, Any]] = []
    actions_executed: List[Dict[str, Any]] = []
    errors: List[Dict[str, Any]] = []

    grouped = _group_permissions_by_security_group(findings)

    for group_id, permissions in grouped.items():
        if not permissions:
            continue

        action_payload = {
            "group_id": group_id,
            "permissions": permissions,
        }
        actions_planned.append(action_payload)

        if dry_run:
            continue

        try:
            EC2.revoke_security_group_ingress(GroupId=group_id, IpPermissions=permissions)
            actions_executed.append(action_payload)
        except ClientError as exc:
            errors.append(
                {
                    "group_id": group_id,
                    "error": str(exc),
                }
            )

    result = {
        "status": "dry_run" if dry_run else "executed",
        "findings_received": len(findings),
        "actions_planned": actions_planned,
        "actions_executed": actions_executed,
        "errors": errors,
        "remediated_groups_count": len(actions_executed),
    }
    _log("sg_exposure_remediation", status=result["status"], planned=len(actions_planned), executed=len(actions_executed), errors=len(errors))
    return result


def _group_permissions_by_security_group(findings: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    grouped: Dict[str, List[Dict[str, Any]]] = {}
    seen: set[Tuple[str, str]] = set()

    for finding in findings:
        group_id = finding.get("group_id")
        permission = finding.get("offending_permission")
        if not group_id or not permission:
            continue

        signature = (group_id, json.dumps(permission, sort_keys=True))
        if signature in seen:
            continue
        seen.add(signature)

        grouped.setdefault(group_id, []).append(permission)

    return grouped


def _world_ranges(permission: Dict[str, Any]) -> Dict[str, List[Dict[str, Any]]]:
    ipv4_ranges = [item for item in permission.get("IpRanges", []) if item.get("CidrIp") == "0.0.0.0/0"]
    ipv6_ranges = [item for item in permission.get("Ipv6Ranges", []) if item.get("CidrIpv6") == "::/0"]
    return {
        "ipv4": ipv4_ranges,
        "ipv6": ipv6_ranges,
    }


def _build_offending_permission(permission: Dict[str, Any], exposed_ranges: Dict[str, List[Dict[str, Any]]]) -> Dict[str, Any]:
    offending = {
        "IpProtocol": permission.get("IpProtocol", "-1"),
    }

    if permission.get("FromPort") is not None:
        offending["FromPort"] = permission["FromPort"]
    if permission.get("ToPort") is not None:
        offending["ToPort"] = permission["ToPort"]
    if exposed_ranges.get("ipv4"):
        offending["IpRanges"] = [{"CidrIp": "0.0.0.0/0"}]
    if exposed_ranges.get("ipv6"):
        offending["Ipv6Ranges"] = [{"CidrIpv6": "::/0"}]

    return offending


def _critical_ports_in_permission(permission: Dict[str, Any], critical_ports: Iterable[int]) -> List[int]:
    protocol = permission.get("IpProtocol", "-1")
    from_port = permission.get("FromPort")
    to_port = permission.get("ToPort")

    if protocol == "-1":
        return sorted({int(port) for port in critical_ports})

    if protocol not in {"tcp", "udp"}:
        return []

    if from_port is None or to_port is None:
        return []

    exposed = [int(port) for port in critical_ports if int(from_port) <= int(port) <= int(to_port)]
    return sorted(set(exposed))