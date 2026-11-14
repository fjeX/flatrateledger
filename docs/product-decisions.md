# Product decisions

The calls that shaped Flat Rate Ledger, and why. Most came from the shop floor: something I or another tech ran into, or a bug that showed the first idea was wrong.

---

### RO numbers are not unique

**Decision:** A repair-order number is something you search by, never an identity. Each RO has its own internal ID, and the database has no uniqueness rule on the RO number.

**Why:** Shops recycle RO numbers. Mine cycles through five digits, so the same number comes back months later on a different car. The first version treated the number as unique, and a tech re-logging a recycled number got what looked like a "database down" error. Now a matching number opens a choice: if the old RO is recent, edit it; if it's old, log a new one. The vehicle is what tells two ROs apart, which is why the app recommends entering it.

---

### Efficiency is the headline, and there is one formula for it

**Decision:** Efficiency (flagged hours ÷ hours worked) shows up on every span: days, weeks, pay periods, months, all time. It's the first number on the Insights page. Every screen computes it with the same function.

**Why:** It's the number techs actually care about. And two screens computing "the same" figure two ways will eventually disagree. The day they do, the tech stops trusting both. One function means a pay period's efficiency on the History chart is exactly what the Pay Period page says.

---

### The dashboard stays lean

**Decision:** The dashboard shows only what a tech wants to see unprompted, every day, mid-shift: today, pay-period pace, open tickets. Everything else lives on the page that owns that subject, and each feature gets one home, not a copy on the dashboard.

**Why:** It's the screen you open between ROs. When unpaid time shipped, its first version put a card on the dashboard. It came off right away: useful when you're auditing a period, noise when you're checking pace between jobs.

---

### Unpaid time is its own ledger

**Decision:** Comebacks (redoing a job for free), waiting on parts and waiting on approval are tracked as their own kind of time, with up to three job timers running at once.

**Why:** Flat-rate pay hides this time completely. A comeback flags zero hours by definition, so on a paycheck it doesn't exist. Giving it a ledger turns "I was here all day for 6 hours of pay" into a number a tech can point to.

---

### "Can't calculate" is not "no data"

**Decision:** When a figure can't be computed, the screen says why, and still shows everything else it knows about the record.

**Why:** A comeback flags zero hours, so "actual ÷ flagged" divides by zero. An early version treated that as "never timed" and blanked the whole row, which hid hours of real unpaid rework. The math being impossible describes the calculation, not the job.

---

### The day the work happened ≠ the day it's paid

**Decision:** An RO has a pay date, and each line on it can have its own work date.

**Why:** A real RO can start Tuesday and get an upsell finished Thursday. Shops pay it on one date, but the tech worked two days. Without a work date per line, Tuesday's efficiency looks terrible and Thursday's looks impossible. Moving a line's work day never quietly changes the pay date, and every move can be undone.

---

### Time of day is a wall-clock time, off by default

**Decision:** The time on an RO is stored as the time the tech entered ("14:30"), not as a timestamp, and the field is off until the tech turns it on.

**Why:** A timestamp can show a different *day* depending on the time zone it's read in, and "which day was this job" is the question every pay calculation depends on. It's off by default because many techs do their paperwork at the end of the shift. Silently capturing "9:42 PM" twelve times would create fake data that looks real.

---

### Pay periods are a chain, refined from the paystub

**Decision:** Pay periods start from a usual shape, like the 1st–15th and the 16th to the end of the month, and get corrected from the real paystub, which states the exact dates the hours count for. Moving one period's boundary moves its neighbor's to match.

**Why:** Shops don't follow textbook pay calendars. Periods have to line up with what the paystub says, or the comparison against it means nothing, and the periods can never gap or overlap.

---

### True Time: privacy first

**Decision:** Pooled real-world job times are opt-in. A shared figure is only ever shown when at least five different techs contributed to it, and that rule is enforced twice: once when the figures are computed and again by the database when they're read.

**Why:** Techs should never be identifiable from what they contribute. Enforcing it in two separate layers means a bug in one can't leak data on its own. The shared view stays closed until there's enough data to be honest. Averaging one person's jobs and calling it "the industry" would be worse than showing nothing.

---

### A real demo instead of a sales page

**Decision:** The public demo is the full app, signed in as a sample tech one year in, with every feature used. Nothing a visitor does is saved.

**Why:** A screenshot tells you what a feature is. A year of sample data shows what *your* account could look like, and teaches you to use all of it. It's the same build as production, so the demo can't drift from the real app.

---

### Help ships with the feature

**Decision:** Every change a user can see updates the in-app Help and the "What's new" page in the same release.

**Why:** Stale help is a bug. If a tech has to ask what a word means, the wording failed, so the copy gets fixed, not just explained.
