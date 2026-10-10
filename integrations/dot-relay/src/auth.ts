// Modified for Boring Notch Agents, 2026-10-11. GPL-3.0-only.
import { authorizationErrorRedirect } from "@cloudflare/workers-oauth-provider";
import type { Env, OwnerProps } from "./env";
import { b64, digest, NATIVE_REDIRECT, object, OWNER_ID, RelayError, SCOPES, readForm } from "./security";
const escape=(value:string)=>value.replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]!));
export function configured(env:Env):boolean {
  try {const origin=new URL(env.RELAY_ORIGIN);return origin.protocol==="https:"&&origin.origin===env.RELAY_ORIGIN&&env.OWNER_GITHUB_ID===OWNER_ID&&!!env.GITHUB_CLIENT_ID&&!!env.GITHUB_CLIENT_SECRET&&!!env.RELAY_ENCRYPTION_KEY;}catch{return false;}
}
export async function authorization(request:Request,env:Env):Promise<Response> {
  const url=new URL(request.url);const oauth=env.OAUTH_PROVIDER;
  if(url.pathname==="/authorize"&&request.method==="GET") {
    const info=await oauth.parseAuthRequest(request);
    const client=await oauth.lookupClient(info.clientId);
    if(!client)throw new RelayError("invalid_client");
    // Native OAuth is restricted to the exact callback scheme; private-use
    // redirects registered by another application never obtain any scopes.
    if(!info.redirectUri.startsWith("https:")&&info.redirectUri!==NATIVE_REDIRECT)throw new RelayError("invalid_redirect");
    const consent=await oauth.beginConsent(info);
    const native=info.redirectUri===NATIVE_REDIRECT;
    const permitted=native?["notch:read","notch:send","offline_access"]:["notch:context","notch:reply","notch:subscribe","offline_access"];
    if(!info.scope.length||info.scope.some(scope=>!permitted.includes(scope)))throw new RelayError("invalid_scope");
    consent.headers.set("Content-Type","text/html;charset=utf-8");
    consent.headers.set("Content-Security-Policy","default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
    return new Response(`<!doctype html><meta charset="utf-8"><title>Connect private Dot channel</title><style>body{font:17px system-ui;max-width:600px;margin:60px auto;padding:24px}button{font:inherit;margin:12px 12px 0 0;padding:10px}</style><h1>Connect ${escape(client.clientName??"OAuth client")}</h1><p>Only GitHub owner ${escape(OWNER_ID)} can connect this private notch channel.</p><p>Requested access: ${info.scope.map(escape).join(", ")}.</p><p>Only sent chat messages leave the Mac. Session monitoring stays local. Relay payloads expire after seven days.</p><form method="post" action="/authorize"><input type="hidden" name="handle" value="${escape(consent.handle)}"><button name="decision" value="allow">Continue to GitHub</button><button name="decision" value="deny">Cancel</button></form>`,{headers:consent.headers});
  }
  if(url.pathname==="/authorize"&&request.method==="POST") {
    if(request.headers.get("origin")!==env.RELAY_ORIGIN)throw new RelayError("invalid_origin",403);
    if(Number(request.headers.get("content-length"))>4096)throw new RelayError("payload_too_large",413);
    const form=await readForm(request);const handle=String(form.get("handle")??"");
    if(form.get("decision")==="deny") {
      const denied=await oauth.denyConsent(request,handle);return new Response(null,{status:302,headers:denied.headers});
    }
    if(form.get("decision")!=="allow")throw new RelayError("invalid_consent");
    const approved=await oauth.approveConsent(request,handle);
    const verifier=b64(crypto.getRandomValues(new Uint8Array(32))).replace(/\+/g,"-").replace(/\//g,"_").replace(/=/g,"");
    const upstream=await oauth.beginUpstream(approved.request,{data:{verifier},headers:approved.headers});
    const challenge=b64(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(verifier)))).replace(/\+/g,"-").replace(/\//g,"_").replace(/=/g,"");
    const github=new URL("https://github.com/login/oauth/authorize");
    github.search=new URLSearchParams({client_id:env.GITHUB_CLIENT_ID,redirect_uri:`${env.RELAY_ORIGIN}/callback`,scope:"read:user",state:upstream.state,code_challenge:challenge,code_challenge_method:"S256"}).toString();
    upstream.headers.set("Location",github.href);return new Response(null,{status:302,headers:upstream.headers});
  }
  if(url.pathname==="/callback"&&request.method==="GET") {
    const resumed=await oauth.finishUpstream<{verifier:string}>(request);
    if(url.searchParams.has("error")||!url.searchParams.get("code")) {
      resumed.headers.set("Location",authorizationErrorRedirect(resumed.request,"access_denied"));return new Response(null,{status:302,headers:resumed.headers});
    }
    const response=await fetch("https://github.com/login/oauth/access_token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded",Accept:"application/json"},body:new URLSearchParams({client_id:env.GITHUB_CLIENT_ID,client_secret:env.GITHUB_CLIENT_SECRET,code:url.searchParams.get("code")!,redirect_uri:`${env.RELAY_ORIGIN}/callback`,code_verifier:resumed.data.verifier}),redirect:"error",signal:AbortSignal.timeout(10000)});
    const token=object(await response.json());
    if(!response.ok||typeof token.access_token!=="string")throw new RelayError("github_sign_in_failed",401);
    const github=await fetch("https://api.github.com/user",{headers:{Authorization:`Bearer ${token.access_token}`,Accept:"application/vnd.github+json","User-Agent":"Boring-Notch-Dot-Relay"},redirect:"error",signal:AbortSignal.timeout(10000)});
    const identity=object(await github.json());
    if(!github.ok||String(identity.id)!==OWNER_ID||String(identity.id)!==env.OWNER_GITHUB_ID) {
      resumed.headers.set("Location",authorizationErrorRedirect(resumed.request,"access_denied"));return new Response(null,{status:302,headers:resumed.headers});
    }
    const props:OwnerProps={githubId:OWNER_ID,githubToken:token.access_token};
    const completed=await oauth.completeAuthorization({request:resumed.request,userId:OWNER_ID,metadata:{label:"Private notch owner"},scope:resumed.request.scope,props});
    resumed.headers.set("Location",completed.redirectTo);return new Response(null,{status:302,headers:resumed.headers});
  }
  return new Response("Not found",{status:404});
}
