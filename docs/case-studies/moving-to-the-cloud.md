# Moving to the cloud with every record intact

> **In short:** I moved Flat Rate Ledger, with real users and their pay records, from my homelab to Vercel and Supabase Cloud. I rehearsed the whole copy against the new database first, ran the real move from a written script where every step had a check and an abort condition, and went live in 48 minutes on a Saturday night. Every table matched exactly, every login carried over, and the verification pass found one bug, fixed right after.

## Why move

The app started on a virtual machine in my homelab, with a self-hosted copy of Supabase in Docker. That got it to real users, but it had limits:

- **One machine, little memory.** The app, its database and all the automation shared one VM, and memory was a constant fight.
- **Deploys were mine to babysit.** Every release was a script I ran and watched.
- **My home internet was the uptime.** If my connection dropped, so did the app.

The plan, decided in July: the app moves to **Vercel**; the database, logins and file storage move to **Supabase Cloud**; the homelab keeps the automation and the backups. Since the app was already built on Supabase, this was a data copy and a configuration change, not a rewrite.

## Rehearse first

Moving the data was the risky part, so I did it twice.

**The rehearsal (October 13)** copied everything into the new production database while the old one stayed live:

- every table's row count matched exactly,
- zero broken references between tables,
- stored photos byte-for-byte identical (checked by hash),
- user IDs preserved, not recreated. Every repair order points to its owner by ID, so recreating accounts would have orphaned every record.

**The test pass (October 14)** ran a preview build of the app against the rehearsed database: email and Google sign-in, two accounts proving they can't see each other's data, photos, password-reset email, the database's own abuse throttle, and the sign-in rate limiter.

That last test **failed**, and that's why rehearsals exist. On Vercel, several copies of the app run at once, each counting sign-in attempts in its own memory, so 11 wrong passwords in a row went straight through. Connecting a shared Redis counter fixed it, and "Redis connected" became a **blocker**: no move without it. → [the rate limiter story](rate-limiter-that-never-ran.md)

## The script

I wrote the move as a script. Every step had three parts:

- **Do:** the exact action.
- **Verify:** what proves it worked.
- **Abort:** what result sends me to the rollback section instead.

The rollback section was written before the move, not during one.

The day before, the pre-checks caught something: the dependency audit had gone red overnight on newly published Next.js security advisories. Moving onto code with a known hole wasn't an option, so I patched it, and the patch went through every release check, on the preview and in production, before the move.

## The move: Saturday, October 24

The plan said Sunday noon. I moved it to **Saturday at 7:27 PM**: past shop hours, nobody logs repair orders until Monday, and it left a full day of slack if something went wrong. The final checks showed two techs had logged work that Saturday afternoon, so they got a text first.

The order mattered:

1. **Stop writes first, then back up.** The old app went to a maintenance page *before* the final safety backup, so the backup held every last write.
2. **Copy in one transaction.** The final copy loaded in a single database transaction: all of it or none of it. **35 of 35 tables matched exactly**, zero broken references, and every account's password hash carried over, so nobody had to reset a password.
3. **Point everything at the new home.** Login settings, production environment variables, and the release checks' smoke-test account.
4. **Release on the temporary address, then switch the domain.** The release passed all its checks on Vercel's own address before DNS moved.
5. **Turn on CAPTCHA last.** Sign-in was proven once with CAPTCHA off and once with it on, so a failure would point to one change, not two.
6. **Forward the old address.** Every old link redirects to the same page on the new domain.
7. **Repoint the automation.** Backups, health checks, the QA bot and the digest switched to the new database. The first cloud backup ran clean.

**Live at about 8:15 PM: 48 minutes.**

## Where the script met reality

A script is a plan. These are the places the night didn't follow it, and how each was handled:

- **Photos didn't need copying.** The new storage already held identical files from the rehearsal. Deleting and re-uploading them would have risked orphaning files, so I proved they matched by hash instead.
- **One setting had to wait.** If the release checks had learned the production URL before DNS pointed there, the post-release check would have failed three times and **automatically rolled back** the release I was trying to launch. I held that setting until after the DNS switch.
- **Secrets that saved as empty.** Piping secret values into the GitHub command line on Windows stored them *blank*, with no error. A later check caught it, and I set them again from files.
- **A rejected access key.** The access key for the auth settings, created that morning, was rejected; a fresh one fixed it.

## Verify, then go to bed

Before calling it done, a verification pass on the live site:

- signing in with a password and with Google,
- creating, editing and deleting a repair order, with a photo,
- sending a bug report and watching it get sorted,
- the rate limiter refusing at its limit,
- **data isolation:** the smoke-test account could see its own 2 repair orders out of roughly 1,900,
- a test error landing in error tracking, tagged with the release.

That pass found one real bug: **errors from the browser were tagged "development"** instead of "production", so the morning digest's "new production errors" filter would have missed every browser crash. The cause was a Next.js detail: browser code only gets an environment variable when the code names it literally. Passing the whole environment object to a function hands the browser an empty object. I fixed it in a release right after the move.

## What I took from it

- **Rehearse the risky part for real.** The rehearsal found a broken rate limiter that would otherwise have shipped.
- **Write the abort conditions before you start.** Deciding under pressure is how a bad step turns into a bad night.
- **Freeze, then back up.** A backup taken while writes are still happening isn't the last word.
- **One change at a time where you can.** CAPTCHA off, then on; the release on the temporary address, then DNS. When something fails, there's only one suspect.
- **Verify the boring things.** The bug I found was in error reporting, the system that tells me about every other bug.
