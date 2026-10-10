// Configure/deploy through cf. No Wrangler configuration is used.
import { bindings, defineConfig, exports } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

export default defineConfig({
  worker: {
    name: "boring-notch-dot-relay",
    compatibilityDate: "2026-10-10",
    compatibilityFlags: ["nodejs_compat", "global_fetch_strictly_public"],
    entrypoint,
    exports: { DotRelay: exports.durableObject({ storage: "sqlite" }) },
    env: {
      RELAY: bindings.durableObject({ worker: "boring-notch-dot-relay", exportName: "DotRelay" }),
      OAUTH_KV: bindings.kv(),
      RELAY_ORIGIN: bindings.text("https://boring-notch-dot-relay.ext-joao-junqueira.workers.dev"), // Set exact deployed origin after first health-only deployment.
      OWNER_GITHUB_ID: bindings.text("39351332"),
      CALLBACK_ORIGINS: bindings.text(""), // Exact verified public ChatGPT callback origins, comma-separated.
      GITHUB_CLIENT_ID: bindings.text(""), // Replace with bindings.secret() after GitHub OAuth app registration.
      GITHUB_CLIENT_SECRET: bindings.text(""), // Replace with bindings.secret(); never put credentials here.
      RELAY_ENCRYPTION_KEY: bindings.text(""), // Replace with bindings.secret(); 32 random bytes, base64.
    },
    observability: {
      enabled: true,
      redactQueryString: true,
      logs: { enabled: true, invocationLogs: false },
      traces: { enabled: true, headSamplingRate: 0.01 },
    },
  },
});
