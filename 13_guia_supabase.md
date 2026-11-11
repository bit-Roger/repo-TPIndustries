# Guia: rodar o DB_TP_INDUSTRIA no Supabase

O Supabase é um PostgreSQL na nuvem: não há nada para instalar no computador além do Python. Ao final, o banco estará criado, testado e pronto para a interface em Python/Tkinter.

Arquivos usados (pasta `db_tp_industria`):
- `10_db_tp_industria_supabase.sql`: cria o banco inteiro no schema `industria`
- `11_testes_supabase.sql`: popula dados de exemplo e roda os 16 testes
- `12_teste_conexao_supabase.py`: testa a conexão do Python com o banco

---

## Passo 1. Criar o projeto

1. Entre em https://supabase.com e crie uma conta (pode usar o GitHub ou e-mail). O plano **Free** basta.
2. Clique em **New project**:
   - **Name**: `tp-industria` (qualquer nome)
   - **Database Password**: crie uma senha e guarde. É a senha do usuário administrador `postgres`
   - **Region**: **South America (São Paulo)**
3. Clique em **Create new project** e espere uns 2 minutos até o projeto ficar pronto.

> No plano Free o projeto é **pausado depois de 7 dias sem uso**. Antes da apresentação, abra o painel e, se aparecer "Paused", clique em **Restore project**.

---

## Passo 2. Criar o banco

1. No menu da esquerda, abra o **SQL Editor** e clique em **New query** (ou no **+**).
2. Abra `10_db_tp_industria_supabase.sql` num editor de texto (Bloco de Notas, VS Code), copie **tudo** e cole no SQL Editor.
3. Clique em **Run** (ou Ctrl+Enter).
4. O Supabase avisa que o script tem uma operação destrutiva (o `DROP SCHEMA`). Clique em **Run this query**.
5. O resultado deve ser uma linha: `industria | 8 | 3 | 24 | 20` (8 tabelas, 3 triggers, 24 procedures de manutenção e 20 funções de consulta e relatório).

> O script apaga e recria o schema `industria`. Pode rodar de novo sempre que quiser voltar ao estado inicial.

## Passo 3. Rodar os testes

1. Abra uma **New query**, cole o conteúdo de `11_testes_supabase.sql` e clique em **Run**.
2. O resultado é uma tabela com **41 conferências** dos 16 testes (colunas `teste`, `conferencia`, `esperado`, `obtido`, `ok`). Todas devem estar com `ok = true`.
3. Os testes T4, T8, T9, T10 e T11 conferem códigos de erro (TP011, TP010, TP002, 23514 e 42501): eles provam que as regras bloqueiam operações proibidas.

Com isso o banco já tem dados de exemplo (2 produtos, 2 setores, 2 fornecedores, compras e requisições). Para ver um relatório inteiro, rode-o sozinho numa nova query, por exemplo:
```sql
SELECT * FROM industria.sp_Rel_ConsumoPorSetor();
SELECT * FROM industria.sp_Rel_FichaProduto(1);
```
As tabelas também aparecem no **Table Editor**, escolhendo o schema `industria` no seletor do topo.

---

## Passo 4. Criar o login da aplicação

O enunciado exige que tudo passe por procedures. Por isso a aplicação entra com um usuário do papel `rl_aplicacao`, que só pode executar as rotinas `sp_*`.

Numa **New query**, execute (troque a senha):
```sql
CREATE ROLE app_industria LOGIN PASSWORD 'TroqueEstaSenha#2026' IN ROLE rl_aplicacao;
```
Isso é feito **uma vez só**: rodar o `10` de novo não apaga o login.

> O schema `industria` não fica exposto na API automática do Supabase (Data API), e o script retira qualquer acesso dos papéis `anon`, `authenticated` e `service_role`. O único caminho para os dados é pelas procedures.

---

## Passo 5. Pegar os dados de conexão

1. No topo do painel do projeto, clique em **Connect**.
2. Escolha a opção **Session pooler** (funciona em qualquer rede; a "Direct connection" exige IPv6).
3. Anote:
   - **host**: algo como `aws-0-sa-east-1.pooler.supabase.com`
   - **port**: `5432`
   - **database**: `postgres`
   - **user**: aparece como `postgres.abcdefghijklmnopqrst`. A parte depois do ponto é o **código do projeto** (project ref). Para a aplicação, o usuário será `app_industria.abcdefghijklmnopqrst`

---

## Passo 6. Preparar o Python

1. Instale o **Python 3.12 ou mais novo** (python.org). No instalador, marque **Add python.exe to PATH**. O Tkinter já vem junto.
2. No Prompt de Comando:
   ```
   pip install "psycopg[binary]"
   ```
   (não precisa instalar driver ODBC: o psycopg já traz tudo)
3. Abra `12_teste_conexao_supabase.py` num editor e ajuste o topo com os dados do passo 5:
   - `HOST`: o host do Session pooler
   - `PROJECT_REF`: o código do projeto
   - `SENHA`: a senha do `app_industria` (passo 4)
4. Rode:
   ```
   python 12_teste_conexao_supabase.py
   ```
   Deve listar os produtos, o consumo por setor e o menor preço por fornecedor, mostrar o id devolvido por uma inclusão de teste (desfeita em seguida), confirmar que o SELECT direto na tabela foi negado e terminar com "Conexão e procedures funcionando."

---

## Como a aplicação chama o banco

| O que | Como | Exemplo em Python |
|---|---|---|
| Consultas e relatórios | `SELECT * FROM` a função | `cur.execute("SELECT * FROM industria.sp_Produto_Listar(%s)", ("chapa",))` |
| Inclusões | `CALL` a procedure, com `NULL` no lugar do id; o id volta na linha de resultado | `cur.execute("CALL industria.sp_Setor_Inserir(%s, NULL)", ("Pintura",))` e depois `cur.fetchone()[0]` |
| Alterações e exclusões | `CALL` a procedure | `cur.execute("CALL industria.sp_Setor_Excluir(%s)", (3,))` |
| Gravar | `conexao.commit()` depois das operações | |
| Erros de regra | exceção `psycopg.Error` com `e.sqlstate` (`TP001` não encontrado, `TP002` tem dependentes, `TP003` dado inválido, `TP010` estorno deixaria estoque negativo, `TP011` estoque insuficiente) e a mensagem em `e.diag.message_primary` | |

---

## Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| `password authentication failed for user "app_industria"` | Usuário sem o código do projeto ou senha errada | No pooler o usuário é `app_industria.<código do projeto>`. Confira a senha do passo 4 |
| `Tenant or user not found` | Host ou código do projeto errado | Copie de novo o host e o usuário em **Connect > Session pooler** |
| Conexão demora e dá timeout | Projeto pausado ou rede bloqueando a porta 5432 | Abra o painel e restaure o projeto. Em rede de faculdade/empresa, teste em outra rede |
| `permission denied for table ...` (42501) ao fazer `SELECT` direto com `app_industria` | Comportamento esperado | A aplicação só pode chamar as rotinas `sp_*` (requisito 4) |
| `function ... does not exist` | Faltou o schema no nome | Use `industria.sp_...` |
| `role "app_industria" already exists` | O login já foi criado antes | Nada a fazer. Para trocar a senha: `ALTER ROLE app_industria PASSWORD 'nova';` |
| Acentos trocados por símbolos no SQL Editor | Arquivo aberto com codificação errada | Os scripts estão em UTF-8; abra no VS Code ou Bloco de Notas e copie de novo |
