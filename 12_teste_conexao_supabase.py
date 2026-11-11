"""
Teste de conexão Python -> Supabase (PostgreSQL) para o DB_TP_INDUSTRIA.

Pré-requisitos (ver 13_guia_supabase.md):
  - Projeto no Supabase com os scripts 10 e 11 já executados no SQL Editor
  - Login app_industria criado (passo 4 do guia)
  - pip install "psycopg[binary]"

Uso:
  python 12_teste_conexao_supabase.py

O script chama funções de consulta e de relatório e testa uma inclusão
por procedure (CALL), desfeita no final com ROLLBACK: nenhum dado muda.
"""
import sys

import psycopg

# ---------------------------------------------------------------------------
# Configuração: copie de Connect > Session pooler, no painel do Supabase
# ---------------------------------------------------------------------------
HOST = "aws-0-sa-east-1.pooler.supabase.com"   # host do "Session pooler"
PORTA = 5432
BANCO = "postgres"
PROJECT_REF = "abcdefghijklmnopqrst"           # o código do projeto (aparece na URL do painel)
USUARIO = f"app_industria.{PROJECT_REF}"       # no pooler o usuário leva o código do projeto
SENHA = "TroqueEstaSenha#2026"
SSLMODE = "require"                            # o Supabase exige conexão criptografada

SCHEMA = "industria"


def conectar():
    return psycopg.connect(host=HOST, port=PORTA, dbname=BANCO, user=USUARIO,
                           password=SENHA, sslmode=SSLMODE, connect_timeout=10)


def consultar(cursor, funcao, *parametros):
    """Chama uma função de consulta e devolve (colunas, linhas)."""
    marcadores = ", ".join("%s" for _ in parametros)
    cursor.execute(f"SELECT * FROM {SCHEMA}.{funcao}({marcadores})", parametros)
    colunas = [c.name for c in cursor.description]
    return colunas, cursor.fetchall()


def executar(cursor, procedure, *parametros):
    """Chama uma procedure de manutenção. Se ela devolve um id (parâmetro
    INOUT, sempre o último), passe None no lugar dele: o id volta no retorno."""
    marcadores = ", ".join("%s" for _ in parametros)
    cursor.execute(f"CALL {SCHEMA}.{procedure}({marcadores})", parametros)
    return cursor.fetchone() if cursor.description else None


def imprimir(titulo, colunas, linhas):
    print(f"\n=== {titulo} ===")
    print(" | ".join(colunas))
    for linha in linhas:
        print(" | ".join("" if v is None else str(v) for v in linha))
    if not linhas:
        print("(nenhuma linha)")


def main():
    try:
        conexao = conectar()
    except psycopg.Error as erro:
        print("Não foi possível conectar ao Supabase.")
        print(f"Servidor: {HOST}:{PORTA}  Usuário: {USUARIO}")
        print(f"Detalhe: {erro}")
        sys.exit(1)

    with conexao, conexao.cursor() as cursor:
        cursor.execute("SELECT version()")
        print("Conectado a:", cursor.fetchone()[0].split(",")[0])

        imprimir("Produtos (sp_Produto_Listar)", *consultar(cursor, "sp_Produto_Listar"))
        imprimir("Consumo por setor (sp_Rel_ConsumoPorSetor)", *consultar(cursor, "sp_Rel_ConsumoPorSetor"))
        imprimir("Menor preço por fornecedor (sp_Rel_MenorPrecoFornecedor)",
                 *consultar(cursor, "sp_Rel_MenorPrecoFornecedor"))

        # Inclusão de teste por procedure, desfeita em seguida
        (novo_id,) = executar(cursor, "sp_Setor_Inserir", "Setor de teste (será desfeito)", None)
        print(f"\nsp_Setor_Inserir devolveu o id {novo_id}")

        # A aplicação não pode acessar as tabelas diretamente (requisito 4)
        try:
            with conexao.transaction():
                cursor.execute(f"SELECT * FROM {SCHEMA}.setor")
            print("ATENÇÃO: o SELECT direto na tabela foi aceito; confira o passo 4 do guia.")
        except psycopg.errors.InsufficientPrivilege:
            print("SELECT direto na tabela negado, como esperado.")

        conexao.rollback()

    print("\nConexão e procedures funcionando.")


if __name__ == "__main__":
    main()
