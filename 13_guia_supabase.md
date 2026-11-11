# Guia: rodar o DB_TP_INDUSTRIA no Supabase com a interface web

O Supabase é um PostgreSQL na nuvem. A interface é uma página em HTML, CSS e JavaScript (pasta `web`) que conversa direto com o Supabase: não há servidor nem nada para instalar, só um navegador (Chrome ou Edge).

Arquivos usados (pasta `db_tp_industria`):
- `10_db_tp_industria_supabase.sql`: cria o banco inteiro no schema `industria`
- `11_testes_supabase.sql`: popula dados de exemplo e roda os 16 testes
- `web/`: a interface (`index.html`, `css/estilo.css`, `js/*.js`)

---

## Passo 1. Criar o projeto

1. Entre em https://supabase.com e crie uma conta. O plano **Free** basta.
2. Clique em **New project**:
   - **Name**: `tp-industria` (qualquer nome)
   - **Database Password**: crie uma senha e guarde (é a do administrador do banco)
   - **Region**: **South America (São Paulo)**
3. Clique em **Create new project** e espere uns 2 minutos.

> No plano Free o projeto é **pausado depois de 7 dias sem uso**. Antes da apresentação, abra o painel e, se aparecer "Paused", clique em **Restore project**.

---

## Passo 2. Criar o banco

1. No menu da esquerda, abra o **SQL Editor** e clique em **New query**.
2. Abra `10_db_tp_industria_supabase.sql` num editor de texto (Bloco de Notas, VS Code), copie **tudo** e cole no SQL Editor.
3. Clique em **Run** (ou Ctrl+Enter). O Supabase avisa que há uma operação destrutiva (o `DROP SCHEMA`): clique em **Run this query**.
4. O resultado deve ser uma linha: `industria | 8 | 3 | 24 | 20` (8 tabelas, 3 triggers, 24 rotinas de manutenção e 20 de consulta e relatório).

> O script apaga e recria o schema `industria`. Pode rodar de novo sempre que quiser voltar ao estado inicial.

## Passo 3. Rodar os testes (opcional, mas recomendado)

1. **New query**, cole o conteúdo de `11_testes_supabase.sql` e clique em **Run**.
2. Aparece uma tabela com **41 conferências** dos 16 testes. Todas devem estar com `ok = true`.
3. Com isso o banco fica com dados de exemplo (2 produtos, 2 setores, 2 fornecedores, compras e requisições), bons para mostrar a interface.

Para repetir os testes, rode o `10` antes, para começar do banco vazio.

---

## Passo 4. Liberar o schema na API

A página chama as rotinas `sp_*` pela API do Supabase, que por padrão só enxerga o schema `public`.

1. Vá em **Project Settings > Data API** (em algumas versões do painel: **Integrations > Data API > Settings**).
2. Em **Exposed schemas**, adicione `industria` (mantenha os que já estão lá).
3. Clique em **Save**.

Isso **não** abre as tabelas: o script só dá permissão de executar as rotinas `sp_*`, e só para quem fez login. Sem login, a API responde "permission denied" para tudo.

---

## Passo 5. Criar o usuário que vai entrar no sistema

1. Vá em **Authentication > Users > Add user > Create new user**.
2. Informe e-mail e senha, marque **Auto Confirm User** e clique em **Create user**.
3. Crie um usuário para cada integrante do grupo, se quiser.
4. Recomendado: em **Authentication > Sign In / Providers**, desligue **Allow new users to sign up**. Assim ninguém cria conta sozinho; só os usuários que você cadastrou entram.

---

## Passo 6. Configurar a página

1. No painel, clique em **Connect** (no topo) e escolha **App Frameworks**, ou vá em **Project Settings > API Keys**. Copie:
   - a **Project URL** (algo como `https://abcdefghijklmnopqrst.supabase.co`)
   - a chave **publishable** (começa com `sb_publishable_`) ou, em projetos mais antigos, a **anon public**
2. Abra `web/js/config.js` num editor e cole os dois valores:
   ```js
   window.CONFIG = {
     SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co",
     SUPABASE_KEY: "sb_publishable_...",
   };
   ```
3. **Nunca** coloque ali a chave secreta (`secret` / `service_role`). A chave pública pode ficar no navegador porque, sozinha, não dá acesso a nada.

## Passo 7. Abrir o sistema

1. Dê dois cliques em `web/index.html` (abre no navegador).
2. Entre com o e-mail e a senha do passo 5.

Se a página abrir em branco ou não conectar, use a extensão **Live Server** do VS Code (botão direito no `index.html` > **Open with Live Server**). A página precisa de internet para baixar a biblioteca do Supabase.

---

## O que a interface tem

| Área | Telas | Rotinas usadas |
|---|---|---|
| Cadastros | Grupos, Produtos, Setores, Fornecedores (busca, incluir, editar, excluir) | `sp_GrupoProduto_*`, `sp_Produto_*`, `sp_Setor_*`, `sp_Fornecedor_*` |
| Movimentação | Compras e Requisições, cada uma com seus itens | `sp_Compra_*`, `sp_ItemCompra_*`, `sp_Requisicao_*`, `sp_ItemRequisicao_*` |
| Consultas | Início (resumo do mês), Estoque por grupo | `sp_Produto_Listar`, `sp_Produto_ListarPorGrupo`, `sp_Compra_Listar`, `sp_Requisicao_Listar` |
| Relatórios | Consumo por setor, Ficha do produto, Evolução do preço, Fornecedor e menor preço (com botão Imprimir) | `sp_Rel_*` |

Os erros das regras aparecem como aviso na tela: estoque insuficiente (TP011), estorno que deixaria o estoque negativo (TP010), exclusão de registro com dependentes (TP002), CNPJ inválido ou repetido.

### Como a página chama o banco

Tudo passa por `API.rpc` em `web/js/api.js`, que usa a biblioteca oficial do Supabase:
```js
// consulta: devolve as linhas
const produtos = await API.rpc("sp_produto_listar", { p_filtronome: "chapa" });
// inclusão: devolve o id gerado
const id = await API.rpc("sp_setor_inserir", { p_setor_nome: "Pintura" });
```
O PostgreSQL guarda nomes em minúsculas, por isso as rotinas e os parâmetros aparecem assim no JavaScript.

---

## Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| Página mostra "Configuração pendente" | `config.js` sem a URL ou a chave | Passo 6 |
| "E-mail ou senha incorretos." | Usuário não existe ou não foi confirmado | Passo 5, com **Auto Confirm User** marcado |
| "O schema industria não está liberado na API" | Faltou o passo 4 | Adicione `industria` em **Exposed schemas** |
| "Rotina não encontrada na API" | A API ainda não releu as rotinas | Rode o `10` de novo, espere uns segundos e recarregue a página |
| "Sem permissão para essa operação" | Sessão expirada, ou o `10` foi rodado sem o bloco de segurança | Clique em Sair e entre de novo; se continuar, rode o `10` inteiro |
| "Não foi possível falar com o Supabase" | Sem internet, URL errada ou projeto pausado | Confira o `config.js` e restaure o projeto no painel |
| Página em branco ao abrir com dois cliques | Navegador bloqueando arquivo local | Use o Live Server (passo 7) |
