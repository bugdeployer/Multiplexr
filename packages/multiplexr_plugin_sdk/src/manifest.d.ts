import type { Manifest, SettingField, Scope, Json } from './index.js';
export function validateManifest(value: unknown): Manifest;
export function validateField(field: SettingField, owner: string, sectionScopes: Scope['scope'][]): void;
export function validateSettingValue(field: SettingField, value: Json): void;
