# The Echo Beta Tester Guide

Welcome — and thank you. Echo is built by one person around a full-time mail route, which means every tester genuinely moves the project. This guide covers how the beta works, how to send feedback that actually helps, and a set of structured test plans if you want to hunt bugs on purpose.

The short version: **use Echo like you really listen** — commute, chores, workouts, bedtime — and tell us the moment something feels wrong.

---

## 1. Joining the beta

1. Install **TestFlight** (Apple's free beta app) from the App Store.
2. Open your Echo invite link on the device — it opens in TestFlight.
3. Tap **Accept**, then **Install**. Echo appears on your home screen like any app, with a small orange dot in TestFlight marking it as a beta.

Don't have an invite yet? Request access via [GitHub Issues](https://github.com/dfakkeldy/Echo/issues) — include the device you'd test on.

**Requirements:** a recent iPhone (the on-device alignment uses the Neural Engine, so newer hardware aligns faster). Apple Watch and Mac are optional but very welcome test surfaces — the watch app installs automatically from the iPhone's Watch app.

**Updates:** TestFlight notifies you when a new build lands. Each build's **What to Test** notes tell you where to aim. Beta builds expire after 90 days; updating resets the clock.

**Your data:** beta builds share data with release builds going forward — but it's a beta, so keep your source audiobook files backed up (you should anyway; Echo never modifies them).

---

## 2. Sending feedback that helps

### The fastest way: TestFlight screenshots

See something wrong? **Take a screenshot right then.** Tap the screenshot preview → **Share** → **Send Beta Feedback**. Your note arrives with the build number, device model, and iOS version attached automatically — that's half the diagnosis done.

### Crashes

If Echo crashes, TestFlight will offer to send the crash report with a comment box. Please add one sentence about what you were doing — a crash log with *"happened when I tapped Auto-Align on a 40-hour book"* is worth ten without.

### Trackable bugs & feature ideas: GitHub

For anything you want tracked (or to check whether it's known): [github.com/dfakkeldy/Echo/issues](https://github.com/dfakkeldy/Echo/issues). The developer reads every one.

### Reporting alignment problems (special instructions)

Alignment bugs are the most valuable reports and need the most context. Include:

- **Book title + narrator** (different narrations of the same book behave differently)
- **Where the ePub/PDF came from** — store, edition, year if you know it (editions drift; that's often the whole bug)
- **What the audio is** — single M4B, folder of MP3s, LibriVox, Libation export…
- **Where it went wrong** — chapter and roughly what the text said vs. what was playing
- Whether **Auto-Align** had run, and whether you'd placed any **manual anchors**

> "Book X aligned perfectly except chapter 7 drifted ~30s after an ad-libbed intro; ePub is the 2nd edition from Kobo; audio is a Libation M4B" — that's a *perfect* report.

---

## 3. Structured test plans

Pick whichever matches your life. Each plan is 10–20 minutes of intentional testing.

### Plan A — The Commute Run *(Smart Rewind & interruptions)*
1. Start a book, then live your interrupted life: pause for seconds, for minutes, for an hour.
2. Each resume: did Smart Rewind back up a sensible amount? Did it ever dump you somewhere confusing?
3. Mid-sentence, unplug your headphones / disconnect Bluetooth. Echo should pause — never blast the speaker.
4. Take a phone call. After it ends, does Echo behave correctly (resume if it was playing, stay paused if you'd paused)?

### Plan B — The Alignment Gauntlet *(EPUB + auto-align)*
1. Put an ePub in the audiobook's folder; confirm Echo imports it automatically.
2. Run **Auto-Align Chapters** and watch the progress view (plug in for long books — the first run also downloads the ~40 MB speech model).
3. Spot-check five chapters: tap a paragraph, does audio land on those words (or close)?
4. Find the worst spot and fix it: long-press → **Align to Now**. Does the surrounding text snap into place?
5. Search a distinctive phrase; tap the result. Text and audio should jump together.

### Plan C — The Study Session *(bookmarks, flashcards, review)*
1. While listening, make three bookmarks: one plain, one with a **voice memo**, one with a **photo**.
2. Re-listen across them: does the voice memo play inline? Does the player artwork switch to your photo and back?
3. Promote a bookmark to a **flashcard** (front as a question). Attach the audio snippet.
4. Tomorrow, when the review notification arrives: do your **Daily Review** on the phone — then try a session on the **watch**, hands-free.
5. Grade honestly and check the stats module updates (due / reviewed today / total).

### Plan D — The Library Stress Test *(formats & playlist)*
1. Load your messiest book: a multi-file M4B, a 100-file LibriVox folder, weird filenames.
2. Check the chapter list: grouping sensible? Sections under chapters where expected?
3. Drag-reorder a few tracks; dim one (e.g., a disclaimer track) and confirm playback skips it.
4. iCloud users: try a book *without* "Keep Downloaded" on cellular — how does Echo cope? Then set Keep Downloaded and compare.

### Plan E — The Wrist-Only Day *(watch remote)*
1. From the phone, design your button layout (try filling multiple pages; leave one page empty — it should hide).
2. Drive a full listening session from the watch only: play, skip, sections, loop, speed, sleep timer, a bookmark with a voice memo.
3. Set the Digital Crown to scrubbing; check the deadzone (brushing the crown shouldn't jump position).
4. Leave the watch off-wrist overnight; next morning, raise it: right book, right position, no phantom commands?
5. Run a **Pomodoro**: set 25 minutes, lower your wrist, confirm the alarm is unmissable.

### Plan F — The Accessibility Pass
1. Crank Dynamic Type to a large size: anything truncated, overlapping, or unreadable?
2. Switch the reader font to **OpenDyslexic**, then **Lexend**; adjust size and line spacing.
3. If you use VoiceOver: a pass over the player and reader — every control labeled and operable?
4. Enable Reduce Motion: anything still animating that shouldn't?

---

## 4. Known limitations (current beta)

Honest list — these are known, so you don't need to report them (though opinions on them are welcome):

- **First auto-align is heavy.** Model download (~40 MB) + Neural Engine work; phones run warm on long books. Plug in.
- **CarPlay is minimal** — browse + transport only, richer templates on the roadmap.
- **iCloud sync covers alignment anchors only** so far; bookmarks/flashcards/position sync across devices is roadmap work.
- **Edition drift is real.** Auto-align gets you close; some books need two or three manual anchors. That's expected, not a bug — but tell us about books that need *lots*.
- **Watch review sessions** can briefly show stale state if the phone app was killed mid-review; relaunching the phone app reconverges.

---

## 5. Privacy during the beta

Echo's promise is unchanged in beta: **no analytics, no tracking, no servers, alignment fully on-device.**

One thing TestFlight itself adds: Apple's beta system shares **crash reports** and **the feedback you choose to send** with the developer, along with device/OS/build info. That's TestFlight's standard mechanism (it's how your reports reach us), not telemetry inside Echo. The full policy is at [dfakkeldy.github.io/Echo/privacy.html](https://dfakkeldy.github.io/Echo/privacy.html).

---

*Thank you for testing. Every report makes the player better for the next interrupted listener.* — Dan
