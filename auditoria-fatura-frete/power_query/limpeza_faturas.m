// =============================================================================
// POWER QUERY (M) - Limpeza e padronização das faturas de frete
//
// Como usar no Excel (ou Power BI):
//   1. Dados > Obter Dados > Consulta em Branco > Editor Avançado
//   2. Crie UMA consulta para cada bloco abaixo, com o NOME indicado em "CONSULTA:"
//      (cole só o código do bloco; os nomes importam porque uma consulta chama a outra)
//   3. Na consulta Param_CaminhoPasta, troque o caminho pela pasta dados\brutos no seu PC
//   4. Marque como "Somente Conexão": Param_CaminhoPasta, fnLerCsv,
//      DePara_Transportadoras, DePara_Cidades e Rotas
//   5. Carregue para planilhas: Faturas_Limpas (para analisar no Excel/Power BI)
//      e Faturas_Para_SQL (para exportar como CSV e alimentar o banco)
//
// Problemas de qualidade que esta limpeza resolve:
//   - linhas totalmente em branco
//   - espaços sobrando no começo/fim dos textos
//   - nome da transportadora escrito de várias formas (maiúscula, sem acento, abreviado...)
//   - cidades escritas de várias formas ("Campinas/SP", "CAMPINAS-SP", "campinas - sp"...)
//   - datas em dois formatos (dd/mm/aaaa e aaaa-mm-dd)
//   - peso como texto, às vezes com " kg" ("1.234,5 kg")
//   - valor como texto, às vezes com "R$" ("R$ 1.234,56")
//   - faturas reenviadas (linhas 100% repetidas)
//   - identificação da rota (rota_id) a partir de origem + destino
// =============================================================================


// -----------------------------------------------------------------------------
// CONSULTA: Param_CaminhoPasta      (tipo: Parâmetro, texto)
// -----------------------------------------------------------------------------
"C:\projetos\auditoria-fatura-frete\dados\brutos\" meta [IsParameterQuery = true, IsParameterQueryRequired = true, Type = "Text"]


// -----------------------------------------------------------------------------
// CONSULTA: fnLerCsv                (função: lê um CSV da pasta e deixa tudo como texto)
// Por que tudo como texto? Porque o Excel "adivinha" tipos e erra com datas
// e números em formato brasileiro. Aqui nós convertemos com regras explícitas.
// -----------------------------------------------------------------------------
(nomeArquivo as text) as table =>
let
    Caminho = Param_CaminhoPasta & nomeArquivo,
    Fonte = Csv.Document(File.Contents(Caminho), [Delimiter = ";", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Cabecalho = Table.PromoteHeaders(Fonte, [PromoteAllScalars = true]),
    TudoTexto = Table.TransformColumnTypes(Cabecalho, List.Transform(Table.ColumnNames(Cabecalho), each {_, type text}))
in
    TudoTexto


// -----------------------------------------------------------------------------
// CONSULTA: DePara_Transportadoras
// Tabela "como veio" -> "nome padrão". A chave é guardada em MAIÚSCULAS e sem espaços
// nas pontas, assim a busca não depende de como a transportadora digitou.
// -----------------------------------------------------------------------------
let
    Fonte = fnLerCsv("de_para_transportadoras.csv"),
    ChaveMaiuscula = Table.TransformColumns(Fonte, {{"variacao", each Text.Upper(Text.Trim(_)), type text}})
in
    ChaveMaiuscula


// -----------------------------------------------------------------------------
// CONSULTA: DePara_Cidades
// -----------------------------------------------------------------------------
let
    Fonte = fnLerCsv("de_para_cidades.csv"),
    ChaveMaiuscula = Table.TransformColumns(Fonte, {{"variacao", each Text.Upper(Text.Trim(_)), type text}})
in
    ChaveMaiuscula


// -----------------------------------------------------------------------------
// CONSULTA: Rotas
// -----------------------------------------------------------------------------
let
    Fonte = fnLerCsv("rotas.csv")
in
    Fonte


// -----------------------------------------------------------------------------
// CONSULTA: Faturas_Limpas          (a consulta principal)
// -----------------------------------------------------------------------------
let
    // 1) Ler o arquivo bruto (tudo texto)
    Fonte = fnLerCsv("faturas_brutas.csv"),

    // 2) Remover linhas em branco (sem número de fatura)
    SemLinhasVazias = Table.SelectRows(Fonte, each [numero_fatura] <> null and Text.Trim([numero_fatura]) <> ""),

    // 3) Tirar espaços e caracteres invisíveis de TODAS as colunas
    TextoLimpo = Table.TransformColumns(
        SemLinhasVazias,
        List.Transform(Table.ColumnNames(SemLinhasVazias), each {_, each Text.Trim(Text.Clean(_)), type text})
    ),

    // 4) Chaves de busca em maiúsculas (transportadora, origem e destino)
    Maiusculas = Table.TransformColumns(
        TextoLimpo,
        {{"transportadora", Text.Upper, type text}, {"origem", Text.Upper, type text}, {"destino", Text.Upper, type text}}
    ),

    // 5) Padronizar nomes usando as tabelas de-para (mesclar consultas = PROCV do Power Query)
    JuntaTransp = Table.NestedJoin(Maiusculas, {"transportadora"}, DePara_Transportadoras, {"variacao"}, "dp_transp", JoinKind.LeftOuter),
    ExpandeTransp = Table.ExpandTableColumn(JuntaTransp, "dp_transp", {"nome_padrao"}, {"transportadora_padrao"}),

    JuntaOrigem = Table.NestedJoin(ExpandeTransp, {"origem"}, DePara_Cidades, {"variacao"}, "dp_origem", JoinKind.LeftOuter),
    ExpandeOrigem = Table.ExpandTableColumn(JuntaOrigem, "dp_origem", {"cidade_padrao"}, {"origem_padrao"}),

    JuntaDestino = Table.NestedJoin(ExpandeOrigem, {"destino"}, DePara_Cidades, {"variacao"}, "dp_destino", JoinKind.LeftOuter),
    ExpandeDestino = Table.ExpandTableColumn(JuntaDestino, "dp_destino", {"cidade_padrao"}, {"destino_padrao"}),

    // 6) Data: tenta dd/mm/aaaa; se não der certo, tenta aaaa-mm-dd
    ComData = Table.AddColumn(
        ExpandeDestino, "data_emissao_dt",
        each try Date.FromText([data_emissao], [Format = "dd/MM/yyyy", Culture = "pt-BR"])
             otherwise Date.FromText([data_emissao], [Format = "yyyy-MM-dd", Culture = "en-US"]),
        type date
    ),

    // 7) Peso: tira o "kg" e converte o número no formato brasileiro (1.234,5)
    ComPeso = Table.AddColumn(
        ComData, "peso_num",
        each Number.FromText(Text.Trim(Text.Replace(Text.Lower([peso_kg]), "kg", "")), "pt-BR"),
        type number
    ),

    // 8) Valor: tira o "R$" e converte
    ComValor = Table.AddColumn(
        ComPeso, "valor_num",
        each Number.FromText(Text.Trim(Text.Replace([valor_cobrado], "R$", "")), "pt-BR"),
        type number
    ),

    // 9) Descobrir o rota_id a partir de origem + destino (já padronizados)
    JuntaRota = Table.NestedJoin(ComValor, {"origem_padrao", "destino_padrao"}, Rotas, {"origem", "destino"}, "rt", JoinKind.LeftOuter),
    ExpandeRota = Table.ExpandTableColumn(JuntaRota, "rt", {"rota_id"}),

    // 10) Ficar só com as colunas finais, com os nomes definitivos
    Selecionadas = Table.SelectColumns(
        ExpandeRota,
        {"numero_fatura", "cte", "transportadora_padrao", "data_emissao_dt", "origem_padrao", "destino_padrao", "rota_id", "peso_num", "valor_num"}
    ),
    Renomeadas = Table.RenameColumns(
        Selecionadas,
        {{"transportadora_padrao", "transportadora"}, {"data_emissao_dt", "data_emissao"}, {"origem_padrao", "origem"},
         {"destino_padrao", "destino"}, {"peso_num", "peso_kg"}, {"valor_num", "valor_cobrado"}}
    ),

    // 11) Remover linhas 100% repetidas (fatura reenviada).
    //     Atenção: NÃO remover por CT-e! Mesmo CT-e em faturas diferentes é cobrança em duplicidade,
    //     e isso é justamente o que a auditoria em SQL precisa enxergar.
    SemRepetidas = Table.Distinct(Renomeadas),

    // 12) Tipos finais
    Tipado = Table.TransformColumnTypes(
        SemRepetidas,
        {{"numero_fatura", type text}, {"cte", type text}, {"transportadora", type text}, {"data_emissao", type date},
         {"origem", type text}, {"destino", type text}, {"rota_id", type text}, {"peso_kg", type number}, {"valor_cobrado", Currency.Type}}
    )
in
    Tipado


// -----------------------------------------------------------------------------
// CONSULTA: Checagem_Qualidade      (opcional, mas mostra cuidado com o dado)
// Conta quantas linhas ficaram com algum campo importante vazio.
// Se der mais que zero: falta uma variação no de-para ou há um formato novo.
// -----------------------------------------------------------------------------
let
    Fonte = Faturas_Limpas,
    Problemas = Table.SelectRows(
        Fonte,
        each [transportadora] = null or [rota_id] = null
             or (try [data_emissao] = null otherwise true)
             or (try [peso_kg] = null otherwise true)
             or (try [valor_cobrado] = null otherwise true)
    )
in
    Problemas


// -----------------------------------------------------------------------------
// CONSULTA: Faturas_Para_SQL
// Mesmos dados, mas em TEXTO no formato que o banco entende (ponto decimal, data ISO).
// Carregue na planilha e salve como "CSV UTF-8 (delimitado por vírgulas)":
// no Excel em português o separador sai como ponto e vírgula, igual ao do projeto.
// Salve como dados\tratados\faturas_limpas.csv
// -----------------------------------------------------------------------------
let
    Fonte = Faturas_Limpas,
    Ordenada = Table.Sort(Fonte, {{"numero_fatura", Order.Ascending}}),
    ComoTexto = Table.TransformColumns(
        Ordenada,
        {{"data_emissao", each Date.ToText(_, [Format = "yyyy-MM-dd"]), type text},
         {"peso_kg", each Number.ToText(_, "F1", "en-US"), type text},
         {"valor_cobrado", each Number.ToText(_, "F2", "en-US"), type text}}
    )
in
    ComoTexto
