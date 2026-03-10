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


class DummyTaggingClient:
    def __init__(self):
        self.calls = []

    def get_resources(self, ResourceARNList):
        self.calls.append(list(ResourceARNList))
        return {
            "ResourceTagMappingList": [
                {
                    "ResourceARN": arn,
                    "Tags": [{"Key": "Environment", "Value": "dev"}],
                }
                for arn in ResourceARNList
            ]
        }


def test_tags_match_by_environment_and_application():
    mod = load_module("drift/generate_baseline_from_aws.py", "drift_baseline_generator")

    assert mod._tags_match({"Environment": "dev", "Application": "app"}, "dev", "app")
    assert mod._tags_match({"Environment": "dev"}, "dev", None)
    assert not mod._tags_match({"Environment": "prod", "Application": "app"}, "dev", "app")


def test_list_resource_tags_deduplicates_and_batches():
    mod = load_module("drift/generate_baseline_from_aws.py", "drift_baseline_generator")

    dummy = DummyTaggingClient()
    resource_arns = [f"arn:aws:ecs:us-east-1:111122223333:service/cluster/svc-{idx}" for idx in range(25)]
    # include duplicates to validate de-duplication
    resource_arns.extend(resource_arns[:5])

    mappings = mod._list_resource_tags(dummy, resource_arns)
    returned_arns = {item["arn"] for item in mappings}

    assert len(returned_arns) == 25
    assert len(dummy.calls) == 2  # batches of 20 + 5
