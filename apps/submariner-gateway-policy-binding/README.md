# Submariner gateway policy binding

This Application creates a temporary `PlacementBinding` for the existing
`submariner-gateway-nodes` Policy. It lets an already-running Argo CD operation
finish when the Policy was created before its corrected binding.

Once `cluster-admins` is healthy and its own `PlacementBinding` exists, this
Application can be removed. Its binding has a distinct name, so deleting it does
not remove the primary binding used by `cluster-admins`.
