/*
 * Telas do sistema. Cada tela é uma função que recebe a área de conteúdo
 * (e, quando houver, o id da rota, como em #/compras/5) e desenha a página.
 * Todas as leituras e gravações usam API.rpc com uma rotina sp_*.
 */

/* =====================================================================
   Listas para os campos de seleção
   ===================================================================== */
const opcoes = {
  async grupos() {
    const linhas = await API.rpc("sp_grupoproduto_listar");
    return linhas.map((g) => ({ valor: g.grupoprod_id, texto: g.grupoprod_nome }));
  },
  async produtos(detalhado = false) {
    const linhas = await API.rpc("sp_produto_listar");
    return linhas.map((p) => ({
      valor: p.prod_id,
      texto: detalhado
        ? `${p.prod_nome} (estoque ${fmt.qtd(p.prod_qtdestoque)}, PM ${fmt.moeda(p.prod_precomedio)})`
        : p.prod_nome,
    }));
  },
  async setores() {
    const linhas = await API.rpc("sp_setor_listar");
    return linhas.map((s) => ({ valor: s.setor_id, texto: s.setor_nome }));
  },
  async fornecedores() {
    const linhas = await API.rpc("sp_fornecedor_listar");
    return linhas.map((f) => ({ valor: f.fornec_id, texto: `${f.fornec_razaosocial} (${fmt.cnpj(f.fornec_cnpj)})` }));
  },
};

function irPara(rota) {
  location.hash = "#/" + rota;
}

/* =====================================================================
   Cadastro genérico: busca + tabela + incluir / editar / excluir
   ===================================================================== */
function telaCadastro(cfg) {
  return async function (alvo) {
    const busca = el("input", { type: "search", class: "busca", placeholder: cfg.placeholderBusca, "aria-label": "Buscar" });
    const extra = cfg.filtroExtra ? campo(await cfg.filtroExtra().catch(() => ({ ...cfg.filtroBase, opcoes: [] }))) : null;
    const area = el("div", { class: "area-dados" }, carregando());
    const botaoNovo = el("button", { type: "button", class: "botao primario", onclick: () => abrirFormulario() }, cfg.textos.novo);

    alvo.replaceChildren(
      cabecalhoPagina(cfg.titulo, cfg.descricao, botaoNovo),
      el("div", { class: "barra-filtros" }, el("label", { class: "campo campo-busca" }, el("span", {}, "Buscar"), busca), extra),
      area);

    async function carregar() {
      try {
        const valorExtra = extra ? extra.querySelector("select").value : "";
        const linhas = await cfg.listar(busca.value.trim(), valorExtra);
        area.replaceChildren(
          tabela({
            colunas: cfg.colunas,
            linhas,
            acoes: [
              ...(cfg.acoesExtras || []),
              { rotulo: "Editar", fn: (l) => abrirFormulario(l) },
              { rotulo: "Excluir", classe: "perigo-texto", fn: (l) => excluir(l) },
            ],
          }),
          el("p", { class: "sutil contagem" }, `${linhas.length} registro(s)`));
      } catch (falha) {
        area.replaceChildren(caixaErro(falha));
      }
    }

    async function abrirFormulario(linha) {
      let campos;
      try {
        campos = await cfg.campos();
      } catch (falha) {
        avisar(falha.message, "erro");
        return;
      }
      formularioModal({
        titulo: linha ? cfg.textos.editar : cfg.textos.novo,
        campos,
        valores: linha ? cfg.valoresDe(linha) : {},
        aoSalvar: async (dados) => {
          if (linha) await cfg.alterar(cfg.idDe(linha), dados);
          else await cfg.inserir(dados);
          avisar(cfg.textos.salvo, "ok");
          carregar();
        },
      });
    }

    async function excluir(linha) {
      if (!(await confirmar(`Excluir ${cfg.textos.artigo} "${cfg.nomeDe(linha)}"?`))) return;
      try {
        await executarAcao(() => cfg.excluir(cfg.idDe(linha)), cfg.textos.excluido);
        carregar();
      } catch { /* aviso já exibido */ }
    }

    let espera;
    busca.addEventListener("input", () => { clearTimeout(espera); espera = setTimeout(carregar, 300); });
    if (extra) extra.querySelector("select").addEventListener("change", carregar);
    carregar();
  };
}

/* =====================================================================
   Cadastros
   ===================================================================== */
const telaGrupos = telaCadastro({
  titulo: "Grupos de produto",
  descricao: "Categorias usadas para separar os produtos.",
  placeholderBusca: "Nome do grupo",
  textos: { novo: "Novo grupo", editar: "Editar grupo", artigo: "o grupo", salvo: "Grupo salvo.", excluido: "Grupo excluído." },
  listar: (busca) => API.rpc("sp_grupoproduto_listar", { p_filtronome: busca }),
  colunas: [
    { titulo: "Código", campo: "grupoprod_id" },
    { titulo: "Grupo", campo: "grupoprod_nome" },
    { titulo: "Produtos", campo: "qtdprodutos", tipo: "qtd" },
  ],
  campos: async () => [{ nome: "nome", rotulo: "Nome do grupo", tipo: "texto", obrigatorio: true, max: 100, largura: "inteira" }],
  valoresDe: (l) => ({ nome: l.grupoprod_nome }),
  idDe: (l) => l.grupoprod_id,
  nomeDe: (l) => l.grupoprod_nome,
  inserir: (d) => API.rpc("sp_grupoproduto_inserir", { p_grupoprod_nome: d.nome }),
  alterar: (id, d) => API.rpc("sp_grupoproduto_alterar", { p_grupoprod_id: id, p_grupoprod_nome: d.nome }),
  excluir: (id) => API.rpc("sp_grupoproduto_excluir", { p_grupoprod_id: id }),
});

const telaProdutos = telaCadastro({
  titulo: "Produtos",
  descricao: "Estoque, preço médio e última compra são atualizados automaticamente pelas compras e requisições.",
  placeholderBusca: "Nome do produto",
  textos: { novo: "Novo produto", editar: "Editar produto", artigo: "o produto", salvo: "Produto salvo.", excluido: "Produto excluído." },
  filtroBase: { nome: "grupo", rotulo: "Grupo", tipo: "select", vazio: "(todos os grupos)" },
  filtroExtra: async () => ({ nome: "grupo", rotulo: "Grupo", tipo: "select", vazio: "(todos os grupos)", opcoes: await opcoes.grupos() }),
  listar: (busca, grupo) => API.rpc("sp_produto_listar", { p_filtronome: busca, p_grupoprod_id: grupo === "" ? "" : Number(grupo) }),
  colunas: [
    { titulo: "Produto", campo: "prod_nome" },
    { titulo: "Grupo", campo: "grupoprod_nome" },
    { titulo: "Estoque", campo: "prod_qtdestoque", tipo: "qtd", classe: (l) => (Number(l.prod_qtdestoque) === 0 ? "zerado" : "") },
    { titulo: "Preço médio", campo: "prod_precomedio", tipo: "moeda" },
    { titulo: "Valor em estoque", campo: "valorestoque", tipo: "moeda" },
    {
      titulo: "Última compra",
      valor: (l) => (Number(l.prod_qtdultcompra) > 0 ? `${fmt.qtd(l.prod_qtdultcompra)} × ${fmt.moeda(l.prod_valorultcompra)}` : "—"),
    },
  ],
  acoesExtras: [{ rotulo: "Ficha", fn: (l) => irPara(`ficha/${l.prod_id}`) }],
  campos: async () => [
    { nome: "grupo", rotulo: "Grupo", tipo: "select", obrigatorio: true, vazio: "Selecione…", opcoes: await opcoes.grupos() },
    { nome: "nome", rotulo: "Nome do produto", tipo: "texto", obrigatorio: true, max: 150 },
  ],
  valoresDe: (l) => ({ grupo: l.grupoprod_fk, nome: l.prod_nome }),
  idDe: (l) => l.prod_id,
  nomeDe: (l) => l.prod_nome,
  inserir: (d) => API.rpc("sp_produto_inserir", { p_grupoprod_fk: d.grupo, p_prod_nome: d.nome }),
  alterar: (id, d) => API.rpc("sp_produto_alterar", { p_prod_id: id, p_grupoprod_fk: d.grupo, p_prod_nome: d.nome }),
  excluir: (id) => API.rpc("sp_produto_excluir", { p_prod_id: id }),
});

const telaSetores = telaCadastro({
  titulo: "Setores",
  descricao: "Setores da fábrica que fazem requisições de material.",
  placeholderBusca: "Nome do setor",
  textos: { novo: "Novo setor", editar: "Editar setor", artigo: "o setor", salvo: "Setor salvo.", excluido: "Setor excluído." },
  listar: (busca) => API.rpc("sp_setor_listar", { p_filtronome: busca }),
  colunas: [
    { titulo: "Código", campo: "setor_id" },
    { titulo: "Setor", campo: "setor_nome" },
  ],
  campos: async () => [{ nome: "nome", rotulo: "Nome do setor", tipo: "texto", obrigatorio: true, max: 100, largura: "inteira" }],
  valoresDe: (l) => ({ nome: l.setor_nome }),
  idDe: (l) => l.setor_id,
  nomeDe: (l) => l.setor_nome,
  inserir: (d) => API.rpc("sp_setor_inserir", { p_setor_nome: d.nome }),
  alterar: (id, d) => API.rpc("sp_setor_alterar", { p_setor_id: id, p_setor_nome: d.nome }),
  excluir: (id) => API.rpc("sp_setor_excluir", { p_setor_id: id }),
});

const telaFornecedores = telaCadastro({
  titulo: "Fornecedores",
  descricao: "A busca aceita razão social ou CNPJ, com ou sem máscara.",
  placeholderBusca: "Razão social ou CNPJ",
  textos: { novo: "Novo fornecedor", editar: "Editar fornecedor", artigo: "o fornecedor", salvo: "Fornecedor salvo.", excluido: "Fornecedor excluído." },
  listar: (busca) => API.rpc("sp_fornecedor_listar", { p_filtro: busca }),
  colunas: [
    { titulo: "Razão social", campo: "fornec_razaosocial" },
    { titulo: "CNPJ", campo: "fornec_cnpj", tipo: "cnpj" },
  ],
  campos: async () => [
    { nome: "razao", rotulo: "Razão social", tipo: "texto", obrigatorio: true, max: 150, largura: "inteira" },
    { nome: "cnpj", rotulo: "CNPJ", tipo: "cnpj", obrigatorio: true, placeholder: "00.000.000/0000-00" },
  ],
  valoresDe: (l) => ({ razao: l.fornec_razaosocial, cnpj: l.fornec_cnpj }),
  idDe: (l) => l.fornec_id,
  nomeDe: (l) => l.fornec_razaosocial,
  inserir: (d) => API.rpc("sp_fornecedor_inserir", { p_fornec_razaosocial: d.razao, p_fornec_cnpj: d.cnpj }),
  alterar: (id, d) => API.rpc("sp_fornecedor_alterar", { p_fornec_id: id, p_fornec_razaosocial: d.razao, p_fornec_cnpj: d.cnpj }),
  excluir: (id) => API.rpc("sp_fornecedor_excluir", { p_fornec_id: id }),
});

/* =====================================================================
   Movimentação: compras (entradas) e requisições (saídas)
   As duas telas têm o mesmo formato, então são geradas pela mesma função.
   ===================================================================== */
const MOV = {
  compras: {
    rota: "compras",
    titulo: "Compras",
    descricao: "Entradas de material. Cada item lançado soma ao estoque e recalcula o preço médio.",
    singular: "Compra",
    artigo: "a compra",
    parceiro: { nome: "fornecedor", rotulo: "Fornecedor", opcoes: () => opcoes.fornecedores() },
    listar: (f) => API.rpc("sp_compra_listar", { p_dataini: f.de, p_datafim: f.ate, p_fornec_id: f.parceiro }),
    buscar: async (id) => (await API.rpc("sp_compra_buscar", { p_compra_id: id }))[0],
    itens: (id) => API.rpc("sp_itemcompra_listar", { p_compra_id: id }),
    inserir: (d) => API.rpc("sp_compra_inserir", { p_fornec_fk: d.fornecedor, p_compra_data: d.data }),
    alterar: (id, d) => API.rpc("sp_compra_alterar", { p_compra_id: id, p_fornec_fk: d.fornecedor, p_compra_data: d.data }),
    excluir: (id) => API.rpc("sp_compra_excluir", { p_compra_id: id }),
    id: (l) => l.compra_id,
    data: (l) => l.compra_data,
    total: (l) => l.compra_valortotal,
    nomeParceiro: (l) => l.fornec_razaosocial,
    idParceiro: (l) => l.fornec_fk,
    detalheParceiro: (l) => fmt.cnpj(l.fornec_cnpj),
    item: {
      id: (i) => i.itemcompra_id,
      colunas: [
        { titulo: "Produto", campo: "prod_nome" },
        { titulo: "Quantidade", campo: "itemcompra_qtd", tipo: "qtd" },
        { titulo: "Valor unitário", campo: "itemcompra_valoruni", tipo: "moeda" },
        { titulo: "Total", campo: "itemcompra_valortotal", tipo: "moeda" },
      ],
      campos: async () => [
        { nome: "produto", rotulo: "Produto", tipo: "select", obrigatorio: true, vazio: "Selecione…", opcoes: await opcoes.produtos(), largura: "inteira" },
        { nome: "qtd", rotulo: "Quantidade", tipo: "numero", obrigatorio: true, passo: "0.001", min: "0.001" },
        { nome: "valor", rotulo: "Valor unitário (R$)", tipo: "numero", obrigatorio: true, passo: "0.01", min: "0" },
      ],
      valoresDe: (i) => ({ produto: i.prod_fk, qtd: Number(i.itemcompra_qtd), valor: Number(i.itemcompra_valoruni) }),
      inserir: (idMov, d) => API.rpc("sp_itemcompra_inserir", { p_compra_fk: idMov, p_prod_fk: d.produto, p_itemcompra_qtd: d.qtd, p_itemcompra_valoruni: d.valor }),
      alterar: (id, d) => API.rpc("sp_itemcompra_alterar", { p_itemcompra_id: id, p_prod_fk: d.produto, p_itemcompra_qtd: d.qtd, p_itemcompra_valoruni: d.valor }),
      excluir: (id) => API.rpc("sp_itemcompra_excluir", { p_itemcompra_id: id }),
      total: (i) => i.itemcompra_valortotal,
    },
  },
  requisicoes: {
    rota: "requisicoes",
    titulo: "Requisições",
    descricao: "Saídas de material para os setores. Cada item é valorizado pelo preço médio do produto.",
    singular: "Requisição",
    artigo: "a requisição",
    parceiro: { nome: "setor", rotulo: "Setor", opcoes: () => opcoes.setores() },
    listar: (f) => API.rpc("sp_requisicao_listar", { p_dataini: f.de, p_datafim: f.ate, p_setor_id: f.parceiro }),
    buscar: async (id) => (await API.rpc("sp_requisicao_buscar", { p_req_id: id }))[0],
    itens: (id) => API.rpc("sp_itemrequisicao_listar", { p_req_id: id }),
    inserir: (d) => API.rpc("sp_requisicao_inserir", { p_setor_fk: d.setor, p_req_data: d.data }),
    alterar: (id, d) => API.rpc("sp_requisicao_alterar", { p_req_id: id, p_setor_fk: d.setor, p_req_data: d.data }),
    excluir: (id) => API.rpc("sp_requisicao_excluir", { p_req_id: id }),
    id: (l) => l.req_id,
    data: (l) => l.req_data,
    total: (l) => l.req_valortotal,
    nomeParceiro: (l) => l.setor_nome,
    idParceiro: (l) => l.setor_fk,
    detalheParceiro: () => null,
    item: {
      id: (i) => i.itemreq_id,
      colunas: [
        { titulo: "Produto", campo: "prod_nome" },
        { titulo: "Quantidade", campo: "itemreq_qtd", tipo: "qtd" },
        { titulo: "Valor unitário (PM)", campo: "itemreq_valoruni", tipo: "moeda" },
        { titulo: "Total", campo: "itemreq_valortotal", tipo: "moeda" },
      ],
      campos: async () => [
        { nome: "produto", rotulo: "Produto", tipo: "select", obrigatorio: true, vazio: "Selecione…", opcoes: await opcoes.produtos(true), largura: "inteira" },
        { nome: "qtd", rotulo: "Quantidade", tipo: "numero", obrigatorio: true, passo: "0.001", min: "0.001",
          dica: "O valor unitário será o preço médio atual do produto." },
      ],
      valoresDe: (i) => ({ produto: i.prod_fk, qtd: Number(i.itemreq_qtd) }),
      inserir: (idMov, d) => API.rpc("sp_itemrequisicao_inserir", { p_req_fk: idMov, p_prod_fk: d.produto, p_itemreq_qtd: d.qtd }),
      alterar: (id, d) => API.rpc("sp_itemrequisicao_alterar", { p_itemreq_id: id, p_prod_fk: d.produto, p_itemreq_qtd: d.qtd }),
      excluir: (id) => API.rpc("sp_itemrequisicao_excluir", { p_itemreq_id: id }),
      total: (i) => i.itemreq_valortotal,
    },
  },
};

function camposMovimento(m) {
  return async () => [
    { nome: m.parceiro.nome, rotulo: m.parceiro.rotulo, tipo: "select", obrigatorio: true, vazio: "Selecione…",
      opcoes: await m.parceiro.opcoes(), largura: "inteira" },
    { nome: "data", rotulo: "Data e hora", tipo: "datahora", dica: "Em branco, usa o momento atual." },
  ];
}

function telaMovimentos(m) {
  return async function (alvo) {
    let listaParceiros = [];
    try { listaParceiros = await m.parceiro.opcoes(); } catch { /* a tabela mostra o erro */ }

    const filtros = el("form", { class: "barra-filtros" },
      campo({ nome: "de", rotulo: "De", tipo: "data" }),
      campo({ nome: "ate", rotulo: "Até", tipo: "data" }),
      campo({ nome: "parceiro", rotulo: m.parceiro.rotulo, tipo: "select", vazio: "(todos)", opcoes: listaParceiros }),
      el("button", { type: "submit", class: "botao" }, "Filtrar"));
    const area = el("div", { class: "area-dados" }, carregando());

    alvo.replaceChildren(
      cabecalhoPagina(m.titulo, m.descricao,
        el("button", { type: "button", class: "botao primario", onclick: novo }, `Nova ${m.singular.toLowerCase()}`)),
      filtros, area);

    async function carregar() {
      try {
        const f = { de: filtros.elements.de.value, ate: filtros.elements.ate.value,
                    parceiro: filtros.elements.parceiro.value === "" ? "" : Number(filtros.elements.parceiro.value) };
        const linhas = await m.listar(f);
        const soma = linhas.reduce((s, l) => s + Number(m.total(l) || 0), 0);
        area.replaceChildren(tabela({
          colunas: [
            { titulo: "Nº", valor: (l) => m.id(l) },
            { titulo: "Data", valor: (l) => m.data(l), tipo: "data" },
            { titulo: m.parceiro.rotulo, valor: (l) => m.nomeParceiro(l) },
            { titulo: "Itens", campo: "qtditens", tipo: "qtd" },
            { titulo: "Valor total", valor: (l) => m.total(l), tipo: "moeda" },
          ],
          linhas,
          acoes: [
            { rotulo: "Abrir", classe: "secundario", fn: (l) => irPara(`${m.rota}/${m.id(l)}`) },
            { rotulo: "Excluir", classe: "perigo-texto", fn: (l) => excluir(l) },
          ],
          rodape: linhas.length ? el("tr", {},
            el("td", { colspan: 4 }, `${linhas.length} registro(s)`),
            el("td", { class: "num" }, fmt.moeda(soma)), el("td")) : null,
        }));
      } catch (falha) {
        area.replaceChildren(caixaErro(falha));
      }
    }

    async function novo() {
      let campos;
      try { campos = await camposMovimento(m)(); } catch (falha) { avisar(falha.message, "erro"); return; }
      formularioModal({
        titulo: `Nova ${m.singular.toLowerCase()}`,
        campos,
        textoBotao: "Criar e lançar itens",
        aoSalvar: async (d) => {
          const id = await m.inserir(d);
          avisar(`${m.singular} nº ${id} criada.`, "ok");
          irPara(`${m.rota}/${id}`);
        },
      });
    }

    async function excluir(l) {
      if (!(await confirmar(`Excluir ${m.artigo} nº ${m.id(l)} e todos os seus itens? O estoque será ajustado.`))) return;
      try {
        await executarAcao(() => m.excluir(m.id(l)), `${m.singular} excluída.`);
        carregar();
      } catch { /* aviso já exibido */ }
    }

    filtros.addEventListener("submit", (e) => { e.preventDefault(); carregar(); });
    filtros.elements.parceiro.addEventListener("change", carregar);
    carregar();
  };
}

function telaMovimentoDetalhe(m) {
  return async function (alvo, id) {
    id = Number(id);
    alvo.replaceChildren(carregando());

    async function desenhar() {
      let cab, itens;
      try {
        [cab, itens] = await Promise.all([m.buscar(id), m.itens(id)]);
      } catch (falha) {
        alvo.replaceChildren(caixaErro(falha));
        return;
      }
      if (!cab) {
        alvo.replaceChildren(
          el("a", { class: "voltar", href: `#/${m.rota}` }, `← ${m.titulo}`),
          caixaErro(new Error(`${m.singular} nº ${id} não encontrada.`)));
        return;
      }

      const resumo = el("div", { class: "resumo" },
        el("div", {}, el("span", {}, m.parceiro.rotulo), el("strong", {}, m.nomeParceiro(cab)),
          m.detalheParceiro(cab) ? el("small", {}, m.detalheParceiro(cab)) : null),
        el("div", {}, el("span", {}, "Data"), el("strong", {}, fmt.data(m.data(cab)))),
        el("div", {}, el("span", {}, "Valor total"), el("strong", { class: "destaque" }, fmt.moeda(m.total(cab)))));

      alvo.replaceChildren(
        el("a", { class: "voltar", href: `#/${m.rota}` }, `← ${m.titulo}`),
        cabecalhoPagina(`${m.singular} nº ${id}`, null,
          el("button", { type: "button", class: "botao", onclick: () => editarCabecalho(cab) }, "Editar dados"),
          el("button", { type: "button", class: "botao perigo", onclick: excluirTudo }, `Excluir ${m.singular.toLowerCase()}`)),
        resumo,
        el("section", { class: "secao" },
          el("header", { class: "secao-cabecalho" },
            el("h2", {}, "Itens"),
            el("button", { type: "button", class: "botao primario", onclick: () => formItem() }, "Adicionar item")),
          tabela({
            colunas: m.item.colunas,
            linhas: itens,
            vazio: "Nenhum item lançado ainda. Use \"Adicionar item\".",
            acoes: [
              { rotulo: "Editar", fn: (i) => formItem(i) },
              { rotulo: "Excluir", classe: "perigo-texto", fn: (i) => excluirItem(i) },
            ],
            rodape: itens.length ? el("tr", {},
              el("td", { colspan: m.item.colunas.length - 1 }, "Total"),
              el("td", { class: "num" }, fmt.moeda(m.total(cab))), el("td")) : null,
          })));
    }

    async function editarCabecalho(cab) {
      let campos;
      try { campos = await camposMovimento(m)(); } catch (falha) { avisar(falha.message, "erro"); return; }
      campos[1] = { ...campos[1], obrigatorio: true, dica: undefined };
      formularioModal({
        titulo: `Editar ${m.singular.toLowerCase()} nº ${id}`,
        campos,
        valores: { [m.parceiro.nome]: m.idParceiro(cab), data: m.data(cab) },
        aoSalvar: async (d) => {
          await m.alterar(id, d);
          avisar("Dados atualizados.", "ok");
          desenhar();
        },
      });
    }

    async function excluirTudo() {
      if (!(await confirmar(`Excluir ${m.artigo} nº ${id} e todos os seus itens? O estoque será ajustado.`))) return;
      try {
        await executarAcao(() => m.excluir(id), `${m.singular} excluída.`);
        irPara(m.rota);
      } catch { /* aviso já exibido */ }
    }

    async function formItem(item) {
      let campos;
      try { campos = await m.item.campos(); } catch (falha) { avisar(falha.message, "erro"); return; }
      formularioModal({
        titulo: item ? "Editar item" : "Adicionar item",
        campos,
        valores: item ? m.item.valoresDe(item) : {},
        aoSalvar: async (d) => {
          if (item) await m.item.alterar(m.item.id(item), d);
          else await m.item.inserir(id, d);
          avisar(item ? "Item alterado." : "Item lançado.", "ok");
          desenhar();
        },
      });
    }

    async function excluirItem(item) {
      if (!(await confirmar(`Excluir o item "${item.prod_nome}"? O estoque será ajustado.`))) return;
      try {
        await executarAcao(() => m.item.excluir(m.item.id(item)), "Item excluído.");
        desenhar();
      } catch { /* aviso já exibido */ }
    }

    desenhar();
  };
}

const telaCompras = telaMovimentos(MOV.compras);
const telaCompraDetalhe = telaMovimentoDetalhe(MOV.compras);
const telaRequisicoes = telaMovimentos(MOV.requisicoes);
const telaRequisicaoDetalhe = telaMovimentoDetalhe(MOV.requisicoes);

/* =====================================================================
   Início
   ===================================================================== */
async function telaInicio(alvo) {
  alvo.replaceChildren(cabecalhoPagina("Início", "Resumo do estoque e da movimentação do mês."), carregando());
  try {
    const de = primeiroDiaDoMesISO();
    const ate = hojeISO();
    const [produtos, compras, requisicoes, ultimas] = await Promise.all([
      API.rpc("sp_produto_listar"),
      API.rpc("sp_compra_listar", { p_dataini: de, p_datafim: ate }),
      API.rpc("sp_requisicao_listar", { p_dataini: de, p_datafim: ate }),
      API.rpc("sp_compra_listar"),
    ]);
    const soma = (lista, f) => lista.reduce((s, l) => s + Number(l[f] || 0), 0);
    const semEstoque = produtos.filter((p) => Number(p.prod_qtdestoque) === 0);

    const cartao = (rotulo, valor, detalhe, rota) => el("a", { class: "cartao-numero", href: `#/${rota}` },
      el("span", {}, rotulo), el("strong", {}, valor), el("small", {}, detalhe));

    alvo.replaceChildren(
      cabecalhoPagina("Início", "Resumo do estoque e da movimentação do mês."),
      el("div", { class: "cartoes" },
        cartao("Produtos cadastrados", fmt.qtd(produtos.length), `${semEstoque.length} sem estoque`, "produtos"),
        cartao("Valor em estoque", fmt.moeda(soma(produtos, "valorestoque")), "pelo preço médio", "estoque"),
        cartao("Compras no mês", fmt.moeda(soma(compras, "compra_valortotal")), `${compras.length} compra(s)`, "compras"),
        cartao("Consumo no mês", fmt.moeda(soma(requisicoes, "req_valortotal")), `${requisicoes.length} requisição(ões)`, "requisicoes")),
      el("div", { class: "duas-colunas" },
        el("section", { class: "secao" },
          el("header", { class: "secao-cabecalho" }, el("h2", {}, "Últimas compras")),
          tabela({
            colunas: [
              { titulo: "Nº", campo: "compra_id" },
              { titulo: "Data", campo: "compra_data", tipo: "data" },
              { titulo: "Fornecedor", campo: "fornec_razaosocial" },
              { titulo: "Total", campo: "compra_valortotal", tipo: "moeda" },
            ],
            linhas: ultimas.slice(0, 5),
            vazio: "Nenhuma compra lançada.",
          })),
        el("section", { class: "secao" },
          el("header", { class: "secao-cabecalho" }, el("h2", {}, "Produtos sem estoque")),
          tabela({
            colunas: [{ titulo: "Produto", campo: "prod_nome" }, { titulo: "Grupo", campo: "grupoprod_nome" }],
            linhas: semEstoque.slice(0, 8),
            vazio: "Todos os produtos têm estoque.",
          }))));
  } catch (falha) {
    alvo.replaceChildren(cabecalhoPagina("Início"), caixaErro(falha));
  }
}

/* =====================================================================
   Consulta: produtos por grupo (necessidade b.vii)
   ===================================================================== */
async function telaEstoque(alvo) {
  let grupos = [];
  try { grupos = await opcoes.grupos(); } catch { /* a tabela mostra o erro */ }
  const filtro = campo({ nome: "grupo", rotulo: "Grupo", tipo: "select", vazio: "(todos os grupos)", opcoes: grupos });
  const area = el("div", { class: "area-dados" }, carregando());
  alvo.replaceChildren(
    cabecalhoPagina("Estoque por grupo", "Produtos separados por grupo, com saldo, preço médio e valor em estoque.",
      el("button", { type: "button", class: "botao", onclick: () => window.print() }, "Imprimir")),
    el("div", { class: "barra-filtros" }, filtro),
    el("p", { class: "so-impressao" }, `Emitido em ${new Date().toLocaleString("pt-BR")}`),
    area);

  async function carregar() {
    try {
      const g = filtro.querySelector("select").value;
      const linhas = await API.rpc("sp_produto_listarporgrupo", { p_grupoprod_id: g === "" ? "" : Number(g) });
      const total = linhas.filter((l) => l.prod_id === null).reduce((s, l) => s + Number(l.valorestoque || 0), 0);
      area.replaceChildren(tabela({
        colunas: [
          { titulo: "Grupo", valor: (l) => (l.prod_id === null ? "" : l.grupoprod_nome) },
          { titulo: "Produto", campo: "prod_nome" },
          { titulo: "Estoque", campo: "prod_qtdestoque", tipo: "qtd" },
          { titulo: "Preço médio", campo: "prod_precomedio", tipo: "moeda" },
          { titulo: "Valor em estoque", campo: "valorestoque", tipo: "moeda" },
        ],
        linhas,
        classeLinha: (l) => (l.prod_id === null ? "linha-total" : ""),
        rodape: linhas.length ? el("tr", {}, el("td", { colspan: 4 }, "Total geral"), el("td", { class: "num" }, fmt.moeda(total))) : null,
      }));
    } catch (falha) {
      area.replaceChildren(caixaErro(falha));
    }
  }
  filtro.querySelector("select").addEventListener("change", carregar);
  carregar();
}

/* =====================================================================
   Relatórios gerenciais (item c do enunciado)
   ===================================================================== */
function telaRelatorio({ titulo, descricao, filtros, gerar, gerarAoAbrir = true }) {
  return async function (alvo, parametro) {
    let defs;
    try {
      defs = await filtros(parametro);
    } catch (falha) {
      alvo.replaceChildren(cabecalhoPagina(titulo, descricao), caixaErro(falha));
      return;
    }
    const form = el("form", { class: "barra-filtros" },
      defs.map((d) => campo(d, d.inicial)),
      el("button", { type: "submit", class: "botao primario" }, "Gerar"));
    const area = el("div", { class: "area-dados" });
    const emitido = el("p", { class: "so-impressao" });

    alvo.replaceChildren(
      cabecalhoPagina(titulo, descricao,
        el("button", { type: "button", class: "botao", onclick: () => window.print() }, "Imprimir")),
      form, emitido, area);

    async function executar() {
      if (!form.reportValidity()) return;
      area.replaceChildren(carregando());
      try {
        const valores = lerFormulario(form, defs);
        emitido.textContent = `Emitido em ${new Date().toLocaleString("pt-BR")}`;
        area.replaceChildren(...[].concat(await gerar(valores)));
      } catch (falha) {
        area.replaceChildren(caixaErro(falha));
      }
    }
    form.addEventListener("submit", (e) => { e.preventDefault(); executar(); });
    if (gerarAoAbrir && defs.every((d) => !d.obrigatorio || d.inicial)) executar();
  };
}

const filtrosPeriodo = () => [
  { nome: "de", rotulo: "De", tipo: "data" },
  { nome: "ate", rotulo: "Até", tipo: "data" },
];

const telaRelConsumo = telaRelatorio({
  titulo: "Consumo por setor",
  descricao: "Quantidade e valor de material consumido por cada setor, com total por setor.",
  filtros: async () => [
    ...filtrosPeriodo(),
    { nome: "setor", rotulo: "Setor", tipo: "select", vazio: "(todos)", opcoes: await opcoes.setores() },
  ],
  gerar: async (f) => {
    const linhas = await API.rpc("sp_rel_consumoporsetor", { p_dataini: f.de, p_datafim: f.ate, p_setor_id: f.setor });
    const total = linhas.filter((l) => l.prod_id === null).reduce((s, l) => s + Number(l.valorconsumido || 0), 0);
    return tabela({
      colunas: [
        { titulo: "Setor", valor: (l) => (l.prod_id === null ? "" : l.setor_nome) },
        { titulo: "Produto", valor: (l) => (l.prod_id === null ? `Total ${l.setor_nome}` : l.prod_nome) },
        { titulo: "Quantidade", campo: "qtdconsumida", tipo: "qtd" },
        { titulo: "Valor consumido", campo: "valorconsumido", tipo: "moeda" },
      ],
      linhas,
      classeLinha: (l) => (l.prod_id === null ? "linha-total" : ""),
      vazio: "Nenhuma requisição no período.",
      rodape: linhas.length ? el("tr", {}, el("td", { colspan: 3 }, "Total geral"), el("td", { class: "num" }, fmt.moeda(total))) : null,
    });
  },
});

const telaRelFicha = telaRelatorio({
  titulo: "Ficha do produto",
  descricao: "Todas as entradas e saídas do produto, com o saldo depois de cada movimento.",
  filtros: async (prodId) => [
    { nome: "produto", rotulo: "Produto", tipo: "select", obrigatorio: true, vazio: "Selecione…",
      opcoes: await opcoes.produtos(), inicial: prodId },
    ...filtrosPeriodo(),
  ],
  gerar: async (f) => {
    const [produto, linhas] = await Promise.all([
      API.rpc("sp_produto_buscar", { p_prod_id: f.produto }).then((r) => r[0]),
      API.rpc("sp_rel_fichaproduto", { p_prod_id: f.produto, p_dataini: f.de, p_datafim: f.ate }),
    ]);
    return [
      el("div", { class: "resumo" },
        el("div", {}, el("span", {}, "Produto"), el("strong", {}, produto.prod_nome), el("small", {}, produto.grupoprod_nome)),
        el("div", {}, el("span", {}, "Estoque atual"), el("strong", {}, fmt.qtd(produto.prod_qtdestoque))),
        el("div", {}, el("span", {}, "Preço médio"), el("strong", {}, fmt.moeda(produto.prod_precomedio))),
        el("div", {}, el("span", {}, "Última compra"),
          el("strong", {}, Number(produto.prod_qtdultcompra) > 0
            ? `${fmt.qtd(produto.prod_qtdultcompra)} × ${fmt.moeda(produto.prod_valorultcompra)}` : "—"))),
      tabela({
        colunas: [
          { titulo: "Data", campo: "data", tipo: "data" },
          { titulo: "Tipo", valor: (l) => el("span", { class: `etiqueta ${l.tipo === "ENTRADA" ? "entrada" : "saida"}` }, l.tipo === "ENTRADA" ? "Entrada" : "Saída") },
          { titulo: "Documento", valor: (l) => `${l.tipo === "ENTRADA" ? "Compra" : "Requisição"} nº ${l.documento}` },
          { titulo: "Fornecedor / setor", campo: "origemdestino" },
          { titulo: "Entrada", valor: (l) => (Number(l.qtdentrada) ? l.qtdentrada : ""), tipo: "qtd" },
          { titulo: "Saída", valor: (l) => (Number(l.qtdsaida) ? l.qtdsaida : ""), tipo: "qtd" },
          { titulo: "Valor unitário", campo: "valoruni", tipo: "moeda" },
          { titulo: "Valor total", campo: "valortotal", tipo: "moeda" },
          { titulo: "Saldo", campo: "saldo", tipo: "qtd", classe: () => "forte" },
        ],
        linhas,
        vazio: "Nenhum movimento no período.",
      }),
    ];
  },
});

const telaRelPreco = telaRelatorio({
  titulo: "Evolução do preço de compra",
  descricao: "Cada compra do produto com a variação em relação à compra anterior, e o resumo por mês.",
  filtros: async (prodId) => [
    { nome: "produto", rotulo: "Produto", tipo: "select", obrigatorio: true, vazio: "Selecione…",
      opcoes: await opcoes.produtos(), inicial: prodId },
    ...filtrosPeriodo(),
  ],
  gerar: async (f) => {
    const p = { p_prod_id: f.produto, p_dataini: f.de, p_datafim: f.ate };
    const [compras, meses] = await Promise.all([
      API.rpc("sp_rel_evolucaoprecocompra", p),
      API.rpc("sp_rel_evolucaoprecomensal", p),
    ]);
    const sinal = (v) => (v === null ? "" : Number(v) > 0 ? "sobe" : Number(v) < 0 ? "desce" : "");
    return [
      tabela({
        colunas: [
          { titulo: "Data", campo: "compra_data", tipo: "data" },
          { titulo: "Compra", valor: (l) => `nº ${l.compra_id}` },
          { titulo: "Fornecedor", campo: "fornec_razaosocial" },
          { titulo: "Quantidade", campo: "itemcompra_qtd", tipo: "qtd" },
          { titulo: "Valor unitário", campo: "itemcompra_valoruni", tipo: "moeda" },
          { titulo: "Valor anterior", campo: "valoranterior", tipo: "moeda" },
          { titulo: "Variação", campo: "variacaopercentual", tipo: "pct", classe: (l) => sinal(l.variacaopercentual) },
        ],
        linhas: compras,
        vazio: "Nenhuma compra do produto no período.",
      }),
      el("h2", { class: "subtitulo" }, "Resumo por mês"),
      tabela({
        colunas: [
          { titulo: "Mês", valor: (l) => fmt.mesAno(l.ano, l.mes) },
          { titulo: "Compras", campo: "qtdcompras", tipo: "qtd" },
          { titulo: "Quantidade", campo: "qtdcomprada", tipo: "qtd" },
          { titulo: "Menor preço", campo: "menorpreco", tipo: "moeda" },
          { titulo: "Maior preço", campo: "maiorpreco", tipo: "moeda" },
          { titulo: "Média ponderada", campo: "precomedioponderado", tipo: "moeda" },
        ],
        linhas: meses,
        vazio: "Nenhuma compra no período.",
      }),
    ];
  },
});

const telaRelMenorPreco = telaRelatorio({
  titulo: "Fornecedor e menor preço",
  descricao: "Para cada produto, o fornecedor que vendeu pelo menor preço (empates aparecem todos).",
  filtros: async () => [
    { nome: "produto", rotulo: "Produto", tipo: "select", vazio: "(todos)", opcoes: await opcoes.produtos() },
    ...filtrosPeriodo(),
  ],
  gerar: async (f) => tabela({
    colunas: [
      { titulo: "Produto", campo: "prod_nome" },
      { titulo: "Fornecedor", campo: "fornec_razaosocial" },
      { titulo: "Menor preço", campo: "menorpreco", tipo: "moeda", classe: () => "forte" },
      { titulo: "Data da compra", campo: "compra_data", tipo: "data" },
      { titulo: "Compra", valor: (l) => `nº ${l.compra_id}` },
      { titulo: "Preço médio atual", campo: "prod_precomedio", tipo: "moeda" },
      { titulo: "Última compra", campo: "prod_valorultcompra", tipo: "moeda" },
    ],
    linhas: await API.rpc("sp_rel_menorprecofornecedor", { p_prod_id: f.produto, p_dataini: f.de, p_datafim: f.ate }),
    vazio: "Nenhuma compra no período.",
  }),
});
