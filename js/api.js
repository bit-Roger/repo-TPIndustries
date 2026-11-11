/*
 * Acesso ao banco.
 * Toda operação passa por uma rotina sp_* do schema industria (requisito 4):
 * a página nunca lê nem grava tabelas diretamente.
 *   API.rpc("sp_setor_listar", { p_filtronome: "prod" })  -> linhas
 *   API.rpc("sp_setor_inserir", { p_setor_nome: "Pintura" }) -> id novo
 * O PostgreSQL guarda os nomes em minúsculas, por isso rotinas e
 * parâmetros aparecem assim aqui.
 */
const API = (() => {
  let cliente = null;

  function configurado() {
    const c = window.CONFIG || {};
    return /^https?:\/\//.test(c.SUPABASE_URL || "")
      && !String(c.SUPABASE_URL).includes("SEU-PROJETO")
      && c.SUPABASE_KEY && !String(c.SUPABASE_KEY).startsWith("COLE-AQUI");
  }

  function iniciar() {
    if (!window.supabase || !window.supabase.createClient) {
      throw new Error("A biblioteca do Supabase não carregou. Confira a conexão com a internet.");
    }
    cliente = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_KEY, {
      db: { schema: "industria" },
    });
    return cliente;
  }

  // Erros do banco viram mensagens para o usuário
  function traduzirErro(erro) {
    const codigo = erro && erro.code ? String(erro.code) : "";
    const texto = erro && erro.message ? String(erro.message) : String(erro || "");
    let mensagem;

    if (codigo.startsWith("TP")) {
      mensagem = texto;                                   // regras de negócio: a rotina já explica
    } else if (codigo === "23505") {
      mensagem = "Já existe um cadastro com esse valor (nome ou CNPJ repetido).";
    } else if (codigo === "23514") {
      mensagem = /cnpj/i.test(texto)
        ? "CNPJ inválido: informe os 14 dígitos."
        : "Valor inválido: confira os campos.";
    } else if (codigo === "23502") {
      mensagem = "Preencha todos os campos obrigatórios.";
    } else if (codigo === "23503") {
      mensagem = "O registro está ligado a outro cadastro.";
    } else if (codigo === "22P02" || codigo === "22007" || codigo === "22008" || codigo === "22003") {
      mensagem = "Formato inválido em algum campo (número ou data).";
    } else if (codigo === "42501") {
      mensagem = "Sem permissão para essa operação. Entre novamente no sistema.";
    } else if (codigo === "PGRST106") {
      mensagem = "O schema industria não está liberado na API do Supabase (guia, passo 5).";
    } else if (codigo === "PGRST202") {
      mensagem = "Rotina não encontrada na API. Rode o script 10 de novo e confira o passo 5 do guia.";
    } else if (codigo.startsWith("PGRST3")) {
      mensagem = "Sua sessão expirou. Entre novamente.";
    } else if (/fetch|network|Failed/i.test(texto)) {
      mensagem = "Não foi possível falar com o Supabase. Confira a internet e o config.js.";
    } else {
      mensagem = texto || "Erro inesperado.";
    }

    const e = new Error(mensagem);
    e.codigo = codigo;
    e.original = erro;
    return e;
  }

  async function rpc(nome, parametros = {}) {
    // Campo vazio vira NULL (= "sem filtro" nas consultas); undefined é omitido
    const enviados = {};
    for (const [chave, valor] of Object.entries(parametros)) {
      if (valor === undefined) continue;
      enviados[chave] = valor === "" ? null : valor;
    }
    let resposta;
    try {
      resposta = await cliente.rpc(nome, enviados);
    } catch (falha) {
      throw traduzirErro(falha);
    }
    if (resposta.error) throw traduzirErro(resposta.error);
    return resposta.data;
  }

  return {
    configurado,
    iniciar,
    rpc,
    get auth() { return cliente.auth; },
  };
})();
