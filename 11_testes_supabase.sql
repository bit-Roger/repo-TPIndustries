/* =====================================================================
   DB_TP_INDUSTRIA - Roteiro de testes (PostgreSQL / Supabase)
   Executar DEPOIS de 10_db_tp_industria_supabase.sql (rode o 10 de novo
   antes de repetir os testes, para começar do banco vazio).

   Mesmos 16 testes do 02_testes.sql (versão SQL Server).
   O SQL Editor do Supabase mostra só o resultado do último comando, por
   isso cada teste grava suas conferências numa tabela temporária e o
   script termina com um SELECT dela:
       teste | conferência | esperado | obtido | ok
   Todas as linhas devem vir com ok = true.

   Os testes usam só as procedures (CALL) e funções (SELECT * FROM sp_...);
   as tabelas são lidas diretamente apenas para conferir o resultado.
   ===================================================================== */
SET search_path = industria, public;

DROP TABLE IF EXISTS resultado_testes;   -- a temporária da sessão, se já existir
CREATE TEMP TABLE resultado_testes (
    ordem       INT GENERATED ALWAYS AS IDENTITY,
    teste       VARCHAR(5),
    conferencia VARCHAR(120),
    esperado    TEXT,
    obtido      TEXT,
    ok          BOOLEAN GENERATED ALWAYS AS (esperado IS NOT DISTINCT FROM obtido) STORED
);

-- Registra uma conferência
CREATE OR REPLACE FUNCTION pg_temp.conferir(p_teste TEXT, p_conf TEXT, p_esperado ANYELEMENT, p_obtido ANYELEMENT)
RETURNS VOID LANGUAGE sql AS $$
    INSERT INTO resultado_testes (teste, conferencia, esperado, obtido)
    VALUES (p_teste, p_conf, p_esperado::TEXT, p_obtido::TEXT);
$$;

-- Executa um comando que DEVE falhar e devolve o SQLSTATE do erro
CREATE OR REPLACE FUNCTION pg_temp.erro_de(p_comando TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_comando;
    RETURN 'nenhum erro';
EXCEPTION WHEN OTHERS THEN
    RETURN SQLSTATE;
END;
$$;

/* ---------- Cadastros básicos + Testes 1 a 3 ---------- */
DO $$
DECLARE
    g BIGINT; p1 BIGINT; p2 BIGINT; s BIGINT; f BIGINT;
    c1 BIGINT; c2 BIGINT; i BIGINT; r BIGINT; ir BIGINT;
    v RECORD;
BEGIN
    CALL sp_GrupoProduto_Inserir('Matéria-prima', g);
    CALL sp_Produto_Inserir(g, 'Chapa de aço 2mm', p1);
    CALL sp_Produto_Inserir(g, 'Parafuso M8', p2);
    CALL sp_Setor_Inserir('Produção', s);
    CALL sp_Fornecedor_Inserir('Aços Brasil Ltda', '12.345.678/0001-90', f);

    /* Teste 1: primeira compra. Chapa 10 x 5,00 | Parafuso 100 x 0,50 */
    CALL sp_Compra_Inserir(f, '2026-09-01', c1);
    CALL sp_ItemCompra_Inserir(c1, p1, 10, 5.00, i);
    CALL sp_ItemCompra_Inserir(c1, p2, 100, 0.50, i);

    SELECT * INTO v FROM sp_Produto_Buscar(p2);
    PERFORM pg_temp.conferir('T1', 'parafuso: estoque', 100.000, v.prod_qtdEstoque);
    PERFORM pg_temp.conferir('T1', 'parafuso: preço médio', 0.50, v.prod_precoMedio);
    PERFORM pg_temp.conferir('T1', 'compra 1: valor total', 100.00,
                             (SELECT compra_valorTotal FROM sp_Compra_Buscar(c1)));

    /* Teste 2: segunda compra. Chapa 10 x 7,00 -> PM (10*5 + 10*7)/20 = 6,00 */
    CALL sp_Compra_Inserir(f, '2026-09-10', c2);
    CALL sp_ItemCompra_Inserir(c2, p1, 10, 7.00, i);

    SELECT * INTO v FROM sp_Produto_Buscar(p1);
    PERFORM pg_temp.conferir('T2', 'chapa: estoque', 20.000, v.prod_qtdEstoque);
    PERFORM pg_temp.conferir('T2', 'chapa: preço médio', 6.00, v.prod_precoMedio);
    PERFORM pg_temp.conferir('T2', 'chapa: última compra (qtd x valor)', '10.000 x 7.00',
                             v.prod_qtdUltCompra || ' x ' || v.prod_valorUltCompra);
    PERFORM pg_temp.conferir('T2', 'compra 2: valor total', 70.00,
                             (SELECT compra_valorTotal FROM sp_Compra_Buscar(c2)));

    /* Teste 3: requisição de 5 chapas, valorizadas pelo PM 6,00 */
    CALL sp_Requisicao_Inserir(s, NULL, r);
    CALL sp_ItemRequisicao_Inserir(r, p1, 5, ir);

    SELECT * INTO v FROM sp_Produto_Buscar(p1);
    PERFORM pg_temp.conferir('T3', 'chapa: estoque', 15.000, v.prod_qtdEstoque);
    PERFORM pg_temp.conferir('T3', 'chapa: preço médio não muda', 6.00, v.prod_precoMedio);
    PERFORM pg_temp.conferir('T3', 'item: valor unitário = PM', 6.00,
                             (SELECT itemReq_valorUni FROM sp_ItemRequisicao_Listar(r)));
    PERFORM pg_temp.conferir('T3', 'requisição: valor total', 30.00,
                             (SELECT req_valorTotal FROM sp_Requisicao_Buscar(r)));

    /* Teste 4: estoque insuficiente -> erro TP011, estoque continua 15 */
    PERFORM pg_temp.conferir('T4', 'requisição acima do estoque: código do erro', 'TP011',
                             pg_temp.erro_de(format('CALL sp_ItemRequisicao_Inserir(%s, %s, 1000)', r, p1)));
    PERFORM pg_temp.conferir('T4', 'chapa: estoque inalterado', 15.000,
                             (SELECT prod_qtdEstoque FROM sp_Produto_Buscar(p1)));

    /* Teste 5: alterar a quantidade da requisição de 5 para 8 */
    CALL sp_ItemRequisicao_Alterar(ir, p1, 8);
    PERFORM pg_temp.conferir('T5', 'chapa: estoque', 12.000,
                             (SELECT prod_qtdEstoque FROM sp_Produto_Buscar(p1)));
    PERFORM pg_temp.conferir('T5', 'requisição: valor total', 48.00,
                             (SELECT req_valorTotal FROM sp_Requisicao_Buscar(r)));

    /* Teste 6: excluir a requisição -> estoque volta a 20, PM 6,00 */
    CALL sp_Requisicao_Excluir(r);
    SELECT * INTO v FROM sp_Produto_Buscar(p1);
    PERFORM pg_temp.conferir('T6', 'chapa: estoque', 20.000, v.prod_qtdEstoque);
    PERFORM pg_temp.conferir('T6', 'chapa: preço médio', 6.00, v.prod_precoMedio);

    /* Teste 7: excluir a segunda compra -> estoque 10, PM (20*6 - 70)/10 = 5,00 */
    CALL sp_Compra_Excluir(c2);
    SELECT * INTO v FROM sp_Produto_Buscar(p1);
    PERFORM pg_temp.conferir('T7', 'chapa: estoque', 10.000, v.prod_qtdEstoque);
    PERFORM pg_temp.conferir('T7', 'chapa: preço médio', 5.00, v.prod_precoMedio);
    PERFORM pg_temp.conferir('T7', 'chapa: última compra volta a 10 x 5,00', '10.000 x 5.00',
                             v.prod_qtdUltCompra || ' x ' || v.prod_valorUltCompra);

    /* Teste 8: consome 8 chapas e tenta excluir a compra 1 (10 chapas)
       -> erro TP010 e nada muda (estoque 2, 1 compra)                 */
    CALL sp_Requisicao_Inserir(s, NULL, r);
    CALL sp_ItemRequisicao_Inserir(r, p1, 8, ir);
    PERFORM pg_temp.conferir('T8', 'estorno com estoque negativo: código do erro', 'TP010',
                             pg_temp.erro_de(format('CALL sp_Compra_Excluir(%s)', c1)));
    PERFORM pg_temp.conferir('T8', 'chapa: estoque inalterado', 2.000,
                             (SELECT prod_qtdEstoque FROM sp_Produto_Buscar(p1)));
    PERFORM pg_temp.conferir('T8', 'quantidade de compras', 1::BIGINT,
                             (SELECT COUNT(*) FROM sp_Compra_Listar()));

    /* Teste 9: excluir produto com movimentação -> erro TP002 */
    PERFORM pg_temp.conferir('T9', 'excluir produto com compras: código do erro', 'TP002',
                             pg_temp.erro_de(format('CALL sp_Produto_Excluir(%s)', p1)));

    /* Teste 10: CNPJ inválido -> 23514 (violação do CHECK CK_FORNECEDOR_cnpj) */
    PERFORM pg_temp.conferir('T10', 'CNPJ "123": código do erro', '23514',
                             pg_temp.erro_de('CALL sp_Fornecedor_Inserir(''Fornecedor X'', ''123'')'));
END;
$$;

/* ---------- Teste 11: papel da aplicação só executa procedures ----------
   O usuário atual assume temporariamente o papel rl_aplicacao.
   Esperado: INSERT e SELECT diretos negados (42501 = permissão negada);
             sp_Setor_Inserir e sp_Setor_Listar funcionam.             */
GRANT rl_aplicacao TO CURRENT_USER;

DO $$
DECLARE
    e_insert TEXT; e_select TEXT; s2 BIGINT; achou BOOLEAN;
BEGIN
    SET ROLE rl_aplicacao;
    e_insert := pg_temp.erro_de('INSERT INTO industria.SETOR (setor_nome) VALUES (''Direto'')');
    e_select := pg_temp.erro_de('SELECT * FROM industria.SETOR');
    CALL industria.sp_Setor_Inserir('Manutenção', s2);
    achou := EXISTS (SELECT 1 FROM industria.sp_Setor_Listar('Manut'));
    RESET ROLE;

    PERFORM pg_temp.conferir('T11', 'INSERT direto na tabela: código do erro', '42501', e_insert);
    PERFORM pg_temp.conferir('T11', 'SELECT direto na tabela: código do erro', '42501', e_select);
    PERFORM pg_temp.conferir('T11', 'sp_Setor_Inserir + sp_Setor_Listar funcionam', true, achou);
END;
$$;

REVOKE rl_aplicacao FROM CURRENT_USER;

/* ---------- Massa de dados para os relatórios ----------
   Situação da chapa antes: estoque 2, PM 5,00
   Compra 15/09 (Metalúrgica Sul) 20 x 4,50 -> estoque 22, PM 4,55
   Compra 20/09 (Aços Brasil)     10 x 5,50 -> estoque 32, PM 4,85
   Requisição 21/09 (Manutenção): 6 chapas (x 4,85) e 30 parafusos (x 0,50)
   -> chapa estoque 26, parafuso estoque 70                               */
DO $$
DECLARE
    f1    BIGINT := (SELECT fornec_id FROM sp_Fornecedor_Listar('12345678000190'));
    chapa BIGINT := (SELECT prod_id FROM sp_Produto_Listar('Chapa'));
    paraf BIGINT := (SELECT prod_id FROM sp_Produto_Listar('Parafuso'));
    manut BIGINT := (SELECT setor_id FROM sp_Setor_Listar('Manutenção'));
    f2 BIGINT; c BIGINT; r BIGINT; i BIGINT;
BEGIN
    CALL sp_Fornecedor_Inserir('Metalúrgica Sul S.A.', '98765432000110', f2);
    CALL sp_Compra_Inserir(f2, '2026-09-15', c);
    CALL sp_ItemCompra_Inserir(c, chapa, 20, 4.50, i);
    CALL sp_Compra_Inserir(f1, '2026-09-20', c);
    CALL sp_ItemCompra_Inserir(c, chapa, 10, 5.50, i);
    CALL sp_Requisicao_Inserir(manut, '2026-09-21', r);
    CALL sp_ItemRequisicao_Inserir(r, chapa, 6, i);
    CALL sp_ItemRequisicao_Inserir(r, paraf, 30, i);
END;
$$;

/* ---------- Testes 12 a 16: consultas e relatórios ---------- */
DO $$
DECLARE
    chapa BIGINT := (SELECT prod_id FROM sp_Produto_Listar('Chapa'));
    v RECORD;
    t TEXT;
BEGIN
    /* Teste 12: consultas */
    SELECT * INTO v FROM sp_Produto_Buscar(chapa);
    PERFORM pg_temp.conferir('T12', 'chapa: estoque', 26.000, v.prod_qtdEstoque);
    PERFORM pg_temp.conferir('T12', 'chapa: preço médio', 4.85, v.prod_precoMedio);
    PERFORM pg_temp.conferir('T12', 'parafuso: estoque', 70.000,
                             (SELECT prod_qtdEstoque FROM sp_Produto_Listar('Parafuso')));
    PERFORM pg_temp.conferir('T12', 'total do grupo Matéria-prima (26x4,85 + 70x0,50)', 161.10,
                             (SELECT valorEstoque FROM sp_Produto_ListarPorGrupo()
                               WHERE prod_nome = 'TOTAL DO GRUPO'));
    PERFORM pg_temp.conferir('T12', 'fornecedor por CNPJ com máscara', 'Metalúrgica Sul S.A.',
                             (SELECT fornec_razaoSocial FROM sp_Fornecedor_Listar('98.765.432')));
    PERFORM pg_temp.conferir('T12', 'compras de setembro', 3::BIGINT,
                             (SELECT COUNT(*) FROM sp_Compra_Listar('2026-09-01', '2026-09-30')));

    /* Teste 13: relatório c.i - consumo por setor */
    SELECT string_agg(setor_nome || ': ' || prod_nome || ' ' || COALESCE(qtdConsumida::TEXT, '-')
                      || ' / ' || valorConsumido, ' | ')
      INTO t FROM sp_Rel_ConsumoPorSetor();
    PERFORM pg_temp.conferir('T13', 'consumo por setor (qtd / valor)',
        'Manutenção: Chapa de aço 2mm 6.000 / 29.10 | Manutenção: Parafuso M8 30.000 / 15.00 | '
        || 'Manutenção: TOTAL DO SETOR - / 44.10 | Produção: Chapa de aço 2mm 8.000 / 40.00 | '
        || 'Produção: TOTAL DO SETOR - / 40.00', t);

    /* Teste 14: relatório c.ii - ficha do produto (saldo acumulado) */
    SELECT string_agg(to_char(data, 'DD/MM') || ' ' || tipo || ' ' || saldo, ' | ')
      INTO t FROM sp_Rel_FichaProduto(chapa, NULL, '2026-09-30');
    PERFORM pg_temp.conferir('T14', 'ficha da chapa até 30/09',
        '01/09 ENTRADA 10.000 | 15/09 ENTRADA 30.000 | 20/09 ENTRADA 40.000 | 21/09 SAÍDA 34.000', t);
    PERFORM pg_temp.conferir('T14', 'saldo final da ficha = estoque atual', 26.000,
        (SELECT saldo FROM sp_Rel_FichaProduto(chapa) ORDER BY data DESC LIMIT 1));
    PERFORM pg_temp.conferir('T14', 'ficha de 15/09 a 21/09: primeiro saldo', 30.000,
        (SELECT saldo FROM sp_Rel_FichaProduto(chapa, '2026-09-15', '2026-09-21') LIMIT 1));

    /* Teste 15: relatório c.iii - evolução do preço */
    SELECT string_agg(itemCompra_valorUni || ' (' || COALESCE(variacaoPercentual::TEXT, '-') || '%)', ' -> ')
      INTO t FROM sp_Rel_EvolucaoPrecoCompra(chapa, '2026-09-01', '2026-09-30');
    PERFORM pg_temp.conferir('T15', 'evolução do preço da chapa',
        '5.00 (-%) -> 4.50 (-10.00%) -> 5.50 (22.22%)', t);
    SELECT * INTO v FROM sp_Rel_EvolucaoPrecoMensal(chapa, '2026-09-01', '2026-09-30');
    PERFORM pg_temp.conferir('T15', 'set/2026: compras, qtd, menor, maior, média ponderada',
        '3 | 40.000 | 4.50 | 5.50 | 4.88',
        v.qtdCompras || ' | ' || v.qtdComprada || ' | ' || v.menorPreco || ' | '
        || v.maiorPreco || ' | ' || v.precoMedioPonderado);

    /* Teste 16: relatório c.iv - menor preço por fornecedor */
    SELECT string_agg(prod_nome || ': ' || fornec_razaoSocial || ' ' || menorPreco, ' | ')
      INTO t FROM sp_Rel_MenorPrecoFornecedor();
    PERFORM pg_temp.conferir('T16', 'menor preço por produto',
        'Chapa de aço 2mm: Metalúrgica Sul S.A. 4.50 | Parafuso M8: Aços Brasil Ltda 0.50', t);
END;
$$;

/* ---------- Resultado ----------
   Todas as linhas devem ter ok = true.
   Para ver um relatório completo, rode-o sozinho, por exemplo:
       SELECT * FROM industria.sp_Rel_ConsumoPorSetor();
       SELECT * FROM industria.sp_Rel_FichaProduto(1);                   */
SELECT teste, conferencia, esperado, obtido, ok
  FROM resultado_testes
 ORDER BY ordem;
