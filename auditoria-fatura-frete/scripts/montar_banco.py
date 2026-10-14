"""
Monta o banco SQLite, carrega os CSVs e roda a auditoria.

    python scripts/montar_banco.py

Passos:
  1. cria as tabelas            (sql/01_criar_tabelas.sql)
  2. carrega os CSVs            (dados/brutos/rotas.csv, tabela_contrato.csv, dados/tratados/faturas_limpas.csv)
  3. cria as views da auditoria (sql/02_auditoria.sql)
  4. roda cada consulta de sql/03_resumos.sql e salva em resultados/<nome>.csv
"""
import csv
import re
import sqlite3
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DB = RAIZ / "auditoria_frete.db"
RESULTADOS = RAIZ / "resultados"
RESULTADOS.mkdir(exist_ok=True)


def ler_csv(caminho):
    with open(caminho, newline="", encoding="utf-8-sig") as fh:  # utf-8-sig: aceita CSV do Excel (com BOM)
        return list(csv.DictReader(fh, delimiter=";"))


def carregar(con, tabela, linhas, colunas, numericas=()):
    marcadores = ",".join("?" for _ in colunas)
    dados = [[float(l[c]) if c in numericas else l[c] for c in colunas] for l in linhas]
    con.executemany(f"INSERT INTO {tabela} ({','.join(colunas)}) VALUES ({marcadores})", dados)


def main():
    if DB.exists():
        DB.unlink()
    con = sqlite3.connect(DB)

    con.executescript((RAIZ / "sql" / "01_criar_tabelas.sql").read_text(encoding="utf-8"))

    carregar(con, "rotas", ler_csv(RAIZ / "dados" / "brutos" / "rotas.csv"),
             ["rota_id", "origem", "destino", "distancia_km"], numericas=("distancia_km",))
    carregar(con, "tarifas_contrato", ler_csv(RAIZ / "dados" / "brutos" / "tabela_contrato.csv"),
             ["transportadora", "rota_id", "vigencia_inicio", "vigencia_fim", "tarifa_kg", "frete_minimo"],
             numericas=("tarifa_kg", "frete_minimo"))
    carregar(con, "faturas", ler_csv(RAIZ / "dados" / "tratados" / "faturas_limpas.csv"),
             ["numero_fatura", "cte", "transportadora", "data_emissao", "origem", "destino",
              "rota_id", "peso_kg", "valor_cobrado"], numericas=("peso_kg", "valor_cobrado"))
    con.commit()

    con.executescript((RAIZ / "sql" / "02_auditoria.sql").read_text(encoding="utf-8"))

    texto = (RAIZ / "sql" / "03_resumos.sql").read_text(encoding="utf-8")
    blocos = re.split(r"^-- @nome:\s*(\w+)\s*$", texto, flags=re.MULTILINE)
    for nome, sql in zip(blocos[1::2], blocos[2::2]):
        cur = con.execute(sql.strip().rstrip(";"))
        colunas = [c[0] for c in cur.description]
        linhas = cur.fetchall()
        with open(RESULTADOS / f"{nome}.csv", "w", newline="", encoding="utf-8-sig") as fh:
            w = csv.writer(fh, delimiter=";")
            w.writerow(colunas)
            w.writerows(linhas)
        print(f"[{nome}] {len(linhas)} linhas")

    # Detalhe completo (usado no relatório em Excel)
    cur = con.execute("SELECT * FROM vw_auditoria ORDER BY data_emissao, numero_fatura")
    colunas = [c[0] for c in cur.description]
    with open(RESULTADOS / "auditoria_detalhada.csv", "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(colunas)
        w.writerows(cur.fetchall())
    con.close()
    print("Pronto:", DB.name)


if __name__ == "__main__":
    main()
