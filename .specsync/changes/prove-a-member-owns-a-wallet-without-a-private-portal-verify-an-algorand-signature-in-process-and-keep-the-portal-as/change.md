---
id: prove-a-member-owns-a-wallet-without-a-private-portal-verify-an-algorand-signature-in-process-and-keep-the-portal-as
state: draft
type: feature
base_commit: 769ac92a79230935f4eff9856af9d6f964b15a33
---

# Prove a member owns a wallet without a private portal: verify an Algorand signature in process, and keep the portal as one option rather than the only one

## Intent

Prove a member owns a wallet without a private portal: verify an Algorand signature in process, and keep the portal as one option rather than the only one

## Affected Canonical Specs

- `verify`

## Acceptance Criteria

- A member proves a wallet is theirs and the bot never sees a key. Somebody who clones this repository can run verification without standing up a second service, which is the difference between a product and a demo. Whatever a member signs cannot be replayed, cannot be used for a different server, expires, and names in its own bytes the opaque subject the session was minted for, so that a proof cannot be moved to another member's session. A relayed prompt, where somebody runs the command themselves and sends the link to a member, is answered **on the operator's own page** rather than in the signed bytes: the page names the chat account the session belongs to, in the words a member already knows that account by, with a warning that only they should ever open this link, and the reply carries the same warning. That is sufficient against this attack because the victim is on the operator's real page, which cannot be made to lie about whose session it is; putting a person's name in the signed bytes would additionally defend a counterfeit page, which is a different attack with a different answer, and would cost the rule that nothing person-derived crosses below the chat boundary. The opaque subject line stays beside it rather than being replaced by it. `/verify` also takes an optional wallet argument, which pins the session to one address and refuses a proof signed by any other with a reason of its own; it may be a name rather than an address, resolved by the host through a naming service that fails soft, so a service that cannot be reached asks the member for the raw address instead and stops neither the boot nor verification. The accepted proof is a zero amount self payment whose fee is bounded at the network minimum rather than at zero, so a leaked blob costs a member a fraction of a cent instead of their balance and no wallet is locked out by a fee policy the page cannot enforce inside it. What is left over is a first-time verifier who does not read the warning, and `context.md` says so plainly rather than claiming the attack closed. A portal remains supported for operators who want the hosted flow, against the contract in docs/VERIFICATION.md, and the bot half is the same either way. The whole path is exercised with no network and no live wallet, using generated keys.

## No-spec Rationale

Not applicable
