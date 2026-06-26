-- Wave SNS — ボード件数制限・申請スパム防止 マイグレーション
-- Supabase SQL Editor で実行してください

-- ─────────────────────────────────────────────
-- 1. ボード件数制限トリガー（DB安全網）
--    個人ボード: 3件まで / 非公開ボード: 3件まで
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_board_limits()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INT;
  v_limit INT := 3;
BEGIN
  IF NEW.board_type IN ('personal', 'private') THEN
    SELECT COUNT(*) INTO v_count
    FROM public.boards
    WHERE user_id = NEW.user_id
      AND board_type = NEW.board_type;

    IF v_count >= v_limit THEN
      RAISE EXCEPTION '%ボードは%件までです',
        CASE NEW.board_type WHEN 'personal' THEN '個人' ELSE '非公開' END,
        v_limit;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS boards_check_limits ON public.boards;
CREATE TRIGGER boards_check_limits
  BEFORE INSERT ON public.boards
  FOR EACH ROW EXECUTE FUNCTION public.check_board_limits();

-- ─────────────────────────────────────────────
-- 2. 申請スパム防止: pending中の申請があれば新規申請をブロック
--    （公開ボード新規作成 & 既存ボードの申請、両方に効く）
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_pending_application()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_pending_count INT;
BEGIN
  SELECT COUNT(*) INTO v_pending_count
  FROM public.board_requests
  WHERE requester_id = NEW.requester_id
    AND status = 'pending'
    AND board_id != COALESCE(NEW.board_id, -1);  -- 同一ボードの再申請（upsert）は除外

  IF v_pending_count > 0 THEN
    RAISE EXCEPTION '審査中の申請があります。承認または却下されるまでお待ちください。';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS board_requests_check_pending ON public.board_requests;
CREATE TRIGGER board_requests_check_pending
  BEFORE INSERT ON public.board_requests
  FOR EACH ROW EXECUTE FUNCTION public.check_pending_application();
