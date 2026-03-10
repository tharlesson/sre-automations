import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Tuple

import boto3
from botocore.exceptions import ClientError


LOGGER = logging.getLogger()
LOGGER.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

DRY_RUN = os.getenv("DRY_RUN", "true").lower() == "true"
TAG_SELECTOR = json.loads(os.getenv("TAG_SELECTOR_JSON", "{}"))
STATE_BUCKET = os.getenv("STATE_BUCKET", "")
STATE_OBJECT_KEY = os.getenv("STATE_OBJECT_KEY", "scheduler/state.json")
EC2_PRE_STOP_SSM_DOCUMENT = os.getenv("EC2_PRE_STOP_SSM_DOCUMENT", "").strip()
EC2_PRE_STOP_SSM_TIMEOUT_SECONDS = int(os.getenv("EC2_PRE_STOP_SSM_TIMEOUT_SECONDS", "600"))

SESSION = boto3.session.Session()
EC2 = SESSION.client("ec2")
RDS = SESSION.client("rds")
ECS = SESSION.client("ecs")
ASG = SESSION.client("autoscaling")
S3 = SESSION.client("s3")
SSM = SESSION.client("ssm")


def _log(message: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "message": message,
        "dry_run": DRY_RUN,
    }
    payload.update(fields)
    LOGGER.info(json.dumps(payload, default=str))


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    action = _resolve_action(event)
    _log("scheduler_started", action=action, tag_selector=TAG_SELECTOR)

    if not STATE_BUCKET:
        raise ValueError("STATE_BUCKET must be configured.")

    state_store = S3StateStore(STATE_BUCKET, STATE_OBJECT_KEY)

    if action == "stop":
        result = _handle_stop(state_store)
    else:
        result = _handle_start(state_store)

    _log("scheduler_finished", action=action, result=result)
    return result


def _resolve_action(event: Dict[str, Any]) -> str:
    if not isinstance(event, dict):
        raise ValueError("Event must be a dictionary.")

    action = str(event.get("action", "")).strip().lower()
    if action not in {"start", "stop"}:
        raise ValueError("Input must contain action=start|stop.")
    return action


def _handle_stop(state_store: "S3StateStore") -> Dict[str, Any]:
    ecs_state, ecs_scaled = _stop_ecs_services()
    asg_state, asg_scaled = _stop_auto_scaling_groups()

    state_store.save(
        {
            "saved_at": datetime.now(timezone.utc).isoformat(),
            "ecs": ecs_state,
            "asg": asg_state,
        }
    )

    ec2_instances = _find_tagged_ec2("running")
    if EC2_PRE_STOP_SSM_DOCUMENT and ec2_instances:
        _run_pre_stop_ssm(ec2_instances)

    stopped_ec2 = _stop_ec2(ec2_instances)
    stopped_rds_instances, stopped_rds_clusters = _stop_rds()

    return {
        "action": "stop",
        "state_saved": True,
        "stopped_ec2": len(stopped_ec2),
        "stopped_rds_instances": len(stopped_rds_instances),
        "stopped_rds_clusters": len(stopped_rds_clusters),
        "scaled_ecs_services": ecs_scaled,
        "scaled_asg_groups": asg_scaled,
    }


def _handle_start(state_store: "S3StateStore") -> Dict[str, Any]:
    started_ec2 = _start_ec2(_find_tagged_ec2("stopped"))
    started_rds_instances, started_rds_clusters = _start_rds()

    state = state_store.load()
    restored_ecs = _restore_ecs_services((state or {}).get("ecs", {}))
    restored_asg = _restore_auto_scaling_groups((state or {}).get("asg", {}))

    return {
        "action": "start",
        "state_loaded": state is not None,
        "started_ec2": len(started_ec2),
        "started_rds_instances": len(started_rds_instances),
        "started_rds_clusters": len(started_rds_clusters),
        "restored_ecs_services": restored_ecs,
        "restored_asg_groups": restored_asg,
    }


def _ec2_filters(state: str) -> List[Dict[str, Any]]:
    filters = [{"Name": "instance-state-name", "Values": [state]}]
    for key, value in TAG_SELECTOR.items():
        filters.append({"Name": f"tag:{key}", "Values": [str(value)]})
    return filters


def _find_tagged_ec2(state: str) -> List[str]:
    instance_ids: List[str] = []
    paginator = EC2.get_paginator("describe_instances")
    for page in paginator.paginate(Filters=_ec2_filters(state)):
        for reservation in page.get("Reservations", []):
            for instance in reservation.get("Instances", []):
                instance_ids.append(instance["InstanceId"])
    return instance_ids


def _run_pre_stop_ssm(instance_ids: List[str]) -> None:
    _log(
        "ec2_pre_stop_ssm_start",
        document=EC2_PRE_STOP_SSM_DOCUMENT,
        instance_count=len(instance_ids),
    )

    if DRY_RUN:
        return

    response = SSM.send_command(
        InstanceIds=instance_ids,
        DocumentName=EC2_PRE_STOP_SSM_DOCUMENT,
        TimeoutSeconds=EC2_PRE_STOP_SSM_TIMEOUT_SECONDS,
    )
    command_id = response["Command"]["CommandId"]
    deadline = time.time() + EC2_PRE_STOP_SSM_TIMEOUT_SECONDS

    while time.time() < deadline:
        invocations = SSM.list_command_invocations(CommandId=command_id, Details=True).get(
            "CommandInvocations", []
        )
        if not invocations:
            time.sleep(5)
            continue

        statuses = {item.get("Status") for item in invocations}
        if statuses.issubset({"Success"}):
            _log("ec2_pre_stop_ssm_success", command_id=command_id)
            return
        if any(status in {"Failed", "Cancelled", "TimedOut"} for status in statuses):
            raise RuntimeError(f"SSM pre-stop command failed: {statuses}")
        time.sleep(5)

    raise TimeoutError("Timed out waiting for EC2 pre-stop SSM command to complete.")


def _stop_ec2(instance_ids: List[str]) -> List[str]:
    if not instance_ids:
        return []
    _log("ec2_stop", instances=instance_ids)
    if not DRY_RUN:
        EC2.stop_instances(InstanceIds=instance_ids)
    return instance_ids


def _start_ec2(instance_ids: List[str]) -> List[str]:
    if not instance_ids:
        return []
    _log("ec2_start", instances=instance_ids)
    if not DRY_RUN:
        EC2.start_instances(InstanceIds=instance_ids)
    return instance_ids


def _stop_rds() -> Tuple[List[str], List[str]]:
    stopped_instances: List[str] = []
    stopped_clusters: List[str] = []

    for db in _iter_rds_instances():
        if db.get("DBInstanceStatus") != "available":
            continue
        if not _rds_matches_tags(db["DBInstanceArn"]):
            continue

        identifier = db["DBInstanceIdentifier"]
        _log("rds_instance_stop", db_instance=identifier)
        if not DRY_RUN:
            try:
                RDS.stop_db_instance(DBInstanceIdentifier=identifier)
            except ClientError as exc:
                _log("rds_instance_stop_failed", db_instance=identifier, error=str(exc))
                continue
        stopped_instances.append(identifier)

    for cluster in _iter_rds_clusters():
        if cluster.get("Status") != "available":
            continue
        if not _rds_matches_tags(cluster["DBClusterArn"]):
            continue

        identifier = cluster["DBClusterIdentifier"]
        _log("rds_cluster_stop", db_cluster=identifier)
        if not DRY_RUN:
            try:
                RDS.stop_db_cluster(DBClusterIdentifier=identifier)
            except ClientError as exc:
                _log("rds_cluster_stop_failed", db_cluster=identifier, error=str(exc))
                continue
        stopped_clusters.append(identifier)

    return stopped_instances, stopped_clusters


def _start_rds() -> Tuple[List[str], List[str]]:
    started_instances: List[str] = []
    started_clusters: List[str] = []

    for db in _iter_rds_instances():
        if db.get("DBInstanceStatus") != "stopped":
            continue
        if not _rds_matches_tags(db["DBInstanceArn"]):
            continue

        identifier = db["DBInstanceIdentifier"]
        _log("rds_instance_start", db_instance=identifier)
        if not DRY_RUN:
            try:
                RDS.start_db_instance(DBInstanceIdentifier=identifier)
            except ClientError as exc:
                _log("rds_instance_start_failed", db_instance=identifier, error=str(exc))
                continue
        started_instances.append(identifier)

    for cluster in _iter_rds_clusters():
        if cluster.get("Status") != "stopped":
            continue
        if not _rds_matches_tags(cluster["DBClusterArn"]):
            continue

        identifier = cluster["DBClusterIdentifier"]
        _log("rds_cluster_start", db_cluster=identifier)
        if not DRY_RUN:
            try:
                RDS.start_db_cluster(DBClusterIdentifier=identifier)
            except ClientError as exc:
                _log("rds_cluster_start_failed", db_cluster=identifier, error=str(exc))
                continue
        started_clusters.append(identifier)

    return started_instances, started_clusters


def _iter_rds_instances() -> Iterable[Dict[str, Any]]:
    paginator = RDS.get_paginator("describe_db_instances")
    for page in paginator.paginate():
        for db_instance in page.get("DBInstances", []):
            yield db_instance


def _iter_rds_clusters() -> Iterable[Dict[str, Any]]:
    paginator = RDS.get_paginator("describe_db_clusters")
    for page in paginator.paginate():
        for db_cluster in page.get("DBClusters", []):
            yield db_cluster


def _rds_matches_tags(resource_arn: str) -> bool:
    tags = RDS.list_tags_for_resource(ResourceName=resource_arn).get("TagList", [])
    normalized = {item["Key"]: str(item.get("Value", "")) for item in tags}
    return _tags_match(normalized, TAG_SELECTOR)


def _stop_ecs_services() -> Tuple[Dict[str, Any], int]:
    state: Dict[str, Any] = {"clusters": {}}
    scaled = 0

    for cluster_arn in _list_ecs_clusters():
        service_arns = list(_list_ecs_services(cluster_arn))
        if not service_arns:
            continue

        cluster_state: Dict[str, Any] = {}
        for batch in _chunked(service_arns, 10):
            response = ECS.describe_services(cluster=cluster_arn, services=batch, include=["TAGS"])
            for svc in response.get("services", []):
                if not _tags_match(_service_tags_to_map(svc.get("tags", [])), TAG_SELECTOR):
                    continue

                desired = int(svc.get("desiredCount", 0))
                if desired <= 0:
                    continue

                svc_name = svc["serviceName"]
                cluster_state[svc_name] = {"desired_count": desired}
                _log("ecs_scale_to_zero", cluster=cluster_arn, service=svc_name, desired_count=desired)
                if not DRY_RUN:
                    ECS.update_service(cluster=cluster_arn, service=svc_name, desiredCount=0)
                scaled += 1

        if cluster_state:
            state["clusters"][cluster_arn] = cluster_state

    return state, scaled


def _restore_ecs_services(state: Dict[str, Any]) -> int:
    restored = 0
    for cluster_arn, services in state.get("clusters", {}).items():
        for service_name, config in services.items():
            desired = int(config.get("desired_count", 0))
            _log("ecs_restore", cluster=cluster_arn, service=service_name, desired_count=desired)
            if not DRY_RUN:
                ECS.update_service(cluster=cluster_arn, service=service_name, desiredCount=desired)
            restored += 1
    return restored


def _stop_auto_scaling_groups() -> Tuple[Dict[str, Any], int]:
    state: Dict[str, Any] = {"groups": {}}
    scaled = 0

    paginator = ASG.get_paginator("describe_auto_scaling_groups")
    for page in paginator.paginate():
        for group in page.get("AutoScalingGroups", []):
            tags = {item["Key"]: str(item.get("Value", "")) for item in group.get("Tags", [])}
            if not _tags_match(tags, TAG_SELECTOR):
                continue

            desired = int(group.get("DesiredCapacity", 0))
            if desired <= 0:
                continue

            group_name = group["AutoScalingGroupName"]
            state["groups"][group_name] = {
                "min_size": int(group.get("MinSize", 0)),
                "max_size": int(group.get("MaxSize", 0)),
                "desired_capacity": desired,
            }

            _log("asg_scale_to_zero", auto_scaling_group=group_name, desired_capacity=desired)
            if not DRY_RUN:
                ASG.update_auto_scaling_group(
                    AutoScalingGroupName=group_name,
                    MinSize=0,
                    DesiredCapacity=0,
                )
            scaled += 1

    return state, scaled


def _restore_auto_scaling_groups(state: Dict[str, Any]) -> int:
    restored = 0

    for group_name, config in state.get("groups", {}).items():
        min_size = int(config.get("min_size", 0))
        max_size = int(config.get("max_size", 0))
        desired = int(config.get("desired_capacity", 0))

        _log(
            "asg_restore",
            auto_scaling_group=group_name,
            min_size=min_size,
            max_size=max_size,
            desired_capacity=desired,
        )

        if not DRY_RUN:
            ASG.update_auto_scaling_group(
                AutoScalingGroupName=group_name,
                MinSize=min_size,
                MaxSize=max_size,
                DesiredCapacity=desired,
            )
        restored += 1

    return restored


def _list_ecs_clusters() -> Iterable[str]:
    paginator = ECS.get_paginator("list_clusters")
    for page in paginator.paginate():
        for cluster_arn in page.get("clusterArns", []):
            yield cluster_arn


def _list_ecs_services(cluster_arn: str) -> Iterable[str]:
    paginator = ECS.get_paginator("list_services")
    for page in paginator.paginate(cluster=cluster_arn):
        for service_arn in page.get("serviceArns", []):
            yield service_arn


def _service_tags_to_map(tags: List[Dict[str, str]]) -> Dict[str, str]:
    return {item.get("key", ""): str(item.get("value", "")) for item in tags if item.get("key")}


def _tags_match(resource_tags: Dict[str, str], selector: Dict[str, str]) -> bool:
    if not selector:
        return True
    for key, expected in selector.items():
        if str(resource_tags.get(key, "")).strip() != str(expected).strip():
            return False
    return True


def _chunked(items: List[str], chunk_size: int) -> Iterable[List[str]]:
    for idx in range(0, len(items), chunk_size):
        yield items[idx : idx + chunk_size]


class S3StateStore:
    def __init__(self, bucket: str, key: str) -> None:
        self._bucket = bucket
        self._key = key

    def save(self, payload: Dict[str, Any]) -> None:
        _log("state_save", bucket=self._bucket, key=self._key)
        if DRY_RUN:
            return
        S3.put_object(
            Bucket=self._bucket,
            Key=self._key,
            Body=json.dumps(payload).encode("utf-8"),
            ContentType="application/json",
        )

    def load(self) -> Dict[str, Any] | None:
        _log("state_load", bucket=self._bucket, key=self._key)
        try:
            response = S3.get_object(Bucket=self._bucket, Key=self._key)
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in {"NoSuchKey", "404", "NotFound"}:
                return None
            raise

        return json.loads(response["Body"].read().decode("utf-8"))