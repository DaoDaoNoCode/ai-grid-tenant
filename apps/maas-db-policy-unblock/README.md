# MaaS database policy unblock

This Application creates a second `PlacementBinding` for the existing
`maas-db-replication-secrets` Policy. It exists to let an already-running Argo CD
sync operation finish when the Policy was created before its original binding.

Once `maas-db` is healthy and its own `PlacementBinding` exists, this Application
can be removed. Its binding has a distinct name, so deleting it does not remove
the primary binding used by `maas-db`.
