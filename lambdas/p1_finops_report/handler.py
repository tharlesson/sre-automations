import csv
import io
import json
import os
from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, Iterable, List, Tuple

import boto3


LOOKBACK_DAYS = int(os.getenv("LOOKBACK_DAYS", "30"))
REPORT_BUCKET = os.getenv("REPORT_BUCKET", "")
REPORT_PREFIX = os.getenv("REPORT_PREFIX", "finops-reports")
GROUP_BY_TAG_KEYS = json.loads(os.getenv("GROUP_BY_TAG_KEYS_JSON", '["Environment","Application","CostCenter"]'))
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "")
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"

CE = boto3.client("ce")
S3 = boto3.client("s3")
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
    if not REPORT_BUCKET:
        raise ValueError("REPORT_BUCKET must be configured")

    end_date = date.today()
    start_date = end_date - timedelta(days=LOOKBACK_DAYS)

    total_cost = _fetch_total_cost(start_date, end_date)
    by_account = _fetch_grouped_costs(start_date, end_date, [{"Type": "DIMENSION", "Key": "LINKED_ACCOUNT"}])
    by_service = _fetch_grouped_costs(start_date, end_date, [{"Type": "DIMENSION", "Key": "SERVICE"}])

    by_tags: Dict[str, List[Dict[str, Any]]] = {}
    for tag_key in GROUP_BY_TAG_KEYS:
        by_tags[tag_key] = _fetch_grouped_costs(start_date, end_date, [{"Type": "TAG", "Key": tag_key}])

    top_wastes = _compute_top_wastes(by_service=by_service, by_tags=by_tags)

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "window": {
            "start": start_date.isoformat(),
            "end": end_date.isoformat(),
            "lookback_days": LOOKBACK_DAYS,
        },
        "currency": total_cost.get("unit", "USD"),
        "total_cost": total_cost,
        "cost_by_account": by_account,
        "cost_by_service": by_service,
        "cost_by_tags": by_tags,
        "top_wastes": top_wastes,
    }

    csv_files = {
        "services": _to_csv(by_service, ["group", "amount", "unit"]),
        "accounts": _to_csv(by_account, ["group", "amount", "unit"]),
        "wastes": _to_csv(top_wastes, ["category", "group", "amount", "unit"]),
    }

    storage = _store_report(report, csv_files)
    response = {
        "status": "dry_run" if DRY_RUN else "stored",
        "report_bucket": REPORT_BUCKET,
        "report_prefix": REPORT_PREFIX,
        "generated_files": storage,
        "total_cost": total_cost,
        "top_wastes_count": len(top_wastes),
    }

    _notify(response)
    _log("finops_report_finished", status=response["status"], files=len(storage))
    return response


def _fetch_total_cost(start_date: date, end_date: date) -> Dict[str, Any]:
    response = CE.get_cost_and_usage(
        TimePeriod={"Start": start_date.isoformat(), "End": end_date.isoformat()},
        Granularity="MONTHLY",
        Metrics=["UnblendedCost"],
    )

    amount = 0.0
    unit = "USD"
    for period in response.get("ResultsByTime", []):
        metric = period.get("Total", {}).get("UnblendedCost", {})
        amount += float(metric.get("Amount", "0"))
        unit = metric.get("Unit", unit)

    return {
        "amount": round(amount, 2),
        "unit": unit,
    }


def _fetch_grouped_costs(start_date: date, end_date: date, group_by: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    next_token = None
    grouped: Dict[str, Dict[str, Any]] = {}

    while True:
        payload = {
            "TimePeriod": {"Start": start_date.isoformat(), "End": end_date.isoformat()},
            "Granularity": "DAILY",
            "Metrics": ["UnblendedCost"],
            "GroupBy": group_by,
        }
        if next_token:
            payload["NextPageToken"] = next_token

        response = CE.get_cost_and_usage(**payload)
        for period in response.get("ResultsByTime", []):
            for group in period.get("Groups", []):
                key = " | ".join(group.get("Keys", []))
                metric = group.get("Metrics", {}).get("UnblendedCost", {})
                amount = float(metric.get("Amount", "0"))
                unit = metric.get("Unit", "USD")

                if key not in grouped:
                    grouped[key] = {"group": key, "amount": 0.0, "unit": unit}
                grouped[key]["amount"] += amount

        next_token = response.get("NextPageToken")
        if not next_token:
            break

    rows = list(grouped.values())
    for row in rows:
        row["amount"] = round(float(row.get("amount", 0.0)), 2)

    rows.sort(key=lambda item: item["amount"], reverse=True)
    return rows


def _compute_top_wastes(by_service: List[Dict[str, Any]], by_tags: Dict[str, List[Dict[str, Any]]]) -> List[Dict[str, Any]]:
    candidates: List[Dict[str, Any]] = []

    for row in by_service[:10]:
        candidates.append(
            {
                "category": "high_cost_service",
                "group": row["group"],
                "amount": row["amount"],
                "unit": row["unit"],
            }
        )

    for tag_key, rows in by_tags.items():
        for row in rows:
            if "$" in row["group"] or row["group"].endswith(":"):
                candidates.append(
                    {
                        "category": f"untagged_{tag_key.lower()}",
                        "group": row["group"],
                        "amount": row["amount"],
                        "unit": row["unit"],
                    }
                )

    candidates.sort(key=lambda item: float(item["amount"]), reverse=True)
    return candidates[:10]


def _store_report(report: Dict[str, Any], csv_files: Dict[str, str]) -> List[Dict[str, str]]:
    timestamp = datetime.now(timezone.utc)
    base_key = f"{REPORT_PREFIX}/{timestamp.strftime('%Y/%m/%d')}/finops-{timestamp.strftime('%H%M%S')}"

    objects = [
        {
            "type": "json",
            "key": f"{base_key}.json",
            "body": json.dumps(report, default=str).encode("utf-8"),
            "content_type": "application/json",
        }
    ]

    for csv_name, csv_content in csv_files.items():
        objects.append(
            {
                "type": "csv",
                "key": f"{base_key}-{csv_name}.csv",
                "body": csv_content.encode("utf-8"),
                "content_type": "text/csv",
            }
        )

    if DRY_RUN:
        return [{"type": item["type"], "s3_uri": f"s3://{REPORT_BUCKET}/{item['key']}"} for item in objects]

    for item in objects:
        S3.put_object(Bucket=REPORT_BUCKET, Key=item["key"], Body=item["body"], ContentType=item["content_type"])

    return [{"type": item["type"], "s3_uri": f"s3://{REPORT_BUCKET}/{item['key']}"} for item in objects]


def _notify(payload: Dict[str, Any]) -> None:
    if not SNS_TOPIC_ARN:
        return
    SNS.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="[SRE][FinOpsReport] Relatorio gerado",
        Message=json.dumps(payload, default=str),
    )


def _to_csv(rows: List[Dict[str, Any]], headers: List[str]) -> str:
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=headers)
    writer.writeheader()
    for row in rows:
        writer.writerow({key: row.get(key, "") for key in headers})
    return buffer.getvalue()