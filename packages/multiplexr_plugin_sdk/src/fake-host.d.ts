import type { Manifest, Title, HostMethods, Response } from './index.js';
export class FakeHost {
  constructor(manifest: Manifest, options?: { collections?: string[]; inputs?: Record<string,{text:string;mime:string}>; titles?: Title[]; offeredCapabilities?: string[] });
  disable(): void;
  call<M extends keyof HostMethods>(method: M, params?: HostMethods[M]['params']): HostMethods[M]['result'];
  transport(text: string): string;
}
