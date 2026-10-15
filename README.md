🚛 Auditoria de Fatura de Frete — SQL + Power Query + Excel + Python

Projeto que simula a conferência das faturas de frete: verificar se cada transportadora cobrou exatamente o que estava combinado em contrato e, quando não cobrou, quanto dinheiro isso representa.

⚠️ Projeto educacional. Todos os dados são fictícios, gerados por script com semente fixa (sempre saem iguais). Nenhuma empresa, preço ou fatura real foi usada.

O problema

Todo mês as transportadoras enviam faturas com o valor cobrado por cada embarque. O contrato, porém, já define quanto cada embarque deveria custar. Com centenas de linhas, conferir uma a uma à mão não é viável. Este projeto automatiza a conferência e responde a quatro perguntas:

Quais faturas vieram acima do combinado e quanto isso custou?
Quais transportadoras e rotas concentram o problema?
Algum embarque foi cobrado duas vezes?
Alguém cobrou por uma rota que não existe no contrato?
Principais resultados (base fictícia)
Indicador	Valor
Faturas analisadas	620
Faturas acima da tabela	104
Valor cobrado a mais	R$ 20.246,94 (2,83% acima do valor de tabela)
Cobranças em duplicidade	8 embarques, R$ 6.466,16 a mais
Potencial a recuperar (excesso + duplicidades)	R$ 26.713,10
Faturas em rotas sem tarifa no contrato	12 faturas, R$ 22.716,45 (precisam de análise, não entram no potencial)
Faturas abaixo da tabela	11 (a favor da empresa, mas também merecem explicação)
O que a análise mostra
Veloz Cargas concentra o maior valor cobrado a mais (R$ 11.304,31). Cerca de 31% das faturas dela vêm acima da tabela, de forma constante ao longo do ano, o que indica um padrão, e não um erro isolado.
Atlântico Logística tem a maior proporção de faturas acima da tabela (47%), e o problema começa depois do reajuste de julho: a diferença média sobe de cerca de 3% (jan–jun) para cerca de 8% (jul–set). Isso sugere que ela aplicou um reajuste maior que o previsto em contrato. Consulta: reajuste_por_periodo.
As rotas para Salvador e Recife concentram o maior excesso em reais. Como são as mais longas e caras, o mesmo erro percentual vira mais dinheiro.
As outras três transportadoras ficam entre 5% e 8% de faturas acima da tabela, o que pode ser tratado como erro pontual.

Os números completos estão na pasta resultados/ e no relatorio_auditoria.xlsx.

Conceitos usados
Termo	O que significa
Tarifa por kg	Preço combinado por quilo transportado numa rota (ex.: R$ 0,36/kg de Campinas a São Paulo)
Frete mínimo	Valor mínimo por embarque: uma carga pequena nunca paga menos que isso
Valor de tabela	O que o contrato diz que deveria ser cobrado: o maior entre (peso × tarifa por kg) e o frete mínimo
Divergência	Valor cobrado menos valor de tabela
Vigência	Período em que uma tarifa vale. Em julho/2026 as tarifas sobem 5%, conforme previsto em contrato
CT-e	Documento que identifica um embarque. Se o mesmo CT-e aparece em duas faturas, houve cobrança em duplicidade

Exemplo: 100 kg numa rota com tarifa de R$ 0,36/kg e frete mínimo de R$ 72. 100 × 0,36 = R$ 36, que é menos que o mínimo, então o valor de tabela é R$ 72. Se a transportadora cobrou R$ 90, a divergência é de +R$ 18.

Como o projeto funciona
Etapa	Ferramenta	O que faz
1. Gerar dados	Python	Cria a base fictícia de faturas, contrato e rotas, já com os "defeitos" de arquivos reais
2. Limpar	Power Query	Padroniza nomes, datas, números e remove linhas repetidas
3. Auditar	SQL	Cruza as faturas limpas com o contrato e aponta as divergências
4. Apresentar	Excel	Mostra o resumo, refazendo a regra com fórmulas e com tolerância editável
Parte 1: Power Query (limpeza)

O arquivo faturas_brutas.csv foi gerado com os mesmos problemas que aparecem em arquivos reais de transportadoras:

Problema nos dados	Exemplo	Como foi resolvido
Linhas em branco	;;;;;;;	Filtro por número de fatura vazio
Espaços sobrando	" NF-100004 "	Text.Trim + Text.Clean
Transportadora escrita de várias formas	RODOFACIL TRANSPORTES, Rodofacil Transp.	Tabela de-para (mesclar consultas)
Cidade escrita de várias formas	Campinas/SP, campinas - sp, SAO PAULO / SP	Tabela de-para de cidades
Dois formatos de data	01/01/2026 e 2026-01-01	try ... otherwise testando os dois formatos
Peso em texto, às vezes com unidade	1.234,5 kg	Remove "kg" e converte no padrão brasileiro
Valor em texto, às vezes com moeda	R$ 1.234,56	Remove "R$" e converte no padrão brasileiro
Fatura reenviada (linha idêntica)	mesma linha duas vezes	Table.Distinct
Falta o código da rota	só origem e destino	Mesclar com a tabela de rotas

Decisão importante: a remoção de repetidas apaga só linhas 100% idênticas (o mesmo arquivo enviado de novo). Duas faturas com números diferentes e o mesmo CT-e não são removidas, porque isso é cobrança em duplicidade e precisa chegar até a auditoria no SQL.

O passo a passo para rodar está no cabeçalho de power_query/limpeza_faturas.m.

Como conferir se a limpeza deu certo: a consulta Faturas_Limpas deve ter 620 linhas, soma de valor_cobrado de R$ 757.529,80 e soma de peso_kg de 442.023,6. São os mesmos totais do gabarito dados/tratados/faturas_limpas.csv.

Parte 2: SQL (auditoria)

Usa o SQLite, que roda em qualquer computador sem instalar servidor. Em SQL Server ou PostgreSQL, mudam só detalhes como tipos de dados e a função GROUP_CONCAT.

Regra central, em sql/02_auditoria.sql:

sql
-- Valor de tabela = o maior entre (peso × tarifa) e o frete mínimo
ROUND(CASE WHEN f.peso_kg * t.tarifa_kg > t.frete_minimo
           THEN f.peso_kg * t.tarifa_kg
           ELSE t.frete_minimo END, 2) AS valor_tabela

Cuidados tratados no código:

Vigência: cada fatura é comparada com a tarifa que valia na data dela (BETWEEN vigencia_inicio AND vigencia_fim). Sem isso, as faturas a partir de julho seriam comparadas com a tarifa antiga.
LEFT JOIN: faturas de rotas que não estão no contrato não desaparecem do resultado; aparecem como SEM TARIFA NO CONTRATO.
Tolerância de R$ 1,00: diferenças de centavos por arredondamento não contam como divergência.
Duplicidade: GROUP BY cte HAVING COUNT(*) > 1 encontra CT-es cobrados mais de uma vez.

Status possíveis: OK, ACIMA DA TABELA, ABAIXO DA TABELA, SEM TARIFA NO CONTRATO.

Como executar

Pré-requisito: Python 3.9 ou superior. O SQLite já vem com o Python; só o relatório em Excel precisa do pacote openpyxl.

bash
# 1. Gerar a base fictícia (sempre sai igual, por causa da semente fixa)
python scripts/gerar_dados.py

# 2. Criar o banco, carregar os dados e rodar a auditoria
python scripts/montar_banco.py

# 3. (opcional) Gerar o relatório em Excel
pip install openpyxl
python scripts/gerar_relatorio_excel.py

Para explorar o SQL manualmente: abra auditoria_frete.db no DB Browser for SQLite e rode os arquivos da pasta sql/.

Para testar a sua própria limpeza no Power Query: faça a limpeza no Excel, exporte a consulta Faturas_Para_SQL como CSV e salve por cima de dados/tratados/faturas_limpas.csv. Depois rode montar_banco.py de novo. Se a limpeza estiver correta, os resultados serão idênticos.

Estrutura do projeto
auditoria-fatura-frete/
├── dados/
│   ├── brutos/        # faturas "sujas", contrato, rotas e tabelas de-para
│   └── tratados/      # faturas_limpas.csv (resultado esperado do Power Query)
├── power_query/       # limpeza_faturas.m (código M comentado)
├── sql/               # 01_criar_tabelas, 02_auditoria (views), 03_resumos (perguntas)
├── scripts/           # gerar_dados.py, montar_banco.py, gerar_relatorio_excel.py
└── resultados/        # CSVs das consultas + relatorio_auditoria.xlsx
Limitações e próximos passos
Regra de preço simples: considera só tarifa por kg e frete mínimo. Contratos reais costumam ter taxas extras (seguro, pedágio, coleta), que poderiam virar novas colunas na tabela de contrato.
Peso da própria fatura: o ideal é comparar com o peso real medido na expedição, porque cobrar peso a mais é uma causa comum de divergência.
Tolerância fixa de R$ 1,00: poderia ser percentual ou variar por transportadora.
Possível contagem dupla: se uma mesma fatura estiver acima da tabela e em duplicidade, parte do valor seria contada duas vezes no potencial a recuperar. Isso não ocorre nesta base, mas precisaria ser tratado numa base real.
Próximo passo natural: um dashboard em Power BI ligado a este modelo, com excesso por transportadora, por rota e por mês.
Habilidades demonstradas
SQL: JOIN por período de vigência, CASE, agregações, views, GROUP BY/HAVING
Power Query: de-para, mesclagem de consultas, tratamento de datas e números no padrão brasileiro, controle de qualidade com totais de conferência
Excel: fórmulas SOMASES/CONT.SES (SUMIFS/COUNTIFS), parâmetro editável, formatação condicional
Python: geração de dados reproduzível e automação do fluxo
Negócio: raciocínio de processo logístico e gestão de custos de frete

Antonio Aguiar · GitHub · LinkedIn
