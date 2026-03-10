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


def test_scheduler_tag_match():
    mod = load_module("lambdas/p0_environment_scheduler/handler.py", "scheduler_handler")

    assert mod._tags_match({"Environment": "dev", "Schedule": "office-hours"}, {"Environment": "dev"})
    assert not mod._tags_match({"Environment": "prod"}, {"Environment": "dev"})


def test_tag_auditor_default_remediation():
    mod = load_module("lambdas/p0_tag_auditor/handler.py", "tag_auditor_handler")

    tags = mod._build_remediation_tags(["ManagedBy", "Owner"])
    assert tags.get("ManagedBy") in {"Terraform", mod.DEFAULT_TAG_VALUES.get("ManagedBy")}


def test_backup_restore_returns_simulated_when_dry_run():
    mod = load_module("lambdas/p0_backup_validation/handler.py", "backup_validation_handler")

    response = mod._restore_snapshot("snap-1234567890")
    assert response["simulated"] is True
    assert response["restore_performed"] is False