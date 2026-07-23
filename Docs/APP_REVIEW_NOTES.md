# App Review notes template

Paste into App Store Connect ▸ App Review Information ▸ Notes. Fill the
brackets. Keep it short — reviewers skim.

---

```
AI FEATURE — DATA HANDLING

This app includes an AI assistant feature at: [Tab name] > [Screen name].

WHAT IS SENT
Only text the user types into the assistant field, plus documents the user
explicitly attaches. No contacts, location, health data, or photos are sent
unless the user attaches them.

WHO RECEIVES IT
[Anthropic PBC / OpenAI, L.L.C.], via our own backend at [api.yourdomain.com].
We do not send raw user identifiers to the vendor; requests are keyed to a
random per-install identifier.

CONSENT
Before the first request, the user sees a full-screen disclosure naming the
data categories and the receiving company, with equally weighted Allow and
Don't Allow buttons. No request is made unless Allow is tapped. The decision
can be reversed at Settings > Privacy > AI features.

TO REACH THE CONSENT SCREEN
1. Launch the app and sign in with the demo account below.
2. Tap [Tab name].
3. Tap [Button].
The disclosure appears immediately. If you have already accepted it, reset via
Settings > Privacy > AI features > Turn off, then repeat.

PRIVACY POLICY
[https://yourdomain.com/privacy] — section "AI features" names the vendor and
describes retention.

DEMO ACCOUNT
Username: [reviewer@yourdomain.com]
Password: [...]
This account has an elevated usage limit so the feature will not be throttled
during review.

NOTES
- The app does not download or execute code. Model output is rendered as
  text and never evaluated.
- [If applicable] AI-generated content is moderated by [describe] and users
  can report output via [describe].
```

---

## If you do NOT use third-party AI

Apple's rejection template explicitly allows this reply. Say it plainly:

```
This app does not send user data to any third-party AI service. [Feature name]
runs entirely on device using [Core ML / Apple's Foundation Models framework /
Natural Language framework]. No user content leaves the device.
```

## Why the demo account line matters

A reviewer working through a queue does not have your billing account. If your
AI feature is behind a paid tier, or your backend rate-limits per user, the
reviewer may hit a wall and file the rejection as "app is incomplete" or
"feature did not work". Give the review account a raised limit, and say so.

If your backend cannot do that, point the demo account at `MockProvider` and
disclose it in the notes — a scripted demo path is honest, and far better than
a reviewer seeing an error toast.
