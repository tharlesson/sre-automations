#!/usr/bin/env python3
"""Generate a drift baseline JSON from real AWS resources."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Sequence, Tuple

import boto3
from botocore.exceptions import BotoCoreError, ClientError


def _log(message: str, **fields: Any) -> None:
    payload: Dict[str, Any] = {"message": message}
    payload.update(fields)
    print(json.dumps(payload, default=str), file=sys.stderr)


def _to_tag_map(tags: Sequence[Dict[str, Any]] | None) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for tag in tags or []:
        key = tag.get("Key")
        if not key:
            continue
        result[str(key)] = str(tag.get("Value", ""))
    return result


def _tags_match(tags: Dict[str, str], environment: str, application: str | None) -> bool:
    if tags.get("Environment") != environment:
        return False
    if application and tags.get("Application") != application:
        return False
    return True


def _chunk(items: Sequence[str], size: int) -> Iterable[List[str]]:
    for index in range(0, len(items), size):
        yield list(items[index : index + size])


def _list_security_groups(
    ec2: Any,
    environment: str,
    application: str | None,
    limit: int,
) -> List[Dict[str, Any]]:
    filters: List[Dict[str, Any]] = [{"Name": "tag:Environment", "Values": [environment]}]
    if application:
        filters.append({"Name": "tag:Application", "Values": [application]})

    groups: List[Dict[str, Any]] = []
    paginator = ec2.get_paginator("describe_security_groups")
    for page in paginator.paginate(Filters=filters):
        for group in page.get("SecurityGroups", []):
            groups.append(
                {
                    "id": group["GroupId"],
                    "allowed_ingress": group.get("IpPermissions", []),
                }
            )
            if len(groups) >= limit:
                return groups
    return groups


def _list_ecs_services(
    ecs: Any,
    environment: str,
    application: str | None,
    limit: int,
) -> Tuple[List[Dict[str, Any]], List[str]]:
    services: List[Dict[str, Any]] = []
    tagged_arns: List[str] = []

    clusters: List[str] = []
    for page in ecs.get_paginator("list_clusters").paginate():
        clusters.extend(page.get("clusterArns", []))

    for cluster_arn in clusters:
        for page in ecs.get_paginator("list_services").paginate(cluster=cluster_arn):
            service_arns = page.get("serviceArns", [])
            for service_batch in _chunk(service_arns, 10):
                response = ecs.describe_services(
                    cluster=cluster_arn,
                    services=service_batch,
                    include=["TAGS"],
                )
                for service in response.get("services", []):
                    tags = _to_tag_map(service.get("tags", []))
                    if not _tags_match(tags, environment, application):
                        continue
                    services.append(
                        {
                            "cluster": cluster_arn,
                            "service": service.get("serviceName"),
                            "task_definition": service.get("taskDefinition"),
                            "desired_count": int(service.get("desiredCount", 0)),
                        }
                    )
                    service_arn = service.get("serviceArn")
                    if service_arn:
                        tagged_arns.append(str(service_arn))
                    if len(services) >= limit:
                        return services, tagged_arns

    return services, tagged_arns


def _list_listeners(
    elbv2: Any,
    environment: str,
    application: str | None,
    limit: int,
) -> Tuple[List[Dict[str, Any]], List[str]]:
    listeners: List[Dict[str, Any]] = []
    tagged_arns: List[str] = []

    for page in elbv2.get_paginator("describe_load_balancers").paginate():
        for lb in page.get("LoadBalancers", []):
            lb_arn = lb.get("LoadBalancerArn")
            if not lb_arn:
                continue

            tag_response = elbv2.describe_tags(ResourceArns=[lb_arn])
            descriptions = tag_response.get("TagDescriptions", [])
            lb_tags = _to_tag_map(descriptions[0].get("Tags", []) if descriptions else [])
            if not _tags_match(lb_tags, environment, application):
                continue

            response = elbv2.describe_listeners(LoadBalancerArn=lb_arn)
            for listener in response.get("Listeners", []):
                listener_arn = listener.get("ListenerArn")
                if not listener_arn:
                    continue
                listeners.append(
                    {
                        "arn": listener_arn,
                        "protocol": listener.get("Protocol"),
                        "port": listener.get("Port"),
                    }
                )
                tagged_arns.append(str(listener_arn))
                if len(listeners) >= limit:
                    return listeners, tagged_arns

    return listeners, tagged_arns


def _list_ssm_parameters(ssm: Any, prefixes: Sequence[str], limit: int) -> List[Dict[str, Any]]:
    if not prefixes:
        return []

    parameters: List[Dict[str, Any]] = []
    seen: set[str] = set()
    paginator = ssm.get_paginator("get_parameters_by_path")

    for prefix in prefixes:
        for page in paginator.paginate(Path=prefix, Recursive=True, WithDecryption=True):
            for parameter in page.get("Parameters", []):
                name = parameter.get("Name")
                if not name or name in seen:
                    continue
                parameters.append(
                    {
                        "name": name,
                        "value": parameter.get("Value", ""),
                    }
                )
                seen.add(name)
                if len(parameters) >= limit:
                    return parameters
    return parameters


def _list_resource_tags(tagging: Any, resource_arns: Sequence[str]) -> List[Dict[str, Any]]:
    unique_arns = list(dict.fromkeys([arn for arn in resource_arns if arn]))
    if not unique_arns:
        return []

    output: List[Dict[str, Any]] = []
    for arn_batch in _chunk(unique_arns, 20):
        response = tagging.get_resources(ResourceARNList=arn_batch)
        for mapping in response.get("ResourceTagMappingList", []):
            resource_arn = mapping.get("ResourceARN")
            if not resource_arn:
                continue
            output.append(
                {
                    "arn": resource_arn,
                    "tags": _to_tag_map(mapping.get("Tags", [])),
                }
            )

    return output


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate drift baseline from real AWS resources.")
    parser.add_argument("--region", required=True, help="AWS region.")
    parser.add_argument("--profile", default=None, help="Optional AWS profile name.")
    parser.add_argument("--environment", required=True, help="Environment tag value (ex.: dev).")
    parser.add_argument("--application", default=None, help="Optional Application tag value.")
    parser.add_argument(
        "--output",
        default="drift/baseline.initial.json",
        help="Output file path for baseline JSON.",
    )
    parser.add_argument(
        "--ssm-parameter-prefix",
        action="append",
        default=[],
        help="Optional SSM parameter path prefix (can be repeated).",
    )
    parser.add_argument("--max-security-groups", type=int, default=50, help="Max SGs in baseline.")
    parser.add_argument("--max-ecs-services", type=int, default=50, help="Max ECS services in baseline.")
    parser.add_argument("--max-listeners", type=int, default=50, help="Max ELB listeners in baseline.")
    parser.add_argument("--max-ssm-parameters", type=int, default=50, help="Max SSM parameters in baseline.")
    parser.add_argument(
        "--extra-resource-arn",
        action="append",
        default=[],
        help="Optional extra resource ARN for tag baseline (can be repeated).",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()

    session_kwargs: Dict[str, Any] = {"region_name": args.region}
    if args.profile:
        session_kwargs["profile_name"] = args.profile

    try:
        session = boto3.session.Session(**session_kwargs)
        sts = session.client("sts")
        identity = sts.get_caller_identity()
        account_id = identity.get("Account")

        _log(
            "aws_identity_loaded",
            account_id=account_id,
            region=args.region,
            profile=args.profile,
            environment=args.environment,
            application=args.application,
        )

        ec2 = session.client("ec2")
        ecs = session.client("ecs")
        elbv2 = session.client("elbv2")
        ssm = session.client("ssm")
        tagging = session.client("resourcegroupstaggingapi")

        security_groups = _list_security_groups(
            ec2=ec2,
            environment=args.environment,
            application=args.application,
            limit=args.max_security_groups,
        )
        _log("security_groups_collected", count=len(security_groups))

        ecs_services, ecs_service_arns = _list_ecs_services(
            ecs=ecs,
            environment=args.environment,
            application=args.application,
            limit=args.max_ecs_services,
        )
        _log("ecs_services_collected", count=len(ecs_services))

        listeners, listener_arns = _list_listeners(
            elbv2=elbv2,
            environment=args.environment,
            application=args.application,
            limit=args.max_listeners,
        )
        _log("listeners_collected", count=len(listeners))

        ssm_parameters = _list_ssm_parameters(
            ssm=ssm,
            prefixes=args.ssm_parameter_prefix,
            limit=args.max_ssm_parameters,
        )
        _log("ssm_parameters_collected", count=len(ssm_parameters))

        resource_tags = _list_resource_tags(
            tagging=tagging,
            resource_arns=[*ecs_service_arns, *listener_arns, *args.extra_resource_arn],
        )
        _log("resource_tags_collected", count=len(resource_tags))

    except (ClientError, BotoCoreError) as exc:
        _log("baseline_generation_failed", error=str(exc))
        return 1

    baseline = {
        "security_groups": security_groups,
        "ecs_services": ecs_services,
        "listeners": listeners,
        "ssm_parameters": ssm_parameters,
        "resource_tags": resource_tags,
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(baseline, indent=2), encoding="utf-8")

    _log("baseline_written", output_path=str(output_path.resolve()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
