export type CheckResult = "ok" | "warning" | "unregistered";

export interface Product {
  id: string;
  name: string;
  aliases: string[];
  normal_price: number;
  warning_price: number;
  memo: string;
  created_at: string;
  updated_at: string;
}

export interface PriceCheck {
  id: string;
  product_id: string | null;
  input_name: string;
  input_price: number;
  normal_price_at_check: number | null;
  warning_price_at_check: number | null;
  result: CheckResult;
  staff_name: string;
  note: string;
  created_at: string;
}

export interface Settings {
  id: string;
  manager_pin: string;
}

export interface Receipt {
  id: string;
  /** base64 JPEG データ（Supabase移行後はStorage URL） */
  image_data: string | null;
  supplier_name: string;
  purchased_at: string; // YYYY-MM-DD
  created_by: string;
  created_at: string;
}

export interface ReceiptItem {
  id: string;
  receipt_id: string;
  product_name: string;
  unit_price: number;
  quantity: number;
  memo: string;
}
