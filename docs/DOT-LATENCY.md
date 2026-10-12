# Dot latency investigation — 12 October 2026

The private relay is responsive, but an MCP event wakes Dot asynchronously.
This integration currently cannot promise the response time of the native Dot chat.

## Measured stages

The earlier automatic validation message was created at 08:03:32.882 UTC,
accepted by ChatGPT at 08:03:33.671, woke Dot at 08:04:37, and received a
successful reply call by 08:06:14. Wake/reply times were reported by actual Dot
from its recorded activity; callback times came from authenticated relay diagnostics.

For a subsequent ordinary message, the relay recorded creation at 08:27:23.826
and callback acceptance at 08:27:24.836. Actual Dot reported a wake at 08:31:12
and reply at 08:31:49: about 227 seconds after callback acceptance to wake,
then 37 seconds to finish. That sample's dominant delay was outside the relay.

The native client checks events every two seconds while visible, eight while
hidden, plus request duration. Network failures back off. Faster polling cannot
remove a minutes-long delay before Dot runs, so polling and relay code were not
changed merely to create the appearance of optimization.

## Task optimization

Actual Dot confirmed on 12 October that the existing event task prompt was
updated and saved without changing its binding or permissions. The routine path
is context then reply; missing event payloads use pending queue then context then
reply. Unnecessary automation/history inspection, final status checks, diagnostic
narration and shell calls solely to create UUIDs were removed from routine work.
Oldest-first recovery, stable IDs, duplicate protection and pagination remain.
This removes avoidable work after wake; it does not control the wake-up queue.

## Platform boundary

[OpenAI MCP Events](https://developers.openai.com/plugins/build/mcp-events)
documents asynchronous processing after webhook acceptance and task batching.
It supports webhooks, not a streaming chat connection to Dot. The existing task's
available tools exposed no batching/debounce field. A relay HTTP 200 is receipt,
not evidence of generation starting or a read receipt.

A direct native-Dot baseline (simple fixed-text response) was sent at
08:44:21.294 UTC and observed complete by 08:44:39.795: at most 18.5 seconds,
including observation delay. This is one sample, not a statistical benchmark.

Only explicitly sent messages enter this channel. No monitoring data, private
browser session APIs or alternate model impersonating Dot were used.

## Fresh automatic benchmark after prompt cleanup

The native notch sent a simple fixed-text baseline without any manual prompt
asking Dot to handle it. Authenticated relay evidence:

| Stage | UTC timestamp | Elapsed from relay creation |
| --- | --- | --- |
| Relay message created | 08:47:47.983 | 0 |
| ChatGPT callback accepted, HTTP 200, attempt 1 | 08:47:48.968 | 0.985 seconds |
| Actual Dot wake, reported from recorded run | 08:48:53 | about 65 seconds |
| Actual Dot reply stored | 08:49:39.663 | 111.680 seconds |

The reply appeared in the native notch as “Notch baseline: 13”, with its actual
12:49 PM local timestamp and the originating message's double reply ticks.
The native UI was inspected after reply arrival, so sub-second display latency
was not measured. No additional handling prompt or fabricated responder was used.
A later diagnostic-only prompt asked Dot for its recorded wake timestamp.

This single cleaned-up sample remains far slower than the <=18.5-second direct
baseline. These small, nonconcurrent samples do not establish a speedup caused
by the prompt change. The observed 64-second callback-to-wake gap also does not
prove a specific batching/debounce configuration. Current task tools expose none.
To approach native-chat response time, the integration needs a supported direct
Dot message/wake path or platform-side control over event dispatch. The documented
MCP webhook protocol alone provides neither a latency guarantee nor streamed
partial Dot replies. Replacing the actual Dot with a separate API model would
change the product and was not done.
