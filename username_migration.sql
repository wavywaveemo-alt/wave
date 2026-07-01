-- Wave SNS — ユーザー名表示設定 マイグレーション
-- Supabase SQL Editor で実行してください

-- show_username カラムを追加（デフォルト true = 表示する）
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS show_username BOOLEAN NOT NULL DEFAULT true;

-- username が未設定のユーザーに 'Waever' をセット
UPDATE public.profiles SET username = 'Waever' WHERE username IS NULL OR username = '';

-- username の NOT NULL + DEFAULT を確保
ALTER TABLE public.profiles
  ALTER COLUMN username SET DEFAULT 'Waever';

-- 自分のプロフィールを更新できるポリシー（なければ追加）
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());
