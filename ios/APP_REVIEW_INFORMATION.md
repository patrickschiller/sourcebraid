# App Review Information — SourceBraid 1.0.1 (Build 10)

Copy the following text into App Store Connect’s **App Review Information**
Notes field. Replace every value in square brackets before submitting. Never
commit the review token or a link that grants access to the screen recording.

```text
SourceBraid — Weave the web into Markdown.

1. Physical-device screen recording
Screen recording: [private review link or App Store Connect attachment]

The recording starts by launching SourceBraid on a physical device. It shows:
- entering the supplied GitHub test repository settings and fine-grained token;
- tapping “Test connection” and receiving the successful connection message;
- opening Safari, sharing https://example.com/ to SourceBraid, confirming the
  generated title, and saving it; and
- opening SourceBraid again and showing the saved capture in “Recently saved”.

No account-registration, in-app login, account-deletion, payment,
subscription, purchase, or sensitive-device-permission flow exists in the app.
SourceBraid does not provide a public or social user-generated-content service;
captures are written only to the repository selected by the user, so there are
no reporting or blocking controls.

2. Tested physical devices and operating systems
- [device model 1] — [exact iOS version]
- [device model 2] — [exact iOS version]
- [device model 3, if applicable] — [exact iPadOS version]

SourceBraid supports iPhone and iPad running iOS/iPadOS 17.0 or later.

3. Function and target audience
SourceBraid is for people who want to keep a private, portable Markdown
archive of web sources. From the iOS Share Sheet it saves a shared URL,
readable Safari page text, selected text, a PDF, or another file to the user’s
own GitHub repository. It preserves source URLs and capture metadata, so users
can retain research material outside a proprietary reading-list service.

4. Setup and access to the main features
The app has no SourceBraid account or in-app registration. A GitHub account and
a fine-grained personal access token with Contents: Read and write permission
for the dedicated review repository are required.

Enter these values in SourceBraid’s initial screen:
- Owner or organization: [REVIEW_GITHUB_OWNER]
- Repository: [REVIEW_REPOSITORY]
- Branch: main
- Root folder: web-clips
- GitHub token: [TIME-LIMITED_REVIEW_TOKEN]

Then tap “Test connection”. To test the main Share Extension flow, open
https://example.com/ in Safari, tap Share, choose SourceBraid, and tap Save.
The resulting Markdown capture and metadata are written to the configured
review repository under `web-clips/`.

The supplied token is limited to this review repository, has only Contents:
Read and write permission, and will be revoked after review. It is provided
only in App Store Connect, never in the app binary, source repository, or this
document.

5. External services and platforms
- GitHub REST Contents API (`api.github.com`): SourceBraid reads and writes
  the user-selected repository using the user’s fine-grained GitHub token.
- Websites explicitly selected by the user: for a shared public URL,
  SourceBraid may load the page in an isolated web view to create Markdown. If
  loading fails, it saves a clearly identified link-only capture instead.
- GitHub Actions and Docling: optional PDF conversion. When a PDF is saved,
  the configured repository’s GitHub Actions workflow can convert it to
  Markdown. This feature runs only in the user’s repository.

SourceBraid operates no central content-storage, analytics, authentication,
payment, advertising, or AI service.

6. Regional availability
SourceBraid has the same feature set in every region. Availability of a source
website or GitHub itself may be affected by that external service or local
network conditions.

7. Regulated industries and third-party material
SourceBraid is not a regulated-industry service. It does not license, host, or
republish third-party content. Users choose the material they capture and store
it in their own GitHub repository. The review recording and supplied test URL
use only redistributable test material.
```

## Submission checklist

- Record the stated flow on a real, up-to-date iPhone or iPad; do not submit a
  simulator recording.
- Fill in the exact tested device models and OS versions.
- Create a dedicated GitHub review repository and a short-lived, fine-grained
  token limited to that repository’s Contents read/write permission.
- Paste the completed text and private recording reference into App Store
  Connect’s App Review Information section before submitting build 10.
- Revoke the review token once Apple has completed its review.
