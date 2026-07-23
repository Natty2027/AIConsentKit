# Pre-submission checklist — AI features

Work top to bottom. Every line is something that has actually caused a
rejection, not a hypothetical.

## The rule

Apple revised **guideline 5.1.2(i)** on 13 November 2025. The added sentence:

> You must clearly disclose where personal data will be shared with third
> parties, including with third-party AI, and obtain explicit permission
> before doing so.

It was the first time Apple named third-party AI as its own category, and it
took effect immediately. Rejections typically arrive paired with **5.1.1(i)**
(Data Collection) and read roughly: *the app appears to share the user's
personal data with a third-party AI service but does not clearly explain what
data is sent, identify who the data is sent to, and ask the user's permission
before sharing the data.*

The four requirements Apple lists in that rejection are the four rows below.

---

## 1. In-app consent

- [ ] The consent screen names **what data** is sent, in plain language.
- [ ] The consent screen names **who receives it** — legal entity, not product
      name. "Anthropic PBC", not "AI-powered".
- [ ] Consent is obtained **before** the first request, not on first launch as
      a blanket accept and not buried in onboarding.
- [ ] Allow and Don't Allow are visually equal weight.
- [ ] Sheet cannot be dismissed into the granted state. Swipe-to-dismiss is
      disabled or treated as decline.
- [ ] There is a way to withdraw consent later, reachable from Settings.
- [ ] Declining leaves the app usable — a decline that bricks the app invites
      a separate rejection.

## 2. Privacy policy

- [ ] Your policy **names the AI vendor** explicitly. This is the step most
      teams skip and it is checked.
- [ ] Policy states what data the app collects, how it collects it, and all
      uses including sharing with the AI service.
- [ ] Policy confirms the third party provides equal or equivalent protection.
- [ ] Policy URL is live and reachable **before** you submit. Reviewers open it.
- [ ] Policy URL is set in App Store Connect *and* linked in-app.

## 3. App Privacy questionnaire (nutrition labels)

- [ ] Every category in your `AIDataDisclosure` has a matching declaration.
      See `PRIVACY_NUTRITION_LABELS.md` for the mapping.
- [ ] Any third-party SDK that collects data is reflected too.
- [ ] Declared labels match actual data flow. Mismatch between declared labels
      and real behavior is a rising rejection cause.
- [ ] `PrivacyInfo.xcprivacy` is present and its declared reasons match.

## 4. App Review notes

- [ ] Notes tell the reviewer exactly where the AI feature lives and how to
      reach the consent screen. See `APP_REVIEW_NOTES.md`.
- [ ] A working demo account is supplied if sign-in is required.
- [ ] The demo account is **not** rate limited or out of credits. A reviewer
      who hits your quota wall sees a broken app.
- [ ] If the app does *not* send data to a third-party AI service, say so
      explicitly in the notes. Apple's own rejection text offers this as a
      valid reply path.

## 5. Adjacent traps

- [ ] **2.5.2** — the app does not download or execute code that changes its
      features. If you render model output as anything executable, you are in
      scope. This is the guideline behind the 2026 vibe-coding enforcement.
- [ ] **4.3** — the app is not a thin wrapper. Spam rejections are roughly a
      quarter of all rejections and "template-looking" counts. Ship real
      native surface: widgets, App Intents, Live Activities.
- [ ] **4.2** — minimum functionality. A chat box over an API is exactly the
      shape Apple rejects. The app must do something the website does not.
- [ ] **5.1.1(v)** — if the app supports account creation, it must support
      in-app account deletion.
- [ ] **4.8** — if you offer third-party social login, offer an equivalent
      privacy-preserving option.
- [ ] Content moderation exists if users can generate and share output.
- [ ] Build uses the required SDK. From **28 April 2026**, uploads to App
      Store Connect must use the iOS/iPadOS 26 SDK or later.

## 6. Engineering

- [ ] No vendor API key in the binary. `AnthropicProvider` and
      `OpenAIProvider` are `#if DEBUG` only; production goes through
      `ProxyProvider`.
- [ ] Run `strings` on the built binary and grep for `sk-`, `sk-ant`, and your
      key prefixes. The SubmissionPreflightKit does this for you.
- [ ] Every error path shows a message from `AIError.userMessage`. No raw
      `NSError` reaches a screen.
- [ ] Streaming requests cancel on view dismissal.
- [ ] Budget guard is set. A retry loop should hit a wall, not your invoice.
- [ ] Offline behavior is graceful, and tested in Airplane Mode on device.

## Sources

- Apple Developer, *Updated App Review Guidelines now available*, 13 Nov 2025
  — https://developer.apple.com/news/?id=ey6d8onl
- App Store Review Guidelines — https://developer.apple.com/app-store/review/guidelines/
