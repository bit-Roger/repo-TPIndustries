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
  SUPABASE_URL: "https://SEU-PROJETO.supabase.co",
  SUPABASE_KEY: "COLE-AQUI-A-CHAVE-PUBLICA",
};
