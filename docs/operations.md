# Operations

Shipping is half the job. The other half is knowing, every morning, that the app is up, the data is safe, and nothing broke overnight, without spending the morning finding out.

The app runs on Vercel and Supabase Cloud. The automation around it runs on a small server in my homelab.

## The 6 AM digest: one email, a glance not a report

Health checks, the nightly QA bot, backups, uptime and error tracking each **write their result down** instead of emailing me. At 6 AM a single digest reads all of them and sends one email.

It's built around one rule: **length is spent only where something is wrong.**

- **Status banner**: all clear, or not.
- **Needs you**: one line per thing I have to act on, and nothing else ever goes here.
- **Overnight**: one line per area (site and server, QA bot, backups, errors and uptime). Anything healthy collapses to a count, like "25 checks, 6 open questions".

A quiet morning is four lines. On Mondays it adds weekly lines: open dependency updates and how much real-world timing data has come in.

**A missing result is an alarm, not a blank.** If the QA bot never wrote its report, the digest says so. A section that silently disappears would read exactly like a quiet, healthy night. Same with numbers: a figure it couldn't fetch says "figures missing", never a silent zero.

The digest is fully deterministic: no part of the email is generated text, so it can't make something up.

## Backups I don't have to trust

| | |
|---|---|
| How often | Every 6 hours |
| What | The full database plus every stored photo |
| Encryption | Encrypted to a key the backup server **cannot decrypt**. The private key lives offline. A stolen backup server can make backups, not read them. |
| Where | Off-site object storage, uploaded with a key that **can't delete** |
| Deletion lock | Object Lock holds every backup for 56 days, so a mistake or a bad actor can't wipe the history. |
| Watched | The digest expects 4 good runs in every 24 hours. Fewer, or any failed run, goes to **Needs you**. |
| Restore | A written, step-by-step restore procedure |

Every step either succeeds or fails loudly. A backup that's missing photos is a failed backup, not a partial success.

The automation server itself is imaged every night by the hypervisor, and the digest checks that job too. That check exists because it once failed silently for weeks. → [case study](case-studies/)

## The nightly QA bot

Every night a bot signs into the live app with its own test account and uses it like a technician: logs repair orders, edits them, walks through the pay period, checks what the pages say. It follows a written checklist of what each page should do, and reports anything that doesn't match.

Its reports are treated as **symptom reports, not diagnoses.** What it *saw* is trusted; *why* it thinks it happened gets re-checked from the code before anything is changed. It has been wrong about the cause often enough to earn that rule.

## Auto-remediation, with a short leash

When the nightly health check or the QA bot reports a problem, an automated fixer looks at it first. It is only allowed to do a short list of safe things on the automation server: free disk space and clear old build cache. It can't touch the app or the database.

Anything it can't safely fix becomes an **escalation**: a row in an incident log that shows up in my morning digest and at the start of my next work session. The same issue fixed three times is escalated instead of fixed a fourth time, because by then it's a real problem.

## Watching from outside

On-server monitoring can't report its own death. Once, the automation server lost its network address and sat there "healthy", running every check, unable to tell anyone, for 9 hours. → [case study](case-studies/)

So the important watchers live elsewhere:

- **Better Stack** probes the live site, the sign-in page and the database's auth service from outside, with email and phone alerts.
- **A heartbeat:** the digest pings Better Stack after the email goes out. No ping by morning means the whole automation chain is down, and I hear about it from outside.
- **The hypervisor watches the server** that runs the automation, from the host.

## Errors

**Sentry** collects errors from production with the release they first appeared in. Any error *first seen* in the last 24 hours goes into the digest's **Needs you** list by name. Old, known errors don't repeat every morning.

## Dependencies

Dependency updates come in weekly. They are applied in their own pull request and go through the same seven release checks as any change. A high or critical security alert goes to **Needs you** the next morning, any day of the week.

## Bug reports from users

Every page has a "Report a bug" link. Reports land in an inbox, get sorted automatically, and the clear ones get a first investigation before I look.
