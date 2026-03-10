import csv
import io
import json
import os
from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List

import boto3


LOOKBACK_DAYS = int(os.getenv("LOOKBACK_DAYS", "30"))
REPORT_BUCKET = os.getenv("REPORT_BUCKET", "")
REPORT_PREFIX = os.getenv("REPORT_PREFIX", "finops-reports")
GROUP_BY_TAG_KEYS = json.loads(os.getenv("GROUP_BY_TAG_KEYS_JSON", '["Environment","Application","CostCenter"]'))
INCLUDE_SAVINGS_PLANS_ANALYSIS = os.getenv("INCLUDE_SAVINGS_PLANS_ANALYSIS", "true").lower() == "true"
INCLUDE_RESERVATION_ANALYSIS = os.getenv("INCLUDE_RESERVATION_ANALYSIS", "true").lower() == "true"
INCLUDE_RIGHTSIZING_ANALYSIS = os.getenv("INCLUDE_RIGHTSIZING_ANALYSIS", "true").lower() == "true"
RIGHTSIZING_MAX_RESULTS = int(os.getenv("RIGHTSIZING_MAX_RESULTS", "50"))
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "")
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"

CE = boto3.client("ce")
CO = boto3.client("compute-optimizer")
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

    savings_plans = _fetch_savings_plans_utilization(start_date, end_date) if INCLUDE_SAVINGS_PLANS_ANALYSIS else {}
    reservations = _fetch_reservation_utilization(start_date, end_date) if INCLUDE_RESERVATION_ANALYSIS else {}
    rightsizing = _fetch_rightsizing_recommendations() if INCLUDE_RIGHTSIZING_ANALYSIS else {}

    top_wastes = _compute_top_wastes(
        by_service=by_service,
        by_tags=by_tags,
        savings_plans=savings_plans,
        reservations=reservations,
        rightsizing=rightsizing,
    )

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
        "savings_plans_utilization": savings_plans,
        "reservation_utilization": reservations,
        "rightsizing_recommendations": rightsizing,
        "top_wastes": top_wastes,
    }

    csv_files = {
        "services": _to_csv(by_service, ["group", "amount", "unit"]),
        "accounts": _to_csv(by_account, ["group", "amount", "unit"]),
        "wastes": _to_csv(top_wastes, ["category", "group", "amount", "unit", "details"]),
        "rightsizing": _to_csv(rightsizing.get("recommendations", []), ["account_id", "instance_arn", "current_type", "recommended_type", "estimated_monthly_savings", "currency"]),
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
    _log("finops_report_finished", status=response["status"], files=len(storage), wastes=len(top_wastes))
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


def _fetch_savings_plans_utilization(start_date: date, end_date: date) -> Dict[str, Any]:
    try:
        response = CE.get_savings_plans_utilization(
            TimePeriod={"Start": start_date.isoformat(), "End": end_date.isoformat()},
            Granularity="MONTHLY",
        )
    except Exception as exc:  # noqa: BLE001
        return {
            "available": False,
            "error": str(exc),
            "unused_commitment": 0.0,
            "utilization_percentage": None,
        }

    periods = response.get("SavingsPlansUtilizationsByTime", [])
    total_unused = 0.0
    total_commitment = 0.0
    utilization_pct = None

    if periods:
        utilization = periods[-1].get("Utilization", {})
        total_unused = float(utilization.get("UnusedCommitment", "0") or 0)
        total_commitment = float(utilization.get("TotalCommitment", "0") or 0)
        utilization_pct = float(utilization.get("UtilizationPercentage", "0") or 0)

    return {
        "available": True,
        "unused_commitment": round(total_unused, 2),
        "total_commitment": round(total_commitment, 2),
        "utilization_percentage": round(utilization_pct, 2) if utilization_pct is not None else None,
    }


def _fetch_reservation_utilization(start_date: date, end_date: date) -> Dict[str, Any]:
    try:
        response = CE.get_reservation_utilization(
            TimePeriod={"Start": start_date.isoformat(), "End": end_date.isoformat()},
            Granularity="MONTHLY",
        )
    except Exception as exc:  # noqa: BLE001
        return {
            "available": False,
            "error": str(exc),
            "unused_amount": 0.0,
            "utilization_percentage": None,
        }

    periods = response.get("UtilizationsByTime", [])
    unused_amount = 0.0
    utilization_pct = None

    if periods:
        total = periods[-1].get("Total", {})
        unused_amount = float(total.get("UnusedAmortizedUpfrontFeePlusUnusedRecurringFee", "0") or 0)
        utilization_pct = float(total.get("UtilizationPercentage", "0") or 0)

    return {
        "available": True,
        "unused_amount": round(unused_amount, 2),
        "utilization_percentage": round(utilization_pct, 2) if utilization_pct is not None else None,
    }


def _fetch_rightsizing_recommendations() -> Dict[str, Any]:
    try:
        enrollment = CO.get_enrollment_status()
        if enrollment.get("status") != "Active":
            return {
                "available": False,
                "reason": f"Compute Optimizer enrollment status is {enrollment.get('status')}",
                "recommendations": [],
                "total_estimated_monthly_savings": 0.0,
                "currency": "USD",
            }

        recommendations: List[Dict[str, Any]] = []
        next_token = None
        while True:
            payload: Dict[str, Any] = {"maxResults": RIGHTSIZING_MAX_RESULTS}
            if next_token:
                payload["nextToken"] = next_token

            response = CO.get_ec2_instance_recommendations(**payload)
            for item in response.get("instanceRecommendations", []):
                options = item.get("recommendationOptions", [])
                if not options:
                    continue

                best = options[0]
                savings_obj = best.get("savingsOpportunity", {})
                savings_value = float((savings_obj.get("estimatedMonthlySavings") or {}).get("value", 0) or 0)
                currency = (savings_obj.get("estimatedMonthlySavings") or {}).get("currency", "USD")

                recommendations.append(
                    {
                        "account_id": item.get("accountId"),
                        "instance_arn": item.get("instanceArn"),
                        "current_type": item.get("currentInstanceType"),
                        "recommended_type": best.get("instanceType"),
                        "estimated_monthly_savings": round(savings_value, 2),
                        "currency": currency,
                    }
                )

            next_token = response.get("nextToken")
            if not next_token:
                break

        recommendations.sort(key=lambda row: float(row.get("estimated_monthly_savings", 0.0)), reverse=True)
        total_savings = round(sum(float(row.get("estimated_monthly_savings", 0.0)) for row in recommendations), 2)

        return {
            "available": True,
            "recommendations": recommendations[:RIGHTSIZING_MAX_RESULTS],
            "total_estimated_monthly_savings": total_savings,
            "currency": recommendations[0]["currency"] if recommendations else "USD",
        }
    except Exception as exc:  # noqa: BLE001
        return {
            "available": False,
            "error": str(exc),
            "recommendations": [],
            "total_estimated_monthly_savings": 0.0,
            "currency": "USD",
        }


def _compute_top_wastes(
    by_service: List[Dict[str, Any]],
    by_tags: Dict[str, List[Dict[str, Any]]],
    savings_plans: Dict[str, Any],
    reservations: Dict[str, Any],
    rightsizing: Dict[str, Any],
) -> List[Dict[str, Any]]:
    candidates: List[Dict[str, Any]] = []

    for row in by_service[:10]:
        candidates.append(
            {
                "category": "high_cost_service",
                "group": row["group"],
                "amount": row["amount"],
                "unit": row["unit"],
                "details": "High absolute service spend in lookback window",
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
                        "details": f"Costs without {tag_key} tag attribution",
                    }
                )

    if savings_plans.get("available"):
        unused_commitment = float(savings_plans.get("unused_commitment", 0.0))
        if unused_commitment > 0:
            candidates.append(
                {
                    "category": "savings_plans_underutilized",
                    "group": "SavingsPlans",
                    "amount": round(unused_commitment, 2),
                    "unit": "USD",
                    "details": f"Utilization={savings_plans.get('utilization_percentage')}%",
                }
            )

    if reservations.get("available"):
        unused_amount = float(reservations.get("unused_amount", 0.0))
        if unused_amount > 0:
            candidates.append(
                {
                    "category": "ri_underutilized",
                    "group": "ReservedInstances",
                    "amount": round(unused_amount, 2),
                    "unit": "USD",
                    "details": f"Utilization={reservations.get('utilization_percentage')}%",
                }
            )

    for row in rightsizing.get("recommendations", [])[:10]:
        savings = float(row.get("estimated_monthly_savings", 0.0))
        if savings <= 0:
            continue
        candidates.append(
            {
                "category": "rightsizing_opportunity",
                "group": row.get("instance_arn", "instance"),
                "amount": round(savings, 2),
                "unit": row.get("currency", "USD"),
                "details": f"{row.get('current_type')} -> {row.get('recommended_type')}",
            }
        )

    candidates.sort(key=lambda item: float(item["amount"]), reverse=True)
    return candidates[:20]


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