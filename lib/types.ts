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
