-- Wave SNS — 個人ボード対応マイグレーション
-- Supabase SQL Editor で実行してください

ALTER TABLE public.boards
  ADD COLUMN IF NOT EXISTS board_type TEXT NOT NULL DEFAULT 'personal'
  CHECK (board_type IN ('personal', 'public'));
