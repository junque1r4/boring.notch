import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";
import type { DotRelay } from "./relay";
// cf infers a string cross-Worker binding as untyped; this class supplies the RPC generic.
export type Env = Omit<Cloudflare.Env, "RELAY"> & { RELAY: DurableObjectNamespace<DotRelay>; OAUTH_PROVIDER: OAuthHelpers };
export interface OwnerProps { githubId: string; githubToken: string; }
