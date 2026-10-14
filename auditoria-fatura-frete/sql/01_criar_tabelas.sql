-- =============================================================================
-- 01_criar_tabelas.sql
-- Cria as tabelas do projeto de auditoria de fatura de frete.
-- Dialeto: SQLite (roda em qualquer computador, sem instalar servidor).
-- Em SQL Server / PostgreSQL só mudam os tipos (REAL -> DECIMAL) e funções de texto.
-- =============================================================================

DROP TABLE IF EXISTS faturas;
DROP TABLE IF EXISTS tarifas_contrato;
DROP TABLE IF EXISTS rotas;

-- Cadastro de rotas (origem -> destino)
CREATE TABLE rotas (
    rota_id       TEXT PRIMARY KEY,
    origem        TEXT NOT NULL,
    destino       TEXT NOT NULL,
    distancia_km  INTEGER
);

-- O que foi combinado em contrato: tarifa por kg + frete mínimo, por período de validade
CREATE TABLE tarifas_contrato (
    transportadora   TEXT NOT NULL,
    rota_id          TEXT NOT NULL REFERENCES rotas (rota_id),
    vigencia_inicio  TEXT NOT NULL,     -- formato AAAA-MM-DD
    vigencia_fim     TEXT NOT NULL,
    tarifa_kg        REAL NOT NULL,     -- R$ por kg
    frete_minimo     REAL NOT NULL,     -- R$ mínimo por embarque
    PRIMARY KEY (transportadora, rota_id, vigencia_inicio)
);

-- Faturas JÁ LIMPAS (saída do Power Query)
CREATE TABLE faturas (
    numero_fatura  TEXT PRIMARY KEY,
    cte            TEXT NOT NULL,       -- nº do conhecimento de transporte (1 por embarque)
    transportadora TEXT NOT NULL,
    data_emissao   TEXT NOT NULL,       -- AAAA-MM-DD
    origem         TEXT,
    destino        TEXT,
    rota_id        TEXT,
    peso_kg        REAL NOT NULL,
    valor_cobrado  REAL NOT NULL
);

CREATE INDEX idx_faturas_cte ON faturas (cte);
CREATE INDEX idx_faturas_transp_rota ON faturas (transportadora, rota_id, data_emissao);
