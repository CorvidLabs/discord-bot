---
id: bring-the-discord-surface-across-gateway-lifecycle-slash-command-registration-validated-offline-the-interaction-router
state: draft
type: feature
base_commit: 769ac92a79230935f4eff9856af9d6f964b15a33
---

# Bring the Discord surface across: gateway lifecycle, slash command registration validated offline, the interaction router, the reply layer and its payload bounds, and cards as values

## Intent

Bring the Discord surface across: gateway lifecycle, slash command registration validated offline, the interaction router, the reply layer and its payload bounds, and cards as values

## Affected Canonical Specs

- None

## Acceptance Criteria

- Every command definition is validated offline, before anything is registered with Discord, and a definition Discord would reject fails a test rather than crash-looping a boot. A handler that will take longer than three seconds defers first, and one that can outlive a fifteen minute interaction token reaches the person who asked another way. Every reply is bounded in the units Discord counts, and an over-long payload is refused with a message rather than becoming a reply that never arrives. A card is a value a test can assert on without a gateway. The whole surface is exercised with no token, no network and no guild.

## No-spec Rationale

A new Discord target arrives with its own contract under specs/, which is an addition. No merged module's canonical spec text changes.
