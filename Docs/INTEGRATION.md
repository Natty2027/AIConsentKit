# Integration

## Install

Xcode ▸ File ▸ Add Package Dependencies ▸ paste your repo URL. Or in a
`Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/YOURORG/AIConsentKit.git", from: "1.0.0")
]
```

Minimum: iOS 17 / macOS 14, Swift 5.9.

## The one architectural rule

**Call sites hold a `ConsentGate`, never a provider.** If a view model can
reach `ProxyProvider` directly, the compliance guarantee is gone and you are
back to auditing every call site by hand. Construct the provider once at
composition root, wrap it, and inject the gate.

```swift
// App root — the only place a raw provider exists.
let provider = ProxyProvider(configuration: .init(
    baseURL: URL(string: "https://api.yourdomain.com")!,
    authTokenProvider: { try await session.currentToken() }
))

let meter  = UsageMeter()
let budget = BudgetGuard(meter: meter, maxTokensPerWindow: 200_000)

let gate = ConsentGate(
    upstream: provider,
    isConsentGranted: { [weak consentController] in
        MainActor.assumeIsolated { consentController?.state == .granted } ?? false
    },
    redaction: .standard,
    budget: budget
)
```

## Backend contract

`ProxyProvider` expects your backend to speak this SSE dialect. Two endpoints:
`POST /v1/chat` (JSON) and `POST /v1/chat/stream` (SSE).

```
event: started
data: {"input_tokens": 12}

event: delta
data: {"text": "Once upon"}

event: delta
data: {"text": " a time"}

event: completed
data: {"input_tokens": 12, "output_tokens": 340}
```

Errors:

```
event: error
data: {"message": "Rate limit exceeded", "type": "rate_limit_error"}
```

### Reference Express handler

```ts
import express from "express";

const app = express();
app.use(express.json());

app.post("/v1/chat/stream", async (req, res) => {
  const user = await authenticate(req);          // your auth, e.g. Clerk
  if (!user) return res.status(401).json({ message: "Unauthorized" });

  if (await isOverQuota(user.id)) {
    return res.status(429).json({ message: "Quota exceeded", type: "rate_limit_error" });
  }

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders();

  const send = (event: string, data: unknown) => {
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  };

  try {
    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": process.env.ANTHROPIC_API_KEY!,   // stays server-side
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-sonnet-5",
        max_tokens: req.body.max_tokens ?? 1024,
        system: req.body.system,
        messages: req.body.messages,
        stream: true,
      }),
    });

    if (!upstream.ok || !upstream.body) {
      send("error", { message: "Upstream error", type: "api_error" });
      return res.end();
    }

    // Translate Anthropic's event names into this kit's neutral ones.
    const reader = upstream.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let usage = { input_tokens: 0, output_tokens: 0 };

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      const chunks = buffer.split("\n\n");
      buffer = chunks.pop() ?? "";

      for (const chunk of chunks) {
        const nameLine = chunk.split("\n").find((l) => l.startsWith("event:"));
        const dataLine = chunk.split("\n").find((l) => l.startsWith("data:"));
        if (!nameLine || !dataLine) continue;

        const name = nameLine.slice(6).trim();
        const payload = JSON.parse(dataLine.slice(5).trim());

        if (name === "message_start") {
          usage.input_tokens = payload.message.usage.input_tokens;
          send("started", usage);
        } else if (name === "content_block_delta" && payload.delta?.type === "text_delta") {
          send("delta", { text: payload.delta.text });
        } else if (name === "message_delta" && payload.usage?.output_tokens != null) {
          usage.output_tokens = payload.usage.output_tokens;   // cumulative
        } else if (name === "message_stop") {
          send("completed", usage);
        }
      }
    }

    await recordUsage(user.id, usage);
    res.end();
  } catch (err) {
    send("error", { message: "Internal error", type: "api_error" });
    res.end();
  }
});
```

Note the `message_delta` handling: Anthropic's usage on that event is
**cumulative**, so assign rather than accumulate. Getting this wrong inflates
your cost display by a large factor and is easy to miss in testing.

## Model identifiers

Passed straight through to the vendor; the kit does not validate them. Current
Anthropic strings include `claude-opus-4-8`, `claude-sonnet-5`, and
`claude-haiku-4-5-20251001`. Prefer setting the model server-side so you can
change it without shipping an app update — the client sending a model name is
also a client that can be modified to request an expensive one.

## Testing streaming UI

```swift
let mock = MockProvider(behavior: .stream(
    ["Streaming ", "arrives ", "in ", "pieces."],
    chunkDelay: .milliseconds(120)
))
```

Then point a gate at it. Also exercise the failure path — `MockProvider(behavior:
.fail(.http(status: 429, message: nil, retryAfter: 3)))` — and check that your UI
shows `AIError.userMessage` rather than a spinner that never stops.

## Airplane Mode test

Non-negotiable before submission. Turn on Airplane Mode, send a request, and
confirm you get "You appear to be offline." with a working retry. Reviewers do
test on constrained networks, and a hang here reads as a hang, not a network
problem.
