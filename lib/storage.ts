"use client";

import type { Product, PriceCheck, Settings } from "./types";
import { INITIAL_PRODUCTS, DEFAULT_SETTINGS, STORAGE_KEYS } from "./constants";

function loadJson<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

function saveJson<T>(key: string, value: T): void {
  if (typeof window === "undefined") return;
  localStorage.setItem(key, JSON.stringify(value));
}

// ---------- Products ----------

export function getProducts(): Product[] {
  const stored = loadJson<Product[] | null>(STORAGE_KEYS.PRODUCTS, null);
  if (stored === null) {
    saveJson(STORAGE_KEYS.PRODUCTS, INITIAL_PRODUCTS);
    return INITIAL_PRODUCTS;
  }
  return stored;
}

export function saveProducts(products: Product[]): void {
  saveJson(STORAGE_KEYS.PRODUCTS, products);
}

export function addProduct(product: Omit<Product, "id" | "created_at" | "updated_at">): Product {
  const products = getProducts();
  const newProduct: Product = {
    ...product,
    id: crypto.randomUUID(),
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  saveProducts([...products, newProduct]);
  return newProduct;
}

export function updateProduct(id: string, data: Partial<Omit<Product, "id" | "created_at">>): void {
  const products = getProducts().map((p) =>
    p.id === id ? { ...p, ...data, updated_at: new Date().toISOString() } : p
  );
  saveProducts(products);
}

export function deleteProduct(id: string): void {
  saveProducts(getProducts().filter((p) => p.id !== id));
}

// ---------- PriceChecks ----------

export function getPriceChecks(): PriceCheck[] {
  return loadJson<PriceCheck[]>(STORAGE_KEYS.PRICE_CHECKS, []);
}

export function addPriceCheck(check: Omit<PriceCheck, "id" | "created_at">): PriceCheck {
  const checks = getPriceChecks();
  const newCheck: PriceCheck = {
    ...check,
    id: crypto.randomUUID(),
    created_at: new Date().toISOString(),
  };
  // 最新1000件のみ保持
  const updated = [newCheck, ...checks].slice(0, 1000);
  saveJson(STORAGE_KEYS.PRICE_CHECKS, updated);
  return newCheck;
}

// ---------- Settings ----------

export function getSettings(): Settings {
  return loadJson<Settings>(STORAGE_KEYS.SETTINGS, DEFAULT_SETTINGS);
}

export function saveSettings(settings: Settings): void {
  saveJson(STORAGE_KEYS.SETTINGS, settings);
}

// ---------- Staff name ----------

export function getStaffName(): string {
  if (typeof window === "undefined") return "";
  return localStorage.getItem(STORAGE_KEYS.STAFF_NAME) ?? "";
}

export function saveStaffName(name: string): void {
  if (typeof window === "undefined") return;
  localStorage.setItem(STORAGE_KEYS.STAFF_NAME, name);
}
