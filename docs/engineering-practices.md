# Engineering practices

Technicians keep their pay records in Flat Rate Ledger. A bug here isn't a broken button; it's a tech walking into the service manager's office with the wrong numbers. These are the practices that keep that from happening.

The code excerpts below are short rewrites of the real thing, trimmed to show the idea.

## Testing, layer by layer

| Layer | Tool | What it catches |
|---|---|---|
| Logic tests (3,000+) | Vitest | Pay math, efficiency, pay periods, imports, every edge case I've found at work |
| Visual canary | Playwright | Any page that looks different from its approved screenshot |
| Quality checks | Playwright | Horizontal overflow, clipped text, missing focus rings, touch targets under 44 px |
| Write smoke | Playwright | Signing in and actually saving records, on staging, for every change |
| Release smoke | Playwright | The same suite against the exact build about to go live |
| Post-release check | curl | The live site after release; rolls back automatically if it fails |
| Nightly QA bot | Playwright | Uses the live app every night like a real tech and reports what it finds |

## The visual canary

Before every release, CI starts the app and photographs every page: phone and desktop, dark and light. Each photo is compared to an approved baseline.

The first version of this photographed a test account with live data, and it failed constantly. The account gained repair orders every night, so pages kept getting taller with no code change at all. One page grew from 2,580 px to 4,495 px. A check that fails for no reason gets ignored, and then it isn't a check.

The fix was **sample mode**: the app serves frozen sample data instead of the database. But frozen data wasn't enough. The data held still while "days left in this pay period" counted down underneath it. So the clock is frozen too. → [The full story](case-studies/visual-tests-that-failed-on-a-schedule.md)

### Snippet 1: freezing the clock without touching app code

"Today" is read in at least six different places in the app. Passing a frozen date into all of them would mean changing production code in six files, and a seventh added next month would silently un-freeze the tests. Instead, sample mode replaces the global `Date` once, at server start:

```ts
// Runs once at server start, before any page code loads.
export function register() {
  if (!SAMPLE_MODE) return;           // production never takes this path

  const RealDate = Date;
  class FrozenDate extends RealDate {
    constructor(...args: [] | ConstructorParameters<typeof Date>) {
      // Only `new Date()` means "now". Explicit dates must still work:
      // the sample data itself is built with new Date(ms).
      if (args.length === 0) super(FROZEN_NOW_MS);
      else super(...(args as ConstructorParameters<typeof Date>));
    }
    static now() { return FROZEN_NOW_MS; }
  }
  globalThis.Date = FrozenDate as DateConstructor;
  console.warn("[SAMPLE MODE] clock frozen at", new RealDate(FROZEN_NOW_MS).toISOString());
}
```

It changes zero lines of application code, and it catches every future "now" too. With both data and clock frozen, nothing needs masking: numbers and charts are compared for real. The canary runs the same build that ships, switched into sample mode at runtime, so it tests exactly what users get.

## Database changes

- **Staging first.** Every migration runs on the staging database before production.
- **Replayed in CI.** CI replays every migration from scratch on the same Postgres version production runs, so a migration that only worked once on my machine fails the build.
- **Expand-only.** Migrations add; they don't rename or drop something the running app still uses. Old code and new code can both run during a release.
- **Applied by hand, on purpose.** A release that needs a migration is held until I apply it. The new code never meets an old schema.
- **Migrations check their own work.** Security changes end with a query against the database catalog that fails loudly if the change didn't take.

### Snippet 2: row security isn't column security

Row-level security answers "which rows can you touch?" It does not answer "which columns?" If a settings row holds user preferences *and* a field the user must never set, a row policy that lets users update their own settings lets them update that field too.

The fix is a column-level grant, plus a tripwire so the next column added can't slip past it:

```sql
-- Users may update their own settings row (row-level security)...
create policy "own_settings" on public.settings
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ...but only these columns. plan_tier is set by the system, never by the user.
-- INSERT is locked too: otherwise a user could delete their own row and insert
-- a fresh one with plan_tier already filled in.
revoke insert, update on public.settings from authenticated;
grant insert (user_id) on public.settings to authenticated;
grant update (theme, accent, timezone) on public.settings to authenticated;

-- Tripwire: fail this migration if any column other than the protected ones
-- has no UPDATE grant. A new column must be granted (or excluded) on purpose.
do $$
declare ungranted text[];
begin
  select array_agg(c.column_name) into ungranted
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'settings'
     and c.column_name not in ('user_id', 'plan_tier')
     and not exists (
       select 1 from information_schema.column_privileges p
        where p.table_name = 'settings' and p.column_name = c.column_name
          and p.grantee = 'authenticated' and p.privilege_type = 'UPDATE');
  if ungranted is not null then
    raise exception 'settings columns % have no UPDATE grant', ungranted;
  end if;
end $$;
```

The same thinking removed `TRUNCATE` from the app's database roles. Postgres doesn't apply row policies to `TRUNCATE` at all, so it was a gap of a different kind. Nothing could reach it, and I closed it anyway, including for every table created in the future.

## Releasing

Every merge to `master` builds a production release and **holds** it. It goes live only when seven checks pass: typecheck/tests/build, lint, the visual canary, migrations, the write smoke, the release smoke against that exact build, and "are production migrations applied?". → [Release pipeline diagram](../media/diagrams/release-pipeline.md)

### Snippet 3: the post-release check that rolls itself back

Once a release is live, one more job checks the real site. It gives the release three chances over about a minute, so a cold start or a CDN edge still serving the old version doesn't trigger a false rollback. Something actually broken fails all three:

```bash
check() {
  # The sign-in page loads and really is a sign-in page
  code=$(curl -s -o signin.html -w '%{http_code}' --max-time 20 "$PROD/signin")
  [ "$code" = 200 ] && grep -qi 'sign in' signin.html || return 1
  # The home page loads
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$PROD/")" = 200 ] || return 1
  # Signed out, the dashboard redirects to sign-in instead of erroring or leaking
  dash=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "$PROD/dashboard")
  [[ "$dash" =~ ^30[27]\ .*/signin ]] || return 1
}

for round in 1 2 3; do
  check && { echo "healthy (round $round)"; exit 0; }
  [ "$round" -lt 3 ] && sleep 25
done
echo "production failed 3 rounds: rolling back"
rollback_to_previous_release      # restores the last good deployment
```

The third check is the subtle one. A dashboard that returns `200` to a signed-out visitor is broken in the most dangerous way, so the test asserts the redirect, not just "the page loaded".

## Habits that came out of real bugs

- **Break the code to test the test.** After writing a test for a fix, I undo the fix and confirm the test fails. A test that passes either way protects nothing, and I've caught a test that was green for the wrong reason because its own expected values used the same broken math.
- **"Is absent" checks need a control.** A test that asserts something *doesn't* appear passes just as happily when its selector is wrong. Each one is paired with a case where the same selector *must* match.
- **Hours are compared in whole hundredths.** In floating point, `1.0 - 0.9` is `0.0999…`, so a "beat book by 0.1 h" check misses exactly the 0.1 h wins, and book times are round tenths, so those happen constantly. Every comparison and ratio on hours goes through integer hundredths.
- **One formula per question.** Efficiency is computed by one function everywhere. Two screens answering the same question with different math will eventually disagree, and the tech stops trusting both.
- **Green checks aren't proof.** Typecheck, tests and build all passing says the code is consistent, not that the feature reaches the screen. I look at the real page in a real browser before calling something done.
- **A swallowed error still reports.** Best-effort side work may not fail the user's action, but it never fails silently: every `catch` reports to error tracking.
