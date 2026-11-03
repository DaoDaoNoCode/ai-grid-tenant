#!/usr/bin/env bash
# Parses the maas-api metrics policy (no cluster): placement on ingress and combined sites, a token Secret with
# metadata only, the ServiceMonitor's bearer token from that Secret over HTTPS with the service CA, read access
# limited to /metrics, the NetworkPolicy limited to the monitoring policy group on 9090, and names derived from
# one prefix. Needs python3 with PyYAML.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
python3 - "$HERE/../hub/11-maas-api-metrics-policy.yaml" <<'END_CHECK'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
fails = 0; total = 0
def check(cond, name, why=""):
    global fails, total; total += 1
    print(("   ok   " if cond else "   FAIL ") + name + ("" if cond else " " + why))
    fails += 0 if cond else 1
pl = [d for d in docs if d["kind"] == "Placement"][0]; sel = pl["spec"]["predicates"][0]["requiredClusterSelector"]["labelSelector"]
check(sel["matchLabels"] == {"ai-grid/enabled": "true"} and sel["matchExpressions"] == [{"key": "ai-grid/role", "operator": "In", "values": ["ingress", "combined"]}], "placed on ingress and combined sites only")
pb = [d for d in docs if d["kind"] == "PlacementBinding"][0]; pol = [d for d in docs if d["kind"] == "Policy"][0]
check(pb["placementRef"]["name"] == pl["metadata"]["name"] and pb["subjects"][0]["name"] == pol["metadata"]["name"], "binding joins the placement and the policy")
objs = {t["objectDefinition"]["kind"]: t["objectDefinition"] for tpl in pol["spec"]["policy-templates"] for t in tpl["objectDefinition"]["spec"]["object-templates"]}
check(set(objs) == {"ServiceAccount", "Secret", "ClusterRole", "ClusterRoleBinding", "NetworkPolicy", "ServiceMonitor"}, "six objects, nothing else", str(set(objs)))
sec = objs["Secret"]
check(sec["type"] == "kubernetes.io/service-account-token" and "data" not in sec and "stringData" not in sec and sec["metadata"]["annotations"]["kubernetes.io/service-account.name"] == objs["ServiceAccount"]["metadata"]["name"], "token Secret carries metadata only, bound to the service account")
sm = objs["ServiceMonitor"]; ep = sm["spec"]["endpoints"][0]
check(ep["scheme"] == "https" and ep["authorization"]["credentials"]["name"] == sec["metadata"]["name"] and ep["authorization"]["credentials"]["key"] == "token" and ep["tlsConfig"]["ca"]["configMap"]["name"] == "openshift-service-ca.crt" and ep["tlsConfig"].get("serverName", "").endswith(".svc"), "ServiceMonitor: HTTPS, token from the Secret, service CA, server name")
check("bearerTokenFile" not in str(sm) and "insecureSkipVerify" not in str(sm), "no token file, no skipped verification")
check(objs["ClusterRole"]["rules"] == [{"nonResourceURLs": ["/metrics"], "verbs": ["get"]}], "read access limited to /metrics")
crb = objs["ClusterRoleBinding"]
check(crb["roleRef"]["name"] == objs["ClusterRole"]["metadata"]["name"] and crb["subjects"] == [{"kind": "ServiceAccount", "name": objs["ServiceAccount"]["metadata"]["name"], "namespace": objs["ServiceAccount"]["metadata"]["namespace"]}], "binding grants the role to the service account only")
np = objs["NetworkPolicy"]; rule = np["spec"]["ingress"][0]
check(np["spec"]["policyTypes"] == ["Ingress"] and rule["ports"] == [{"protocol": "TCP", "port": 9090}] and rule["from"] == [{"namespaceSelector": {"matchLabels": {"network.openshift.io/policy-group": "monitoring"}}}], "NetworkPolicy: monitoring policy group on 9090 only")
check(np["spec"]["podSelector"]["matchLabels"].get("app.kubernetes.io/name") == "maas-api", "NetworkPolicy selects maas-api pods")
check(sm["spec"]["selector"]["matchLabels"] == {"app.kubernetes.io/name": "maas-api", "maas.opendatahub.io/metrics": "true"}, "ServiceMonitor selects RHOAI's metrics Service")
names = [o["metadata"]["name"] for o in objs.values()]
check(all(n.startswith("ai-grid-") for n in names) and all(o["metadata"].get("labels", {}).get("app.kubernetes.io/part-of") == "ai-grid" for o in objs.values()), "names and labels derived from one prefix", str(names))
check(sm["metadata"]["name"] != "maas-api-metrics", "does not replace RHOAI's own ServiceMonitor")
check(all(tpl["objectDefinition"]["spec"].get("pruneObjectBehavior") == "DeleteAll" for tpl in pol["spec"]["policy-templates"]), "objects are removed when the site leaves the MaaS roles")
print(f"maas-api-metrics tests: {total-fails} ok, {fails} failed"); sys.exit(1 if fails else 0)
END_CHECK
