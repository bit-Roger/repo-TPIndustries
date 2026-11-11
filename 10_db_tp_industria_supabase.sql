/* =====================================================================
   DB_TP_INDUSTRIA - versão PostgreSQL para o Supabase
   Setor de compras e controle de estoque da TP Indústria Ltda.
   SGBD alvo : PostgreSQL 15+ (Supabase); testado no PostgreSQL 17
   Normalização: 3FN

   Como executar no Supabase
     Painel do projeto > SQL Editor > New query > colar este arquivo > Run.
     O script pode ser executado de novo: ele apaga e recria o schema.

   Organização do script
     1. Schema
     2. Tabelas (PK, FK, UNIQUE, CHECK, DEFAULT) e índices
     3. Funções internas e triggers de estoque, preço médio e totais
     4. Procedures de manutenção (inserir / alterar / excluir)
     5. Funções de consulta (listar / buscar)
     6. Funções dos relatórios gerenciais
     7. Segurança: papel da aplicação só executa procedures e funções

   Diferenças em relação à versão SQL Server
     - Tudo fica no schema "industria", e não no "public": assim as
       tabelas não aparecem na API automática do Supabase.
     - IDENTITY -> GENERATED ALWAYS AS IDENTITY; DATETIME2 -> TIMESTAMP;
       DECIMAL -> NUMERIC (mesma precisão).
     - Manutenção (inserir/alterar/excluir) usa PROCEDURE, chamada com
       CALL. Consultas e relatórios usam FUNCTION ... RETURNS TABLE,
       chamadas com SELECT * FROM, porque procedures do PostgreSQL não
       devolvem linhas.
     - Os relatórios que no SQL Server devolviam dois resultados viraram
       duas funções (a ficha usa sp_Produto_Buscar para o cabeçalho; a
       evolução de preço ganhou sp_Rel_EvolucaoPrecoMensal).
     - Triggers do PostgreSQL chamam uma função de trigger; aqui são por
       linha (FOR EACH ROW), um trigger por tabela de itens.
     - Erros de negócio usam RAISE EXCEPTION com SQLSTATE próprio:
         TP001 registro não encontrado
         TP002 registro possui dependentes (exclusão bloqueada)
         TP003 dado inválido
         TP010 estorno de compra deixaria o estoque negativo
         TP011 estoque insuficiente para a requisição
     - O PostgreSQL guarda nomes sem aspas em minúsculas:
       sp_Setor_Inserir e sp_setor_inserir são o mesmo objeto.
     - Datas padrão no horário de Brasília (o servidor do Supabase usa UTC).

   Referências
     DATE (2004); ELMASRI e NAVATHE (2019); HEUSER (2009);
     SILBERSCHATZ, KORTH e SUDARSHAN (2020);
     POSTGRESQL GLOBAL DEVELOPMENT GROUP. PostgreSQL Documentation, 2026.
   ===================================================================== */

/* =====================================================================
   1. SCHEMA
   ===================================================================== */
DROP SCHEMA IF EXISTS industria CASCADE;
CREATE SCHEMA industria;
REVOKE ALL ON SCHEMA industria FROM PUBLIC;

SET search_path = industria, pg_temp;

/* =====================================================================
   2. TABELAS
   ===================================================================== */

CREATE TABLE GRUPO_PRODUTO (
    grupoProd_id    BIGINT        GENERATED ALWAYS AS IDENTITY,
    grupoProd_nome  VARCHAR(100)  NOT NULL,
    CONSTRAINT PK_GRUPO_PRODUTO      PRIMARY KEY (grupoProd_id),
    CONSTRAINT UQ_GRUPO_PRODUTO_nome UNIQUE (grupoProd_nome),
    CONSTRAINT CK_GRUPO_PRODUTO_nome CHECK (LENGTH(TRIM(grupoProd_nome)) > 0)
);

CREATE TABLE PRODUTO (
    prod_id              BIGINT         GENERATED ALWAYS AS IDENTITY,
    grupoProd_fk         BIGINT         NOT NULL,
    prod_nome            VARCHAR(150)   NOT NULL,
    prod_qtdEstoque      NUMERIC(12,3)  NOT NULL DEFAULT 0.000,
    prod_precoMedio      NUMERIC(12,2)  NOT NULL DEFAULT 0.00,
    prod_qtdUltCompra    NUMERIC(12,3)  NOT NULL DEFAULT 0.000,
    prod_valorUltCompra  NUMERIC(12,2)  NOT NULL DEFAULT 0.00,
    CONSTRAINT PK_PRODUTO               PRIMARY KEY (prod_id),
    CONSTRAINT FK_PRODUTO_GRUPO_PRODUTO FOREIGN KEY (grupoProd_fk)
        REFERENCES GRUPO_PRODUTO (grupoProd_id),
    CONSTRAINT CK_PRODUTO_nome          CHECK (LENGTH(TRIM(prod_nome)) > 0),
    CONSTRAINT CK_PRODUTO_qtdEstoque    CHECK (prod_qtdEstoque >= 0),
    CONSTRAINT CK_PRODUTO_precoMedio    CHECK (prod_precoMedio >= 0)
);

CREATE TABLE SETOR (
    setor_id    BIGINT        GENERATED ALWAYS AS IDENTITY,
    setor_nome  VARCHAR(100)  NOT NULL,
    CONSTRAINT PK_SETOR      PRIMARY KEY (setor_id),
    CONSTRAINT UQ_SETOR_nome UNIQUE (setor_nome),
    CONSTRAINT CK_SETOR_nome CHECK (LENGTH(TRIM(setor_nome)) > 0)
);

CREATE TABLE FORNECEDOR (
    fornec_id           BIGINT        GENERATED ALWAYS AS IDENTITY,
    fornec_razaoSocial  VARCHAR(150)  NOT NULL,
    fornec_cnpj         VARCHAR(14)   NOT NULL,
    CONSTRAINT PK_FORNECEDOR       PRIMARY KEY (fornec_id),
    CONSTRAINT UQ_FORNECEDOR_cnpj  UNIQUE (fornec_cnpj),
    CONSTRAINT CK_FORNECEDOR_razao CHECK (LENGTH(TRIM(fornec_razaoSocial)) > 0),
    -- CNPJ armazenado só com dígitos: exatamente 14 caracteres numéricos
    CONSTRAINT CK_FORNECEDOR_cnpj  CHECK (fornec_cnpj ~ '^[0-9]{14}$')
);

CREATE TABLE COMPRA (
    compra_id          BIGINT         GENERATED ALWAYS AS IDENTITY,
    fornec_fk          BIGINT         NOT NULL,
    compra_data        TIMESTAMP      NOT NULL DEFAULT (now() AT TIME ZONE 'America/Sao_Paulo'),
    compra_valorTotal  NUMERIC(12,2)  NOT NULL DEFAULT 0.00,
    CONSTRAINT PK_COMPRA            PRIMARY KEY (compra_id),
    CONSTRAINT FK_COMPRA_FORNECEDOR FOREIGN KEY (fornec_fk)
        REFERENCES FORNECEDOR (fornec_id),
    CONSTRAINT CK_COMPRA_valorTotal CHECK (compra_valorTotal >= 0)
);

CREATE TABLE ITEM_COMPRA (
    itemCompra_id        BIGINT         GENERATED ALWAYS AS IDENTITY,
    compra_fk            BIGINT         NOT NULL,
    prod_fk              BIGINT         NOT NULL,
    itemCompra_qtd       NUMERIC(12,3)  NOT NULL,
    itemCompra_valorUni  NUMERIC(12,2)  NOT NULL,
    CONSTRAINT PK_ITEM_COMPRA          PRIMARY KEY (itemCompra_id),
    CONSTRAINT FK_ITEM_COMPRA_COMPRA   FOREIGN KEY (compra_fk)
        REFERENCES COMPRA (compra_id),
    CONSTRAINT FK_ITEM_COMPRA_PRODUTO  FOREIGN KEY (prod_fk)
        REFERENCES PRODUTO (prod_id),
    CONSTRAINT CK_ITEM_COMPRA_qtd      CHECK (itemCompra_qtd > 0),
    CONSTRAINT CK_ITEM_COMPRA_valorUni CHECK (itemCompra_valorUni >= 0)
);

CREATE TABLE REQUISICAO (
    req_id          BIGINT         GENERATED ALWAYS AS IDENTITY,
    setor_fk        BIGINT         NOT NULL,
    req_data        TIMESTAMP      NOT NULL DEFAULT (now() AT TIME ZONE 'America/Sao_Paulo'),
    req_valorTotal  NUMERIC(12,2)  NOT NULL DEFAULT 0.00,
    CONSTRAINT PK_REQUISICAO            PRIMARY KEY (req_id),
    CONSTRAINT FK_REQUISICAO_SETOR      FOREIGN KEY (setor_fk)
        REFERENCES SETOR (setor_id),
    CONSTRAINT CK_REQUISICAO_valorTotal CHECK (req_valorTotal >= 0)
);

CREATE TABLE ITEM_REQUISICAO (
    itemReq_id        BIGINT         GENERATED ALWAYS AS IDENTITY,
    req_fk            BIGINT         NOT NULL,
    prod_fk           BIGINT         NOT NULL,
    itemReq_qtd       NUMERIC(12,3)  NOT NULL,
    itemReq_valorUni  NUMERIC(12,2)  NOT NULL,
    CONSTRAINT PK_ITEM_REQUISICAO            PRIMARY KEY (itemReq_id),
    CONSTRAINT FK_ITEM_REQUISICAO_REQUISICAO FOREIGN KEY (req_fk)
        REFERENCES REQUISICAO (req_id),
    CONSTRAINT FK_ITEM_REQUISICAO_PRODUTO    FOREIGN KEY (prod_fk)
        REFERENCES PRODUTO (prod_id),
    CONSTRAINT CK_ITEM_REQUISICAO_qtd        CHECK (itemReq_qtd > 0),
    CONSTRAINT CK_ITEM_REQUISICAO_valorUni   CHECK (itemReq_valorUni >= 0)
);

-- Índices nas chaves estrangeiras (o PostgreSQL não os cria automaticamente)
CREATE INDEX IX_PRODUTO_grupoProd_fk    ON PRODUTO (grupoProd_fk);
CREATE INDEX IX_COMPRA_fornec_fk        ON COMPRA (fornec_fk);
CREATE INDEX IX_ITEM_COMPRA_compra_fk   ON ITEM_COMPRA (compra_fk);
CREATE INDEX IX_ITEM_COMPRA_prod_fk     ON ITEM_COMPRA (prod_fk);
CREATE INDEX IX_REQUISICAO_setor_fk     ON REQUISICAO (setor_fk);
CREATE INDEX IX_ITEM_REQUISICAO_req_fk  ON ITEM_REQUISICAO (req_fk);
CREATE INDEX IX_ITEM_REQUISICAO_prod_fk ON ITEM_REQUISICAO (prod_fk);

/* =====================================================================
   3. FUNÇÕES INTERNAS E TRIGGERS
   As funções fn_* só são chamadas pelos triggers; a aplicação não tem
   permissão para executá-las (seção 7).
   ===================================================================== */

/* Entrada (qtd > 0) ou estorno (qtd < 0) de compra no estoque,
   recalculando o preço médio ponderado:
       novo PM = (estoque * PM atual + qtd * valor) / (estoque + qtd)   */
CREATE FUNCTION fn_MovimentarEntrada(p_prod_id BIGINT, p_qtd NUMERIC, p_valor NUMERIC)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = industria, pg_temp
AS $$
DECLARE
    v_estoque NUMERIC;
    v_pm      NUMERIC;
BEGIN
    SELECT prod_qtdEstoque, prod_precoMedio
      INTO v_estoque, v_pm
      FROM PRODUTO
     WHERE prod_id = p_prod_id
       FOR UPDATE;

    IF v_estoque + p_qtd < 0 THEN
        RAISE EXCEPTION 'Operação cancelada: o estorno da compra deixaria o estoque do produto negativo.'
            USING ERRCODE = 'TP010';
    END IF;

    UPDATE PRODUTO
       SET prod_precoMedio =
               CASE
                   WHEN v_estoque + p_qtd <= 0 THEN v_pm      -- estoque zerado: mantém o último custo
                   WHEN v_estoque * v_pm + p_valor <= 0 THEN 0
                   ELSE ROUND((v_estoque * v_pm + p_valor) / (v_estoque + p_qtd), 2)
               END,
           prod_qtdEstoque = v_estoque + p_qtd
     WHERE prod_id = p_prod_id;
END;
$$;

/* Última compra do produto: item mais recente pela data da compra */
CREATE FUNCTION fn_AtualizarUltimaCompra(p_prod_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = industria, pg_temp
AS $$
BEGIN
    UPDATE PRODUTO p
       SET prod_qtdUltCompra   = COALESCE(u.itemCompra_qtd, 0),
           prod_valorUltCompra = COALESCE(u.itemCompra_valorUni, 0)
      FROM (SELECT NULL::INT AS x) AS dummy
      LEFT JOIN LATERAL (
            SELECT ic.itemCompra_qtd, ic.itemCompra_valorUni
              FROM ITEM_COMPRA ic
              JOIN COMPRA c ON c.compra_id = ic.compra_fk
             WHERE ic.prod_fk = p_prod_id
             ORDER BY c.compra_data DESC, ic.itemCompra_id DESC
             LIMIT 1
      ) AS u ON TRUE
     WHERE p.prod_id = p_prod_id;
END;
$$;

CREATE FUNCTION fn_TotalizarCompra(p_compra_id BIGINT)
RETURNS VOID
LANGUAGE sql
SET search_path = industria, pg_temp
AS $$
    UPDATE COMPRA
       SET compra_valorTotal = COALESCE((SELECT SUM(itemCompra_qtd * itemCompra_valorUni)
                                           FROM ITEM_COMPRA
                                          WHERE compra_fk = p_compra_id), 0)
     WHERE compra_id = p_compra_id;
$$;

/* Saída (qtd > 0) ou devolução (qtd < 0) de requisição.
   A saída é valorizada pelo preço médio e não altera o preço médio.  */
CREATE FUNCTION fn_MovimentarSaida(p_prod_id BIGINT, p_qtd NUMERIC)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = industria, pg_temp
AS $$
DECLARE
    v_estoque NUMERIC;
BEGIN
    SELECT prod_qtdEstoque INTO v_estoque
      FROM PRODUTO
     WHERE prod_id = p_prod_id
       FOR UPDATE;

    IF v_estoque - p_qtd < 0 THEN
        RAISE EXCEPTION 'Estoque insuficiente para atender a requisição.'
            USING ERRCODE = 'TP011';
    END IF;

    UPDATE PRODUTO
       SET prod_qtdEstoque = v_estoque - p_qtd
     WHERE prod_id = p_prod_id;
END;
$$;

CREATE FUNCTION fn_TotalizarRequisicao(p_req_id BIGINT)
RETURNS VOID
LANGUAGE sql
SET search_path = industria, pg_temp
AS $$
    UPDATE REQUISICAO
       SET req_valorTotal = COALESCE((SELECT SUM(itemReq_qtd * itemReq_valorUni)
                                        FROM ITEM_REQUISICAO
                                       WHERE req_fk = p_req_id), 0)
     WHERE req_id = p_req_id;
$$;

/* ---------------------------------------------------------------------
   Trigger de ITEM_COMPRA (entrada no estoque)
   INSERT soma, DELETE estorna, UPDATE aplica a diferença.
   --------------------------------------------------------------------- */
CREATE FUNCTION fn_trg_ITEM_COMPRA()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = industria, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM fn_MovimentarEntrada(NEW.prod_fk, NEW.itemCompra_qtd,
                                     NEW.itemCompra_qtd * NEW.itemCompra_valorUni);
        PERFORM fn_AtualizarUltimaCompra(NEW.prod_fk);
        PERFORM fn_TotalizarCompra(NEW.compra_fk);

    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.prod_fk = NEW.prod_fk THEN
            -- Mesmo produto: aplica só a diferença, para não barrar um aumento
            -- de quantidade quando parte da compra já foi consumida
            PERFORM fn_MovimentarEntrada(NEW.prod_fk,
                                         NEW.itemCompra_qtd - OLD.itemCompra_qtd,
                                         NEW.itemCompra_qtd * NEW.itemCompra_valorUni
                                         - OLD.itemCompra_qtd * OLD.itemCompra_valorUni);
        ELSE
            PERFORM fn_MovimentarEntrada(OLD.prod_fk, -OLD.itemCompra_qtd,
                                         -(OLD.itemCompra_qtd * OLD.itemCompra_valorUni));
            PERFORM fn_MovimentarEntrada(NEW.prod_fk, NEW.itemCompra_qtd,
                                         NEW.itemCompra_qtd * NEW.itemCompra_valorUni);
            PERFORM fn_AtualizarUltimaCompra(OLD.prod_fk);
        END IF;
        PERFORM fn_AtualizarUltimaCompra(NEW.prod_fk);
        PERFORM fn_TotalizarCompra(NEW.compra_fk);
        IF OLD.compra_fk <> NEW.compra_fk THEN
            PERFORM fn_TotalizarCompra(OLD.compra_fk);
        END IF;

    ELSE  -- DELETE
        PERFORM fn_MovimentarEntrada(OLD.prod_fk, -OLD.itemCompra_qtd,
                                     -(OLD.itemCompra_qtd * OLD.itemCompra_valorUni));
        PERFORM fn_AtualizarUltimaCompra(OLD.prod_fk);
        PERFORM fn_TotalizarCompra(OLD.compra_fk);
    END IF;

    RETURN NULL;   -- trigger AFTER: o valor de retorno é ignorado
END;
$$;

CREATE TRIGGER trg_ITEM_COMPRA_Estoque
AFTER INSERT OR UPDATE OR DELETE ON ITEM_COMPRA
FOR EACH ROW EXECUTE FUNCTION fn_trg_ITEM_COMPRA();

/* ---------------------------------------------------------------------
   Trigger de COMPRA: mudar a data pode mudar a "última compra"
   --------------------------------------------------------------------- */
CREATE FUNCTION fn_trg_COMPRA_Data()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = industria, pg_temp
AS $$
DECLARE
    v_prod BIGINT;
BEGIN
    FOR v_prod IN SELECT DISTINCT prod_fk FROM ITEM_COMPRA WHERE compra_fk = NEW.compra_id LOOP
        PERFORM fn_AtualizarUltimaCompra(v_prod);
    END LOOP;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_COMPRA_DataUltCompra
AFTER UPDATE OF compra_data ON COMPRA
FOR EACH ROW
WHEN (OLD.compra_data IS DISTINCT FROM NEW.compra_data)
EXECUTE FUNCTION fn_trg_COMPRA_Data();

/* ---------------------------------------------------------------------
   Trigger de ITEM_REQUISICAO (saída do estoque)
   --------------------------------------------------------------------- */
CREATE FUNCTION fn_trg_ITEM_REQUISICAO()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = industria, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM fn_MovimentarSaida(NEW.prod_fk, NEW.itemReq_qtd);
        PERFORM fn_TotalizarRequisicao(NEW.req_fk);

    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.prod_fk = NEW.prod_fk THEN
            PERFORM fn_MovimentarSaida(NEW.prod_fk, NEW.itemReq_qtd - OLD.itemReq_qtd);
        ELSE
            PERFORM fn_MovimentarSaida(OLD.prod_fk, -OLD.itemReq_qtd);
            PERFORM fn_MovimentarSaida(NEW.prod_fk, NEW.itemReq_qtd);
        END IF;
        PERFORM fn_TotalizarRequisicao(NEW.req_fk);
        IF OLD.req_fk <> NEW.req_fk THEN
            PERFORM fn_TotalizarRequisicao(OLD.req_fk);
        END IF;

    ELSE  -- DELETE
        PERFORM fn_MovimentarSaida(OLD.prod_fk, -OLD.itemReq_qtd);
        PERFORM fn_TotalizarRequisicao(OLD.req_fk);
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_ITEM_REQUISICAO_Estoque
AFTER INSERT OR UPDATE OR DELETE ON ITEM_REQUISICAO
FOR EACH ROW EXECUTE FUNCTION fn_trg_ITEM_REQUISICAO();

/* =====================================================================
   4. PROCEDURES DE MANUTENÇÃO
   Padrão:
     - SECURITY DEFINER: executam com as permissões do dono do schema,
       por isso a aplicação consegue gravar sem ter acesso às tabelas;
     - SET search_path fixo, como recomenda a documentação do PostgreSQL
       para funções SECURITY DEFINER;
     - inserções devolvem o ID no último parâmetro (INOUT):
         CALL sp_Setor_Inserir('Produção', NULL);   -> devolve setor_id
     - qualquer erro desfaz tudo o que a procedure fez (a chamada é
       atômica dentro da transação de quem chamou).
   ===================================================================== */

/* ------------------------------ GRUPO_PRODUTO ------------------------------ */
CREATE PROCEDURE sp_GrupoProduto_Inserir(p_grupoProd_nome VARCHAR, INOUT p_grupoProd_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    INSERT INTO GRUPO_PRODUTO (grupoProd_nome)
    VALUES (TRIM(p_grupoProd_nome))
    RETURNING grupoProd_id INTO p_grupoProd_id;
END;
$$;

CREATE PROCEDURE sp_GrupoProduto_Alterar(p_grupoProd_id BIGINT, p_grupoProd_nome VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM GRUPO_PRODUTO WHERE grupoProd_id = p_grupoProd_id) THEN
        RAISE EXCEPTION 'Grupo de produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    UPDATE GRUPO_PRODUTO SET grupoProd_nome = TRIM(p_grupoProd_nome)
     WHERE grupoProd_id = p_grupoProd_id;
END;
$$;

CREATE PROCEDURE sp_GrupoProduto_Excluir(p_grupoProd_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM GRUPO_PRODUTO WHERE grupoProd_id = p_grupoProd_id) THEN
        RAISE EXCEPTION 'Grupo de produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF EXISTS (SELECT 1 FROM PRODUTO WHERE grupoProd_fk = p_grupoProd_id) THEN
        RAISE EXCEPTION 'Grupo possui produtos vinculados e não pode ser excluído.' USING ERRCODE = 'TP002';
    END IF;

    DELETE FROM GRUPO_PRODUTO WHERE grupoProd_id = p_grupoProd_id;
END;
$$;

/* --------------------------------- PRODUTO --------------------------------- */
-- Estoque, preço médio e última compra são mantidos pelos triggers.
CREATE PROCEDURE sp_Produto_Inserir(p_grupoProd_fk BIGINT, p_prod_nome VARCHAR, INOUT p_prod_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM GRUPO_PRODUTO WHERE grupoProd_id = p_grupoProd_fk) THEN
        RAISE EXCEPTION 'Grupo de produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    INSERT INTO PRODUTO (grupoProd_fk, prod_nome)
    VALUES (p_grupoProd_fk, TRIM(p_prod_nome))
    RETURNING prod_id INTO p_prod_id;
END;
$$;

CREATE PROCEDURE sp_Produto_Alterar(p_prod_id BIGINT, p_grupoProd_fk BIGINT, p_prod_nome VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM PRODUTO WHERE prod_id = p_prod_id) THEN
        RAISE EXCEPTION 'Produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM GRUPO_PRODUTO WHERE grupoProd_id = p_grupoProd_fk) THEN
        RAISE EXCEPTION 'Grupo de produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    UPDATE PRODUTO
       SET grupoProd_fk = p_grupoProd_fk,
           prod_nome    = TRIM(p_prod_nome)
     WHERE prod_id = p_prod_id;
END;
$$;

CREATE PROCEDURE sp_Produto_Excluir(p_prod_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM PRODUTO WHERE prod_id = p_prod_id) THEN
        RAISE EXCEPTION 'Produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF EXISTS (SELECT 1 FROM ITEM_COMPRA WHERE prod_fk = p_prod_id)
       OR EXISTS (SELECT 1 FROM ITEM_REQUISICAO WHERE prod_fk = p_prod_id) THEN
        RAISE EXCEPTION 'Produto possui movimentação (compras ou requisições) e não pode ser excluído.'
            USING ERRCODE = 'TP002';
    END IF;

    DELETE FROM PRODUTO WHERE prod_id = p_prod_id;
END;
$$;

/* ---------------------------------- SETOR ---------------------------------- */
CREATE PROCEDURE sp_Setor_Inserir(p_setor_nome VARCHAR, INOUT p_setor_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    INSERT INTO SETOR (setor_nome) VALUES (TRIM(p_setor_nome))
    RETURNING setor_id INTO p_setor_id;
END;
$$;

CREATE PROCEDURE sp_Setor_Alterar(p_setor_id BIGINT, p_setor_nome VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM SETOR WHERE setor_id = p_setor_id) THEN
        RAISE EXCEPTION 'Setor não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    UPDATE SETOR SET setor_nome = TRIM(p_setor_nome) WHERE setor_id = p_setor_id;
END;
$$;

CREATE PROCEDURE sp_Setor_Excluir(p_setor_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM SETOR WHERE setor_id = p_setor_id) THEN
        RAISE EXCEPTION 'Setor não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF EXISTS (SELECT 1 FROM REQUISICAO WHERE setor_fk = p_setor_id) THEN
        RAISE EXCEPTION 'Setor possui requisições e não pode ser excluído.' USING ERRCODE = 'TP002';
    END IF;

    DELETE FROM SETOR WHERE setor_id = p_setor_id;
END;
$$;

/* -------------------------------- FORNECEDOR ------------------------------- */
-- O CNPJ pode vir com ou sem máscara (00.000.000/0000-00)
CREATE PROCEDURE sp_Fornecedor_Inserir(p_fornec_razaoSocial VARCHAR, p_fornec_cnpj VARCHAR,
                                       INOUT p_fornec_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
DECLARE
    v_cnpj VARCHAR := regexp_replace(p_fornec_cnpj, '[./-]', '', 'g');
BEGIN
    IF EXISTS (SELECT 1 FROM FORNECEDOR WHERE fornec_cnpj = v_cnpj) THEN
        RAISE EXCEPTION 'Já existe fornecedor cadastrado com este CNPJ.' USING ERRCODE = 'TP003';
    END IF;

    INSERT INTO FORNECEDOR (fornec_razaoSocial, fornec_cnpj)
    VALUES (TRIM(p_fornec_razaoSocial), v_cnpj)
    RETURNING fornec_id INTO p_fornec_id;
END;
$$;

CREATE PROCEDURE sp_Fornecedor_Alterar(p_fornec_id BIGINT, p_fornec_razaoSocial VARCHAR, p_fornec_cnpj VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
DECLARE
    v_cnpj VARCHAR := regexp_replace(p_fornec_cnpj, '[./-]', '', 'g');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM FORNECEDOR WHERE fornec_id = p_fornec_id) THEN
        RAISE EXCEPTION 'Fornecedor não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF EXISTS (SELECT 1 FROM FORNECEDOR WHERE fornec_cnpj = v_cnpj AND fornec_id <> p_fornec_id) THEN
        RAISE EXCEPTION 'Já existe outro fornecedor cadastrado com este CNPJ.' USING ERRCODE = 'TP003';
    END IF;

    UPDATE FORNECEDOR
       SET fornec_razaoSocial = TRIM(p_fornec_razaoSocial),
           fornec_cnpj        = v_cnpj
     WHERE fornec_id = p_fornec_id;
END;
$$;

CREATE PROCEDURE sp_Fornecedor_Excluir(p_fornec_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM FORNECEDOR WHERE fornec_id = p_fornec_id) THEN
        RAISE EXCEPTION 'Fornecedor não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF EXISTS (SELECT 1 FROM COMPRA WHERE fornec_fk = p_fornec_id) THEN
        RAISE EXCEPTION 'Fornecedor possui compras e não pode ser excluído.' USING ERRCODE = 'TP002';
    END IF;

    DELETE FROM FORNECEDOR WHERE fornec_id = p_fornec_id;
END;
$$;

/* ---------------------------------- COMPRA --------------------------------- */
-- compra_valorTotal não é informado: é recalculado pelo trigger de ITEM_COMPRA.
CREATE PROCEDURE sp_Compra_Inserir(p_fornec_fk BIGINT, p_compra_data TIMESTAMP DEFAULT NULL,
                                   INOUT p_compra_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM FORNECEDOR WHERE fornec_id = p_fornec_fk) THEN
        RAISE EXCEPTION 'Fornecedor não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    INSERT INTO COMPRA (fornec_fk, compra_data)
    VALUES (p_fornec_fk, COALESCE(p_compra_data, now() AT TIME ZONE 'America/Sao_Paulo'))
    RETURNING compra_id INTO p_compra_id;
END;
$$;

CREATE PROCEDURE sp_Compra_Alterar(p_compra_id BIGINT, p_fornec_fk BIGINT, p_compra_data TIMESTAMP)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM COMPRA WHERE compra_id = p_compra_id) THEN
        RAISE EXCEPTION 'Compra não encontrada.' USING ERRCODE = 'TP001';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM FORNECEDOR WHERE fornec_id = p_fornec_fk) THEN
        RAISE EXCEPTION 'Fornecedor não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    UPDATE COMPRA
       SET fornec_fk   = p_fornec_fk,
           compra_data = p_compra_data
     WHERE compra_id = p_compra_id;
END;
$$;

-- Exclui a compra inteira: os itens primeiro (o trigger estorna o estoque), depois o cabeçalho.
CREATE PROCEDURE sp_Compra_Excluir(p_compra_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM COMPRA WHERE compra_id = p_compra_id) THEN
        RAISE EXCEPTION 'Compra não encontrada.' USING ERRCODE = 'TP001';
    END IF;

    DELETE FROM ITEM_COMPRA WHERE compra_fk = p_compra_id;
    DELETE FROM COMPRA      WHERE compra_id = p_compra_id;
END;
$$;

/* ------------------------------- ITEM_COMPRA ------------------------------- */
CREATE PROCEDURE sp_ItemCompra_Inserir(p_compra_fk BIGINT, p_prod_fk BIGINT,
                                       p_itemCompra_qtd NUMERIC, p_itemCompra_valorUni NUMERIC,
                                       INOUT p_itemCompra_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM COMPRA WHERE compra_id = p_compra_fk) THEN
        RAISE EXCEPTION 'Compra não encontrada.' USING ERRCODE = 'TP001';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM PRODUTO WHERE prod_id = p_prod_fk) THEN
        RAISE EXCEPTION 'Produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF p_itemCompra_qtd IS NULL OR p_itemCompra_qtd <= 0 THEN
        RAISE EXCEPTION 'A quantidade comprada deve ser maior que zero.' USING ERRCODE = 'TP003';
    END IF;

    IF p_itemCompra_valorUni IS NULL OR p_itemCompra_valorUni < 0 THEN
        RAISE EXCEPTION 'O valor unitário não pode ser negativo.' USING ERRCODE = 'TP003';
    END IF;

    INSERT INTO ITEM_COMPRA (compra_fk, prod_fk, itemCompra_qtd, itemCompra_valorUni)
    VALUES (p_compra_fk, p_prod_fk, p_itemCompra_qtd, p_itemCompra_valorUni)
    RETURNING itemCompra_id INTO p_itemCompra_id;
END;
$$;

CREATE PROCEDURE sp_ItemCompra_Alterar(p_itemCompra_id BIGINT, p_prod_fk BIGINT,
                                       p_itemCompra_qtd NUMERIC, p_itemCompra_valorUni NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ITEM_COMPRA WHERE itemCompra_id = p_itemCompra_id) THEN
        RAISE EXCEPTION 'Item de compra não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM PRODUTO WHERE prod_id = p_prod_fk) THEN
        RAISE EXCEPTION 'Produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF p_itemCompra_qtd IS NULL OR p_itemCompra_qtd <= 0 THEN
        RAISE EXCEPTION 'A quantidade comprada deve ser maior que zero.' USING ERRCODE = 'TP003';
    END IF;

    IF p_itemCompra_valorUni IS NULL OR p_itemCompra_valorUni < 0 THEN
        RAISE EXCEPTION 'O valor unitário não pode ser negativo.' USING ERRCODE = 'TP003';
    END IF;

    UPDATE ITEM_COMPRA
       SET prod_fk             = p_prod_fk,
           itemCompra_qtd      = p_itemCompra_qtd,
           itemCompra_valorUni = p_itemCompra_valorUni
     WHERE itemCompra_id = p_itemCompra_id;
END;
$$;

CREATE PROCEDURE sp_ItemCompra_Excluir(p_itemCompra_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ITEM_COMPRA WHERE itemCompra_id = p_itemCompra_id) THEN
        RAISE EXCEPTION 'Item de compra não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    DELETE FROM ITEM_COMPRA WHERE itemCompra_id = p_itemCompra_id;
END;
$$;

/* -------------------------------- REQUISICAO ------------------------------- */
CREATE PROCEDURE sp_Requisicao_Inserir(p_setor_fk BIGINT, p_req_data TIMESTAMP DEFAULT NULL,
                                       INOUT p_req_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM SETOR WHERE setor_id = p_setor_fk) THEN
        RAISE EXCEPTION 'Setor não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    INSERT INTO REQUISICAO (setor_fk, req_data)
    VALUES (p_setor_fk, COALESCE(p_req_data, now() AT TIME ZONE 'America/Sao_Paulo'))
    RETURNING req_id INTO p_req_id;
END;
$$;

CREATE PROCEDURE sp_Requisicao_Alterar(p_req_id BIGINT, p_setor_fk BIGINT, p_req_data TIMESTAMP)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM REQUISICAO WHERE req_id = p_req_id) THEN
        RAISE EXCEPTION 'Requisição não encontrada.' USING ERRCODE = 'TP001';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM SETOR WHERE setor_id = p_setor_fk) THEN
        RAISE EXCEPTION 'Setor não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    UPDATE REQUISICAO
       SET setor_fk = p_setor_fk,
           req_data = p_req_data
     WHERE req_id = p_req_id;
END;
$$;

-- Exclui a requisição inteira: os itens voltam ao estoque pelo trigger.
CREATE PROCEDURE sp_Requisicao_Excluir(p_req_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM REQUISICAO WHERE req_id = p_req_id) THEN
        RAISE EXCEPTION 'Requisição não encontrada.' USING ERRCODE = 'TP001';
    END IF;

    DELETE FROM ITEM_REQUISICAO WHERE req_fk = p_req_id;
    DELETE FROM REQUISICAO      WHERE req_id = p_req_id;
END;
$$;

/* ----------------------------- ITEM_REQUISICAO ----------------------------- */
-- O valor unitário da saída é o preço médio do produto no momento do lançamento.
CREATE PROCEDURE sp_ItemRequisicao_Inserir(p_req_fk BIGINT, p_prod_fk BIGINT, p_itemReq_qtd NUMERIC,
                                           INOUT p_itemReq_id BIGINT DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
DECLARE
    v_pm NUMERIC;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM REQUISICAO WHERE req_id = p_req_fk) THEN
        RAISE EXCEPTION 'Requisição não encontrada.' USING ERRCODE = 'TP001';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM PRODUTO WHERE prod_id = p_prod_fk) THEN
        RAISE EXCEPTION 'Produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF p_itemReq_qtd IS NULL OR p_itemReq_qtd <= 0 THEN
        RAISE EXCEPTION 'A quantidade requisitada deve ser maior que zero.' USING ERRCODE = 'TP003';
    END IF;

    SELECT prod_precoMedio INTO v_pm FROM PRODUTO WHERE prod_id = p_prod_fk FOR UPDATE;

    INSERT INTO ITEM_REQUISICAO (req_fk, prod_fk, itemReq_qtd, itemReq_valorUni)
    VALUES (p_req_fk, p_prod_fk, p_itemReq_qtd, v_pm)
    RETURNING itemReq_id INTO p_itemReq_id;
END;
$$;

-- Troca de produto revaloriza o item pelo preço médio do novo produto;
-- mudança só de quantidade mantém o valor unitário original.
CREATE PROCEDURE sp_ItemRequisicao_Alterar(p_itemReq_id BIGINT, p_prod_fk BIGINT, p_itemReq_qtd NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
DECLARE
    v_pm NUMERIC;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ITEM_REQUISICAO WHERE itemReq_id = p_itemReq_id) THEN
        RAISE EXCEPTION 'Item de requisição não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM PRODUTO WHERE prod_id = p_prod_fk) THEN
        RAISE EXCEPTION 'Produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    IF p_itemReq_qtd IS NULL OR p_itemReq_qtd <= 0 THEN
        RAISE EXCEPTION 'A quantidade requisitada deve ser maior que zero.' USING ERRCODE = 'TP003';
    END IF;

    SELECT prod_precoMedio INTO v_pm FROM PRODUTO WHERE prod_id = p_prod_fk;

    UPDATE ITEM_REQUISICAO
       SET itemReq_valorUni = CASE WHEN prod_fk = p_prod_fk THEN itemReq_valorUni ELSE v_pm END,
           prod_fk          = p_prod_fk,
           itemReq_qtd      = p_itemReq_qtd
     WHERE itemReq_id = p_itemReq_id;
END;
$$;

CREATE PROCEDURE sp_ItemRequisicao_Excluir(p_itemReq_id BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ITEM_REQUISICAO WHERE itemReq_id = p_itemReq_id) THEN
        RAISE EXCEPTION 'Item de requisição não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    DELETE FROM ITEM_REQUISICAO WHERE itemReq_id = p_itemReq_id;
END;
$$;

/* =====================================================================
   5. FUNÇÕES DE CONSULTA
   Chamada: SELECT * FROM sp_Produto_Listar();
   Filtros opcionais: NULL = sem filtro. Períodos em DATE; a data final
   inclui o dia inteiro.
   ===================================================================== */

/* ------------------------------ GRUPO_PRODUTO ------------------------------ */
CREATE FUNCTION sp_GrupoProduto_Listar(p_filtroNome VARCHAR DEFAULT NULL)
RETURNS TABLE (grupoProd_id BIGINT, grupoProd_nome VARCHAR, qtdProdutos BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT g.grupoProd_id,
           g.grupoProd_nome,
           (SELECT COUNT(*) FROM PRODUTO p WHERE p.grupoProd_fk = g.grupoProd_id)
      FROM GRUPO_PRODUTO g
     WHERE p_filtroNome IS NULL OR g.grupoProd_nome ILIKE '%' || p_filtroNome || '%'
     ORDER BY g.grupoProd_nome;
$$;

CREATE FUNCTION sp_GrupoProduto_Buscar(p_grupoProd_id BIGINT)
RETURNS TABLE (grupoProd_id BIGINT, grupoProd_nome VARCHAR)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT g.grupoProd_id, g.grupoProd_nome
      FROM GRUPO_PRODUTO g
     WHERE g.grupoProd_id = p_grupoProd_id;
$$;

/* --------------------------------- PRODUTO --------------------------------- */
CREATE FUNCTION sp_Produto_Listar(p_filtroNome VARCHAR DEFAULT NULL, p_grupoProd_id BIGINT DEFAULT NULL)
RETURNS TABLE (prod_id BIGINT, prod_nome VARCHAR, grupoProd_fk BIGINT, grupoProd_nome VARCHAR,
               prod_qtdEstoque NUMERIC, prod_precoMedio NUMERIC, valorEstoque NUMERIC,
               prod_qtdUltCompra NUMERIC, prod_valorUltCompra NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT p.prod_id, p.prod_nome, p.grupoProd_fk, g.grupoProd_nome,
           p.prod_qtdEstoque, p.prod_precoMedio,
           ROUND(p.prod_qtdEstoque * p.prod_precoMedio, 2),
           p.prod_qtdUltCompra, p.prod_valorUltCompra
      FROM PRODUTO p
      JOIN GRUPO_PRODUTO g ON g.grupoProd_id = p.grupoProd_fk
     WHERE (p_filtroNome   IS NULL OR p.prod_nome ILIKE '%' || p_filtroNome || '%')
       AND (p_grupoProd_id IS NULL OR p.grupoProd_fk = p_grupoProd_id)
     ORDER BY p.prod_nome;
$$;

CREATE FUNCTION sp_Produto_Buscar(p_prod_id BIGINT)
RETURNS TABLE (prod_id BIGINT, prod_nome VARCHAR, grupoProd_fk BIGINT, grupoProd_nome VARCHAR,
               prod_qtdEstoque NUMERIC, prod_precoMedio NUMERIC,
               prod_qtdUltCompra NUMERIC, prod_valorUltCompra NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT p.prod_id, p.prod_nome, p.grupoProd_fk, g.grupoProd_nome,
           p.prod_qtdEstoque, p.prod_precoMedio, p.prod_qtdUltCompra, p.prod_valorUltCompra
      FROM PRODUTO p
      JOIN GRUPO_PRODUTO g ON g.grupoProd_id = p.grupoProd_fk
     WHERE p.prod_id = p_prod_id;
$$;

-- Necessidade b.vii: produtos separados por grupo, com subtotal de cada grupo
CREATE FUNCTION sp_Produto_ListarPorGrupo(p_grupoProd_id BIGINT DEFAULT NULL)
RETURNS TABLE (grupoProd_id BIGINT, grupoProd_nome VARCHAR, prod_id BIGINT, prod_nome VARCHAR,
               prod_qtdEstoque NUMERIC, prod_precoMedio NUMERIC, valorEstoque NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT g.grupoProd_id,
           g.grupoProd_nome,
           p.prod_id,
           CASE WHEN GROUPING(p.prod_id) = 1 THEN 'TOTAL DO GRUPO' ELSE MAX(p.prod_nome) END::VARCHAR,
           CASE WHEN GROUPING(p.prod_id) = 1 THEN NULL ELSE SUM(p.prod_qtdEstoque) END,
           CASE WHEN GROUPING(p.prod_id) = 1 THEN NULL ELSE MAX(p.prod_precoMedio) END,
           ROUND(SUM(p.prod_qtdEstoque * p.prod_precoMedio), 2)
      FROM GRUPO_PRODUTO g
      JOIN PRODUTO p ON p.grupoProd_fk = g.grupoProd_id
     WHERE p_grupoProd_id IS NULL OR g.grupoProd_id = p_grupoProd_id
     GROUP BY GROUPING SETS ((g.grupoProd_id, g.grupoProd_nome, p.prod_id),
                             (g.grupoProd_id, g.grupoProd_nome))
     ORDER BY g.grupoProd_nome, GROUPING(p.prod_id), 4;
$$;

/* ---------------------------------- SETOR ---------------------------------- */
CREATE FUNCTION sp_Setor_Listar(p_filtroNome VARCHAR DEFAULT NULL)
RETURNS TABLE (setor_id BIGINT, setor_nome VARCHAR)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT s.setor_id, s.setor_nome
      FROM SETOR s
     WHERE p_filtroNome IS NULL OR s.setor_nome ILIKE '%' || p_filtroNome || '%'
     ORDER BY s.setor_nome;
$$;

CREATE FUNCTION sp_Setor_Buscar(p_setor_id BIGINT)
RETURNS TABLE (setor_id BIGINT, setor_nome VARCHAR)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT s.setor_id, s.setor_nome FROM SETOR s WHERE s.setor_id = p_setor_id;
$$;

/* -------------------------------- FORNECEDOR ------------------------------- */
-- p_filtro procura na razão social ou no CNPJ (com ou sem máscara)
CREATE FUNCTION sp_Fornecedor_Listar(p_filtro VARCHAR DEFAULT NULL)
RETURNS TABLE (fornec_id BIGINT, fornec_razaoSocial VARCHAR, fornec_cnpj VARCHAR)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT f.fornec_id, f.fornec_razaoSocial, f.fornec_cnpj
      FROM FORNECEDOR f
     WHERE p_filtro IS NULL
        OR f.fornec_razaoSocial ILIKE '%' || p_filtro || '%'
        OR f.fornec_cnpj LIKE '%' || regexp_replace(p_filtro, '[./-]', '', 'g') || '%'
     ORDER BY f.fornec_razaoSocial;
$$;

CREATE FUNCTION sp_Fornecedor_Buscar(p_fornec_id BIGINT)
RETURNS TABLE (fornec_id BIGINT, fornec_razaoSocial VARCHAR, fornec_cnpj VARCHAR)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT f.fornec_id, f.fornec_razaoSocial, f.fornec_cnpj
      FROM FORNECEDOR f WHERE f.fornec_id = p_fornec_id;
$$;

/* ---------------------------------- COMPRA --------------------------------- */
CREATE FUNCTION sp_Compra_Listar(p_dataIni DATE DEFAULT NULL, p_dataFim DATE DEFAULT NULL,
                                 p_fornec_id BIGINT DEFAULT NULL)
RETURNS TABLE (compra_id BIGINT, compra_data TIMESTAMP, fornec_fk BIGINT, fornec_razaoSocial VARCHAR,
               compra_valorTotal NUMERIC, qtdItens BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT c.compra_id, c.compra_data, c.fornec_fk, f.fornec_razaoSocial, c.compra_valorTotal,
           (SELECT COUNT(*) FROM ITEM_COMPRA ic WHERE ic.compra_fk = c.compra_id)
      FROM COMPRA c
      JOIN FORNECEDOR f ON f.fornec_id = c.fornec_fk
     WHERE (p_dataIni   IS NULL OR c.compra_data >= p_dataIni)
       AND (p_dataFim   IS NULL OR c.compra_data <  p_dataFim + 1)
       AND (p_fornec_id IS NULL OR c.fornec_fk = p_fornec_id)
     ORDER BY c.compra_data DESC, c.compra_id DESC;
$$;

CREATE FUNCTION sp_Compra_Buscar(p_compra_id BIGINT)
RETURNS TABLE (compra_id BIGINT, compra_data TIMESTAMP, fornec_fk BIGINT, fornec_razaoSocial VARCHAR,
               fornec_cnpj VARCHAR, compra_valorTotal NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT c.compra_id, c.compra_data, c.fornec_fk, f.fornec_razaoSocial, f.fornec_cnpj, c.compra_valorTotal
      FROM COMPRA c
      JOIN FORNECEDOR f ON f.fornec_id = c.fornec_fk
     WHERE c.compra_id = p_compra_id;
$$;

CREATE FUNCTION sp_ItemCompra_Listar(p_compra_id BIGINT)
RETURNS TABLE (itemCompra_id BIGINT, prod_fk BIGINT, prod_nome VARCHAR, itemCompra_qtd NUMERIC,
               itemCompra_valorUni NUMERIC, itemCompra_valorTotal NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT ic.itemCompra_id, ic.prod_fk, p.prod_nome, ic.itemCompra_qtd, ic.itemCompra_valorUni,
           ROUND(ic.itemCompra_qtd * ic.itemCompra_valorUni, 2)
      FROM ITEM_COMPRA ic
      JOIN PRODUTO p ON p.prod_id = ic.prod_fk
     WHERE ic.compra_fk = p_compra_id
     ORDER BY ic.itemCompra_id;
$$;

/* -------------------------------- REQUISICAO ------------------------------- */
CREATE FUNCTION sp_Requisicao_Listar(p_dataIni DATE DEFAULT NULL, p_dataFim DATE DEFAULT NULL,
                                     p_setor_id BIGINT DEFAULT NULL)
RETURNS TABLE (req_id BIGINT, req_data TIMESTAMP, setor_fk BIGINT, setor_nome VARCHAR,
               req_valorTotal NUMERIC, qtdItens BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT r.req_id, r.req_data, r.setor_fk, s.setor_nome, r.req_valorTotal,
           (SELECT COUNT(*) FROM ITEM_REQUISICAO ir WHERE ir.req_fk = r.req_id)
      FROM REQUISICAO r
      JOIN SETOR s ON s.setor_id = r.setor_fk
     WHERE (p_dataIni  IS NULL OR r.req_data >= p_dataIni)
       AND (p_dataFim  IS NULL OR r.req_data <  p_dataFim + 1)
       AND (p_setor_id IS NULL OR r.setor_fk = p_setor_id)
     ORDER BY r.req_data DESC, r.req_id DESC;
$$;

CREATE FUNCTION sp_Requisicao_Buscar(p_req_id BIGINT)
RETURNS TABLE (req_id BIGINT, req_data TIMESTAMP, setor_fk BIGINT, setor_nome VARCHAR, req_valorTotal NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT r.req_id, r.req_data, r.setor_fk, s.setor_nome, r.req_valorTotal
      FROM REQUISICAO r
      JOIN SETOR s ON s.setor_id = r.setor_fk
     WHERE r.req_id = p_req_id;
$$;

CREATE FUNCTION sp_ItemRequisicao_Listar(p_req_id BIGINT)
RETURNS TABLE (itemReq_id BIGINT, prod_fk BIGINT, prod_nome VARCHAR, itemReq_qtd NUMERIC,
               itemReq_valorUni NUMERIC, itemReq_valorTotal NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT ir.itemReq_id, ir.prod_fk, p.prod_nome, ir.itemReq_qtd, ir.itemReq_valorUni,
           ROUND(ir.itemReq_qtd * ir.itemReq_valorUni, 2)
      FROM ITEM_REQUISICAO ir
      JOIN PRODUTO p ON p.prod_id = ir.prod_fk
     WHERE ir.req_fk = p_req_id
     ORDER BY ir.itemReq_id;
$$;

/* =====================================================================
   6. RELATÓRIOS GERENCIAIS (item c do enunciado)
   ===================================================================== */

/* c.i  Quantidade e valor consumidos por setor, com total por setor */
CREATE FUNCTION sp_Rel_ConsumoPorSetor(p_dataIni DATE DEFAULT NULL, p_dataFim DATE DEFAULT NULL,
                                       p_setor_id BIGINT DEFAULT NULL)
RETURNS TABLE (setor_id BIGINT, setor_nome VARCHAR, prod_id BIGINT, prod_nome VARCHAR,
               qtdConsumida NUMERIC, valorConsumido NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT s.setor_id,
           s.setor_nome,
           p.prod_id,
           CASE WHEN GROUPING(p.prod_id) = 1 THEN 'TOTAL DO SETOR' ELSE MAX(p.prod_nome) END::VARCHAR,
           CASE WHEN GROUPING(p.prod_id) = 1 THEN NULL ELSE SUM(ir.itemReq_qtd) END,
           ROUND(SUM(ir.itemReq_qtd * ir.itemReq_valorUni), 2)
      FROM SETOR s
      JOIN REQUISICAO      r  ON r.setor_fk = s.setor_id
      JOIN ITEM_REQUISICAO ir ON ir.req_fk  = r.req_id
      JOIN PRODUTO         p  ON p.prod_id  = ir.prod_fk
     WHERE (p_dataIni  IS NULL OR r.req_data >= p_dataIni)
       AND (p_dataFim  IS NULL OR r.req_data <  p_dataFim + 1)
       AND (p_setor_id IS NULL OR s.setor_id = p_setor_id)
     GROUP BY GROUPING SETS ((s.setor_id, s.setor_nome, p.prod_id),
                             (s.setor_id, s.setor_nome))
     ORDER BY s.setor_nome, GROUPING(p.prod_id), 4;
$$;

/* c.ii Ficha do produto: todas as entradas e saídas, com saldo acumulado.
   O saldo é calculado sobre todo o histórico e só depois filtrado pelo
   período. Os dados atuais do produto vêm de sp_Produto_Buscar.        */
CREATE FUNCTION sp_Rel_FichaProduto(p_prod_id BIGINT, p_dataIni DATE DEFAULT NULL, p_dataFim DATE DEFAULT NULL)
RETURNS TABLE (data TIMESTAMP, tipo VARCHAR, documento BIGINT, origemDestino VARCHAR,
               qtdEntrada NUMERIC, qtdSaida NUMERIC, valorUni NUMERIC, valorTotal NUMERIC, saldo NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM PRODUTO WHERE prod_id = p_prod_id) THEN
        RAISE EXCEPTION 'Produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    RETURN QUERY
    WITH movimentos AS (
        SELECT c.compra_data AS m_data, 1 AS ordemTipo, ic.itemCompra_id AS idItem,
               'ENTRADA'::VARCHAR AS m_tipo, c.compra_id AS m_doc, f.fornec_razaoSocial AS m_orig,
               ic.itemCompra_qtd AS m_ent, 0::NUMERIC AS m_sai, ic.itemCompra_valorUni AS m_vu
          FROM ITEM_COMPRA ic
          JOIN COMPRA     c ON c.compra_id = ic.compra_fk
          JOIN FORNECEDOR f ON f.fornec_id = c.fornec_fk
         WHERE ic.prod_fk = p_prod_id
        UNION ALL
        SELECT r.req_data, 2, ir.itemReq_id, 'SAÍDA'::VARCHAR, r.req_id, s.setor_nome,
               0::NUMERIC, ir.itemReq_qtd, ir.itemReq_valorUni
          FROM ITEM_REQUISICAO ir
          JOIN REQUISICAO r ON r.req_id   = ir.req_fk
          JOIN SETOR      s ON s.setor_id = r.setor_fk
         WHERE ir.prod_fk = p_prod_id
    ),
    ficha AS (
        SELECT m.*,
               SUM(m.m_ent - m.m_sai) OVER (ORDER BY m.m_data, m.ordemTipo, m.idItem
                                            ROWS UNBOUNDED PRECEDING) AS m_saldo
          FROM movimentos m
    )
    SELECT fi.m_data, fi.m_tipo, fi.m_doc, fi.m_orig, fi.m_ent, fi.m_sai, fi.m_vu,
           ROUND((fi.m_ent + fi.m_sai) * fi.m_vu, 2), fi.m_saldo
      FROM ficha fi
     WHERE (p_dataIni IS NULL OR fi.m_data >= p_dataIni)
       AND (p_dataFim IS NULL OR fi.m_data <  p_dataFim + 1)
     ORDER BY fi.m_data, fi.ordemTipo, fi.idItem;
END;
$$;

/* c.iii Evolução do preço de compra: cada compra com a variação em
   relação à anterior (LAG)                                            */
CREATE FUNCTION sp_Rel_EvolucaoPrecoCompra(p_prod_id BIGINT, p_dataIni DATE DEFAULT NULL, p_dataFim DATE DEFAULT NULL)
RETURNS TABLE (compra_data TIMESTAMP, compra_id BIGINT, fornec_razaoSocial VARCHAR, itemCompra_qtd NUMERIC,
               itemCompra_valorUni NUMERIC, valorAnterior NUMERIC, variacaoPercentual NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM PRODUTO WHERE prod_id = p_prod_id) THEN
        RAISE EXCEPTION 'Produto não encontrado.' USING ERRCODE = 'TP001';
    END IF;

    RETURN QUERY
    WITH compras AS (
        SELECT c.compra_data AS c_data, c.compra_id AS c_id, f.fornec_razaoSocial AS c_forn,
               ic.itemCompra_qtd AS c_qtd, ic.itemCompra_valorUni AS c_vu,
               LAG(ic.itemCompra_valorUni) OVER (ORDER BY c.compra_data, ic.itemCompra_id) AS c_ant
          FROM ITEM_COMPRA ic
          JOIN COMPRA     c ON c.compra_id = ic.compra_fk
          JOIN FORNECEDOR f ON f.fornec_id = c.fornec_fk
         WHERE ic.prod_fk = p_prod_id
    )
    SELECT x.c_data, x.c_id, x.c_forn, x.c_qtd, x.c_vu, x.c_ant,
           CASE WHEN x.c_ant > 0 THEN ROUND((x.c_vu - x.c_ant) * 100.0 / x.c_ant, 2) END
      FROM compras x
     WHERE (p_dataIni IS NULL OR x.c_data >= p_dataIni)
       AND (p_dataFim IS NULL OR x.c_data <  p_dataFim + 1)
     ORDER BY x.c_data;
END;
$$;

/* c.iii (complemento) Resumo mensal: menor, maior e média ponderada */
CREATE FUNCTION sp_Rel_EvolucaoPrecoMensal(p_prod_id BIGINT, p_dataIni DATE DEFAULT NULL, p_dataFim DATE DEFAULT NULL)
RETURNS TABLE (ano INT, mes INT, qtdCompras BIGINT, qtdComprada NUMERIC, menorPreco NUMERIC,
               maiorPreco NUMERIC, precoMedioPonderado NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    SELECT EXTRACT(YEAR FROM c.compra_data)::INT,
           EXTRACT(MONTH FROM c.compra_data)::INT,
           COUNT(*),
           SUM(ic.itemCompra_qtd),
           MIN(ic.itemCompra_valorUni),
           MAX(ic.itemCompra_valorUni),
           ROUND(SUM(ic.itemCompra_qtd * ic.itemCompra_valorUni) / SUM(ic.itemCompra_qtd), 2)
      FROM ITEM_COMPRA ic
      JOIN COMPRA c ON c.compra_id = ic.compra_fk
     WHERE ic.prod_fk = p_prod_id
       AND (p_dataIni IS NULL OR c.compra_data >= p_dataIni)
       AND (p_dataFim IS NULL OR c.compra_data <  p_dataFim + 1)
     GROUP BY 1, 2
     ORDER BY 1, 2;
$$;

/* c.iv Fornecedor e menor preço de compra de cada produto
   (empates: todos os fornecedores com o menor preço aparecem)          */
CREATE FUNCTION sp_Rel_MenorPrecoFornecedor(p_prod_id BIGINT DEFAULT NULL, p_dataIni DATE DEFAULT NULL,
                                            p_dataFim DATE DEFAULT NULL)
RETURNS TABLE (prod_id BIGINT, prod_nome VARCHAR, fornec_id BIGINT, fornec_razaoSocial VARCHAR,
               menorPreco NUMERIC, compra_data TIMESTAMP, compra_id BIGINT,
               prod_precoMedio NUMERIC, prod_valorUltCompra NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = industria, pg_temp
AS $$
    WITH precos AS (
        SELECT ic.prod_fk, ic.itemCompra_valorUni, c.compra_data, c.compra_id,
               f.fornec_id, f.fornec_razaoSocial,
               RANK() OVER (PARTITION BY ic.prod_fk ORDER BY ic.itemCompra_valorUni) AS posicao
          FROM ITEM_COMPRA ic
          JOIN COMPRA     c ON c.compra_id = ic.compra_fk
          JOIN FORNECEDOR f ON f.fornec_id = c.fornec_fk
         WHERE (p_prod_id IS NULL OR ic.prod_fk = p_prod_id)
           AND (p_dataIni IS NULL OR c.compra_data >= p_dataIni)
           AND (p_dataFim IS NULL OR c.compra_data <  p_dataFim + 1)
    )
    SELECT p.prod_id, p.prod_nome, pr.fornec_id, pr.fornec_razaoSocial, pr.itemCompra_valorUni,
           pr.compra_data, pr.compra_id, p.prod_precoMedio, p.prod_valorUltCompra
      FROM precos pr
      JOIN PRODUTO p ON p.prod_id = pr.prod_fk
     WHERE pr.posicao = 1
     ORDER BY p.prod_nome, pr.compra_data;
$$;

/* =====================================================================
   7. SEGURANÇA (requisito 4)
   O papel rl_aplicacao só executa as procedures e funções sp_*.
   Ele não tem nenhuma permissão nas tabelas nem nas funções internas.
   As procedures funcionam porque são SECURITY DEFINER.
   O login da aplicação é criado à parte (ver guia), com senha própria.
   ===================================================================== */
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rl_aplicacao') THEN
        CREATE ROLE rl_aplicacao NOLOGIN;
    END IF;
END;
$$;

-- No PostgreSQL toda função nova pode ser executada por PUBLIC: retira isso
REVOKE ALL ON ALL TABLES    IN SCHEMA industria FROM PUBLIC;
REVOKE ALL ON ALL ROUTINES  IN SCHEMA industria FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA industria FROM PUBLIC;

/* No Supabase existem os papéis da API (anon, authenticated, service_role).
   Garante que nenhum deles tenha acesso ao schema industria.             */
DO $$
DECLARE
    papel TEXT;
BEGIN
    FOREACH papel IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = papel) THEN
            EXECUTE format('REVOKE ALL ON SCHEMA industria FROM %I', papel);
            EXECUTE format('REVOKE ALL ON ALL TABLES    IN SCHEMA industria FROM %I', papel);
            EXECUTE format('REVOKE ALL ON ALL ROUTINES  IN SCHEMA industria FROM %I', papel);
            EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA industria FROM %I', papel);
        END IF;
    END LOOP;
END;
$$;

GRANT USAGE ON SCHEMA industria TO rl_aplicacao;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS assinatura, p.prokind
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'industria'
           AND p.proname LIKE 'sp\_%'
    LOOP
        IF r.prokind = 'p' THEN
            EXECUTE format('GRANT EXECUTE ON PROCEDURE %s TO rl_aplicacao', r.assinatura);
        ELSE
            EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO rl_aplicacao', r.assinatura);
        END IF;
    END LOOP;
END;
$$;

/* Resumo do que foi criado */
SELECT 'industria' AS schema,
       (SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'industria')                         AS tabelas,
       (SELECT COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'industria' AND NOT t.tgisinternal)                                 AS triggers,
       (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'industria' AND p.proname LIKE 'sp\_%' AND p.prokind = 'p')         AS procedures,
       (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'industria' AND p.proname LIKE 'sp\_%' AND p.prokind = 'f')         AS funcoes_consulta;
