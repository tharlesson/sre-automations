import base64
import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Tuple
from urllib.parse import quote

import boto3
import botocore.session
import urllib3
from botocore.config import Config
from botocore.exceptions import ClientError
from botocore.signers import RequestSigner


LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
STATE_BUCKET = os.getenv("STATE_BUCKET", "")
STATE_OBJECT_KEY = os.getenv("STATE_OBJECT_KEY", "environment-scheduler/state.json")
DRY_RUN = os.getenv("DRY_RUN", "false").strip().lower() == "true"
RESTORE_DELAY_SECONDS = int(os.getenv("RESTORE_DELAY_SECONDS", "0"))
EKS_EXCLUDED_NAMESPACES = {
    item.strip()
    for item in os.getenv(
        "EKS_EXCLUDED_NAMESPACES", "kube-system,kube-public,kube-node-lease"
    ).split(",")
    if item.strip()
}

AWS_CONFIG = Config(retries={"max_attempts": 8, "mode": "standard"})
SESSION = boto3.session.Session(region_name=AWS_REGION)
EC2 = SESSION.client("ec2", config=AWS_CONFIG)
RDS = SESSION.client("rds", config=AWS_CONFIG)
ECS = SESSION.client("ecs", config=AWS_CONFIG)
EKS = SESSION.client("eks", config=AWS_CONFIG)
S3 = SESSION.client("s3", config=AWS_CONFIG)


def lambda_handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    action = _resolve_action(event)
    LOGGER.info("Starting action=%s dry_run=%s", action, DRY_RUN)

    if not STATE_BUCKET:
        raise ValueError("STATE_BUCKET environment variable is required.")

    state_store = S3StateStore(bucket=STATE_BUCKET, key=STATE_OBJECT_KEY)

    if action == "stop":
        response = _handle_stop(state_store)
    elif action == "start":
        response = _handle_start(state_store)
    else:
        raise ValueError("Action must be 'start' or 'stop'.")

    LOGGER.info("Finished action=%s response=%s", action, json.dumps(response))
    return response


def _handle_stop(state_store: "S3StateStore") -> Dict[str, Any]:
    state: Dict[str, Any] = {
        "version": "1",
        "saved_at": datetime.now(timezone.utc).isoformat(),
        "region": AWS_REGION,
        "ecs": {"clusters": {}},
        "eks": {"clusters": {}},
    }

    ecs_state, ecs_scaled = collect_and_scale_down_ecs_services()
    eks_state, eks_scaled = collect_and_scale_down_eks_deployments()
    state["ecs"] = ecs_state
    state["eks"] = eks_state
    state_store.save(state)

    stopped_rds_instances, stopped_rds_clusters = stop_tagged_rds()
    stopped_ec2_instances = stop_tagged_ec2()

    return {
        "action": "stop",
        "state_saved": True,
        "ecs_services_scaled_to_zero": ecs_scaled,
        "eks_deployments_scaled_to_zero": eks_scaled,
        "stopped_ec2_instances": len(stopped_ec2_instances),
        "stopped_rds_instances": len(stopped_rds_instances),
        "stopped_rds_clusters": len(stopped_rds_clusters),
    }


def _handle_start(state_store: "S3StateStore") -> Dict[str, Any]:
    started_rds_instances, started_rds_clusters = start_tagged_rds()
    started_ec2_instances = start_tagged_ec2()

    if RESTORE_DELAY_SECONDS > 0:
        LOGGER.info(
            "Sleeping %s seconds before restoring ECS/EKS.",
            RESTORE_DELAY_SECONDS,
        )
        time.sleep(RESTORE_DELAY_SECONDS)

    state = state_store.load()
    if state is None:
        LOGGER.warning("No state found. ECS/EKS restore will be skipped.")
        return {
            "action": "start",
            "state_loaded": False,
            "ecs_services_restored": 0,
            "eks_deployments_restored": 0,
            "started_ec2_instances": len(started_ec2_instances),
            "started_rds_instances": len(started_rds_instances),
            "started_rds_clusters": len(started_rds_clusters),
        }

    ecs_restored = restore_ecs_services(state.get("ecs", {}))
    eks_restored = restore_eks_deployments(state.get("eks", {}))

    return {
        "action": "start",
        "state_loaded": True,
        "ecs_services_restored": ecs_restored,
        "eks_deployments_restored": eks_restored,
        "started_ec2_instances": len(started_ec2_instances),
        "started_rds_instances": len(started_rds_instances),
        "started_rds_clusters": len(started_rds_clusters),
    }


def _resolve_action(event: Dict[str, Any]) -> str:
    if not isinstance(event, dict):
        raise ValueError("Event must be a dictionary.")

    candidates = [
        event.get("action"),
        event.get("operation"),
        (event.get("detail") or {}).get("action") if isinstance(event.get("detail"), dict) else None,
    ]
    action = next((str(value).strip().lower() for value in candidates if value), None)
    if action not in {"start", "stop"}:
        raise ValueError("Input must contain action=start|stop.")
    return action


def stop_tagged_ec2() -> List[str]:
    filters = [
        {"Name": "tag:shutdown", "Values": ["true", "True", "TRUE", "1", "yes", "YES"]},
        {"Name": "instance-state-name", "Values": ["running"]},
    ]
    instance_ids: List[str] = []

    paginator = EC2.get_paginator("describe_instances")
    for page in paginator.paginate(Filters=filters):
        for reservation in page.get("Reservations", []):
            for instance in reservation.get("Instances", []):
                instance_ids.append(instance["InstanceId"])

    if not instance_ids:
        LOGGER.info("No running EC2 instances tagged shutdown=true were found.")
        return []

    LOGGER.info("Stopping EC2 instances: %s", instance_ids)
    if not DRY_RUN:
        EC2.stop_instances(InstanceIds=instance_ids)

    return instance_ids


def start_tagged_ec2() -> List[str]:
    filters = [
        {"Name": "tag:shutdown", "Values": ["true", "True", "TRUE", "1", "yes", "YES"]},
        {"Name": "instance-state-name", "Values": ["stopped"]},
    ]
    instance_ids: List[str] = []

    paginator = EC2.get_paginator("describe_instances")
    for page in paginator.paginate(Filters=filters):
        for reservation in page.get("Reservations", []):
            for instance in reservation.get("Instances", []):
                instance_ids.append(instance["InstanceId"])

    if not instance_ids:
        LOGGER.info("No stopped EC2 instances tagged shutdown=true were found.")
        return []

    LOGGER.info("Starting EC2 instances: %s", instance_ids)
    if not DRY_RUN:
        EC2.start_instances(InstanceIds=instance_ids)

    return instance_ids


def stop_tagged_rds() -> Tuple[List[str], List[str]]:
    stopped_instances: List[str] = []
    stopped_clusters: List[str] = []

    db_paginator = RDS.get_paginator("describe_db_instances")
    for page in db_paginator.paginate():
        for db_instance in page.get("DBInstances", []):
            db_id = db_instance["DBInstanceIdentifier"]
            db_arn = db_instance["DBInstanceArn"]
            status = db_instance["DBInstanceStatus"]
            if status != "available":
                continue
            if not _rds_resource_has_shutdown_tag(db_arn):
                continue

            LOGGER.info("Stopping RDS instance: %s", db_id)
            if not DRY_RUN:
                try:
                    RDS.stop_db_instance(DBInstanceIdentifier=db_id)
                except ClientError as exc:
                    LOGGER.warning("Skipping RDS instance %s due to error: %s", db_id, exc)
                    continue
            stopped_instances.append(db_id)

    cluster_paginator = RDS.get_paginator("describe_db_clusters")
    for page in cluster_paginator.paginate():
        for db_cluster in page.get("DBClusters", []):
            cluster_id = db_cluster["DBClusterIdentifier"]
            cluster_arn = db_cluster["DBClusterArn"]
            status = db_cluster["Status"]
            if status != "available":
                continue
            if not _rds_resource_has_shutdown_tag(cluster_arn):
                continue

            LOGGER.info("Stopping RDS cluster: %s", cluster_id)
            if not DRY_RUN:
                try:
                    RDS.stop_db_cluster(DBClusterIdentifier=cluster_id)
                except ClientError as exc:
                    LOGGER.warning("Skipping RDS cluster %s due to error: %s", cluster_id, exc)
                    continue
            stopped_clusters.append(cluster_id)

    return stopped_instances, stopped_clusters


def start_tagged_rds() -> Tuple[List[str], List[str]]:
    started_instances: List[str] = []
    started_clusters: List[str] = []

    db_paginator = RDS.get_paginator("describe_db_instances")
    for page in db_paginator.paginate():
        for db_instance in page.get("DBInstances", []):
            db_id = db_instance["DBInstanceIdentifier"]
            db_arn = db_instance["DBInstanceArn"]
            status = db_instance["DBInstanceStatus"]
            if status != "stopped":
                continue
            if not _rds_resource_has_shutdown_tag(db_arn):
                continue

            LOGGER.info("Starting RDS instance: %s", db_id)
            if not DRY_RUN:
                try:
                    RDS.start_db_instance(DBInstanceIdentifier=db_id)
                except ClientError as exc:
                    LOGGER.warning("Skipping RDS instance %s due to error: %s", db_id, exc)
                    continue
            started_instances.append(db_id)

    cluster_paginator = RDS.get_paginator("describe_db_clusters")
    for page in cluster_paginator.paginate():
        for db_cluster in page.get("DBClusters", []):
            cluster_id = db_cluster["DBClusterIdentifier"]
            cluster_arn = db_cluster["DBClusterArn"]
            status = db_cluster["Status"]
            if status != "stopped":
                continue
            if not _rds_resource_has_shutdown_tag(cluster_arn):
                continue

            LOGGER.info("Starting RDS cluster: %s", cluster_id)
            if not DRY_RUN:
                try:
                    RDS.start_db_cluster(DBClusterIdentifier=cluster_id)
                except ClientError as exc:
                    LOGGER.warning("Skipping RDS cluster %s due to error: %s", cluster_id, exc)
                    continue
            started_clusters.append(cluster_id)

    return started_instances, started_clusters


def _rds_resource_has_shutdown_tag(resource_arn: str) -> bool:
    tags = RDS.list_tags_for_resource(ResourceName=resource_arn).get("TagList", [])
    for tag in tags:
        if tag.get("Key", "").strip().lower() == "shutdown":
            value = str(tag.get("Value", "")).strip().lower()
            return value in {"true", "1", "yes", "y", "on"}
    return False


def collect_and_scale_down_ecs_services() -> Tuple[Dict[str, Any], int]:
    ecs_state: Dict[str, Any] = {"clusters": {}}
    scaled_services = 0

    for cluster_arn in _list_ecs_clusters():
        services = list(_list_ecs_services(cluster_arn))
        if not services:
            continue

        cluster_state: Dict[str, Dict[str, Any]] = {}
        for service_batch in _chunked(services, 10):
            described = ECS.describe_services(cluster=cluster_arn, services=service_batch)
            for service in described.get("services", []):
                service_name = service["serviceName"]
                service_arn = service["serviceArn"]
                desired_count = int(service.get("desiredCount", 0))
                running_count = int(service.get("runningCount", 0))
                restore_count = running_count if running_count > 0 else desired_count

                if restore_count <= 0:
                    continue

                cluster_state[service_arn] = {
                    "service_name": service_name,
                    "restore_count": restore_count,
                    "running_count": running_count,
                    "desired_count": desired_count,
                }
                _ecs_update_service_desired_count(cluster_arn, service_name, 0)
                scaled_services += 1

        if cluster_state:
            ecs_state["clusters"][cluster_arn] = cluster_state

    return ecs_state, scaled_services


def restore_ecs_services(ecs_state: Dict[str, Any]) -> int:
    restored_services = 0
    clusters = ecs_state.get("clusters", {})

    for cluster_arn, services in clusters.items():
        for service_arn, service_data in services.items():
            service_name = service_data.get("service_name") or service_arn
            restore_count = int(
                service_data.get(
                    "restore_count",
                    service_data.get(
                        "running_count",
                        service_data.get("desired_count", 0),
                    ),
                )
            )
            _ecs_update_service_desired_count(cluster_arn, service_name, restore_count)
            restored_services += 1

    return restored_services


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


def _ecs_update_service_desired_count(cluster_arn: str, service_name: str, desired_count: int) -> None:
    LOGGER.info(
        "Updating ECS service cluster=%s service=%s desired=%s",
        cluster_arn,
        service_name,
        desired_count,
    )
    if DRY_RUN:
        return

    try:
        ECS.update_service(cluster=cluster_arn, service=service_name, desiredCount=desired_count)
    except ClientError as exc:
        LOGGER.warning(
            "Failed to update ECS service cluster=%s service=%s: %s",
            cluster_arn,
            service_name,
            exc,
        )


def collect_and_scale_down_eks_deployments() -> Tuple[Dict[str, Any], int]:
    eks_state: Dict[str, Any] = {"clusters": {}}
    scaled_deployments = 0

    for cluster_name in _list_eks_clusters():
        try:
            k8s_client = KubernetesApiClient(cluster_name=cluster_name)
        except Exception as exc:
            LOGGER.warning("Failed to initialize Kubernetes client for %s: %s", cluster_name, exc)
            continue

        deployments = k8s_client.list_deployments()
        cluster_state: Dict[str, Dict[str, Any]] = {}

        for deployment in deployments:
            metadata = deployment.get("metadata", {})
            spec = deployment.get("spec", {})
            status = deployment.get("status", {})
            namespace = metadata.get("namespace", "")
            name = metadata.get("name", "")
            desired_replicas = int(spec.get("replicas") or 0)
            running_replicas = int(
                status.get("readyReplicas")
                or status.get("availableReplicas")
                or status.get("replicas")
                or 0
            )
            restore_replicas = running_replicas if running_replicas > 0 else desired_replicas

            if not namespace or not name:
                continue
            if namespace in EKS_EXCLUDED_NAMESPACES:
                continue
            if restore_replicas <= 0:
                continue

            state_key = f"{namespace}/{name}"
            cluster_state[state_key] = {
                "namespace": namespace,
                "name": name,
                "restore_replicas": restore_replicas,
                "running_replicas": running_replicas,
                "desired_replicas": desired_replicas,
            }

            k8s_client.patch_deployment_replicas(namespace=namespace, name=name, replicas=0)
            scaled_deployments += 1

        if cluster_state:
            eks_state["clusters"][cluster_name] = cluster_state

    return eks_state, scaled_deployments


def restore_eks_deployments(eks_state: Dict[str, Any]) -> int:
    restored_deployments = 0
    clusters = eks_state.get("clusters", {})

    for cluster_name, deployment_map in clusters.items():
        try:
            k8s_client = KubernetesApiClient(cluster_name=cluster_name)
        except Exception as exc:
            LOGGER.warning("Failed to initialize Kubernetes client for %s: %s", cluster_name, exc)
            continue

        for deployment_data in deployment_map.values():
            namespace = deployment_data.get("namespace")
            name = deployment_data.get("name")
            replicas = int(
                deployment_data.get(
                    "restore_replicas",
                    deployment_data.get(
                        "running_replicas",
                        deployment_data.get("desired_replicas", 0),
                    ),
                )
            )
            if not namespace or not name:
                continue

            k8s_client.patch_deployment_replicas(
                namespace=namespace,
                name=name,
                replicas=replicas,
            )
            restored_deployments += 1

    return restored_deployments


def _list_eks_clusters() -> Iterable[str]:
    paginator = EKS.get_paginator("list_clusters")
    for page in paginator.paginate():
        for cluster_name in page.get("clusters", []):
            yield cluster_name


class KubernetesApiClient:
    def __init__(self, cluster_name: str) -> None:
        cluster_info = EKS.describe_cluster(name=cluster_name)["cluster"]
        self.cluster_name = cluster_name
        self.endpoint = cluster_info["endpoint"].rstrip("/")
        self.ca_cert_path = _write_ca_certificate(cluster_name, cluster_info["certificateAuthority"]["data"])
        self.http = urllib3.PoolManager(cert_reqs="CERT_REQUIRED", ca_certs=self.ca_cert_path)

    def list_deployments(self) -> List[Dict[str, Any]]:
        deployments: List[Dict[str, Any]] = []
        next_continue_token = ""

        while True:
            query = f"?limit=500"
            if next_continue_token:
                query += f"&continue={quote(next_continue_token, safe='')}"
            path = f"/apis/apps/v1/deployments{query}"

            payload = self._request("GET", path)
            deployments.extend(payload.get("items", []))
            next_continue_token = (payload.get("metadata") or {}).get("continue", "")
            if not next_continue_token:
                break

        return deployments

    def patch_deployment_replicas(self, namespace: str, name: str, replicas: int) -> None:
        path = (
            f"/apis/apps/v1/namespaces/{quote(namespace, safe='')}"
            f"/deployments/{quote(name, safe='')}"
        )
        body = {"spec": {"replicas": replicas}}
        LOGGER.info(
            "Updating EKS deployment cluster=%s namespace=%s name=%s replicas=%s",
            self.cluster_name,
            namespace,
            name,
            replicas,
        )
        if DRY_RUN:
            return
        self._request("PATCH", path, body=body)

    def _request(self, method: str, path: str, body: Dict[str, Any] = None) -> Dict[str, Any]:
        headers = {
            "Authorization": f"Bearer {_build_eks_bearer_token(self.cluster_name)}",
            "Accept": "application/json",
        }
        request_body = None
        if body is not None:
            headers["Content-Type"] = "application/merge-patch+json"
            request_body = json.dumps(body).encode("utf-8")

        response = self.http.request(
            method=method,
            url=f"{self.endpoint}{path}",
            headers=headers,
            body=request_body,
            timeout=urllib3.Timeout(connect=3.0, read=30.0),
            retries=False,
        )

        if response.status >= 400:
            message = response.data.decode("utf-8", errors="replace")
            raise RuntimeError(
                f"Kubernetes API request failed status={response.status} "
                f"path={path} message={message}"
            )

        if not response.data:
            return {}

        return json.loads(response.data.decode("utf-8"))


def _write_ca_certificate(cluster_name: str, ca_data: str) -> str:
    cert_bytes = base64.b64decode(ca_data)
    cert_path = f"/tmp/{cluster_name}-ca.crt"
    with open(cert_path, "wb") as cert_file:
        cert_file.write(cert_bytes)
    return cert_path


def _build_eks_bearer_token(cluster_name: str) -> str:
    session = botocore.session.get_session()
    credentials = session.get_credentials()
    if credentials is None:
        raise RuntimeError("Could not load AWS credentials to build EKS token.")

    signer = RequestSigner(
        session.get_service_model("sts").service_id,
        AWS_REGION,
        "sts",
        "v4",
        credentials,
        session.get_component("event_emitter"),
    )

    request_params = {
        "method": "GET",
        "url": (
            f"https://sts.{AWS_REGION}.amazonaws.com/"
            "?Action=GetCallerIdentity&Version=2011-06-15"
        ),
        "body": {},
        "headers": {"x-k8s-aws-id": cluster_name},
        "context": {},
    }

    signed_url = signer.generate_presigned_url(
        request_dict=request_params,
        region_name=AWS_REGION,
        expires_in=60,
        operation_name="",
    )
    token = base64.urlsafe_b64encode(signed_url.encode("utf-8")).decode("utf-8")
    return f"k8s-aws-v1.{token.rstrip('=')}"


class S3StateStore:
    def __init__(self, bucket: str, key: str) -> None:
        self.bucket = bucket
        self.key = key

    def save(self, state: Dict[str, Any]) -> None:
        state_json = json.dumps(state, ensure_ascii=True, sort_keys=True).encode("utf-8")
        LOGGER.info("Saving state to s3://%s/%s", self.bucket, self.key)
        if DRY_RUN:
            return
        S3.put_object(
            Bucket=self.bucket,
            Key=self.key,
            Body=state_json,
            ContentType="application/json",
        )

    def load(self) -> Dict[str, Any] | None:
        LOGGER.info("Loading state from s3://%s/%s", self.bucket, self.key)
        try:
            response = S3.get_object(Bucket=self.bucket, Key=self.key)
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in {"NoSuchKey", "404", "NotFound"}:
                return None
            raise

        content = response["Body"].read().decode("utf-8")
        return json.loads(content)


def _chunked(items: List[str], size: int) -> Iterable[List[str]]:
    for idx in range(0, len(items), size):
        yield items[idx : idx + size]
