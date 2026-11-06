---
name: orchestrator
description: >
  Describes best practices on setting and configuring Nomad and Podman orchestration. Load whenever working on orchestrator project/repo or dealing with services/containers.
---

Rules:

- really good source of services can be found at https://selfh.st/apps/
- services should always be set to warning level, and all levels should be listed in a comment on the right
- services should not have their own auth, they should be either using the orchestrator auth service or in cases where security requires, their own
- idealy services should be stateless, and prefer sqlite on services that need DB
- try to keep as few moving parts as reasonable
- secrets should come from sops encrypted files
