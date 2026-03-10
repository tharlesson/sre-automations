import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, List

import boto3
from botocore.exceptions import ClientError


STORAGE_BUCKET = os.getenv("STORAGE_BUCKET", "")
BASELINE_OBJECT_KEY = os.getenv("BASELINE_OBJECT_KEY", "drift/baseline.json")
REPORT_PREFIX = os.getenv("REPORT_PREFIX", "drift-reports")
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "")
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"

S3 = boto3.client("s3")
EC2 = boto3.client("ec2")
ECS = boto3.client("ecs")
ELBV2 = boto3.client("elbv2")
SSM = boto3.client("ssm")
TAGGING = boto3.client("resourcegroupstaggingapi")
SNS = boto3.client("sns")


def _log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
        "dry_run": DRY_RUN,
    }
    payload.update(fields)
    print(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    if not STORAGE_BUCKET:
        raise ValueError("STORAGE_BUCKET must be configured")

    baseline = _load_baseline()

    drifts: List[Dict[str, Any]] = []
    drifts.extend(_detect_security_group_drifts(baseline.get("security_groups", [])))
    drifts.extend(_detect_ecs_service_drifts(baseline.get("ecs_services", [])))
    drifts.extend(_detect_listener_drifts(baseline.get("listeners", [])))
    drifts.extend(_detect_parameter_drifts(baseline.get("ssm_parameters", [])))
    drifts.extend(_detect_tag_drifts(baseline.get("resource_tags", [])))

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "baseline_s3_uri": f"s3://{STORAGE_BUCKET}/{BASELINE_OBJECT_KEY}",
        "drift_count": len(drifts),
        "drifts": drifts,
    }

    report_uri = _store_report(report)
    _notify(report, report_uri)

    return {
        "status": "dry_run" if DRY_RUN else "stored",
        "drift_count": len(drifts),
        "report_s3_uri": report_uri,
    }


def _load_baseline() -> Dict[str, Any]:
    try:
        response = S3.get_object(Bucket=STORAGE_BUCKET, Key=BASELINE_OBJECT_KEY)
    except ClientError as exc:
        raise RuntimeError(f"Could not load baseline object s3://{STORAGE_BUCKET}/{BASELINE_OBJECT_KEY}: {exc}") from exc

    return json.loads(response["Body"].read().decode("utf-8"))


def _detect_security_group_drifts(definitions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    drifts: List[Dict[str, Any]] = []
    for definition in definitions:
        group_id = definition.get("id")
        expected_ingress = definition.get("allowed_ingress", [])
        if not group_id:
            continue

        response = EC2.describe_security_groups(GroupIds=[group_id])
        groups = response.get("SecurityGroups", [])
        if not groups:
            drifts.append({"type": "security_group_missing", "id": group_id})
            continue

        actual_rules = _normalize_sg_rules(groups[0].get("IpPermissions", []))
        expected_rules = _normalize_sg_rules(expected_ingress)

        if actual_rules != expected_rules:
            drifts.append(
                {
                    "type": "security_group_ingress_drift",
                    "id": group_id,
                    "expected": expected_rules,
                    "actual": actual_rules,
                }
            )

    return drifts


def _detect_ecs_service_drifts(definitions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    drifts: List[Dict[str, Any]] = []
    for definition in definitions:
        cluster = definition.get("cluster")
        service = definition.get("service")
        if not cluster or not service:
            continue

        response = ECS.describe_services(cluster=cluster, services=[service])
        services = response.get("services", [])
        if not services:
            drifts.append({"type": "ecs_service_missing", "cluster": cluster, "service": service})
            continue

        svc = services[0]
        expected_task_definition = definition.get("task_definition")
        expected_desired_count = definition.get("desired_count")

        if expected_task_definition and svc.get("taskDefinition") != expected_task_definition:
            drifts.append(
                {
                    "type": "ecs_task_definition_drift",
                    "cluster": cluster,
                    "service": service,
                    "expected": expected_task_definition,
                    "actual": svc.get("taskDefinition"),
                }
            )

        if expected_desired_count is not None and int(svc.get("desiredCount", 0)) != int(expected_desired_count):
            drifts.append(
                {
                    "type": "ecs_desired_count_drift",
                    "cluster": cluster,
                    "service": service,
                    "expected": int(expected_desired_count),
                    "actual": int(svc.get("desiredCount", 0)),
                }
            )

    return drifts


def _detect_listener_drifts(definitions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    drifts: List[Dict[str, Any]] = []
    for definition in definitions:
        listener_arn = definition.get("arn")
        if not listener_arn:
            continue

        response = ELBV2.describe_listeners(ListenerArns=[listener_arn])
        listeners = response.get("Listeners", [])
        if not listeners:
            drifts.append({"type": "listener_missing", "arn": listener_arn})
            continue

        listener = listeners[0]
        expected_protocol = definition.get("protocol")
        expected_port = definition.get("port")

        if expected_protocol and listener.get("Protocol") != expected_protocol:
            drifts.append(
                {
                    "type": "listener_protocol_drift",
                    "arn": listener_arn,
                    "expected": expected_protocol,
                    "actual": listener.get("Protocol"),
                }
            )

        if expected_port is not None and int(listener.get("Port", 0)) != int(expected_port):
            drifts.append(
                {
                    "type": "listener_port_drift",
                    "arn": listener_arn,
                    "expected": int(expected_port),
                    "actual": int(listener.get("Port", 0)),
                }
            )

    return drifts


def _detect_parameter_drifts(definitions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    drifts: List[Dict[str, Any]] = []
    for definition in definitions:
        parameter_name = definition.get("name")
        expected_value = definition.get("value")
        if not parameter_name:
            continue

        response = SSM.get_parameter(Name=parameter_name, WithDecryption=True)
        actual_value = response.get("Parameter", {}).get("Value")
        if expected_value is not None and actual_value != str(expected_value):
            drifts.append(
                {
                    "type": "ssm_parameter_drift",
                    "name": parameter_name,
                    "expected": str(expected_value),
                    "actual": actual_value,
                }
            )

    return drifts


def _detect_tag_drifts(definitions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    drifts: List[Dict[str, Any]] = []
    for definition in definitions:
        resource_arn = definition.get("arn")
        expected_tags = definition.get("tags", {})
        if not resource_arn:
            continue

        response = TAGGING.get_resources(ResourceARNList=[resource_arn])
        mappings = response.get("ResourceTagMappingList", [])
        if not mappings:
            drifts.append({"type": "resource_missing_for_tags", "arn": resource_arn})
            continue

        actual_tags = {item.get("Key", ""): str(item.get("Value", "")) for item in mappings[0].get("Tags", [])}
        missing_or_changed = _diff_tags(expected_tags, actual_tags)
        if missing_or_changed:
            drifts.append(
                {
                    "type": "resource_tag_drift",
                    "arn": resource_arn,
                    "expected": expected_tags,
                    "actual": actual_tags,
                    "differences": missing_or_changed,
                }
            )

    return drifts


def _diff_tags(expected: Dict[str, Any], actual: Dict[str, str]) -> Dict[str, Dict[str, str | None]]:
    diff: Dict[str, Dict[str, str | None]] = {}
    for key, expected_value in expected.items():
        actual_value = actual.get(key)
        if actual_value != str(expected_value):
            diff[key] = {
                "expected": str(expected_value),
                "actual": actual_value,
            }
    return diff


def _normalize_sg_rules(rules: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    normalized: List[Dict[str, Any]] = []
    for rule in rules:
        normalized.append(
            {
                "IpProtocol": rule.get("IpProtocol"),
                "FromPort": rule.get("FromPort"),
                "ToPort": rule.get("ToPort"),
                "IpRanges": sorted([item.get("CidrIp") for item in rule.get("IpRanges", []) if item.get("CidrIp")]),
                "Ipv6Ranges": sorted([item.get("CidrIpv6") for item in rule.get("Ipv6Ranges", []) if item.get("CidrIpv6")]),
            }
        )
    normalized.sort(key=lambda item: json.dumps(item, sort_keys=True))
    return normalized


def _store_report(report: Dict[str, Any]) -> str:
    now = datetime.now(timezone.utc)
    key = f"{REPORT_PREFIX}/{now.strftime('%Y/%m/%d')}/drift-{now.strftime('%H%M%S')}.json"
    uri = f"s3://{STORAGE_BUCKET}/{key}"

    if DRY_RUN:
        return uri

    S3.put_object(
        Bucket=STORAGE_BUCKET,
        Key=key,
        Body=json.dumps(report, default=str).encode("utf-8"),
        ContentType="application/json",
    )
    return uri


def _notify(report: Dict[str, Any], report_uri: str) -> None:
    if not SNS_TOPIC_ARN:
        return
    if report.get("drift_count", 0) == 0:
        return

    SNS.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[SRE][DriftDetection] {report['drift_count']} drift(s)",
        Message=json.dumps({"report_s3_uri": report_uri, "drift_count": report["drift_count"]}),
    )