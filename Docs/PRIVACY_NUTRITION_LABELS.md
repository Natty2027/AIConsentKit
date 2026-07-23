# Mapping your disclosure to the App Privacy questionnaire

The consent sheet and the App Store Connect questionnaire must describe the
same reality. Reviewers compare them. This table maps each `DataCategory` in
the kit to the App Privacy answer it implies.

| `DataCategory` | App Privacy category | Data type | Linked to user? | Tracking? |
|---|---|---|---|---|
| `.promptText` | User Content | Other User Content | Yes if you store it against an account; No if stateless | No |
| `.documentContent` | User Content | Other User Content | Same as above | No |
| `.photoContent` | User Content | Photos or Videos | Same as above | No |
| `.accountIdentifier` | Identifiers | User ID | Yes | No |

## How to answer the questionnaire

**"Do you or your third-party partners collect data from this app?"** — Yes,
if anything reaches your backend or the model vendor. Sending prompt text to an
API is collection even if you never write it to a database.

**"Is this data linked to the user's identity?"** — Yes if the request carries
an account identifier, a device identifier, or anything that lets you tie the
content back to a person. Routing through your own backend with an
authenticated session almost always means yes.

**"Is this data used for tracking?"** — No, unless you are combining it with
data from other companies' apps for advertising or sharing it with a data
broker. Sending prompts to a model vendor to produce a response is not
tracking.

## Purpose strings

Pick "App Functionality" for prompt and document content. Do not pick
"Analytics" or "Product Personalization" unless you actually do those things
with it — over-declaring is not the safe option, because it contradicts your
consent sheet, which said the data is sent to generate a reply.

## PrivacyInfo.xcprivacy

Add the manifest to your app target. `Resources/PrivacyInfo.xcprivacy.template`
in this kit has the collected-data-type entries pre-filled for prompt text and
user ID. You still need to add:

- `NSPrivacyAccessedAPITypes` for any required-reason API you call
  (`UserDefaults` needs `CA92.1` for app-group-scoped use, file timestamp APIs
  need their own, etc.)
- `NSPrivacyTrackingDomains` if you track — usually empty for this kit.

Third-party SDKs ship their own manifests. Xcode merges them into a privacy
report at archive time. Generate it (Product ▸ Archive ▸ Generate Privacy
Report) and read it before submitting — it is the closest thing to seeing what
the reviewer sees.

## The consistency check

Before you submit, put three things side by side:

1. The categories listed in your `AIDataDisclosure`.
2. The answers in App Store Connect ▸ App Privacy.
3. The data-handling section of your published privacy policy.

If any one of them mentions something the other two do not, fix it. That
mismatch is the single most common way an otherwise compliant AI feature gets
rejected.
