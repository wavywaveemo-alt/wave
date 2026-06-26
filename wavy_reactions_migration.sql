-- Wave SNS — Wavy反応システム マイグレーション
-- Supabase SQL Editor で実行してください

-- ─────────────────────────────────────────────
-- 1. reactions テーブル
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.reactions (
  id          BIGSERIAL   PRIMARY KEY,
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target_type TEXT        NOT NULL CHECK (target_type IN ('image', 'pin')),
  target_id   BIGINT      NOT NULL,
  reaction    TEXT        NOT NULL CHECK (reaction IN ('surge', 'ripple', 'vortex', 'lightning', 'bubble')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, target_type, target_id, reaction)
);

ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;

-- 全員が閲覧できる
DROP POLICY IF EXISTS "reactions_select_all" ON public.reactions;
CREATE POLICY "reactions_select_all" ON public.reactions
  FOR SELECT USING (true);

-- 自分の反応を追加できる
DROP POLICY IF EXISTS "reactions_insert_own" ON public.reactions;
CREATE POLICY "reactions_insert_own" ON public.reactions
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- 自分の反応を削除できる
DROP POLICY IF EXISTS "reactions_delete_own" ON public.reactions;
CREATE POLICY "reactions_delete_own" ON public.reactions
  FOR DELETE USING (user_id = auth.uid());

-- GRANT
GRANT SELECT, INSERT, DELETE ON public.reactions TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.reactions_id_seq TO authenticated;
