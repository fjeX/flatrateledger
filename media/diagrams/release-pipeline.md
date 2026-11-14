# Release pipeline

Every merge to `master` ships to real users, so nothing reaches them until it has passed seven checks.

```mermaid
flowchart TD
  pr["Pull request"] --> ci
  pr --> preview["Preview deploy<br/>against the staging database"]

  subgraph ci["CI on every push (GitHub Actions)"]
    direction LR
    t["Typecheck,<br/>tests, build"]
    l["Lint"]
    v["Visual canary<br/>every page × phone/desktop<br/>× dark/light"]
    m["Migrations<br/>replayed on<br/>prod's Postgres version"]
    w["Write smoke<br/>real sign-in, real saves<br/>on staging"]
  end

  ci -->|all green| merge["Merge to master"]
  merge --> build["Production build<br/><b>held, not live</b>"]
  build --> checks

  subgraph checks["7 deployment checks"]
    direction LR
    c5["The 5 CI jobs<br/>on the merged commit"]
    rs["Release smoke<br/>against this exact build"]
    pm["Prod migrations<br/>applied?"]
  end

  checks -->|all pass| promote["Promote: live for users"]
  checks -->|any fail| hold["Stays held<br/>users keep the last good version"]
  promote --> post["Post-release check<br/>on the live site"]
  post -->|fails| rollback["Automatic rollback"]
  post -->|passes| done["✅ Released"]
```

**Why it's built this way**

- **The visual canary runs on frozen data and a frozen clock.** Live data made the screenshots change every night, and a check that fails for no reason gets ignored. With both frozen, nothing needs masking: the numbers and charts are compared for real.
- **The smoke test writes.** Pages that only load prove little; almost every real bug was in saving something. The smoke test signs in and saves records.
- **Database changes are applied by hand, on purpose.** A release that needs a migration waits, held, until the migration is applied. The new code never runs against an old schema.
