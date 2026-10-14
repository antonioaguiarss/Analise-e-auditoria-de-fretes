-- =============================================================================
-- 03_resumos.sql
-- Perguntas que a auditoria responde. Cada consulta começa com "-- @nome:"
-- (o script montar_banco.py usa esse nome para salvar cada resultado em CSV).
-- =============================================================================

-- @nome: resumo_geral
-- Quanto foi pago a mais no total?
SELECT
    COUNT(*)                                                                AS qtd_faturas,
    ROUND(SUM(valor_cobrado), 2)                                            AS total_cobrado,
    ROUND(SUM(valor_tabela), 2)                                             AS total_tabela,
    SUM(CASE WHEN status = 'ACIMA DA TABELA' THEN 1 ELSE 0 END)             AS qtd_acima,
    ROUND(SUM(CASE WHEN status = 'ACIMA DA TABELA' THEN diferenca_rs ELSE 0 END), 2) AS excesso_rs,
    ROUND(SUM(CASE WHEN status = 'ACIMA DA TABELA' THEN diferenca_rs ELSE 0 END)
          * 100.0 / SUM(valor_tabela), 2)                                   AS excesso_pct_sobre_tabela
FROM vw_auditoria
WHERE valor_tabela IS NOT NULL;

-- @nome: por_status
-- Quantas faturas em cada situação?
SELECT status,
       COUNT(*)                         AS qtd_faturas,
       ROUND(SUM(valor_cobrado), 2)     AS total_cobrado,
       ROUND(SUM(diferenca_rs), 2)      AS soma_diferencas_rs
FROM vw_auditoria
GROUP BY status
ORDER BY qtd_faturas DESC;

-- @nome: por_transportadora
-- Qual transportadora mais cobra acima do contrato?
SELECT transportadora,
       COUNT(*)                                                             AS qtd_faturas,
       SUM(CASE WHEN status = 'ACIMA DA TABELA' THEN 1 ELSE 0 END)          AS qtd_acima,
       ROUND(SUM(CASE WHEN status = 'ACIMA DA TABELA' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS pct_faturas_acima,
       ROUND(SUM(CASE WHEN status = 'ACIMA DA TABELA' THEN diferenca_rs ELSE 0 END), 2)         AS excesso_rs,
       ROUND(SUM(valor_cobrado), 2)                                         AS total_cobrado
FROM vw_auditoria
WHERE status <> 'SEM TARIFA NO CONTRATO'
GROUP BY transportadora
ORDER BY excesso_rs DESC;

-- @nome: por_rota
-- Em quais rotas o excesso se concentra?
SELECT a.rota_id,
       a.origem || ' > ' || a.destino                                       AS rota,
       COUNT(*)                                                             AS qtd_faturas,
       SUM(CASE WHEN a.status = 'ACIMA DA TABELA' THEN 1 ELSE 0 END)        AS qtd_acima,
       ROUND(SUM(CASE WHEN a.status = 'ACIMA DA TABELA' THEN a.diferenca_rs ELSE 0 END), 2) AS excesso_rs
FROM vw_auditoria a
WHERE a.status <> 'SEM TARIFA NO CONTRATO'
GROUP BY a.rota_id, a.origem, a.destino
ORDER BY excesso_rs DESC;

-- @nome: por_mes
-- O problema está piorando? (repare no que muda a partir de julho: reajuste do contrato)
SELECT mes,
       COUNT(*)                                                             AS qtd_faturas,
       SUM(CASE WHEN status = 'ACIMA DA TABELA' THEN 1 ELSE 0 END)          AS qtd_acima,
       ROUND(SUM(CASE WHEN status = 'ACIMA DA TABELA' THEN diferenca_rs ELSE 0 END), 2) AS excesso_rs
FROM vw_auditoria
WHERE status <> 'SEM TARIFA NO CONTRATO'
GROUP BY mes
ORDER BY mes;

-- @nome: transportadora_por_mes
-- Quem mudou de comportamento ao longo do ano? (excesso em % do valor de tabela)
SELECT transportadora, mes,
       ROUND(SUM(CASE WHEN status = 'ACIMA DA TABELA' THEN diferenca_rs ELSE 0 END) * 100.0
             / SUM(valor_tabela), 2) AS excesso_pct
FROM vw_auditoria
WHERE valor_tabela IS NOT NULL
GROUP BY transportadora, mes
ORDER BY transportadora, mes;

-- @nome: top10_divergencias
-- As 10 faturas com maior valor cobrado a mais (por onde começar a cobrar)
SELECT numero_fatura, transportadora, data_emissao, rota_id, peso_kg,
       valor_cobrado, valor_tabela, diferenca_rs, diferenca_pct
FROM vw_auditoria
WHERE status = 'ACIMA DA TABELA'
ORDER BY diferenca_rs DESC
LIMIT 10;

-- @nome: faturas_acima_da_tabela
-- Lista completa para contestar com a transportadora
SELECT numero_fatura, cte, transportadora, data_emissao, rota_id, origem, destino,
       peso_kg, tarifa_kg, frete_minimo, valor_tabela, valor_cobrado, diferenca_rs, diferenca_pct
FROM vw_auditoria
WHERE status = 'ACIMA DA TABELA'
ORDER BY diferenca_rs DESC;

-- @nome: sem_tarifa
-- Fretes em rotas que a transportadora nem tem no contrato (negociar ou bloquear)
SELECT numero_fatura, cte, transportadora, data_emissao, rota_id, origem, destino,
       peso_kg, valor_cobrado
FROM vw_auditoria
WHERE status = 'SEM TARIFA NO CONTRATO'
ORDER BY valor_cobrado DESC;

-- @nome: duplicidades
-- Embarques cobrados mais de uma vez
SELECT * FROM vw_duplicidades ORDER BY valor_a_mais DESC;

-- @nome: reajuste_por_periodo
-- Investigação: depois do reajuste de julho (que já está na tabela), alguém passou a cobrar acima dela?
SELECT transportadora,
       CASE WHEN data_emissao >= '2026-07-01' THEN 'jul-set (após reajuste)' ELSE 'jan-jun' END AS periodo,
       COUNT(*)                                          AS qtd_faturas,
       ROUND(AVG(diferenca_pct), 2)                      AS media_diferenca_pct
FROM vw_auditoria
WHERE valor_tabela IS NOT NULL
GROUP BY transportadora, periodo
ORDER BY transportadora, periodo;
