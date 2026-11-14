# The rate limiter that never ran

> **In short:** Sign-in had rate limiting: real code, tested, wired into every sign-in path. It had never run once in production. The setting it depended on was never set, so every check quietly said "allowed". I found it, made protection the default instead of an add-on, and proved it on the live site with a control case.

## The setup

Flat Rate Ledger lets people sign in with Google or with an email and password. Password sign-in needs protection against someone trying thousands of passwords, so the app had a rate limiter on sign-in, sign-up and password reset. It used a hosted Redis service to count attempts.

It looked finished. It was imported in the right files, called in the right places, and its comments explained exactly what it protected. Anyone reading the code, including a security audit, came away believing sign-in was covered.

## The symptom

There wasn't one. That's the whole problem.

## The investigation

In August I was working through the pre-launch security list and went to confirm the limiter's settings. The limiter only switched on if two environment variables pointed it at Redis. So I checked where they were set:

- not in the example environment file,
- not in the Docker Compose file,
- not in the production server's environment.

**Nowhere.** With no Redis configured, the limiter's guard returned "not configured", and every call returned `ok: true`. The only trace was a one-time warning in container logs nobody reads.

The investigation took one command: search the *production* environment for the variable, not the source code.

## Why it happened

The limiter was written ahead of time for the move to the cloud, where several copies of the app run at once and counters need to live in a shared store like Redis. Until then, the plan said, it would stay inactive.

"Inactive until a later phase" is honest the day you write it. Then it becomes a silent lie. An unprotected sign-in is visibly unprotected and someone fixes it. This one looked protected to every reader, me included.

## The fix

1. **Protection on by default.** The limiter now always runs. With no Redis, it counts in memory, which was exactly right at the time: one server, one process. Redis became an upgrade the limiter picks up automatically, not something it needs before it does anything.
2. **Fail to safety, not to nothing.** If Redis errors, the limiter falls back to counting in memory instead of letting everything through.
3. **The right IP address.** The limiter read the *first* address in the `X-Forwarded-For` header. That one is written by the client, so an attacker could send a new fake address with every request and get a fresh, empty counter each time. It now reads the address added by the proxy the app trusts.
4. **Limits that fit a shop.** Every tech in a shop shares one Wi-Fi connection, so one public IP address. A per-IP limit close to the per-user limit would let one tech trying a few wrong passwords lock out the whole shop: the limiter causing the outage it exists to prevent. Signed-in limits are keyed to the user, and the per-IP ceiling is set at 8× the per-user limit, so it only catches someone working through many accounts.

## The proof

Unit tests proved the counting logic. They couldn't prove the feature was *on*. So after deploying, I tested it against production:

- Wrong password, same email, over and over: **attempt 9 was refused**, exactly at the configured limit.
- **The control:** a different email from the same IP address still signed in normally right after.

Without the control, "refused" could just as easily mean "I locked everybody out." The control is what shows the limiter is working as designed.

## It came back

Two months later, during cloud-move rehearsals, I ran the same test on the new hosting. Eleven wrong passwords on one email went straight through, then the results alternated between allowed and refused. That pattern meant several copies of the app, each counting separately in its own memory. That was the exact case the Redis version was written for. Redis was made a hard requirement for the move; after it was connected, the same test gave exactly 8 attempts and then a wall.

## What I took from it

- **A control that's off but looks on is worse than no control at all.** Nobody goes looking for a gap they think is covered.
- **Default to on.** A safety feature that needs setup before it works will spend time not working.
- **Check the environment, not the code.** The code was correct. The environment it ran in was empty.
- **Prove it fires where it matters, with a control.** Tests prove the logic. Only the live system proves the feature, and only a control case tells "working" from "broken in a new way".
