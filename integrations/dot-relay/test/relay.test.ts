import { afterEach,beforeEach,describe,expect,it,vi } from "vitest";
import { createExecutionContext,waitOnExecutionContext,runInDurableObject,runDurableObjectAlarm } from "cloudflare:test";
import { env } from "cloudflare:workers";
import worker, {createOAuthProvider} from "../src/index";
import type { Env,OwnerProps } from "../src/env";
import type { DotRelay } from "../src/relay";
import { b64,boundedText,callbackURL,decrypt,diagnosticCallbackOrigin,encrypt,OWNER_ID,readForm,readJSON,REPLY_LIMIT,RETENTION_MS,signedHeaders,signingKey,USER_LIMIT } from "../src/security";
const owner:OwnerProps={githubId:OWNER_ID,githubToken:"test-only-upstream"};
const bindings=env as Env;
const stub=()=>bindings.RELAY.getByName(crypto.randomUUID());
const message=()=>({messageId:crypto.randomUUID(),text:"fixture message"});
const subscription=()=>({name:"notch.message.created",arguments:{conversationId:"notch"},delivery:{mode:"webhook",url:"https://receiver.example.com/callback",secret:`whsec_${b64(new Uint8Array(32).fill(7))}`}});
// Synthetic outbound fixtures exercise protocol behavior; they are never evidence
// of a real Dot connection and never included in the deployed Worker.
type Fixture={url:string;method:string;status:number;body:unknown};
const fixtures:Fixture[]=[];
const outbound={
 activate(){vi.stubGlobal("fetch",async(input:RequestInfo|URL,init?:RequestInit)=>{const url=input instanceof Request?input.url:String(input);const method=init?.method??(input instanceof Request?input.method:"GET");const index=fixtures.findIndex(item=>item.url===url&&item.method===method);if(index<0)throw new Error("Unmatched synthetic outbound request");const fixture=fixtures.splice(index,1)[0];const body=typeof fixture.body==="function"?fixture.body({body:init?.body,headers:init?.headers}):fixture.body;return new Response(typeof body==="string"?body:JSON.stringify(body),{status:fixture.status,headers:{"Content-Type":"application/json"}});});},
 deactivate(){vi.unstubAllGlobals();fixtures.splice(0);},disableNetConnect(){},
 assertNoPendingInterceptors(){expect(fixtures).toHaveLength(0);},
 get(origin:string){return {intercept(options:{path:string;method?:string}){return {reply(status:number,body:unknown){fixtures.push({url:origin+options.path,method:options.method??"GET",status,body});}};}};},
};
async function rejectsInDO(relay:DurableObjectStub<DotRelay>,operation:(instance:DotRelay)=>Promise<unknown>){
 const rejected=await runInDurableObject(relay,async(instance:DotRelay)=>{try{await operation(instance);return false;}catch{return true;}});expect(rejected).toBe(true);
}
beforeEach(()=>{outbound.activate();outbound.disableNetConnect();});
afterEach(()=>{outbound.assertNoPendingInterceptors();outbound.deactivate();});
describe("payload and destination boundaries",()=>{
 it("bounds actual UTF8 payload bytes",()=>{expect(()=>boundedText("a".repeat(USER_LIMIT),USER_LIMIT)).not.toThrow();expect(()=>boundedText("😀".repeat(2049),USER_LIMIT)).toThrow();expect(()=>boundedText("",REPLY_LIMIT)).toThrow();});
 it("rejects arbitrary callback origins, redirects and local addresses",()=>{expect(callbackURL("https://receiver.example.com/callback","https://receiver.example.com").hostname).toBe("receiver.example.com");for(const url of ["http://receiver.example.com/callback","https://127.0.0.1/a","https://evil.example/a","https://user@receiver.example.com/a","https://receiver.example.com/a#x"])expect(()=>callbackURL(url,"https://receiver.example.com")).toThrow();});
 it("captures only a safe HTTPS callback origin for bounded diagnostics",async()=>{expect(diagnosticCallbackOrigin("https://receiver.example.com/a/path?token=hidden")).toBe("https://receiver.example.com");expect(diagnosticCallbackOrigin("http://receiver.example.com/path")).toBeNull();expect(diagnosticCallbackOrigin("https://127.0.0.1/path")).toBeNull();const relay=stub();outbound.get("https://receiver.example.com").intercept({path:"/callback",method:"POST"}).reply(200,{challenge:"wrong"});await rejectsInDO(relay,instance=>instance.subscribe(owner,"grant-diagnostic",subscription()));const readiness=await relay.readiness(owner);expect(readiness.lastSubscriptionAttempt).toMatchObject({origin:"https://receiver.example.com",reason:"challenge_failed"});expect(JSON.stringify(readiness.lastSubscriptionAttempt)).not.toContain("/callback");expect(JSON.stringify(readiness.lastSubscriptionAttempt)).not.toContain("whsec_");const cipher=await runInDurableObject(relay,async(_instance:DotRelay,state)=>state.storage.sql.exec<{cipher:string}>("SELECT cipher FROM subscription_diagnostic WHERE id=1").one().cipher);expect(cipher).not.toContain("receiver.example.com");await runInDurableObject(relay,async(_instance:DotRelay,state)=>state.storage.sql.exec("UPDATE subscription_diagnostic SET expires=0 WHERE id=1"));expect((await relay.readiness(owner)).lastSubscriptionAttempt).toBeNull();});
 it("fails closed with a distinct error when no callback allowlist is configured",()=>{expect(()=>callbackURL("https://receiver.example.com/callback","")).toThrow("callback_origin_unconfigured");});
 it("validates webhook signing secret length",()=>{expect(()=>signingKey(`whsec_${b64(new Uint8Array(23))}`)).toThrow();expect(signingKey(`whsec_${b64(new Uint8Array(24))}`).length).toBe(24);expect(()=>signingKey(`whsec_${b64(new Uint8Array(65))}`)).toThrow();});
 it("signs the stable webhook ID, timestamp and exact body",async()=>{const secret=`whsec_${b64(new Uint8Array(32).fill(7))}`;const headers=await signedHeaders(secret,"evt_fixture","{\"text\":\"fixture\"}","sub_fixture",1700000000000);expect(headers.get("webhook-timestamp")).toBe("1700000000");const key=await crypto.subtle.importKey("raw",signingKey(secret),{name:"HMAC",hash:"SHA-256"},false,["verify"]);const signature=Uint8Array.from(atob(headers.get("webhook-signature")!.slice(3)),c=>c.charCodeAt(0));expect(await crypto.subtle.verify("HMAC",key,signature,new TextEncoder().encode('evt_fixture.1700000000.{"text":"fixture"}'))).toBe(true);});
 it("encrypts payloads and binds ciphertext to its record",async()=>{const cipher=await encrypt({text:"fixture private"},bindings.RELAY_ENCRYPTION_KEY,"message:a");expect(cipher).not.toContain("fixture");expect(await decrypt(cipher,bindings.RELAY_ENCRYPTION_KEY,"message:a")).toEqual({text:"fixture private"});await expect(decrypt(cipher,bindings.RELAY_ENCRYPTION_KEY,"message:b")).rejects.toThrow();});
 it("bounds chunked JSON without trusting Content-Length",async()=>{const request=new Request("https://relay.example.com/a",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({text:"x".repeat(100)})});await expect(readJSON(request,32)).rejects.toThrow("payload_too_large");});
 it("bounds chunked OAuth consent forms",async()=>{const request=new Request("https://relay.example.com/authorize",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:`handle=${"x".repeat(5000)}`});await expect(readForm(request)).rejects.toThrow("payload_too_large");});
});
describe("persistent private channel",()=>{
 it("accepts stable message IDs once and rejects changed content",async()=>{const relay=stub(),input=message();const first=await relay.accept(owner,input);expect(first.status).toBe("queued");expect(await relay.accept(owner,input)).toEqual(first);await rejectsInDO(relay,instance=>instance.accept(owner,{...input,text:"changed"}));expect((await relay.events(owner,0)).events).toHaveLength(1);});
 it("enforces owner boundaries on all private operations",async()=>{const relay=stub(),other={...owner,githubId:"1"};await rejectsInDO(relay,instance=>instance.accept(other,message()));await rejectsInDO(relay,instance=>instance.events(other,0));await rejectsInDO(relay,instance=>instance.settings(other));await rejectsInDO(relay,instance=>instance.readiness(other));await rejectsInDO(relay,instance=>instance.revoke(other));});
 it("returns a bounded oldest-first pending ID queue without message content",async()=>{
  const relay=stub(),items=Array.from({length:23},()=>message()),created=Date.now()-30000;
  for(const item of items)await relay.accept(owner,item);
  await runInDurableObject(relay,async(_instance:DotRelay,state)=>{
   items.forEach((item,index)=>state.storage.sql.exec("UPDATE messages SET created=? WHERE id=?",created+index,item.messageId));
   state.storage.sql.exec("UPDATE messages SET status='failed' WHERE id=?",items[0].messageId);
   state.storage.sql.exec("UPDATE messages SET status='replied' WHERE id=?",items[1].messageId);
   state.storage.sql.exec("UPDATE messages SET created=? WHERE id=?",Date.now()-RETENTION_MS-1,items[2].messageId);
   state.storage.sql.exec("UPDATE messages SET status='delivered' WHERE id=?",items[4].messageId);
  });
  const readiness=await relay.readiness(owner);
  expect(readiness.pendingNativeMessages).toHaveLength(20);
  expect(readiness.pendingNativeMessages.map(item=>item.messageId)).toEqual(items.slice(3,23).map(item=>item.messageId));
  expect(readiness.pendingNativeMessages[1].status).toBe("delivered");
  expect(readiness.hasMorePending).toBe(false);
  expect(JSON.stringify(readiness.pendingNativeMessages)).not.toContain("fixture message");
  expect(Object.keys(readiness.pendingNativeMessages[0]).sort()).toEqual(["createdAt","messageId","status"]);
  await relay.reply(owner,{messageId:items[3].messageId,replyId:crypto.randomUUID(),text:"fixture reply"});
  const afterReply=await relay.readiness(owner);
  expect(afterReply.pendingNativeMessages.map(item=>item.messageId)).not.toContain(items[3].messageId);
 });
 it("signals additional pending messages beyond the readiness queue limit",async()=>{
  const relay=stub(),items=Array.from({length:21},()=>message());for(const item of items)await relay.accept(owner,item);
  const readiness=await relay.readiness(owner);expect(readiness.pendingNativeMessages).toHaveLength(20);expect(readiness.hasMorePending).toBe(true);
 });
 it("ties one deduplicated actual reply to an originating message",async()=>{const relay=stub(),input=message();await relay.accept(owner,input);const reply={messageId:input.messageId,replyId:crypto.randomUUID(),text:"fixture test tool reply"};const first=await relay.reply(owner,reply);expect(await relay.reply(owner,reply)).toEqual(first);await rejectsInDO(relay,instance=>instance.reply(owner,{...reply,replyId:crypto.randomUUID()}));await rejectsInDO(relay,instance=>instance.reply(owner,{...reply,messageId:crypto.randomUUID()}));const events=await relay.events(owner,0);expect(events.events.filter(event=>event.type==="reply")).toHaveLength(1);expect((await relay.accept(owner,input)).status).toBe("replied");});
 it("keeps encrypted storage private and seven-day payloads expire",async()=>{const relay=stub(),input=message();await relay.accept(owner,input);await runInDurableObject(relay,async(_instance:DotRelay,state)=>{const row=state.storage.sql.exec<{cipher:string}>("SELECT cipher FROM messages").one();expect(row.cipher).not.toContain(input.text);state.storage.sql.exec("UPDATE messages SET created=?",Date.now()-RETENTION_MS-1);state.storage.sql.exec("UPDATE events SET created=?",Date.now()-RETENTION_MS-1);});expect((await relay.events(owner,0)).events).toHaveLength(0);await rejectsInDO(relay,instance=>instance.context(owner,{messageId:input.messageId}));});
 it("verifies callback ownership before storing a subscription",async()=>{const relay=stub(),input=subscription();outbound.get("https://receiver.example.com").intercept({path:"/callback",method:"POST"}).reply(200,(options:{body:string})=>({challenge:JSON.parse(options.body as string).challenge}));const result=await relay.subscribe(owner,"grant-fixture",input);expect(result.id).toMatch(/^sub_/);expect((await relay.settings(owner)).subscriptionActive).toBe(true);await relay.unsubscribe(owner,input);expect((await relay.settings(owner)).subscriptionActive).toBe(false);});
 it("rejects wrong verification challenge",async()=>{const relay=stub();outbound.get("https://receiver.example.com").intercept({path:"/callback",method:"POST"}).reply(200,{challenge:"wrong"});await rejectsInDO(relay,instance=>instance.subscribe(owner,"grant-fixture",subscription()));expect((await relay.settings(owner)).subscriptionActive).toBe(false);});
 it("delivers the documented signed MCP event and records only bounded private delivery metadata",async()=>{
  const relay=stub(),input=message(),sub=subscription();let eventBody="";let eventHeaders:Headers|null=null;
  outbound.get("https://receiver.example.com").intercept({path:"/callback",method:"POST"}).reply(200,(options:{body:string})=>({challenge:JSON.parse(options.body).challenge}));
  await bindings.OAUTH_KV.put(`grant:${OWNER_ID}:wire-grant`,JSON.stringify({id:"wire-grant",userId:OWNER_ID,clientId:"fixture-client",scope:["notch:subscribe"],resource:"https://relay.example.com"}));
  const subscriptionResult=await relay.subscribe(owner,"wire-grant",sub);await relay.accept(owner,input);
  outbound.get("https://api.github.com").intercept({path:"/user"}).reply(200,{id:Number(OWNER_ID)});
  outbound.get("https://receiver.example.com").intercept({path:"/callback",method:"POST"}).reply(202,(options:{body:string;headers:HeadersInit})=>{eventBody=options.body;eventHeaders=new Headers(options.headers);return "";});
  await runDurableObjectAlarm(relay);

  const event=JSON.parse(eventBody) as {eventId:string;name:string;timestamp:string;data:Record<string,unknown>;cursor:null};
  expect(Object.keys(event).sort()).toEqual(["cursor","data","eventId","name","timestamp"]);
  expect(event.name).toBe("notch.message.created");expect(event.data).toEqual({conversationId:"notch",messageId:input.messageId,text:input.text});
  expect(Number.isNaN(Date.parse(event.timestamp))).toBe(false);expect(event.cursor).toBeNull();
  const headers=eventHeaders!;expect(headers.get("content-type")).toBe("application/json");
  expect(headers.get("webhook-id")).toBe(event.eventId);expect(headers.get("X-MCP-Subscription-Id")).toBe(subscriptionResult.id);
  const signature=headers.get("webhook-signature")!.split(" ")[0].slice(3);
  const key=await crypto.subtle.importKey("raw",signingKey(sub.delivery.secret),{name:"HMAC",hash:"SHA-256"},false,["verify"]);
  expect(await crypto.subtle.verify("HMAC",key,Uint8Array.from(atob(signature),char=>char.charCodeAt(0)),
    new TextEncoder().encode(`${event.eventId}.${headers.get("webhook-timestamp")}.${eventBody}`))).toBe(true);

  const events=await relay.events(owner,0);expect(events.events.at(-1)?.status).toBe("delivered");expect(events.events.some(value=>value.type==="reply")).toBe(false);
  const readiness=await relay.readiness(owner);expect(readiness.lastNativeMessage).toMatchObject({messageId:input.messageId,status:"delivered"});
  expect(readiness.lastDeliveryAttempt).toMatchObject({messageId:input.messageId,callbackHTTPStatus:202,attempts:1,status:"accepted"});
  expect(Number.isNaN(Date.parse(readiness.lastDeliveryAttempt!.time))).toBe(false);
  const safeDiagnostic=JSON.stringify(readiness.lastDeliveryAttempt);
  expect(safeDiagnostic).not.toContain(input.text);expect(safeDiagnostic).not.toContain("/callback");expect(safeDiagnostic).not.toContain("whsec_");
  expect(JSON.stringify(readiness.lastNativeMessage)).not.toContain(input.text);
  const ciphertext=await runInDurableObject(relay,async(_instance:DotRelay,state)=>state.storage.sql.exec<{cipher:string}>("SELECT cipher FROM delivery_diagnostic WHERE id=1").one().cipher);
  expect(ciphertext).not.toContain(input.messageId);expect(ciphertext).not.toContain(input.text);
  await runInDurableObject(relay,async(_instance:DotRelay,state)=>state.storage.sql.exec("UPDATE delivery_diagnostic SET expires=0 WHERE id=1"));
  expect((await relay.readiness(owner)).lastDeliveryAttempt).toBeNull();
 });
 it("revoked subscription grant prevents outbound delivery",async()=>{const relay=stub(),input=message();outbound.get("https://receiver.example.com").intercept({path:"/callback",method:"POST"}).reply(200,(options:{body:string})=>({challenge:JSON.parse(options.body as string).challenge}));await relay.subscribe(owner,"missing-grant",subscription());await relay.accept(owner,input);await runDurableObjectAlarm(relay);expect((await relay.settings(owner)).subscriptionActive).toBe(false);expect((await relay.events(owner,0)).events.at(-1)?.status).toBe("failed");});
});
describe("HTTP authentication",()=>{
 it("fails closed until owner OAuth credentials are configured",async()=>{const context=createExecutionContext();const response=await worker.fetch(new Request("https://relay.example.com/v1/events"),{...bindings,GITHUB_CLIENT_SECRET:""},context);expect(response.status).toBe(503);await waitOnExecutionContext(context);});
 it("requires credentials for protected native and MCP routes",async()=>{for(const path of ["/v1/events","/mcp"]){const context=createExecutionContext();const response=await createOAuthProvider(bindings).fetch(new Request(`https://relay.example.com${path}`),bindings,context);expect(response.status).toBe(401);expect(response.headers.get("WWW-Authenticate")).toContain("oauth-protected-resource");await waitOnExecutionContext(context);}});
 it("supports PKCE public native registration and issuer discovery",async()=>{let context=createExecutionContext();const response=await createOAuthProvider(bindings).fetch(new Request("https://relay.example.com/oauth/register",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({client_name:"Boring Notch Agents",redirect_uris:["boringnotch-agents://oauth/callback"],token_endpoint_auth_method:"none",grant_types:["authorization_code","refresh_token"],response_types:["code"]})}),bindings,context);expect(response.status).toBe(201);await waitOnExecutionContext(context);context=createExecutionContext();const discovery=await worker.fetch(new Request("https://relay.example.com/.well-known/oauth-authorization-server"),bindings,context);const metadata=await discovery.json() as Record<string,unknown>;expect(metadata.issuer).toBe("https://relay.example.com");expect(metadata.authorization_response_iss_parameter_supported).toBe(true);expect(metadata.code_challenge_methods_supported).toEqual(["S256"]);await waitOnExecutionContext(context);});
});

async function requestLocal(path:string,init?:RequestInit){const context=createExecutionContext();const response=await worker.fetch(new Request(`https://relay.example.com${path}`,init),bindings,context);await waitOnExecutionContext(context);return response;}
function cookies(response:Response):string{return response.headers.getSetCookie().map(cookie=>cookie.split(";")[0]).join("; ");}
async function prepareNativeAuthorization(){
 const registered=await requestLocal("/oauth/register",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({client_name:"Boring Notch Agents",redirect_uris:["boringnotch-agents://oauth/callback"],token_endpoint_auth_method:"none",grant_types:["authorization_code","refresh_token"],response_types:["code"]})});
 const client=await registered.json() as {client_id:string};const verifier="v".repeat(43);
 const challenge=b64(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(verifier)))).replace(/\+/g,"-").replace(/\//g,"_").replace(/=/g,"");
 const parameters=new URLSearchParams({client_id:client.client_id,redirect_uri:"boringnotch-agents://oauth/callback",response_type:"code",scope:"notch:read notch:send offline_access",resource:"https://relay.example.com",state:"fixture-client-state",code_challenge:challenge,code_challenge_method:"S256"});
 const consent=await requestLocal(`/authorize?${parameters}`);expect(consent.status).toBe(200);
 expect(consent.headers.get("Content-Security-Policy")).toContain("form-action 'self' https://github.com;");
 expect(consent.headers.get("Content-Security-Policy")).toContain("frame-ancestors 'none'");
 const page=await consent.text();const handle=/name="handle" value="([^"]+)"/.exec(page)![1];
 return {clientId:client.client_id,verifier,handle,cookie:cookies(consent)};
}
describe("owner OAuth roundtrip fixtures",()=>{
 it("rejects upstream token redirects without forwarding credentials",async()=>{
  const prepared=await prepareNativeAuthorization();
  const redirect=await requestLocal("/authorize",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded",Origin:"https://relay.example.com",Cookie:prepared.cookie},body:new URLSearchParams({handle:prepared.handle,decision:"allow"})});
  const state=new URL(redirect.headers.get("Location")!).searchParams.get("state")!;
  outbound.get("https://github.com").intercept({path:"/login/oauth/access_token",method:"POST"}).reply(302,"");
  const callback=await requestLocal(`/callback?${new URLSearchParams({state,code:"fixture-github-code"})}`,{headers:{Cookie:cookies(redirect)}});
  expect(callback.status).toBe(503);
  expect(await callback.json()).toEqual({error:"github_token_redirect_rejected"});
 });
 it("refuses forged consent without the browser binding",async()=>{const prepared=await prepareNativeAuthorization();const response=await requestLocal("/authorize",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded",Origin:"https://relay.example.com"},body:new URLSearchParams({handle:prepared.handle,decision:"allow"})});expect(response.status).toBe(400);});
 it("refuses cross-site consent posts even with a valid cookie",async()=>{const prepared=await prepareNativeAuthorization();const response=await requestLocal("/authorize",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded",Origin:"https://evil.example",Cookie:prepared.cookie},body:new URLSearchParams({handle:prepared.handle,decision:"allow"})});expect(response.status).toBe(403);});
 it("refuses a different GitHub owner after authenticated callback",async()=>{const prepared=await prepareNativeAuthorization();const redirect=await requestLocal("/authorize",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded",Origin:"https://relay.example.com",Cookie:prepared.cookie},body:new URLSearchParams({handle:prepared.handle,decision:"allow"})});expect(redirect.status).toBe(302);const state=new URL(redirect.headers.get("Location")!).searchParams.get("state")!;outbound.get("https://github.com").intercept({path:"/login/oauth/access_token",method:"POST"}).reply(200,{access_token:"fixture-owner-token"});outbound.get("https://api.github.com").intercept({path:"/user"}).reply(200,{id:1});const callback=await requestLocal(`/callback?${new URLSearchParams({state,code:"fixture-github-code"})}`,{headers:{Cookie:cookies(redirect)}});expect(callback.status).toBe(302);const final=new URL(callback.headers.get("Location")!);expect(final.searchParams.get("error")).toBe("access_denied");expect(final.searchParams.get("iss")).toBe("https://relay.example.com");});
 it("completes owner PKCE OAuth with issuer and enforces native/plugin scope separation",async()=>{const prepared=await prepareNativeAuthorization();const redirect=await requestLocal("/authorize",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded",Origin:"https://relay.example.com",Cookie:prepared.cookie},body:new URLSearchParams({handle:prepared.handle,decision:"allow"})});expect(redirect.status).toBe(302);const state=new URL(redirect.headers.get("Location")!).searchParams.get("state")!;outbound.get("https://github.com").intercept({path:"/login/oauth/access_token",method:"POST"}).reply(200,{access_token:"fixture-owner-token"});outbound.get("https://api.github.com").intercept({path:"/user"}).reply(200,{id:Number(OWNER_ID)});const callback=await requestLocal(`/callback?${new URLSearchParams({state,code:"fixture-github-code"})}`,{headers:{Cookie:cookies(redirect)}});expect(callback.status).toBe(302);const final=new URL(callback.headers.get("Location")!);expect(final.searchParams.get("iss")).toBe("https://relay.example.com");expect(final.searchParams.get("state")).toBe("fixture-client-state");outbound.get("https://api.github.com").intercept({path:"/user"}).reply(200,{id:Number(OWNER_ID)});const exchange=await requestLocal("/oauth/token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:new URLSearchParams({grant_type:"authorization_code",client_id:prepared.clientId,redirect_uri:"boringnotch-agents://oauth/callback",code:final.searchParams.get("code")!,code_verifier:prepared.verifier,resource:"https://relay.example.com"})});expect(exchange.status).toBe(200);const token=await exchange.json() as {access_token:string};const native=await requestLocal("/v1/settings",{headers:{Authorization:`Bearer ${token.access_token}`}});expect(native.status).toBe(200);const plugin=await requestLocal("/mcp",{method:"POST",headers:{Authorization:`Bearer ${token.access_token}`,"Content-Type":"application/json"},body:JSON.stringify({jsonrpc:"2.0",id:1,method:"tools/call",params:{name:"notch_reply",arguments:{messageId:crypto.randomUUID(),replyId:crypto.randomUUID(),text:"fixture-only"}}})});expect(plugin.status).toBe(403);});
});

it("rejects a retained opaque ID after payload expiry instead of triggering another send",async()=>{
 const relay=stub(),input=message();await relay.accept(owner,input);
 await runInDurableObject(relay,async(_instance:DotRelay,state)=>{state.storage.sql.exec("UPDATE messages SET created=?",Date.now()-RETENTION_MS-1);state.storage.sql.exec("UPDATE events SET created=?",Date.now()-RETENTION_MS-1);});
 await relay.events(owner,0);
 const failure=await runInDurableObject(relay,async(instance:DotRelay)=>{try{await instance.accept(owner,input);return {code:"unexpected_accept",status:200};}catch(error){const failure=error as {code:string;status:number};return {code:failure.code,status:failure.status};}});
 expect(failure).toEqual({code:"message_expired",status:410});
});

it("stops at six delivery attempts while preserving the originating event ID",async()=>{
 const relay=stub(),input=message(),ids:string[]=[];
 outbound.get("https://receiver.example.com").intercept({path:"/callback",method:"POST"}).reply(200,(options:{body:string})=>({challenge:JSON.parse(options.body).challenge}));
 await bindings.OAUTH_KV.put(`grant:${OWNER_ID}:retry-grant`,JSON.stringify({id:"retry-grant",userId:OWNER_ID,clientId:"fixture-client",scope:["notch:subscribe"]}));
 await relay.subscribe(owner,"retry-grant",subscription());await relay.accept(owner,input);
 for(let attempt=0;attempt<6;attempt++){
  await runInDurableObject(relay,async(_instance:DotRelay,state)=>{state.storage.sql.exec("UPDATE pending SET next_at=0");});
  outbound.get("https://api.github.com").intercept({path:"/user"}).reply(200,{id:Number(OWNER_ID)});
  outbound.get("https://receiver.example.com").intercept({path:"/callback",method:"POST"}).reply(503,(options:{body:string})=>{ids.push(JSON.parse(options.body).eventId);return "";});
  await runDurableObjectAlarm(relay);
 }
 expect(new Set(ids).size).toBe(1);expect(ids).toHaveLength(6);
 expect((await relay.events(owner,0)).events.at(-1)?.status).toBe("failed");
 const pending=await runInDurableObject(relay,async(_instance:DotRelay,state)=>state.storage.sql.exec<{count:number}>("SELECT COUNT(*) AS count FROM pending").one().count);expect(pending).toBe(0);
});
it("expired subscriptions stop pending sends before any outbound request",async()=>{
 const relay=stub(),input=message();
 outbound.get("https://receiver.example.com").intercept({path:"/callback",method:"POST"}).reply(200,(options:{body:string})=>({challenge:JSON.parse(options.body).challenge}));
 await relay.subscribe(owner,"expiry-grant",subscription());await relay.accept(owner,input);
 await runInDurableObject(relay,async(_instance:DotRelay,state)=>{state.storage.sql.exec("UPDATE subscription SET expires=0");state.storage.sql.exec("UPDATE pending SET next_at=0");});
 await runDurableObjectAlarm(relay);expect((await relay.settings(owner)).subscriptionActive).toBe(false);expect((await relay.events(owner,0)).events.at(-1)?.status).toBe("failed");
});
it("does not follow a callback verification redirect",async()=>{
 const relay=stub();outbound.get("https://receiver.example.com").intercept({path:"/callback",method:"POST"}).reply(302,"");
 await rejectsInDO(relay,instance=>instance.subscribe(owner,"redirect-grant",subscription()));expect((await relay.settings(owner)).subscriptionActive).toBe(false);
});
