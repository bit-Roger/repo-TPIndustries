/*
 * Dados do projeto no Supabase (guia 13_guia_supabase.md, passo 6).
 * Painel do Supabase > botão "Connect" > "App Frameworks", ou
 * Project Settings > API Keys.
 *
 * A chave aqui é a PÚBLICA (anon / publishable). Ela pode ficar no
 * navegador: sozinha não dá acesso a nada, porque o banco só libera as
 * rotinas sp_* para quem fez login. Nunca use a chave secreta
 * (service_role / secret) neste arquivo.
 */
window.CONFIG = {
  NEXT_PUBLIC_SUPABASE_URL: "https://cxfrkoiylnbgpjtjlgdu.supabase.co",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_XRy-ASH14AoWeBpAMQSGPg_JdzFB1rL"
};
