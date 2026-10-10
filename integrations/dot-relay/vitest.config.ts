import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
export default defineConfig({
 plugins:[cloudflareTest({main:"./src/index.ts",miniflare:{
  compatibilityDate:"2026-10-10",compatibilityFlags:["nodejs_compat","global_fetch_strictly_public"],
  kvNamespaces:["OAUTH_KV"],durableObjects:{RELAY:{className:"DotRelay",useSQLite:true}},
  bindings:{RELAY_ORIGIN:"https://relay.example.com",OWNER_GITHUB_ID:"39351332",CALLBACK_ORIGINS:"https://receiver.example.com",GITHUB_CLIENT_ID:"test-only-client",GITHUB_CLIENT_SECRET:"test-only-secret",RELAY_ENCRYPTION_KEY:"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="},
 }})],test:{include:["test/**/*.test.ts"]}
});
