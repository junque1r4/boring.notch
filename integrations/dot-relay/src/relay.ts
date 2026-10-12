// Modified for Boring Notch Agents, 2026-10-11. GPL-3.0-only.
import { DurableObject } from "cloudflare:workers";
import type { Env, OwnerProps } from "./env";
import { boundedText, callbackURL, decrypt, diagnosticCallbackOrigin, digest, encrypt, equal, EVENT_NAME, object, OWNER_ID, RelayError, REPLY_LIMIT, RETENTION_MS, retryDelay, signedHeaders, signingKey, SUBSCRIPTION_TTL_MS, USER_LIMIT, uuid, textFingerprint } from "./security";
export type DeliveryStatus = "queued" | "delivered" | "failed" | "replied";
interface MessageRow extends Record<string,SqlStorageValue> { id:string; cipher:string; hash:string; status:DeliveryStatus; created:number; event_id:string; }
interface Subscription { id:string; url:string; secret:string; previousSecret?:string; rotatedAt?:number; expires:number; owner:OwnerProps; grantId:string; verifiedAt:number; }
interface EventRow extends Record<string,SqlStorageValue> { sequence:number; event_id:string; message_id:string; type:"delivery"|"reply"; cipher:string; created:number; }
interface PendingRow extends Record<string,SqlStorageValue> { message_id:string; subscription_id:string; attempts:number; next_at:number; }
type DeliveryDiagnosticStatus = "accepted"|"retrying"|"failed"|"revoked";
interface DeliveryDiagnostic { messageId:string;callbackHTTPStatus:number|null;time:string;attempts:number;status:DeliveryDiagnosticStatus; }
interface MessageStatusSummary { messageId:string;status:DeliveryStatus;createdAt:string; }
export interface RelayEvent { sequence:number;eventId:string;messageId:string;type:"delivery"|"reply";status?:DeliveryStatus;text?:string;createdAt:string; }
const iso = (value:number) => new Date(value).toISOString();

export class DotRelay extends DurableObject<Env> {
  constructor(ctx:DurableObjectState, env:Env) {
    super(ctx,env);
    ctx.blockConcurrencyWhile(async()=> {
      ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS tombstones(id TEXT PRIMARY KEY,expires INTEGER NOT NULL)`);
      ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,cipher TEXT NOT NULL,hash TEXT NOT NULL,status TEXT NOT NULL,created INTEGER NOT NULL,event_id TEXT NOT NULL UNIQUE)`);
      ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS events(sequence INTEGER PRIMARY KEY AUTOINCREMENT,event_id TEXT NOT NULL UNIQUE,message_id TEXT NOT NULL,type TEXT NOT NULL,cipher TEXT NOT NULL,created INTEGER NOT NULL)`);
      ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS subscription(id TEXT PRIMARY KEY,cipher TEXT NOT NULL,expires INTEGER NOT NULL)`);
      ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS subscription_diagnostic(id INTEGER PRIMARY KEY CHECK(id=1),cipher TEXT NOT NULL,expires INTEGER NOT NULL)`);
      ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS delivery_diagnostic(id INTEGER PRIMARY KEY CHECK(id=1),cipher TEXT NOT NULL,expires INTEGER NOT NULL)`);
      ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS pending(message_id TEXT PRIMARY KEY,subscription_id TEXT NOT NULL,attempts INTEGER NOT NULL,next_at INTEGER NOT NULL)`);
    });
  }
  private owner(owner:OwnerProps) { if (owner.githubId!==OWNER_ID || owner.githubId!==this.env.OWNER_GITHUB_ID) throw new RelayError("forbidden",403); }
  private message(id:string):MessageRow|undefined { return this.ctx.storage.sql.exec<MessageRow>("SELECT * FROM messages WHERE id=?",id).toArray()[0]; }
  private async subscription():Promise<Subscription|undefined> {
    const row=this.ctx.storage.sql.exec<{id:string;cipher:string;expires:number}>("SELECT * FROM subscription LIMIT 1").toArray()[0];
    if (!row || row.expires<=Date.now()) return undefined;
    return decrypt<Subscription>(row.cipher,this.env.RELAY_ENCRYPTION_KEY,`subscription:${row.id}`);
  }
  private sequence():number { return this.ctx.storage.sql.exec<{seq:number}>("SELECT COALESCE(MAX(sequence),0) AS seq FROM events").one().seq; }
  private append(eventId:string,messageId:string,type:string,cipher:string,created=Date.now()) {
    this.ctx.storage.sql.exec("INSERT INTO events(event_id,message_id,type,cipher,created) VALUES(?,?,?,?,?)",eventId,messageId,type,cipher,created);
  }
  async accept(owner:OwnerProps,input:Record<string,unknown>) {
    this.owner(owner); const messageId=uuid(input.messageId); const text=boundedText(input.text,USER_LIMIT);
    if (Object.keys(input).some(key=>!["messageId","text"].includes(key))) throw new RelayError("unexpected_fields");
    if(this.ctx.storage.sql.exec<{id:string}>("SELECT id FROM tombstones WHERE id=?",messageId).toArray().length)throw new RelayError("message_expired",410);
    const hash=await textFingerprint(text,this.env.RELAY_ENCRYPTION_KEY); const existing=this.message(messageId);
    if (existing) { if(existing.hash!==hash) throw new RelayError("message_id_conflict",409);return this.receipt(existing); }
    const count=this.ctx.storage.sql.exec<{count:number}>("SELECT COUNT(*) AS count FROM messages WHERE created>?",Date.now()-60000).one().count;
    if(count>=30) throw new RelayError("rate_limited",429);
    if(this.ctx.storage.sql.exec<{count:number}>("SELECT COUNT(*) AS count FROM messages").one().count>=2000) throw new RelayError("relay_capacity",429);
    const now=Date.now(); const cipher=await encrypt({text},this.env.RELAY_ENCRYPTION_KEY,`message:${messageId}`);
    const eventId=crypto.randomUUID(); const deliveryId=crypto.randomUUID();
    const delivery=await encrypt({status:"queued"},this.env.RELAY_ENCRYPTION_KEY,`event:${deliveryId}`);
    const sub=await this.subscription();
    this.ctx.storage.transactionSync(()=> {
      const raced=this.message(messageId);
      if(raced) {if(raced.hash!==hash)throw new RelayError("message_id_conflict",409);return;}
      this.ctx.storage.sql.exec("INSERT INTO messages VALUES(?,?,?,?,?,?)",messageId,cipher,hash,"queued",now,eventId);
      this.append(deliveryId,messageId,"delivery",delivery,now);
      if(sub) this.ctx.storage.sql.exec("INSERT INTO pending VALUES(?,?,0,?)",messageId,sub.id,now);
    });
    await this.schedule(); return this.receipt(this.message(messageId)!);
  }
  private async receipt(message:MessageRow) { return {messageId:message.id,status:message.status,sequence:this.sequence(),subscriptionActive:!!await this.subscription()}; }
  async events(owner:OwnerProps,after:number) {
    this.owner(owner); if (!Number.isSafeInteger(after)||after<0) throw new RelayError("invalid_cursor");
    await this.purge();
    const rows=this.ctx.storage.sql.exec<EventRow>("SELECT * FROM events WHERE sequence>? ORDER BY sequence LIMIT 100",after).toArray();
    const events:RelayEvent[]=[]; let bytes=0; let cursor=after;
    for (const row of rows) {
      const payload=await decrypt<{status?:DeliveryStatus;text?:string}>(row.cipher,this.env.RELAY_ENCRYPTION_KEY,`event:${row.event_id}`);
      const event={sequence:row.sequence,eventId:row.event_id,messageId:row.message_id,type:row.type,...payload,createdAt:iso(row.created)};
      const size=new TextEncoder().encode(JSON.stringify(event)).length;
      if(bytes+size>900000) break;
      bytes+=size;events.push(event);cursor=row.sequence;
    }
    return {events,cursor,subscriptionActive:!!await this.subscription()};
  }
  async settings(owner:OwnerProps) { this.owner(owner); return {conversationId:"notch",subscriptionActive:!!await this.subscription(),callbackAllowlistConfigured:this.env.CALLBACK_ORIGINS.split(",").some(origin=>origin.trim().length>0),payloadRetentionDays:7,maxUserTextBytes:USER_LIMIT,maxReplyTextBytes:REPLY_LIMIT}; }
  private async recordSubscriptionAttempt(origin:string|null,reason:string) {
    const expires=Date.now()+60*60*1000;
    const cipher=await encrypt({origin,reason},this.env.RELAY_ENCRYPTION_KEY,"subscription-diagnostic");
    this.ctx.storage.sql.exec("INSERT INTO subscription_diagnostic(id,cipher,expires) VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET cipher=excluded.cipher,expires=excluded.expires",cipher,expires);
  }
  private async lastSubscriptionAttempt() {
    const row=this.ctx.storage.sql.exec<{cipher:string;expires:number}>("SELECT cipher,expires FROM subscription_diagnostic WHERE id=1").toArray()[0];
    if(!row)return null;
    if(row.expires<=Date.now()){this.ctx.storage.sql.exec("DELETE FROM subscription_diagnostic WHERE id=1");return null;}
    return decrypt<{origin:string|null;reason:string}>(row.cipher,this.env.RELAY_ENCRYPTION_KEY,"subscription-diagnostic");
  }
  private async recordDeliveryAttempt(value:Omit<DeliveryDiagnostic,"time">) {
    try {
      const expires=Date.now()+60*60*1000;
      const diagnostic:DeliveryDiagnostic={...value,time:iso(Date.now())};
      const cipher=await encrypt(diagnostic,this.env.RELAY_ENCRYPTION_KEY,"delivery-diagnostic");
      this.ctx.storage.sql.exec("INSERT INTO delivery_diagnostic(id,cipher,expires) VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET cipher=excluded.cipher,expires=excluded.expires",cipher,expires);
    } catch { /* diagnostics must never affect delivery behavior */ }
  }
  private async lastDeliveryAttempt():Promise<DeliveryDiagnostic|null> {
    const row=this.ctx.storage.sql.exec<{cipher:string;expires:number}>("SELECT cipher,expires FROM delivery_diagnostic WHERE id=1").toArray()[0];
    if(!row)return null;
    if(row.expires<=Date.now()){this.ctx.storage.sql.exec("DELETE FROM delivery_diagnostic WHERE id=1");return null;}
    return decrypt<DeliveryDiagnostic>(row.cipher,this.env.RELAY_ENCRYPTION_KEY,"delivery-diagnostic");
  }
  private latestMessageStatus():MessageStatusSummary|null {
    const row=this.ctx.storage.sql.exec<{id:string;status:DeliveryStatus;created:number}>("SELECT id,status,created FROM messages ORDER BY created DESC,rowid DESC LIMIT 1").toArray()[0];
    return row?{messageId:row.id,status:row.status,createdAt:iso(row.created)}:null;
  }
  async readiness(owner:OwnerProps) { return {...await this.settings(owner),lastSubscriptionAttempt:await this.lastSubscriptionAttempt(),lastDeliveryAttempt:await this.lastDeliveryAttempt(),lastNativeMessage:this.latestMessageStatus()}; }
  async context(owner:OwnerProps,input:Record<string,unknown>) {
    this.owner(owner); const messageId=uuid(input.messageId);const target=this.message(messageId);
    if(!target || target.created<Date.now()-RETENTION_MS) throw new RelayError("message_not_found",404);
    const rows=this.ctx.storage.sql.exec<MessageRow>("SELECT * FROM messages WHERE created<=? AND created>? ORDER BY created DESC LIMIT 20",target.created,Date.now()-RETENTION_MS).toArray().reverse();
    const messages:Record<string,unknown>[]=[];let bytes=0;
    for(const row of rows) {
      const {text}=await decrypt<{text:string}>(row.cipher,this.env.RELAY_ENCRYPTION_KEY,`message:${row.id}`);
      const item={messageId:row.id,role:"user",text,createdAt:iso(row.created)};
      bytes+=new TextEncoder().encode(JSON.stringify(item)).length;
      if(bytes>65536) {messages.splice(0,messages.length);bytes=new TextEncoder().encode(JSON.stringify(item)).length;}
      messages.push(item);
      const replies=this.ctx.storage.sql.exec<EventRow>("SELECT * FROM events WHERE message_id=? AND type='reply' ORDER BY sequence",row.id).toArray();
      for(const reply of replies) {
        const payload=await decrypt<{text:string}>(reply.cipher,this.env.RELAY_ENCRYPTION_KEY,`event:${reply.event_id}`);
        const item={messageId:row.id,replyId:reply.event_id,role:"assistant",text:payload.text,createdAt:iso(reply.created)};
        const size=new TextEncoder().encode(JSON.stringify(item)).length;
        if(bytes+size<=65536) {messages.push(item);bytes+=size;}
      }
    }
    return {conversationId:"notch",originatingMessageId:messageId,messages};
  }
  async reply(owner:OwnerProps,input:Record<string,unknown>) {
    this.owner(owner); const messageId=uuid(input.messageId); const replyId=uuid(input.replyId); const text=boundedText(input.text,REPLY_LIMIT);
    const message=this.message(messageId);
    if(!message || message.created<Date.now()-RETENTION_MS) throw new RelayError("message_not_found",404);
    const old=this.ctx.storage.sql.exec<EventRow>("SELECT * FROM events WHERE event_id=?",replyId).toArray()[0];
    if(old) {
      const data=await decrypt<{text:string}>(old.cipher,this.env.RELAY_ENCRYPTION_KEY,`event:${replyId}`);
      if(old.message_id!==messageId||old.type!=="reply"||data.text!==text) throw new RelayError("reply_id_conflict",409);
      return {replyId,messageId,sequence:old.sequence};
    }
    // One originating notch send creates at most one Dot response; another reply ID
    // cannot silently duplicate a completed reply after a timeout or restart.
    if(message.status==="replied") throw new RelayError("message_already_replied",409);
    const cipher=await encrypt({text},this.env.RELAY_ENCRYPTION_KEY,`event:${replyId}`);
    this.ctx.storage.transactionSync(()=> {
      if(this.message(messageId)?.status==="replied") throw new RelayError("message_already_replied",409);
      this.append(replyId,messageId,"reply",cipher);
      this.ctx.storage.sql.exec("UPDATE messages SET status='replied' WHERE id=?",messageId);
      this.ctx.storage.sql.exec("DELETE FROM pending WHERE message_id=?",messageId);
    });
    await this.schedule();return {replyId,messageId,sequence:this.sequence()};
  }
  private validateSubscription(input:Record<string,unknown>,allowedOrigins:string,secretRequired=true) {
    if(input.name!==EVENT_NAME)throw new RelayError("unknown_event");
    const args=object(input.arguments);
    if(args.conversationId!=="notch"||Object.keys(args).length!==1)throw new RelayError("invalid_arguments");
    const delivery=object(input.delivery);
    if(delivery.mode!=="webhook")throw new RelayError("invalid_delivery");
    const url=callbackURL(delivery.url,allowedOrigins).href;
    if(secretRequired)signingKey(delivery.secret);
    return {url,secret:delivery.secret as string};
  }
  async subscribe(owner:OwnerProps,grantId:string,input:Record<string,unknown>) {
    this.owner(owner);
    const deliveryOrigin=diagnosticCallbackOrigin(input.delivery&&typeof input.delivery==="object"&&!Array.isArray(input.delivery)?(input.delivery as Record<string,unknown>).url:null);
    try {
    const delivery=this.validateSubscription(input,this.env.CALLBACK_ORIGINS);
    const ttl=input.ttlMs===undefined||input.ttlMs===null?SUBSCRIPTION_TTL_MS:input.ttlMs;
    if(typeof ttl!=="number"||!Number.isSafeInteger(ttl)||ttl<1000)throw new RelayError("invalid_ttl");
    const id=`sub_${await digest(`${owner.githubId}\n${delivery.url}\n${EVENT_NAME}\nnotch`)}`;
    const current=await this.subscription();
    // One actual Dot owns the private channel. A changed callback replaces the prior
    // destination only after the new destination proves possession of its secret.
    const challenge=crypto.randomUUID();const body=JSON.stringify({type:"verification",challenge});
    if(!(current?.id===id&&current.secret===delivery.secret&&current.grantId===grantId&&Date.now()-current.verifiedAt<300000))try {
      const response=await this.webhook(delivery.url,{method:"POST",body,headers:await signedHeaders(delivery.secret,crypto.randomUUID(),body,id)});
      if(!response.ok)throw new RelayError("challenge_failed");
      const echo=await this.boundedResponse(response,4096);
      if(!await equal(String(echo.challenge??""),challenge))throw new RelayError("challenge_failed");
    }catch(error) { if(error instanceof RelayError)throw error;throw new RelayError("callback_unavailable",502); }
    const sub:Subscription={id,...delivery,expires:Date.now()+Math.min(ttl,SUBSCRIPTION_TTL_MS),owner,grantId,verifiedAt:Date.now()};
    if(current?.id===id&&current.secret!==delivery.secret) {sub.previousSecret=current.secret;sub.rotatedAt=Date.now();}
    const cipher=await encrypt(sub,this.env.RELAY_ENCRYPTION_KEY,`subscription:${id}`);
    this.ctx.storage.transactionSync(()=> {
      this.ctx.storage.sql.exec("DELETE FROM subscription");this.ctx.storage.sql.exec("INSERT INTO subscription VALUES(?,?,?)",id,cipher,sub.expires);
      this.ctx.storage.sql.exec("DELETE FROM pending");
      this.ctx.storage.sql.exec("INSERT INTO pending SELECT id,?,0,? FROM messages WHERE status='queued' AND created>?",id,Date.now(),Date.now()-RETENTION_MS);
    });
    await this.schedule();
    try { await this.recordSubscriptionAttempt(deliveryOrigin,"subscribed"); } catch { /* diagnostics must not change delivery behavior */ }
    return {id,refreshBefore:iso(sub.expires),cursor:null,truncated:false};
    } catch(error) {
      const reason=error instanceof RelayError?error.code:"callback_unavailable";
      try { await this.recordSubscriptionAttempt(deliveryOrigin,reason); } catch { /* preserve the original subscription error */ }
      throw error;
    }
  }
  async unsubscribe(owner:OwnerProps,input:Record<string,unknown>) {
    this.owner(owner);const {url}=this.validateSubscription(input,this.env.CALLBACK_ORIGINS,false);const sub=await this.subscription();
    if(sub?.url===url) await this.revoke(owner);
    return {};
  }
  async revoke(owner:OwnerProps) {
    this.owner(owner);this.ctx.storage.sql.exec("DELETE FROM subscription");
    const pending=this.ctx.storage.sql.exec<PendingRow>("SELECT * FROM pending").toArray();
    for(const row of pending)await this.status(row.message_id,"failed");
    this.ctx.storage.sql.exec("DELETE FROM pending");await this.schedule();return {revoked:true};
  }
  private async boundedResponse(response:Response,limit:number):Promise<Record<string,unknown>> {
    const reader=response.body?.getReader();if(!reader)throw new RelayError("challenge_failed");
    let length=0;const parts:Uint8Array[]=[];
    while(true){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>limit){await reader.cancel();throw new RelayError("challenge_failed");}parts.push(value);}
    const bytes=new Uint8Array(length);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}
    try{return object(JSON.parse(new TextDecoder().decode(bytes)));}catch{throw new RelayError("challenge_failed");}
  }
  private webhook(url:string,init:RequestInit):Promise<Response> {
    const approved=callbackURL(url,this.env.CALLBACK_ORIGINS);
    return fetch(approved,{...init,redirect:"manual",signal:AbortSignal.timeout(10000)});
  }
  private async status(messageId:string,status:DeliveryStatus) {
    const message=this.message(messageId);if(!message||message.status==="replied"||message.status===status)return;
    const id=crypto.randomUUID();const cipher=await encrypt({status},this.env.RELAY_ENCRYPTION_KEY,`event:${id}`);
    this.ctx.storage.transactionSync(()=> {if(this.message(messageId)?.status==="replied")return;this.ctx.storage.sql.exec("UPDATE messages SET status=? WHERE id=?",status,messageId);this.append(id,messageId,"delivery",cipher);});
  }
  private async authorized(sub:Subscription):Promise<boolean> {
    if(sub.expires<=Date.now()||sub.owner.githubId!==this.env.OWNER_GITHUB_ID)return false;
    const grant=await this.env.OAUTH_KV.get(`grant:${sub.owner.githubId}:${sub.grantId}`);
    if(!grant)return false;
    const response=await fetch("https://api.github.com/user",{headers:{Authorization:`Bearer ${sub.owner.githubToken}`,Accept:"application/vnd.github+json","User-Agent":"Boring-Notch-Dot-Relay"},redirect:"manual",signal:AbortSignal.timeout(10000)});
    if(response.status===401||response.status===403)return false;
    if(!response.ok)throw new RelayError("identity_temporarily_unavailable",503);
    const user=object(await response.json());return String(user.id)===this.env.OWNER_GITHUB_ID;
  }
  async alarm() {
    await this.purge();const sub=await this.subscription();
    const pending=this.ctx.storage.sql.exec<PendingRow>("SELECT * FROM pending WHERE next_at<=? ORDER BY next_at LIMIT 10",Date.now()).toArray();
    if(!sub) {
      for(const row of this.ctx.storage.sql.exec<PendingRow>("SELECT * FROM pending").toArray())await this.status(row.message_id,"failed");
      this.ctx.storage.sql.exec("DELETE FROM pending");await this.schedule();return;
    }
    let valid=false;try{valid=await this.authorized(sub);}catch {
      // Identity outages count as bounded delivery attempts and never bypass authorization.
      for(const row of pending)await this.retry(row);await this.schedule();return;
    }
    if(!valid){await this.revoke(sub.owner);return;}
    for(const row of pending) {
      const message=this.message(row.message_id);if(!message||message.status==="replied"||row.subscription_id!==sub.id){this.ctx.storage.sql.exec("DELETE FROM pending WHERE message_id=?",row.message_id);continue;}
      const {text}=await decrypt<{text:string}>(message.cipher,this.env.RELAY_ENCRYPTION_KEY,`message:${message.id}`);
      const body=JSON.stringify({eventId:message.event_id,name:EVENT_NAME,timestamp:iso(message.created),data:{conversationId:"notch",messageId:message.id,text},cursor:null});
      const attempts=row.attempts+1;
      try {
        const headers=await signedHeaders(sub.secret,message.event_id,body,sub.id);
        if(sub.previousSecret&&Date.now()-(sub.rotatedAt??0)<300000){const old=await signedHeaders(sub.previousSecret,message.event_id,body,sub.id);headers.set("webhook-signature",`${headers.get("webhook-signature")} ${old.get("webhook-signature")}`);}
        const response=await this.webhook(sub.url,{method:"POST",body,headers});
        const diagnosticStatus:DeliveryDiagnosticStatus=response.ok?"accepted":response.status===410?"revoked":response.status===413||(response.status>=400&&response.status<500&&response.status!==408&&response.status!==429)?"failed":attempts>=6?"failed":"retrying";
        await this.recordDeliveryAttempt({messageId:message.id,callbackHTTPStatus:response.status,attempts,status:diagnosticStatus});
        try { await response.body?.cancel(); } catch { /* response status is already recorded */ }
        const live=await this.subscription();
        if(!live||live.id!==sub.id)continue;
        if(response.ok){await this.status(message.id,"delivered");this.ctx.storage.sql.exec("DELETE FROM pending WHERE message_id=?",message.id);}
        else if(response.status===410){await this.revoke(sub.owner);break;}
        else if(response.status===413||(response.status>=400&&response.status<500&&response.status!==408&&response.status!==429)){await this.status(message.id,"failed");this.ctx.storage.sql.exec("DELETE FROM pending WHERE message_id=?",message.id);}
        else await this.retry(row);
      }catch{await this.retry(row);await this.recordDeliveryAttempt({messageId:message.id,callbackHTTPStatus:null,attempts,status:attempts>=6?"failed":"retrying"});}
    }
    await this.schedule();
  }
  private async retry(row:PendingRow) {
    const attempts=row.attempts+1;
    if(attempts>=6){await this.status(row.message_id,"failed");this.ctx.storage.sql.exec("DELETE FROM pending WHERE message_id=?",row.message_id);}
    else this.ctx.storage.sql.exec("UPDATE pending SET attempts=?,next_at=? WHERE message_id=?",attempts,Date.now()+retryDelay(attempts),row.message_id);
  }
  private async purge() {
    const cutoff=Date.now()-RETENTION_MS;
    this.ctx.storage.transactionSync(()=> {
      this.ctx.storage.sql.exec("DELETE FROM pending WHERE message_id IN (SELECT id FROM messages WHERE created<=?)",cutoff);
      this.ctx.storage.sql.exec("INSERT OR IGNORE INTO tombstones SELECT id,? FROM messages WHERE created<=?",Date.now()+30*86400000,cutoff);
      this.ctx.storage.sql.exec("DELETE FROM tombstones WHERE expires<=?",Date.now());
      this.ctx.storage.sql.exec("DELETE FROM messages WHERE created<=?",cutoff);this.ctx.storage.sql.exec("DELETE FROM events WHERE created<=?",cutoff);
      this.ctx.storage.sql.exec("DELETE FROM subscription WHERE expires<=?",Date.now());
    });
  }
  private async schedule() {
    const pending=this.ctx.storage.sql.exec<{due:number|null}>("SELECT MIN(next_at) AS due FROM pending").one().due;
    const expiry=this.ctx.storage.sql.exec<{due:number|null}>("SELECT MIN(created)+? AS due FROM messages",RETENTION_MS).one().due;
    const subExpiry=this.ctx.storage.sql.exec<{due:number|null}>("SELECT MIN(expires) AS due FROM subscription").one().due;
    const tombstoneExpiry=this.ctx.storage.sql.exec<{due:number|null}>("SELECT MIN(expires) AS due FROM tombstones").one().due;
    const values=[pending,expiry,subExpiry,tombstoneExpiry].filter((value):value is number=>value!==null);
    if(values.length)await this.ctx.storage.setAlarm(Math.max(Date.now()+100,Math.min(...values)));
    else await this.ctx.storage.deleteAlarm();
  }
}
