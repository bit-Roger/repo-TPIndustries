/*
 * Peças de interface reaproveitadas pelas telas:
 * criação de elementos, formatação, tabelas, formulários, modal e avisos.
 * Textos vindos do banco sempre entram como texto (textContent), nunca
 * como HTML.
 */

/* ---------- criação de elementos ---------- */
function el(tag, atributos = {}, ...filhos) {
  const elemento = document.createElement(tag);
  for (const [chave, valor] of Object.entries(atributos || {})) {
    if (valor === undefined || valor === null || valor === false) continue;
    if (chave === "class") elemento.className = valor;
    else if (chave === "dataset") Object.assign(elemento.dataset, valor);
    else if (chave.startsWith("on") && typeof valor === "function") {
      elemento.addEventListener(chave.slice(2), valor);
    } else if (valor === true) elemento.setAttribute(chave, "");
    else elemento.setAttribute(chave, valor);
  }
  for (const filho of filhos.flat()) {
    if (filho === undefined || filho === null || filho === false) continue;
    elemento.append(filho instanceof Node ? filho : document.createTextNode(String(filho)));
  }
  return elemento;
}

/* ---------- formatação (padrão brasileiro) ---------- */
const fmt = {
  moeda(v) {
    if (v === null || v === undefined || v === "") return "";
    return Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  },
  qtd(v) {
    if (v === null || v === undefined || v === "") return "";
    return Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 3 });
  },
  pct(v) {
    if (v === null || v === undefined || v === "") return "";
    const n = Number(v);
    const sinal = n > 0 ? "+" : "";
    return sinal + n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + "%";
  },
  // "2026-09-15T08:30:00" -> "15/09/2026 08:30" (sem conversão de fuso)
  data(v, comHora = true) {
    if (!v) return "";
    const [d, h = ""] = String(v).split(/[T ]/);
    const [ano, mes, dia] = d.split("-");
    const hora = h.slice(0, 5);
    return `${dia}/${mes}/${ano}` + (comHora && hora && hora !== "00:00" ? ` ${hora}` : "");
  },
  // valor para <input type="datetime-local">
  paraInputDataHora(v) {
    if (!v) return "";
    return String(v).replace(" ", "T").slice(0, 16);
  },
  cnpj(v) {
    const d = String(v || "").replace(/\D/g, "");
    if (d.length !== 14) return v || "";
    return d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
  },
  mesAno(ano, mes) {
    const nomes = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];
    return `${nomes[mes - 1]}/${ano}`;
  },
};

function hojeISO() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function primeiroDiaDoMesISO() {
  return hojeISO().slice(0, 8) + "01";
}

/* ---------- avisos (toasts) ---------- */
function avisar(mensagem, tipo = "ok") {
  const caixa = document.getElementById("avisos");
  const aviso = el("div", { class: `aviso aviso-${tipo}`, role: tipo === "erro" ? "alert" : "status" }, mensagem);
  caixa.append(aviso);
  setTimeout(() => aviso.classList.add("saindo"), tipo === "erro" ? 6000 : 3200);
  setTimeout(() => aviso.remove(), tipo === "erro" ? 6400 : 3600);
}

/* ---------- tabela ----------
   colunas: [{ titulo, campo | valor(linha), tipo: texto|qtd|moeda|data|pct|cnpj, classe(linha) }]
   acoes:   [{ rotulo, classe, fn(linha), mostrar(linha) }]                                   */
function tabela({ colunas, linhas, acoes = [], classeLinha, vazio = "Nenhum registro encontrado.", rodape }) {
  const numericos = new Set(["qtd", "moeda", "pct"]);
  const cabecalho = el("tr", {},
    colunas.map((c) => el("th", { class: numericos.has(c.tipo) ? "num" : "" }, c.titulo)),
    acoes.length ? el("th", { class: "acoes" }, "") : null);

  const corpo = el("tbody");
  if (!linhas || linhas.length === 0) {
    corpo.append(el("tr", {}, el("td", { colspan: colunas.length + (acoes.length ? 1 : 0), class: "vazio" }, vazio)));
  } else {
    for (const linha of linhas) {
      const tr = el("tr", { class: classeLinha ? classeLinha(linha) : "" });
      for (const c of colunas) {
        const bruto = c.valor ? c.valor(linha) : linha[c.campo];
        let conteudo = bruto;
        if (!(bruto instanceof Node)) {
          if (c.tipo === "qtd") conteudo = fmt.qtd(bruto);
          else if (c.tipo === "moeda") conteudo = fmt.moeda(bruto);
          else if (c.tipo === "data") conteudo = fmt.data(bruto);
          else if (c.tipo === "pct") conteudo = fmt.pct(bruto);
          else if (c.tipo === "cnpj") conteudo = fmt.cnpj(bruto);
        }
        const classes = [numericos.has(c.tipo) ? "num" : "", c.classe ? c.classe(linha) : ""].join(" ").trim();
        tr.append(el("td", { class: classes }, conteudo ?? ""));
      }
      if (acoes.length) {
        tr.append(el("td", { class: "acoes" },
          acoes.filter((a) => !a.mostrar || a.mostrar(linha))
            .map((a) => el("button", { type: "button", class: `botao pequeno ${a.classe || "fantasma"}`, onclick: () => a.fn(linha) }, a.rotulo))));
      }
      corpo.append(tr);
    }
  }
  const tabelaEl = el("table", { class: "tabela" }, el("thead", {}, cabecalho), corpo);
  if (rodape) tabelaEl.append(el("tfoot", {}, rodape));
  return el("div", { class: "tabela-rolagem" }, tabelaEl);
}

/* ---------- campos de formulário ----------
   { nome, rotulo, tipo: texto|numero|data|datahora|select|cnpj, obrigatorio, opcoes:[{valor,texto}],
     passo, min, dica, vazio (texto da opção vazia do select), largura: "inteira" }            */
function campo(def, valor) {
  let entrada;
  const comum = { name: def.nome, id: `campo-${def.nome}`, required: def.obrigatorio || undefined };
  if (def.tipo === "select") {
    entrada = el("select", comum,
      (def.vazio !== undefined || !def.obrigatorio) ? el("option", { value: "" }, def.vazio ?? "(todos)") : null,
      (def.opcoes || []).map((o) => el("option", { value: o.valor }, o.texto)));
    if (valor !== undefined && valor !== null) entrada.value = String(valor);
  } else {
    const tipos = { texto: "text", numero: "number", data: "date", datahora: "datetime-local", cnpj: "text" };
    entrada = el("input", {
      ...comum,
      type: tipos[def.tipo] || "text",
      step: def.passo,
      min: def.min,
      maxlength: def.max,
      inputmode: def.tipo === "cnpj" ? "numeric" : undefined,
      placeholder: def.placeholder,
      autocomplete: "off",
    });
    if (valor !== undefined && valor !== null) {
      entrada.value = def.tipo === "datahora" ? fmt.paraInputDataHora(valor)
        : def.tipo === "cnpj" ? fmt.cnpj(valor) : valor;
    }
    if (def.tipo === "cnpj") {
      entrada.addEventListener("input", () => {
        const d = entrada.value.replace(/\D/g, "").slice(0, 14);
        let m = d;
        if (d.length > 12) m = d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{0,2})$/, "$1.$2.$3/$4-$5");
        else if (d.length > 8) m = d.replace(/^(\d{2})(\d{3})(\d{3})(\d{0,4})$/, "$1.$2.$3/$4");
        else if (d.length > 5) m = d.replace(/^(\d{2})(\d{3})(\d{0,3})$/, "$1.$2.$3");
        else if (d.length > 2) m = d.replace(/^(\d{2})(\d{0,3})$/, "$1.$2");
        entrada.value = m;
      });
    }
  }
  return el("label", { class: `campo ${def.largura === "inteira" ? "inteira" : ""}`, for: comum.id },
    el("span", {}, def.rotulo, def.obrigatorio ? el("b", { class: "obrigatorio", "aria-hidden": "true" }, " *") : null),
    entrada,
    def.dica ? el("small", {}, def.dica) : null);
}

function lerFormulario(form, defs) {
  const dados = {};
  for (const def of defs) {
    const entrada = form.elements[def.nome];
    if (!entrada) continue;
    let v = entrada.value.trim();
    if (def.tipo === "numero" && v !== "") v = Number(v.replace(",", "."));
    if (def.tipo === "select" && v !== "" && def.numerico !== false) v = Number(v);
    dados[def.nome] = v;
  }
  return dados;
}

/* ---------- modal ---------- */
const modal = {
  abrir(conteudo) {
    const dlg = document.getElementById("modal");
    dlg.replaceChildren(conteudo);
    if (!dlg.open) dlg.showModal();
    const primeiro = dlg.querySelector("input, select, button.primario");
    if (primeiro) primeiro.focus();
  },
  fechar() {
    const dlg = document.getElementById("modal");
    if (dlg.open) dlg.close();
    dlg.replaceChildren();
  },
};

// Formulário em modal. aoSalvar(dados) pode lançar erro: ele aparece no próprio modal.
function formularioModal({ titulo, campos, valores = {}, textoBotao = "Salvar", aoSalvar, extra }) {
  const erro = el("p", { class: "erro", hidden: true });
  const botaoSalvar = el("button", { type: "submit", class: "botao primario" }, textoBotao);
  const form = el("form", { class: "form-modal", novalidate: false },
    el("header", {}, el("h2", {}, titulo)),
    el("div", { class: "grade-campos" }, campos.map((c) => campo(c, valores[c.nome]))),
    extra || null,
    erro,
    el("footer", {},
      el("button", { type: "button", class: "botao fantasma", onclick: () => modal.fechar() }, "Cancelar"),
      botaoSalvar));

  form.addEventListener("submit", async (evento) => {
    evento.preventDefault();
    erro.hidden = true;
    botaoSalvar.disabled = true;
    botaoSalvar.textContent = "Salvando…";
    try {
      await aoSalvar(lerFormulario(form, campos), form);
      modal.fechar();
    } catch (falha) {
      erro.textContent = falha.message;
      erro.hidden = false;
    } finally {
      botaoSalvar.disabled = false;
      botaoSalvar.textContent = textoBotao;
    }
  });
  modal.abrir(form);
  return form;
}

function confirmar(mensagem, { textoBotao = "Excluir", perigo = true } = {}) {
  return new Promise((resolver) => {
    const fechar = (resposta) => { modal.fechar(); resolver(resposta); };
    modal.abrir(el("div", { class: "form-modal" },
      el("header", {}, el("h2", {}, "Confirmar")),
      el("p", {}, mensagem),
      el("footer", {},
        el("button", { type: "button", class: "botao fantasma", onclick: () => fechar(false) }, "Cancelar"),
        el("button", { type: "button", class: `botao ${perigo ? "perigo" : "primario"}`, onclick: () => fechar(true) }, textoBotao))));
    document.getElementById("modal").addEventListener("cancel", () => resolver(false), { once: true });
  });
}

/* ---------- blocos de página ---------- */
function cabecalhoPagina(titulo, descricao, ...botoes) {
  return el("header", { class: "cabecalho-pagina" },
    el("div", {}, el("h1", {}, titulo), descricao ? el("p", { class: "sutil" }, descricao) : null),
    botoes.length ? el("div", { class: "botoes" }, botoes) : null);
}

function carregando() {
  return el("div", { class: "carregando" }, el("span", { class: "giro", "aria-hidden": "true" }), "Carregando…");
}

function caixaErro(falha) {
  return el("div", { class: "caixa-erro", role: "alert" }, falha.message || String(falha));
}

// Executa uma operação de gravação mostrando o resultado num aviso
async function executarAcao(fn, mensagemOk) {
  try {
    const r = await fn();
    if (mensagemOk) avisar(mensagemOk, "ok");
    return r;
  } catch (falha) {
    avisar(falha.message, "erro");
    throw falha;
  }
}
