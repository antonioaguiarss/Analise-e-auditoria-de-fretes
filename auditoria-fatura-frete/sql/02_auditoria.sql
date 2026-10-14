-- =============================================================================
-- 02_auditoria.sql
-- Regras de auditoria, escritas como "views" (consultas salvas).
--
-- Como o valor de tabela é calculado (regra do contrato):
--     valor_tabela = o MAIOR entre  (peso_kg x tarifa_kg)  e  (frete_minimo)
--
-- Tolerância: diferenças de até R$ 1,00 são tratadas como arredondamento (status OK).
-- =============================================================================

DROP VIEW IF EXISTS vw_auditoria_base;
DROP VIEW IF EXISTS vw_auditoria;
DROP VIEW IF EXISTS vw_duplicidades;

-- Passo 1: para cada fatura, achar a tarifa do contrato que valia NA DATA da fatura
--          e calcular quanto deveria ter sido cobrado.
CREATE VIEW vw_auditoria_base AS
SELECT
    f.numero_fatura,
    f.cte,
    f.transportadora,
    f.data_emissao,
    SUBSTR(f.data_emissao, 1, 7)  AS mes,
    f.rota_id,
    f.origem,
    f.destino,
    f.peso_kg,
    f.valor_cobrado,
    t.tarifa_kg,
    t.frete_minimo,
    ROUND(
        CASE WHEN f.peso_kg * t.tarifa_kg > t.frete_minimo
             THEN f.peso_kg * t.tarifa_kg
             ELSE t.frete_minimo
        END, 2)                   AS valor_tabela        -- NULL se não houver tarifa
FROM faturas f
LEFT JOIN tarifas_contrato t
       ON t.transportadora = f.transportadora
      AND t.rota_id        = f.rota_id
      AND f.data_emissao BETWEEN t.vigencia_inicio AND t.vigencia_fim;

-- Passo 2: comparar cobrado x tabela e classificar
CREATE VIEW vw_auditoria AS
SELECT
    b.*,
    ROUND(b.valor_cobrado - b.valor_tabela, 2)                         AS diferenca_rs,
    ROUND((b.valor_cobrado - b.valor_tabela) * 100.0 / b.valor_tabela, 1) AS diferenca_pct,
    CASE
        WHEN b.valor_tabela IS NULL                    THEN 'SEM TARIFA NO CONTRATO'
        WHEN b.valor_cobrado - b.valor_tabela >  1.00  THEN 'ACIMA DA TABELA'
        WHEN b.valor_cobrado - b.valor_tabela < -1.00  THEN 'ABAIXO DA TABELA'
        ELSE 'OK'
    END                                                                AS status
FROM vw_auditoria_base b;

-- Cobrança em duplicidade: o mesmo CT-e (um embarque) aparece em mais de uma fatura
CREATE VIEW vw_duplicidades AS
SELECT
    cte,
    COUNT(*)                          AS qtd_faturas,
    GROUP_CONCAT(numero_fatura, ' | ') AS faturas,
    MIN(transportadora)               AS transportadora,
    ROUND(SUM(valor_cobrado), 2)      AS total_cobrado,
    ROUND(SUM(valor_cobrado) - MIN(valor_cobrado), 2) AS valor_a_mais   -- o que foi pago além da 1ª cobrança
FROM faturas
GROUP BY cte
HAVING COUNT(*) > 1;
