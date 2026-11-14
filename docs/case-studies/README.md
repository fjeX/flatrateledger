# Case studies

Real problems from building and running Flat Rate Ledger: what broke, how I tracked it down, what I changed, and what I took from it.

| Story | What it shows |
|---|---|
| [**The rate limiter that never ran**](rate-limiter-that-never-ran.md) | Sign-in protection that looked finished and had never run in production. Finding a control that's off but looks on, making safety the default, and proving it on the live site with a control case. |
| [**The visual tests that failed on a schedule**](visual-tests-that-failed-on-a-schedule.md) | Screenshot tests nobody could trust, rebuilt on frozen data and a frozen clock. Then two subtler bugs the fix exposed: dates baked in at build time, and light-mode screenshots that were dark. |
| [**The server that went quiet for 9 hours**](server-that-went-quiet.md) | A production server that lost its network address and kept running silently. Proving the cause from three independent logs, and why a watchdog can't live in the thing it watches. |
| [**Moving to the cloud with every record intact**](moving-to-the-cloud.md) | Moving a live app with real users from a homelab to Vercel and Supabase Cloud: a rehearsal that caught a real bug, a step-by-step script with abort conditions, and 48 minutes to live. |
