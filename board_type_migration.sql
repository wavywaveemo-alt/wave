-- Wave SNS — 3種ボード対応マイグレーション
-- Supabase SQL Editor で実行してください

-- 1. CHECK制約に 'private' を追加
ALTER TABLE public.boards
  DROP CONSTRAINT IF EXISTS boards_board_type_check;

ALTER TABLE public.boards
  ADD CONSTRAINT boards_board_type_check
  CHECK (board_type IN ('public', 'personal', 'private'));

-- 2. 既存の 'personal' を 'public' に変換（旧デフォルト値を修正）
--    ※必要に応じてコメントアウト。既存ボードをそのまま残す場合は実行不要。
-- UPDATE public.boards SET board_type = 'public' WHERE board_type = 'personal';

-- 3. SELECT RLSポリシーを更新：非公開ボードは本人のみ閲覧可
DROP POLICY IF EXISTS "boards_select" ON public.boards;

CREATE POLICY "boards_select" ON public.boards
  FOR SELECT USING (
    board_type != 'private'
    OR user_id = auth.uid()
  );

-- ※ INSERT / UPDATE / DELETE ポリシーは既存のものを維持
