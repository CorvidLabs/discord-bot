# Security Policy

## Reporting a vulnerability

Report it privately, through GitHub's private security advisories: open the
**Security** tab of this repository, choose **Report a vulnerability**, and
write it up there. That thread is visible only to you and the maintainers until
we publish it.

Please do not open a public issue, a pull request or a discussion for a
suspected vulnerability, and please do not post it in a chat server. A public
report is a working exploit handed to everybody who reads it.

## What must never be a public issue

This project is built to run a bot that signs blockchain transactions with a hot
wallet, verifies wallet ownership over a webhook, and pays a crowd from a finite
reserve. A mistake in any of those spends real value that nobody can claw back.
So a finding that touches:

- **key handling**: a mnemonic or private key that could be logged, persisted,
  echoed back to a user, or read out of a process,
- **the payout path**: anything that could pay twice, pay somebody who is not
  eligible, pay past a limit or an allocation, or let a record of a payment be
  lost or forged,
- **the verification webhook**: anything that could let somebody claim a wallet
  they do not control, replay a challenge, or forge an authenticated request,

should go through a private advisory, always, even when it looks minor and even
when the affected code is not written yet. Judgement about severity is ours to
get wrong in private.

Everything else, a crash, a wrong figure on a card, a build failure, is an
ordinary issue and very welcome as one.

## What to include

- What you did, in enough detail for us to reproduce it.
- What happened, and what you expected instead.
- Which commit or tag you were on.
- What you think the impact is. A guess is fine.

Proof-of-concept code is useful. Please keep it in the advisory thread.

## What happens next

We will acknowledge the report within a few days and tell you what we think of
it. If we agree it is a vulnerability, we will fix it, credit you in the
advisory unless you would rather we did not, and publish the advisory once a fix
is available. If we disagree, we will say why, and you are welcome to argue.

## Scope

This repository. The engine here has no network access, no key material and no
persistence of its own, so most reports will be about how a host is expected to
use it. Those still count: an API that is easy to hold wrong is a finding.
