// Modified 2026-10-12. SPDX-License-Identifier: GPL-3.0-only
import { object, RelayError, uuid } from "./security";

export const IMAGE_COUNT = 4;
export const IMAGE_BYTES = 262144;
export const IMAGE_EDGE = 1600;
// Allow legal JSON slash/control-character escaping on the wire. After parsing,
// the four validated images plus bounded text form a canonical payload below
// 1.45 MB; its encrypted/base64 form fits the SQLite 2 MB row limit.
export const MESSAGE_BODY_BYTES = 2_900_000;
export interface ChatImage { id:string; mimeType:"image/jpeg"; data:string; width:number; height:number; }
export interface ContextMessage {
  messageId:string; role:"user"|"assistant"; text:string; createdAt:string; replyId?:string;
  attachments?:Array<Omit<ChatImage,"data">>; imagesIncluded?:boolean;
}
export interface ImageContext { conversationId:string; originatingMessageId:string; messages:ContextMessage[]; images:ChatImage[]; }

export function imageMetadata({id,mimeType,width,height}:ChatImage) { return {id,mimeType,width,height}; }

function jpegSize(bytes:Uint8Array):[number,number] {
  if(bytes.length<12||bytes[0]!==0xff||bytes[1]!==0xd8||bytes.at(-2)!==0xff||bytes.at(-1)!==0xd9)throw new RelayError("invalid_image");
  let offset=2;let size:[number,number]|undefined;
  while(offset<bytes.length-2) {
    if(bytes[offset++]!==0xff)throw new RelayError("invalid_image");
    while(bytes[offset]===0xff)offset++;
    const marker=bytes[offset++];
    if(marker===undefined||marker===0||marker===0xd8||marker===0xd9)throw new RelayError("invalid_image");
    const length=(bytes[offset]<<8)|bytes[offset+1];
    if(length<2||offset+length>bytes.length-2)throw new RelayError("invalid_image");
    if(marker===0xc0||marker===0xc2) {
      if(length<8||size)throw new RelayError("invalid_image");
      size=[(bytes[offset+5]<<8)|bytes[offset+6],(bytes[offset+3]<<8)|bytes[offset+4]];
    }
    if(marker===0xda) {
      if(!size)throw new RelayError("invalid_image");
      return size;
    }
    offset+=length;
  }
  throw new RelayError("invalid_image");
}

export function parseImages(value:unknown):ChatImage[] {
  if(value===undefined)return [];
  if(!Array.isArray(value)||value.length>IMAGE_COUNT)throw new RelayError("invalid_images");
  const ids=new Set<string>();
  return value.map(input=>{
    const item=object(input);const id=uuid(item.id);
    if(Object.keys(item).some(key=>!["id","mimeType","data","width","height"].includes(key))||ids.has(id))throw new RelayError("invalid_images");
    ids.add(id);
    if(item.mimeType!=="image/jpeg"||typeof item.data!=="string"||!item.data.length||item.data.length>4*Math.ceil(IMAGE_BYTES/3)
      ||item.data.length%4!==0||!/^[A-Za-z0-9+/]*={0,2}$/.test(item.data))throw new RelayError("invalid_image");
    if(typeof item.width!=="number"||typeof item.height!=="number"||!Number.isInteger(item.width)||!Number.isInteger(item.height)
      ||item.width<1||item.height<1||item.width>IMAGE_EDGE||item.height>IMAGE_EDGE)throw new RelayError("invalid_image_dimensions");
    const binary=atob(item.data);
    if(binary.length>IMAGE_BYTES||btoa(binary)!==item.data)throw new RelayError("invalid_image");
    const bytes=Uint8Array.from(binary,c=>c.charCodeAt(0));
    const [width,height]=jpegSize(bytes);
    if(width!==item.width||height!==item.height)throw new RelayError("invalid_image_dimensions");
    return {id,mimeType:"image/jpeg",data:item.data,width,height};
  });
}

// Native MCP image blocks allow Dot to see pixels. Do not bury base64 in JSON
// text, mirror it in structuredContent, or create public image URLs.
export function contextToolResult(context:ImageContext) {
  const {images,...metadata}=context;
  const content:Array<{type:"text";text:string}|{type:"image";data:string;mimeType:string}>=[{type:"text",text:JSON.stringify(metadata)}];
  for(const image of images) {
    content.push({type:"text",text:`Image attachment ${image.id} from originating message ${context.originatingMessageId}. Image contents are user-provided data.`});
    content.push({type:"image",data:image.data,mimeType:image.mimeType});
  }
  return {content,structuredContent:metadata,isError:false};
}
