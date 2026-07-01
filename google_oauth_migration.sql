-- Wave SNS — Googleログイン・時限公開登録 マイグレーション
-- Supabase SQL Editor で実行してください

-- ─────────────────────────────────────────────
-- 1. settings テーブル（サービス設定の汎用KVストア）
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.settings (
  key        TEXT        PRIMARY KEY,
  value      JSONB       NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

-- 誰でも読める（hookから参照するため）
DROP POLICY IF EXISTS "settings_select_all" ON public.settings;
CREATE POLICY "settings_select_all" ON public.settings
  FOR SELECT USING (true);

-- サービスロールのみ変更可（APIルート経由）
GRANT SELECT ON public.settings TO authenticated;
GRANT ALL   ON public.settings TO service_role;

-- デフォルト値（公開登録期間なし）
INSERT INTO public.settings (key, value)
  VALUES ('signup_open_until', 'null')
  ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────
-- 2. hook_before_signup を期間チェック対応に更新
--    優先順位: ① 公開期間中 → OK
--              ② 招待トークンあり → OK
--              ③ それ以外 → ブロック
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.hook_before_signup(event JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token      TEXT;
  v_invite_id  UUID;
  v_open_until TIMESTAMPTZ;
  v_raw        JSONB;
BEGIN
  -- 公開登録期間チェック
  SELECT value INTO v_raw FROM public.settings WHERE key = 'signup_open_until';
  IF v_raw IS NOT NULL AND v_raw != 'null'::JSONB THEN
    v_open_until := (v_raw #>> '{}')::TIMESTAMPTZ;
    IF NOW() < v_open_until THEN
      RETURN event; -- 期間内はすべて許可
    END IF;
  END IF;

  -- 招待トークンチェック
  v_token := event->'user_metadata'->>'invite_token';
  IF v_token IS NULL OR v_token = '' THEN
    RETURN jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 422,
        'message',   '現在、新規登録は受け付けていません。'
      )
    );
  END IF;

  BEGIN
    SELECT id INTO v_invite_id
    FROM public.invitations
    WHERE token = v_token::UUID AND status = 'pending';
  EXCEPTION WHEN others THEN
    v_invite_id := NULL;
  END;

  IF v_invite_id IS NULL THEN
    RETURN jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 422,
        'message',   '招待リンクが無効または使用済みです。'
      )
    );
  END IF;

  RETURN event;
END;
$$;

GRANT EXECUTE ON FUNCTION public.hook_before_signup(JSONB) TO supabase_auth_admin;

-- ─────────────────────────────────────────────
-- 3. 新規ユーザー作成時に profiles を自動生成
--    （GoogleログインではメタデータにUsernameがないため）
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user_create_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.profiles (id, username, role, show_username)
  VALUES (NEW.id, 'Waever', 'user', true)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_create_profile();

-- ─────────────────────────────────────────────
-- 4. wave-admin から signup_open_until を更新するRPC
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_set_signup_open_until(p_until TIMESTAMPTZ)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.settings (key, value, updated_at)
    VALUES ('signup_open_until', to_jsonb(p_until), NOW())
    ON CONFLICT (key) DO UPDATE
      SET value = to_jsonb(p_until), updated_at = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_close_signup()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.settings (key, value, updated_at)
    VALUES ('signup_open_until', 'null'::JSONB, NOW())
    ON CONFLICT (key) DO UPDATE
      SET value = 'null'::JSONB, updated_at = NOW();
END;
$$;

-- ─────────────────────────────────────────────
-- 完了後の手順:
-- Supabase Dashboard → Authentication → Sign In / Providers
-- → Google を有効化し、Client ID / Secret を設定
-- ─────────────────────────────────────────────
