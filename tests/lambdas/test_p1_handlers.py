import importlib.util
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def load_module(relative_path: str, name: str):
    module_path = REPO_ROOT / relative_path
    spec = importlib.util.spec_from_file_location(name, module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def test_sg_permission_detects_critical_ports():
    mod = load_module("lambdas/p1_sg_exposure_remediation/handler.py", "p1_sg_handler")

    permission = {
        "IpProtocol": "tcp",
        "FromPort": 20,
        "ToPort": 30,
        "IpRanges": [{"CidrIp": "0.0.0.0/0"}],
    }
    assert mod._critical_ports_in_permission(permission, [22, 80]) == [22]


def test_finops_csv_generation():
    mod = load_module("lambdas/p1_finops_report/handler.py", "p1_finops_handler")

    csv_payload = mod._to_csv(
        rows=[{"group": "AmazonEC2", "amount": 10.5, "unit": "USD"}],
        headers=["group", "amount", "unit"],
    )
    assert "group,amount,unit" in csv_payload
    assert "AmazonEC2" in csv_payload


def test_drift_diff_tags():
    mod = load_module("lambdas/p1_drift_detection/handler.py", "p1_drift_handler")

    diff = mod._diff_tags({"Environment": "prod", "Owner": "platform"}, {"Environment": "dev"})
    assert "Environment" in diff
    assert "Owner" in diff


def test_ssm_build_parameters_for_patching():
    mod = load_module("lambdas/p1_ssm_runbooks/handler.py", "p1_ssm_handler")

    params = mod._build_parameters("patching")
    assert "Operation" in params


def test_approval_bridge_keyword_detection():
    mod = load_module("lambdas/p1_approval_bridge/handler.py", "p1_approval_bridge_handler")

    assert mod._is_approval_message("[SRE][SGRemediation] Aprovacao manual requerida", "pending_approval")
    assert not mod._is_approval_message("General notification", "all good")
