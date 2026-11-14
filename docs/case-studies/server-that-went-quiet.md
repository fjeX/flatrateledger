# The server that went quiet for 9 hours

> **In short:** At 12:14 AM my production server lost its network address and sat there "healthy" for 9 hours, unable to reach anything or tell anyone. Every monitor I had ran *on that server*, so the silence looked like a quiet night. I proved what happened from the server's own logs, fixed the networking, and moved the watchdog to a machine that can actually see the server from outside.

## The setup

Before moving to the cloud, Flat Rate Ledger ran on a virtual machine in my homelab. It ran the app, its database, and all the automation: the nightly health check, the QA bot, the auto-fixer and the morning digest email.

## The symptom

One morning everything was down. Every site on that server failed by name. A few services still answered when I went to them by IP address directly, but those all turned out to live on *other* machines. The hypervisor said the virtual machine was **running**.

No alert had fired overnight, and the morning email never came. I found it by hand.

A reboot fixed it instantly, which is the worst kind of fix: it removes the evidence. So before calling it done, I went back through the logs to find out what had actually happened.

## The investigation

**First, rule out a crash.** The machine had never stopped:

- Scheduled jobs and system-stats collection kept running every 10 minutes, all night, right up to the reboot.
- Memory at 44%, load under 1, disk I/O wait under 0.3%, disk 59% full. The host machine's logs were clean too.

So the server was alive and healthy. It just couldn't talk.

**Then, find the moment it stopped.** Three independent records agreed:

1. **The network monitor** of a VPN client on the machine logged the kernel deleting every route on the main network interface at **12:14:45 AM**, including entries in the kernel's own *local* routing table. Those only disappear when the IP address itself is removed. That's the smoking gun: the machine lost its address.
2. **Traffic stats:** outbound packets at **exactly 0.00 per second for 9 hours.** With no address, every attempt to send fails before it leaves. Inbound stayed at a steady trickle of network broadcast noise.
3. **The reverse proxy's logs:** last real request at 12:03 AM, next one after the reboot in the morning. Nothing reached the apps in between.

**Then, why it never recovered.** The virtual network cable never "unplugged", so the network service saw no link change and never asked for its address again. It logged exactly zero lines for the whole outage.

**And the root cause.** I believed the server had a static IP address. It didn't. In the router I had set a *DHCP reservation*, which most router screens label "Static IP". A reservation guarantees *which* address the server gets, but the server still leases it and can still lose it on a failed renewal. One command showed it: the server's default route said `proto dhcp`, not `proto static`.

**A suspect I ruled out:** a weekly disk-maintenance job on the host ran at 12:14:28 to 12:14:57, right around the moment of failure. Tempting, but it ran on a different physical disk than the virtual machine's, and a bigger run of the same job the week before caused nothing. Timing alone isn't evidence.

## The fix

1. **A real static address.** Configured on the server itself, not just the router, and locked so the cloud-init setup tool can't quietly regenerate DHCP settings on a later boot. I kept the router reservation too, so nothing else can claim that address.
2. **Applied safely.** A network change on a remote machine can cut you off from the machine you're fixing. I used `netplan try`, which applies the change and automatically reverts it after two minutes unless you confirm. A typo costs two minutes instead of a trip to the console.
3. **A watchdog that lives outside.** A small service on the **hypervisor host** checks the server every 60 seconds:
   - It probes with **ping *and* an HTTPS connection.** A ping alone would call the server healthy while every service on it was dead.
   - 3 failures in a row → a warning. 10 → a *graceful* reboot, then a 30-minute cooldown, so a server that won't come back gets reported instead of rebooted in a loop.
   - It **does nothing if the host can't reach the router either.** A router restart must not get "fixed" by rebooting a healthy server.
   - I tested all four paths with the reboot command replaced by a stub before trusting it.

## The monitoring lesson

Every monitor I had ran on the server that failed. When it went quiet, they went quiet with it, and **silence read as a quiet night.**

On-server monitoring can't report its own death. So the watchers that matter now live elsewhere:

- The hypervisor watches the server from the host.
- An outside uptime service probes the live site.
- The morning digest sends a **heartbeat** to that outside service after every email. No heartbeat by morning means the whole chain is down, and the alert comes from outside.
- In the digest itself, a missing report is an alarm, never a blank section.

## What I took from it

- **"Running" isn't "working."** Check that it can actually do its job, not just that it's on.
- **Don't let a reboot erase the evidence without a look.** The logs had the whole story; I only had to read them.
- **Verify what you believe about your own setup.** "It's static" was a belief. `proto dhcp` was the fact.
- **The watchdog can't live in the thing it watches.**
