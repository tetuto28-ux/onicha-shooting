-- 仕入れ価格チェックアプリ Supabase スキーマ
-- Supabase の SQL Editor で実行してください

-- 商品テーブル
create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  aliases text[] not null default '{}',
  normal_price integer not null,
  warning_price integer not null,
  memo text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 価格チェック履歴テーブル
create table if not exists price_checks (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references products(id) on delete set null,
  input_name text not null,
  input_price integer not null,
  normal_price_at_check integer,
  warning_price_at_check integer,
  result text not null check (result in ('ok', 'warning', 'unregistered')),
  staff_name text not null,
  note text not null default '',
  created_at timestamptz not null default now()
);

-- 設定テーブル
create table if not exists settings (
  id uuid primary key default gen_random_uuid(),
  manager_pin text not null default '1234'
);

-- updated_at を自動更新するトリガー
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger products_updated_at
  before update on products
  for each row execute function update_updated_at();

-- サンプルデータ
insert into products (name, aliases, normal_price, warning_price, memo)
values (
  '筍',
  array['たけのこ', '竹の子', 'タケノコ'],
  300,
  450,
  '450円を超えたら店長確認'
);

-- デフォルト設定
insert into settings (manager_pin) values ('1234');

-- レシートテーブル
-- image_url: Supabase Storage の公開 URL を格納する
-- （localStorage 版では base64 を image_data カラムに持つが、
--   Supabase 移行時は Storage にアップロードして URL を保存する）
create table if not exists receipts (
  id uuid primary key default gen_random_uuid(),
  image_url text,                      -- Supabase Storage URL
  supplier_name text not null default '',
  purchased_at date not null,
  created_by text not null,
  created_at timestamptz not null default now()
);

-- レシート明細テーブル
create table if not exists receipt_items (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references receipts(id) on delete cascade,
  product_name text not null,
  unit_price integer not null,
  quantity integer not null default 1,
  memo text not null default ''
);

-- インデックス
create index if not exists receipt_items_receipt_id_idx on receipt_items(receipt_id);
create index if not exists receipts_purchased_at_idx on receipts(purchased_at desc);

-- Supabase Storage バケット作成（Storage タブで手動作成 or 以下の SQL）
-- insert into storage.buckets (id, name, public) values ('receipts', 'receipts', false);

-- RLS（Row Level Security）設定例
-- 本番環境では適切なポリシーを設定してください
alter table products enable row level security;
alter table price_checks enable row level security;
alter table settings enable row level security;
alter table receipts enable row level security;
alter table receipt_items enable row level security;

-- 匿名ユーザーに読み取りを許可（MVP用）
create policy "allow_read_products" on products for select using (true);
create policy "allow_all_products" on products for all using (true);
create policy "allow_all_price_checks" on price_checks for all using (true);
create policy "allow_read_settings" on settings for select using (true);
create policy "allow_all_receipts" on receipts for all using (true);
create policy "allow_all_receipt_items" on receipt_items for all using (true);
