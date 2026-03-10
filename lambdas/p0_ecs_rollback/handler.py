import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, List

import boto3


LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

ECS = boto3.client("ecs")
ELBV2 = boto3.client("elbv2")


def _log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": LOG_LEVEL,
        "message": message,
    }
    payload.update(fields)
    print(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    action = str(event.get("action", "")).strip().lower()
    cluster = event.get("cluster") or event.get("cluster_arn")
    service = event.get("service") or event.get("service_name")

    if not action:
        raise ValueError("action is required")
    if not cluster or not service:
        raise ValueError("cluster and service are required")

    _log("ecs_rollback_worker_started", action=action, cluster=cluster, service=service)

    if action == "discover_previous":
        return _discover_previous(cluster, service)
    if action == "apply_rollback":
        target_task_definition = event.get("target_task_definition")
        if not target_task_definition:
            raise ValueError("target_task_definition is required for apply_rollback")
        return _apply_rollback(cluster, service, target_task_definition)
    if action == "check_stability":
        return _check_stability(cluster, service)
    if action == "validate_health":
        return _validate_health(cluster, service)

    raise ValueError(f"Unsupported action: {action}")


def _discover_previous(cluster: str, service: str) -> Dict[str, Any]:
    service_data = _describe_service(cluster, service)
    current_task_definition = service_data.get("taskDefinition")
    if not current_task_definition:
        raise RuntimeError("Current task definition not found")

    family = current_task_definition.split("/")[-1].split(":")[0]
    task_definitions = ECS.list_task_definitions(
        familyPrefix=family,
        sort="DESC",
        status="ACTIVE",
        maxResults=20,
    ).get("taskDefinitionArns", [])

    previous = None
    for task_definition in task_definitions:
        if task_definition != current_task_definition:
            previous = task_definition
            break

    if not previous:
        return {
            "cluster": cluster,
            "service": service,
            "current_task_definition": current_task_definition,
            "previous_task_definition": None,
            "rollback_possible": False,
        }

    return {
        "cluster": cluster,
        "service": service,
        "current_task_definition": current_task_definition,
        "previous_task_definition": previous,
        "rollback_possible": True,
    }


def _apply_rollback(cluster: str, service: str, target_task_definition: str) -> Dict[str, Any]:
    response = ECS.update_service(
        cluster=cluster,
        service=service,
        taskDefinition=target_task_definition,
        forceNewDeployment=True,
    )

    deployments = response.get("service", {}).get("deployments", [])
    return {
        "cluster": cluster,
        "service": service,
        "target_task_definition": target_task_definition,
        "deployment_count": len(deployments),
    }


def _check_stability(cluster: str, service: str) -> Dict[str, Any]:
    service_data = _describe_service(cluster, service)
    deployments = service_data.get("deployments", [])
    running_count = int(service_data.get("runningCount", 0))
    desired_count = int(service_data.get("desiredCount", 0))
    pending_count = int(service_data.get("pendingCount", 0))

    stable = len(deployments) == 1 and running_count == desired_count and pending_count == 0
    payload = {
        "cluster": cluster,
        "service": service,
        "stable": stable,
        "running_count": running_count,
        "desired_count": desired_count,
        "pending_count": pending_count,
        "deployment_count": len(deployments),
    }

    if not stable:
        _log("ecs_service_not_stable", **payload)
        raise RuntimeError("SERVICE_NOT_STABLE")

    return payload


def _validate_health(cluster: str, service: str) -> Dict[str, Any]:
    service_data = _describe_service(cluster, service)
    load_balancers = service_data.get("loadBalancers", [])

    unhealthy_targets: List[Dict[str, Any]] = []
    for lb in load_balancers:
        target_group_arn = lb.get("targetGroupArn")
        if not target_group_arn:
            continue

        target_health = ELBV2.describe_target_health(TargetGroupArn=target_group_arn).get(
            "TargetHealthDescriptions", []
        )
        for target in target_health:
            state = (target.get("TargetHealth") or {}).get("State")
            if state != "healthy":
                unhealthy_targets.append(
                    {
                        "target_group_arn": target_group_arn,
                        "target": target.get("Target"),
                        "state": state,
                        "reason": (target.get("TargetHealth") or {}).get("Reason"),
                    }
                )

    payload = {
        "cluster": cluster,
        "service": service,
        "healthy": len(unhealthy_targets) == 0,
        "unhealthy_targets": unhealthy_targets,
    }

    if unhealthy_targets:
        _log("ecs_service_unhealthy_targets", unhealthy_targets=unhealthy_targets)
        raise RuntimeError("UNHEALTHY_TARGETS")

    return payload


def _describe_service(cluster: str, service: str) -> Dict[str, Any]:
    response = ECS.describe_services(cluster=cluster, services=[service])
    services = response.get("services", [])
    if not services:
        raise RuntimeError(f"Service not found: {service}")
    return services[0]