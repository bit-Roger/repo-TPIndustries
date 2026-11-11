/*
 * Inicialização: login, menu e navegação entre as telas.
 * As rotas ficam no endereço depois do #, por exemplo:
 *   index.html#/produtos      index.html#/compras/5      index.html#/ficha/2
 */
const MENU = [
  { grupo: null, itens: [{ rota: "inicio", texto: "Início", tela: telaInicio }] },
  { grupo: "Cadastros", itens: [
    { rota: "grupos", texto: "Grupos de produto", tela: telaGrupos },
    { rota: "produtos", texto: "Produtos", tela: telaProdutos },
    { rota: "setores", texto: "Setores", tela: telaSetores },
    { rota: "fornecedores", texto: "Fornecedores", tela: telaFornecedores },
  ] },
  { grupo: "Movimentação", itens: [
    { rota: "compras", texto: "Compras", tela: telaCompras, detalhe: telaCompraDetalhe },
    { rota: "requisicoes", texto: "Requisições", tela: telaRequisicoes, detalhe: telaRequisicaoDetalhe },
  ] },
  { grupo: "Consultas", itens: [
    { rota: "estoque", texto: "Estoque por grupo", tela: telaEstoque },
  ] },
  { grupo: "Relatórios", itens: [
    { rota: "consumo", texto: "Consumo por setor", tela: telaRelConsumo },
    { rota: "ficha", texto: "Ficha do produto", tela: telaRelFicha, detalhe: telaRelFicha },
    { rota: "preco", texto: "Evolução do preço", tela: telaRelPreco, detalhe: telaRelPreco },
    { rota: "menor-preco", texto: "Fornecedor e menor preço", tela: telaRelMenorPreco },
  ] },
];

const ROTAS = Object.fromEntries(MENU.flatMap((g) => g.itens).map((i) => [i.rota, i]));

function mostrar(id) {
  for (const tela of ["tela-carregando", "tela-config", "tela-login", "app"]) {
    document.getElementById(tela).hidden = tela !== id;
  }
}

function montarMenu() {
  const nav = document.getElementById("nav");
  nav.replaceChildren(...MENU.map((g) => el("div", { class: "nav-grupo" },
    g.grupo ? el("span", { class: "nav-titulo" }, g.grupo) : null,
    g.itens.map((i) => el("a", { href: `#/${i.rota}`, dataset: { rota: i.rota } }, i.texto)))));
}

async function navegar() {
  const [rota = "inicio", parametro] = location.hash.replace(/^#\/?/, "").split("/");
  const item = ROTAS[rota] || ROTAS.inicio;
  for (const a of document.querySelectorAll("#nav a")) {
    a.classList.toggle("ativo", a.dataset.rota === item.rota);
  }
  const conteudo = document.getElementById("conteudo");
  modal.fechar();
  const tela = parametro && item.detalhe ? item.detalhe : item.tela;
  await tela(conteudo, parametro);
  conteudo.focus({ preventScroll: true });
  window.scrollTo(0, 0);
}

async function entrarNoSistema(sessao) {
  document.getElementById("usuario-email").textContent = sessao.user.email || "";
  mostrar("app");
  await navegar();
}

function configurarLogin() {
  const form = document.getElementById("form-login");
  const erro = document.getElementById("login-erro");
  form.addEventListener("submit", async (evento) => {
    evento.preventDefault();
    erro.hidden = true;
    const botao = form.querySelector("button");
    botao.disabled = true;
    botao.textContent = "Entrando…";
    const { data, error } = await API.auth.signInWithPassword({
      email: form.elements.email.value.trim(),
      password: form.elements.senha.value,
    });
    botao.disabled = false;
    botao.textContent = "Entrar";
    if (error) {
      erro.textContent = /invalid/i.test(error.message)
        ? "E-mail ou senha incorretos."
        : `Não foi possível entrar: ${error.message}`;
      erro.hidden = false;
      return;
    }
    form.reset();
    entrarNoSistema(data.session);
  });

  document.getElementById("botao-sair").addEventListener("click", async () => {
    await API.auth.signOut();
    mostrar("tela-login");
  });
}

async function iniciar() {
  if (!API.configurado()) {
    mostrar("tela-config");
    return;
  }
  try {
    API.iniciar();
  } catch (falha) {
    mostrar("tela-config");
    document.querySelector("#tela-config p").textContent = falha.message;
    return;
  }
  montarMenu();
  configurarLogin();
  window.addEventListener("hashchange", () => { if (!document.getElementById("app").hidden) navegar(); });

  const { data } = await API.auth.getSession();
  if (data.session) entrarNoSistema(data.session);
  else mostrar("tela-login");

  API.auth.onAuthStateChange((evento) => {
    if (evento === "SIGNED_OUT") mostrar("tela-login");
  });
}

iniciar().catch((falha) => {
  mostrar("tela-carregando");
  document.getElementById("carregando-texto").textContent = `Não foi possível iniciar: ${falha.message}`;
});
