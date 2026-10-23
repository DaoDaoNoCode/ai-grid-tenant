# Spoke metrics collection

The hub's collector selects the ScrapeConfigs in open-cluster-management-observability because
they sit on its own cluster. The addon does not distribute them, so a managed cluster's collector
selects nothing until these exist there. They live in redhat-ai-grid because a managed cluster has
no open-cluster-management-observability namespace.

The engine series are absent here. The hub federates them from user workload monitoring, which a
self-managed cluster does not enable by default.
