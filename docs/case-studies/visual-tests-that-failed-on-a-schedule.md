# The visual tests that failed on a schedule

> **In short:** My screenshot tests failed all the time, and almost never because of a real bug. The test account kept gaining data, so every page kept changing. I rebuilt the tests on frozen sample data *and* a frozen clock, then chased down two subtler problems the new setup exposed: dates baked into pages at build time, and "light mode" screenshots that had been dark for four weeks.

## The setup

Flat Rate Ledger has dark and light themes, a phone layout and a desktop layout. A CSS change can break a page I'm not looking at, so I set up visual tests: photograph every page and compare each photo to an approved baseline.

## The symptom

The tests failed constantly. Nearly every failure turned out to be nothing.

The test account was a real account on the live site, and a QA bot logged repair orders on it every night. So every page kept growing. The History page went from **2,580 px tall to 4,495 px** without a single line of CSS changing. I tried masking the parts that change; that hid the pixels, but not the height.

The suite also ran by hand on one machine, against a development server, with baselines that only matched that machine's operating system.

A test that fails for no reason gets ignored, and then it stops being a test.

## The fix, part 1: freeze everything that moves

I added a **sample mode** to the app: one runtime switch that swaps the database for a fixed set of sample data. It's runtime-only, so the same build serves real users and the tests. The tests check exactly what ships.

Frozen data wasn't enough, though. The data held still while the app's idea of "today" kept moving: "3 days left in this pay period" became "2 days left" the next day, and the test failed. "Today" was read in at least six separate places in the code. So sample mode also freezes the clock, by replacing the global `Date` at server start without touching any app code. → [the code](../engineering-practices.md#snippet-1-freezing-the-clock-without-touching-app-code)

Then I moved the whole thing into the deploy pipeline. Every release builds the app, starts it in sample mode, and photographs every page in a pinned browser container before anyone can see the release. Nobody runs anything by hand anymore.

With nothing churning, nothing needs masking. The numbers and charts on every page are compared for real.

## Part 2: four days of red that wasn't my change

A few weeks later the gate went red and stayed red for four days. Two attempts to fix it went after the obvious suspect, the browser's clock, and froze it harder. Neither helped.

The real cause: the guest-mode pages had been **pre-rendered at build time.** Next.js decided they were static, so it rendered them once while building, and the pay period *current on build day* was written straight into the HTML. A runtime clock freeze can't reach HTML that was produced before the app ever started.

The fix was one line, telling Next.js to render those pages on each request. I verified it in the *build output*, which now lists those routes as dynamic with no pre-rendered HTML files. Reading the source to see it had changed wasn't enough.

## Part 3: light mode that was never light

Fixing that turned up something worse. Some "light theme" baselines were **byte-for-byte identical to their dark-theme twins**, and had been since the first day.

The mechanism: the theme is applied by a tiny script before the page loads. When the server's HTML disagrees with what the browser computes (like that baked-in date), React recovers by re-rendering from the top of the page, and that re-render wiped out the theme the script had set. So the "light" screenshots were of dark pages, and they'd been approved that way. Four weeks of light-mode coverage had proved nothing.

The tests now check that the theme on the page *is* the theme being tested, with a control case that must fail, before taking any photo.

## What I took from it

- **A test has to fail only for real reasons.** A flaky test isn't a small problem. It trains you to ignore the result.
- **Freeze data and time together.** Frozen data alone still drifts.
- **Test the thing that ships.** One build, switched at runtime, beats a special test build that can drift from production.
- **Know when your code actually runs.** A runtime setting can't change something produced at build time. Check what the build actually produced instead of assuming.
- **Look at the baseline before you trust it.** "The test passes" only means something if the approved image shows what you think it shows.
