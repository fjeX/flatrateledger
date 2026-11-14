# Architecture

```mermaid
flowchart LR
  tech["📱 Technician<br/>phone in the bay"]

  subgraph app["Web app · Vercel"]
    next["Next.js (App Router)<br/>Server Components + Server Actions<br/>TypeScript"]
  end

  subgraph data["Supabase"]
    pg[("Postgres<br/>row-level security<br/>on every table")]
    auth["Auth<br/>email + Google sign-in"]
    storage["Storage<br/>RO photos"]
    fn["Edge Functions"]
  end

  subgraph watch["Watching it"]
    sentry["Sentry<br/>errors"]
    uptime["Better Stack<br/>uptime + alerts"]
  end

  subgraph ops["Automation host"]
    bot["Nightly QA bot<br/>(Playwright)"]
    backup["Backups every 6 h<br/>encrypted"]
    digest["6 AM digest<br/>one email"]
  end

  b2[("Backblaze B2<br/>off-site, object-locked")]
  email["Resend<br/>transactional email"]

  tech -->|HTTPS| next
  next --> pg
  next --> auth
  next --> storage
  next --> fn
  auth --> email
  next -.-> sentry
  uptime -.->|probes| next
  bot -->|drives the live app| next
  backup -->|dump DB + photos| pg
  backup --> b2
  digest -.->|reads| sentry
  digest -.->|reads| uptime
  digest -.->|reads| bot
  digest -.->|reads| backup
```

**Why this shape**

- **Server-side by default.** Pages render on the server and writes go through Server Actions, so the browser never holds database credentials and the phone does little work on a slow shop connection.
- **Security lives in the database.** Every table has row-level security, so a bug in the app code still can't show one technician another technician's records.
- **One email a day.** Health checks, the QA bot, backups and error tracking each write their results down. A single morning digest reads all of them and shows only what needs attention.
