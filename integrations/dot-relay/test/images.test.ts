import { describe,expect,it } from "vitest";
import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import type { Env,OwnerProps } from "../src/env";
import type { DotRelay } from "../src/relay";
import { contextToolResult } from "../src/images";
import { decrypt,OWNER_ID,RETENTION_MS } from "../src/security";

const owner:OwnerProps={githubId:OWNER_ID,githubToken:"test-only-upstream"};
const bindings=env as Env;
const stub=()=>bindings.RELAY.getByName(crypto.randomUUID());

// A real 2x3 JPEG, encoded as a data field in the native relay contract.
const TINY_JPEG="/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAADAAIDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDzqiiivjj+kT//2Q==";

type Attachment={id:string;mimeType:string;data:string;width:number;height:number};
const image=(overrides:Partial<Attachment>={}):Attachment=>({id:crypto.randomUUID(),mimeType:"image/jpeg",data:TINY_JPEG,width:2,height:3,...overrides});
const message=(text="fixture message",attachments?:Attachment[])=>({messageId:crypto.randomUUID(),text,...(attachments===undefined?{}:{attachments})});

async function rejectsInDO(relay:DurableObjectStub<DotRelay>,operation:(instance:DotRelay)=>Promise<unknown>){
 const rejected=await runInDurableObject(relay,async(instance:DotRelay)=>{try{await operation(instance);return false;}catch{return true;}});
 expect(rejected).toBe(true);
}

function bytesFromBase64(value:string):Uint8Array{return Uint8Array.from(atob(value),character=>character.charCodeAt(0));}
function base64FromBytes(value:Uint8Array):string{
 const chunks:string[]=[];
 for(let offset=0;offset<value.length;offset+=16384)chunks.push(String.fromCharCode(...value.subarray(offset,offset+16384)));
 return btoa(chunks.join(""));
}
function jpegOfExactLength(length:number):string{
 const source=bytesFromBase64(TINY_JPEG),remaining=length-source.length;
 const segmentCount=Math.ceil(remaining/65537),payloadBytes=remaining-segmentCount*4;
 const parts:Uint8Array[]=[source.subarray(0,2)];let payloadLeft=payloadBytes;
 for(let index=0;index<segmentCount;index++){
  const payloadLength=Math.ceil(payloadLeft/(segmentCount-index));payloadLeft-=payloadLength;
  if(payloadLength>65533)throw new Error("JPEG comment segment exceeded its format limit");
  const segment=new Uint8Array(payloadLength+4);segment[0]=0xff;segment[1]=0xfe;segment[2]=(payloadLength+2)>>8;segment[3]=(payloadLength+2)&0xff;parts.push(segment);
 }
 parts.push(source.subarray(2));
 const result=new Uint8Array(length);let offset=0;
 for(const part of parts){result.set(part,offset);offset+=part.length;}
 if(offset!==length)throw new Error("JPEG fixture length mismatch");
 return base64FromBytes(result);
}

describe("native image attachments",()=>{
 it("accepts image-only sends and deduplicates identical image payloads",async()=>{
  const relay=stub(),input=message(" \t ",[image()]);
  const first=await relay.accept(owner,input);
  expect(first.status).toBe("queued");
  expect(await relay.accept(owner,input)).toEqual(first);
  const changed=bytesFromBase64(input.attachments![0].data);changed[13]^=1;
  await rejectsInDO(relay,instance=>instance.accept(owner,{...input,attachments:[{...input.attachments![0],data:base64FromBytes(changed)}]}));
  await expect(relay.accept(owner,message("",[image()]))).resolves.toMatchObject({status:"queued"});
 });

 it("preserves text-only IDs and optional attachments for legacy callers",async()=>{
  const relay=stub(),input=message("legacy fixture");
  const first=await relay.accept(owner,input);
  expect(await relay.accept(owner,{...input,attachments:[]})).toEqual(first);
 });

 it("rejects invalid JPEG metadata and unrecognized fields",async()=>{
  const relay=stub(),valid=image();
  const invalidInputs:Record<string,unknown>[]=[
   message("caption",[({...valid,width:3})]),
   message("caption",[({...valid,height:0})]),
   message("caption",[({...valid,width:1601})]),
   message("caption",[({...valid,mimeType:"image/png"})]),
   message("caption",[({...valid,data:"not base64!"})]),
   message("caption",[({...valid,data:btoa("not a JPEG")})]),
   message("caption",[({...valid,extra:"unexpected"} as Attachment & {extra:string})]),
   message("caption",[{...valid,id:"not-a-uuid"}]),
   {messageId:crypto.randomUUID(),text:"caption",attachments:[valid],unexpected:true},
   {messageId:crypto.randomUUID(),text:"   ",attachments:[]},
   {messageId:crypto.randomUUID(),text:"   "},
  ];
  for(const input of invalidInputs)await rejectsInDO(relay,instance=>instance.accept(owner,input));
  const duplicateId=crypto.randomUUID();
  await rejectsInDO(relay,instance=>instance.accept(owner,message("caption",[image({id:duplicateId}),image({id:duplicateId})])));
  await rejectsInDO(relay,instance=>instance.accept(owner,message("caption",Array.from({length:5},()=>image()))));
  await rejectsInDO(relay,instance=>instance.accept(owner,message("caption",[image({data:jpegOfExactLength(262145)})])));
 });

 it("stores image payloads encrypted and supports four maximum-sized JPEGs without stack-sized conversions",async()=>{
  const relay=stub(),data=jpegOfExactLength(262144),attachments=Array.from({length:4},()=>image({data}));
  expect(bytesFromBase64(data)).toHaveLength(262144);
  const input=message("large fixture",attachments);
  await expect(relay.accept(owner,input)).resolves.toMatchObject({status:"queued"});
  const stored=await runInDurableObject(relay,async(_instance:DotRelay,state)=>{
   const cipher=state.storage.sql.exec<{cipher:string}>("SELECT cipher FROM messages WHERE id=?",input.messageId).one().cipher;
   return {cipher,payload:await decrypt<{text:string;attachments:Attachment[]}>(cipher,bindings.RELAY_ENCRYPTION_KEY,`message:${input.messageId}`)};
  });
  expect(stored.cipher).not.toContain(data);
  expect(stored.payload.attachments.map(item=>item.data)).toEqual([data,data,data,data]);
  const publicState=JSON.stringify({events:await relay.events(owner,0),readiness:await relay.readiness(owner)});
  expect(publicState).not.toContain(data);
 });

 it("keeps legacy ciphertext readable and deletes expired image payloads",async()=>{
  const relay=stub(),legacy=message("old encrypted fixture"),imageInput=message("image fixture",[image()]);
  await relay.accept(owner,legacy);await relay.accept(owner,imageInput);
  const legacyPayload=await runInDurableObject(relay,async(_instance:DotRelay,state)=>{
   const cipher=state.storage.sql.exec<{cipher:string}>("SELECT cipher FROM messages WHERE id=?",legacy.messageId).one().cipher;
   return decrypt<{text:string;attachments?:Attachment[]}>(cipher,bindings.RELAY_ENCRYPTION_KEY,`message:${legacy.messageId}`);
  });
  expect(legacyPayload).toEqual({text:legacy.text});
  await runInDurableObject(relay,async(_instance:DotRelay,state)=>{
   const expiredAt=Date.now()-RETENTION_MS-1;
   state.storage.sql.exec("UPDATE messages SET created=? WHERE id=?",expiredAt,imageInput.messageId);
   state.storage.sql.exec("UPDATE events SET created=? WHERE message_id=?",expiredAt,imageInput.messageId);
  });
  await relay.events(owner,0);
  const remaining=await runInDurableObject(relay,async(_instance:DotRelay,state)=>state.storage.sql.exec<{count:number}>("SELECT COUNT(*) AS count FROM messages WHERE id=?",imageInput.messageId).one().count);
  expect(remaining).toBe(0);
  await rejectsInDO(relay,instance=>instance.context(owner,{messageId:imageInput.messageId}));
 });

 it("enforces owner boundaries for image acceptance and context",async()=>{
  const relay=stub(),other={...owner,githubId:"1"},input=message("private image",[image()]);
  await rejectsInDO(relay,instance=>instance.accept(other,input));
  await relay.accept(owner,input);
  await rejectsInDO(relay,instance=>instance.context(other,{messageId:input.messageId}));
 });

 it("returns target image bytes while earlier context messages expose metadata only",async()=>{
  const relay=stub(),earlier=message("earlier image",[image()]),target=message("target image",[image()]);
  await relay.accept(owner,earlier);await relay.accept(owner,target);
  await runInDurableObject(relay,async(_instance:DotRelay,state)=>state.storage.sql.exec("UPDATE messages SET created=? WHERE id=?",Date.now()-1000,earlier.messageId));
  const context=await runInDurableObject(relay,instance=>instance.context(owner,{messageId:target.messageId}));
  expect(context.conversationId).toBe("notch");
  expect(context.originatingMessageId).toBe(target.messageId);
  expect(context.images.map(item=>item.id)).toEqual([target.attachments![0].id]);
  expect(context.messages.map(item=>item.messageId)).toContain(earlier.messageId);
  const prior=context.messages.find(item=>item.messageId===earlier.messageId)!;
  expect(prior.attachments).toEqual([{id:earlier.attachments![0].id,mimeType:"image/jpeg",width:2,height:3}]);
  expect(JSON.stringify(prior)).not.toContain(earlier.attachments![0].data);
  const result=contextToolResult(context);
  expect(result.isError).toBe(false);
  expect(JSON.stringify(result.structuredContent)).not.toContain(target.attachments![0].data);
  expect(JSON.stringify(result.content.filter(item=>item.type==="text"))).not.toContain(target.attachments![0].data);
  expect(result.content.at(-1)).toMatchObject({type:"image",mimeType:"image/jpeg",data:target.attachments![0].data});
 });
});
