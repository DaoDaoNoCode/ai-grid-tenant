#!/usr/bin/env bash
# Renders the Keycloak app and checks the redirect URI reconciler contract.
# Needs kubectl and PyYAML.
set -Eeuo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

kubectl kustomize "$HERE/.." > "$TMP_DIR/rendered.yaml"

python3 - "$TMP_DIR/rendered.yaml" "$TMP_DIR" <<'PY'
import sys
import yaml

documents = list(yaml.safe_load_all(open(sys.argv[1])))
cron_job = next(document for document in documents
                if document and document.get("kind") == "CronJob"
                and document["metadata"]["name"] == "keycloak-redirect-uris")
assert cron_job["spec"]["schedule"] == "*/5 * * * *"
assert cron_job["spec"]["concurrencyPolicy"] == "Forbid"
pod_spec = cron_job["spec"]["jobTemplate"]["spec"]["template"]["spec"]
assert pod_spec["serviceAccountName"] == "keycloak-redirect-uris"

init_container = pod_spec["initContainers"][0]
update_container = pod_spec["containers"][0]
init_script = init_container["command"][2]
update_script = update_container["command"][2]
assert "ai-grid/enabled=true,ai-grid/role in (ingress,combined)" in init_script
assert "consoleurl.cluster.open-cluster-management.io" in init_script
assert "https://maas.apps.%s/oauth2/callback" in init_script
assert "http://localhost:8000/callback" in init_script
assert "kcadm.sh update" in update_script
assert '--config "$kcadm_config"' in update_script
assert "redirectUris=" in update_script
with open(f"{sys.argv[2]}/init.sh", "w") as stream:
    stream.write(init_script)
with open(f"{sys.argv[2]}/update.sh", "w") as stream:
    stream.write(update_script)
PY

bash -n "$TMP_DIR/init.sh"
bash -n "$TMP_DIR/update.sh"

echo "keycloak-redirect-uris tests: 1 ok, 0 failed"
