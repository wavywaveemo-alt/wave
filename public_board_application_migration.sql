-- Wave SNS — 公開ボード申請フロー マイグレーション
-- Supabase SQL Editor で実行してください

-- ─────────────────────────────────────────────
-- 1. boards に board_status カラムを追加
-- ─────────────────────────────────────────────
ALTER TABLE public.boards
  ADD COLUMN IF NOT EXISTS board_status TEXT NOT NULL DEFAULT 'active'
  CHECK (board_status IN ('active', 'pending', 'rejected'));

-- 既存の public ボードは active に設定済み（DEFAULT で OK）

-- ─────────────────────────────────────────────
-- 2. board_requests テーブル（なければ作成）
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.board_requests (
  id            BIGSERIAL PRIMARY KEY,
  board_id      UUID        NOT NULL REFERENCES public.boards(id) ON DELETE CASCADE,
  board_name    TEXT        NOT NULL,
  requester_id  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason        TEXT,
  status        TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reject_reason TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at   TIMESTAMPTZ
);

-- RLS 有効化
ALTER TABLE public.board_requests ENABLE ROW LEVEL SECURITY;

-- ユーザーは自分の申請を閲覧できる
DROP POLICY IF EXISTS "board_requests_select_own" ON public.board_requests;
CREATE POLICY "board_requests_select_own" ON public.board_requests
  FOR SELECT USING (requester_id = auth.uid());

-- ユーザーは自分の申請を INSERT できる
DROP POLICY IF EXISTS "board_requests_insert_own" ON public.board_requests;
CREATE POLICY "board_requests_insert_own" ON public.board_requests
  FOR INSERT WITH CHECK (requester_id = auth.uid());

-- ─────────────────────────────────────────────
-- 3. boards SELECT RLS を更新
--    pending/rejected の公開ボードは本人のみ見える
-- ─────────────────────────────────────────────
DROP POLICY IF EXISTS "boards_select" ON public.boards;

CREATE POLICY "boards_select" ON public.boards
  FOR SELECT USING (
    -- 非公開ボードは本人のみ
    (board_type = 'private' AND user_id = auth.uid())
    OR
    -- 申請中・却下ボードは本人のみ
    (board_status != 'active' AND user_id = auth.uid())
    OR
    -- 公開・個人 かつ active → 誰でも見える
    (board_type != 'private' AND board_status = 'active')
  );

-- ─────────────────────────────────────────────
-- 4. approve_board_request RPC
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.approve_board_request(p_request_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_board_id UUID;
BEGIN
  -- 申請を承認済みに更新
  UPDATE public.board_requests
     SET status = 'approved', reviewed_at = NOW()
   WHERE id = p_request_id AND status = 'pending'
  RETURNING board_id INTO v_board_id;

  IF v_board_id IS NULL THEN
    RAISE EXCEPTION '申請が見つからないか、すでに処理済みです';
  END IF;

  -- ボードを active に更新
  UPDATE public.boards
     SET board_status = 'active'
   WHERE id = v_board_id;
END;
$$;

-- ─────────────────────────────────────────────
-- 5. reject_board_request RPC
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_board_request(p_request_id BIGINT, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_board_id UUID;
BEGIN
  -- 申請を却下済みに更新
  UPDATE public.board_requests
     SET status = 'rejected', reject_reason = p_reason, reviewed_at = NOW()
   WHERE id = p_request_id AND status = 'pending'
  RETURNING board_id INTO v_board_id;

  IF v_board_id IS NULL THEN
    RAISE EXCEPTION '申請が見つからないか、すでに処理済みです';
  END IF;

  -- ボードを rejected + 個人ボードに変更（非公開扱い）
  UPDATE public.boards
     SET board_status = 'rejected',
         board_type   = 'personal'
   WHERE id = v_board_id;
END;
$$;

-- ─────────────────────────────────────────────
-- 6. 管理者用ビュー（board_requests + プロフィール）
--    wave-admin が使う reports_with_reporter と同様の構造
-- ─────────────────────────────────────────────
DROP VIEW IF EXISTS public.board_requests_with_requester;

CREATE VIEW public.board_requests_with_requester AS
SELECT
  br.id,
  br.board_id,
  br.board_name,
  br.reason,
  br.status,
  br.reject_reason,
  br.created_at,
  br.reviewed_at,
  p.id       AS requester_id,
  p.username AS requester_username
FROM public.board_requests br
LEFT JOIN public.profiles p ON p.id = br.requester_id;
