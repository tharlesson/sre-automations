import json
import os
import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

import boto3


EVIDENCE_BUCKET = os.getenv("EVIDENCE_BUCKET", "")
EVIDENCE_PREFIX = os.getenv("EVIDENCE_PREFIX", "incident-evidence")
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "")
TARGET_GROUP_ARNS = json.loads(os.getenv("TARGET_GROUP_ARNS", "[]"))
LOG_GROUP_NAMES = json.loads(os.getenv("LOG_GROUP_NAMES", "[]"))
ECS_CLUSTER_ARNS = json.loads(os.getenv("ECS_CLUSTER_ARNS", "[]"))
EKS_CLUSTER_NAMES = json.loads(os.getenv("EKS_CLUSTER_NAMES", "[]"))

CW = boto3.client("cloudwatch")
LOGS = boto3.client("logs")
ECS = boto3.client("ecs")
EKS = boto3.client("eks")
ELBV2 = boto3.client("elbv2")
CODEDEPLOY = boto3.client("codedeploy")
S3 = boto3.client("s3")
SNS = boto3.client("sns")


def _structured_log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
    }
    payload.update(fields)
    print(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    if not EVIDENCE_BUCKET:
        raise ValueError("EVIDENCE_BUCKET is required")

    _structured_log("incident_evidence_started", event=event)

    alarm_name = _extract_alarm_name(event)
    evidence = {
        "version": "1",
        "collected_at": datetime.now(timezone.utc).isoformat(),
        "alarm": {
            "name": alarm_name,
            "event": event,
            "configuration": _fetch_alarm_configuration(alarm_name) if alarm_name else None,
            "recent_metrics": _fetch_alarm_metrics(alarm_name) if alarm_name else [],
        },
        "recent_logs": _fetch_recent_logs(),
        "ecs_events": _fetch_ecs_events(),
        "eks_events": _fetch_eks_events(),
        "target_group_health": _fetch_target_group_health(),
        "recent_deploy_events": _fetch_recent_deploy_events(),
    }

    s3_key = _save_evidence(evidence, alarm_name)
    _notify(s3_key, alarm_name)

    response = {
        "status": "ok",
        "alarm_name": alarm_name,
        "evidence_s3_uri": f"s3://{EVIDENCE_BUCKET}/{s3_key}",
    }
    _structured_log("incident_evidence_finished", response=response)
    return response


def _extract_alarm_name(event: Dict[str, Any]) -> str | None:
    detail = event.get("detail", {}) if isinstance(event, dict) else {}
    candidates = [
        detail.get("alarmName"),
        detail.get("alarm-name"),
        event.get("AlarmName") if isinstance(event, dict) else None,
    ]
    for candidate in candidates:
        if candidate:
            return str(candidate)
    return None


def _fetch_alarm_configuration(alarm_name: str) -> Dict[str, Any] | None:
    result = CW.describe_alarms(AlarmNames=[alarm_name])
    metric_alarms = result.get("MetricAlarms", [])
    if metric_alarms:
        return metric_alarms[0]

    composite_alarms = result.get("CompositeAlarms", [])
    if composite_alarms:
        return composite_alarms[0]

    return None


def _fetch_alarm_metrics(alarm_name: str) -> List[Dict[str, Any]]:
    configuration = _fetch_alarm_configuration(alarm_name)
    if not configuration or "MetricName" not in configuration:
        return []

    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(minutes=30)
    metric_name = configuration["MetricName"]
    namespace = configuration.get("Namespace", "AWS/CloudWatch")
    statistic = configuration.get("Statistic", "Average")
    period = int(configuration.get("Period", 60))

    dimensions = configuration.get("Dimensions", [])
    datapoints = CW.get_metric_statistics(
        Namespace=namespace,
        MetricName=metric_name,
        Dimensions=dimensions,
        StartTime=start_time,
        EndTime=end_time,
        Period=period,
        Statistics=[statistic],
    ).get("Datapoints", [])

    datapoints.sort(key=lambda item: item.get("Timestamp", datetime.now(timezone.utc)))
    return datapoints[-20:]


def _fetch_recent_logs() -> Dict[str, List[Dict[str, Any]]]:
    if not LOG_GROUP_NAMES:
        return {}

    start_time_ms = int((datetime.now(timezone.utc) - timedelta(minutes=20)).timestamp() * 1000)
    logs_by_group: Dict[str, List[Dict[str, Any]]] = {}

    for log_group in LOG_GROUP_NAMES:
        events = LOGS.filter_log_events(logGroupName=log_group, startTime=start_time_ms, limit=100).get(
            "events", []
        )
        logs_by_group[log_group] = [
            {
                "timestamp": item.get("timestamp"),
                "message": item.get("message"),
                "log_stream": item.get("logStreamName"),
            }
            for item in events
        ]

    return logs_by_group


def _fetch_ecs_events() -> Dict[str, Any]:
    cluster_arns = ECS_CLUSTER_ARNS or ECS.list_clusters(maxResults=5).get("clusterArns", [])
    result: Dict[str, Any] = {}

    for cluster_arn in cluster_arns[:5]:
        services = ECS.list_services(cluster=cluster_arn, maxResults=10).get("serviceArns", [])
        if not services:
            result[cluster_arn] = []
            continue

        described = ECS.describe_services(cluster=cluster_arn, services=services).get("services", [])
        result[cluster_arn] = [
            {
                "service_name": svc.get("serviceName"),
                "status": svc.get("status"),
                "desired_count": svc.get("desiredCount"),
                "running_count": svc.get("runningCount"),
                "events": svc.get("events", [])[:10],
            }
            for svc in described
        ]

    return result


def _fetch_eks_events() -> Dict[str, Any]:
    cluster_names = EKS_CLUSTER_NAMES or EKS.list_clusters(maxResults=5).get("clusters", [])
    result: Dict[str, Any] = {}

    for cluster_name in cluster_names[:5]:
        updates = []
        update_ids = EKS.list_updates(name=cluster_name, maxResults=10).get("updateIds", [])
        for update_id in update_ids[:10]:
            updates.append(EKS.describe_update(name=cluster_name, updateId=update_id).get("update", {}))
        result[cluster_name] = updates

    return result


def _fetch_target_group_health() -> Dict[str, Any]:
    if not TARGET_GROUP_ARNS:
        return {}

    health: Dict[str, Any] = {}
    for target_group_arn in TARGET_GROUP_ARNS:
        described = ELBV2.describe_target_health(TargetGroupArn=target_group_arn).get("TargetHealthDescriptions", [])
        health[target_group_arn] = described
    return health


def _fetch_recent_deploy_events() -> Dict[str, Any]:
    deployments: Dict[str, Any] = {}
    apps = CODEDEPLOY.list_applications().get("applications", [])

    for app_name in apps[:5]:
        group_names = CODEDEPLOY.list_deployment_groups(applicationName=app_name).get("deploymentGroups", [])
        for group in group_names[:5]:
            deployment_ids = CODEDEPLOY.list_deployments(
                applicationName=app_name,
                deploymentGroupName=group,
                includeOnlyStatuses=["Created", "Queued", "InProgress", "Succeeded", "Failed", "Stopped"],
            ).get("deployments", [])
            deployment_details = [
                CODEDEPLOY.get_deployment(deploymentId=deployment_id).get("deploymentInfo", {})
                for deployment_id in deployment_ids[:5]
            ]
            deployments[f"{app_name}:{group}"] = deployment_details

    return deployments


def _save_evidence(evidence: Dict[str, Any], alarm_name: str | None) -> str:
    safe_alarm_name = _slugify(alarm_name or "unknown-alarm")
    now = datetime.now(timezone.utc)
    key = (
        f"{EVIDENCE_PREFIX}/{now.strftime('%Y/%m/%d')}/"
        f"{safe_alarm_name}-{now.strftime('%H%M%S')}-{uuid.uuid4().hex}.json"
    )
    S3.put_object(
        Bucket=EVIDENCE_BUCKET,
        Key=key,
        Body=json.dumps(evidence, default=str).encode("utf-8"),
        ContentType="application/json",
    )
    return key


def _notify(s3_key: str, alarm_name: str | None) -> None:
    if not SNS_TOPIC_ARN:
        _structured_log("sns_topic_missing", message="SNS_TOPIC_ARN not set, skipping notification")
        return

    payload = {
        "alarm_name": alarm_name,
        "evidence_s3_uri": f"s3://{EVIDENCE_BUCKET}/{s3_key}",
    }

    SNS.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[SRE][IncidentEvidence] {alarm_name or 'alarm'}",
        Message=json.dumps(payload),
    )


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9-]+", "-", value.strip().lower())
    return slug.strip("-")[:80] or "alarm"