"""
Gera a base FICTÍCIA do projeto de auditoria de fatura de frete.

Saídas (pasta dados/):
  brutos/faturas_brutas.csv          -> faturas "sujas", como chegam das transportadoras
  brutos/tabela_contrato.csv         -> tarifas combinadas em contrato (limpa)
  brutos/rotas.csv                   -> cadastro de rotas (limpa)
  brutos/de_para_transportadoras.csv -> como cada nome "sujo" vira o nome padrão
  brutos/de_para_cidades.csv         -> idem para cidades
  tratados/faturas_limpas.csv        -> resultado esperado do Power Query (referência)

Tudo é gerado com semente fixa (SEED), então o resultado é sempre o mesmo.
Nenhum dado é real.
"""
import csv
import random
import unicodedata
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path

SEED = 42
random.seed(SEED)

RAIZ = Path(__file__).resolve().parent.parent
BRUTOS = RAIZ / "dados" / "brutos"
TRATADOS = RAIZ / "dados" / "tratados"
BRUTOS.mkdir(parents=True, exist_ok=True)
TRATADOS.mkdir(parents=True, exist_ok=True)

# ----------------------------------------------------------------------------
# 1) Cadastros: rotas e transportadoras
# ----------------------------------------------------------------------------
ROTAS = [  # (rota_id, origem, destino, distancia_km)
    ("R01", "Campinas/SP", "São Paulo/SP", 100),
    ("R02", "Campinas/SP", "Rio de Janeiro/RJ", 500),
    ("R03", "Campinas/SP", "Belo Horizonte/MG", 590),
    ("R04", "Campinas/SP", "Curitiba/PR", 410),
    ("R05", "Campinas/SP", "Porto Alegre/RS", 1100),
    ("R06", "Campinas/SP", "Salvador/BA", 1960),
    ("R07", "Campinas/SP", "Recife/PE", 2650),
    ("R08", "Campinas/SP", "Goiânia/GO", 930),
    ("R09", "Curitiba/PR", "São Paulo/SP", 410),
    ("R10", "Curitiba/PR", "Porto Alegre/RS", 700),
]
KM = {r[0]: r[3] for r in ROTAS}
ROTA_POR_PAR = {(r[1], r[2]): r[0] for r in ROTAS}

TRANSPORTADORAS = {
    "TransLog Express": dict(
        fator=1.00, prob_excesso=0.07,
        rotas=["R01", "R02", "R03", "R04", "R05", "R09"],
        variacoes=["TransLog Express", "TRANSLOG EXPRESS", "Translog Express", "TransLog Exp."]),
    "RodoFácil Transportes": dict(
        fator=0.95, prob_excesso=0.06,
        rotas=["R01", "R02", "R03", "R04", "R08", "R09", "R10"],
        variacoes=["RodoFácil Transportes", "RODOFACIL TRANSPORTES", "Rodofacil Transp.", "RODOFÁCIL TRANSP"]),
    "Veloz Cargas": dict(
        fator=1.10, prob_excesso=0.30,
        rotas=["R02", "R03", "R05", "R06", "R07", "R08"],
        variacoes=["Veloz Cargas", "VELOZ CARGAS LTDA", "veloz cargas", "Veloz Cargas Ltda."]),
    "Atlântico Logística": dict(
        fator=1.05, prob_excesso=0.12,
        rotas=["R03", "R04", "R05", "R06", "R07", "R10"],
        variacoes=["Atlântico Logística", "ATLANTICO LOGISTICA", "Atlantico Logistica", "ATLÂNTICO LOG."]),
    "Norte Sul Fretes": dict(
        fator=0.92, prob_excesso=0.07,
        rotas=["R01", "R04", "R06", "R07", "R08", "R09"],
        variacoes=["Norte Sul Fretes", "NORTE SUL FRETES", "Norte-Sul Fretes", "norte sul fretes ltda"]),
}

REAJUSTE_CONTRATUAL = 0.05           # reajuste previsto em contrato a partir de 01/07/2026
INICIO_REAJUSTE = date(2026, 7, 1)


def sem_acento(txt):
    return "".join(c for c in unicodedata.normalize("NFD", txt) if unicodedata.category(c) != "Mn")


def variacoes_cidade(cidade_uf):
    nome, uf = cidade_uf.split("/")
    return [f"{nome}/{uf}", f"{nome.upper()}-{uf}", f"{nome.lower()} - {uf.lower()}",
            f"{sem_acento(nome)} / {uf}"]


# ----------------------------------------------------------------------------
# 2) Tabela de contrato (tarifa por kg + frete mínimo, em dois períodos)
# ----------------------------------------------------------------------------
tarifas = []  # (transportadora, rota_id, vig_ini, vig_fim, tarifa_kg, frete_minimo)
for nome, cfg in TRANSPORTADORAS.items():
    for rota_id in cfg["rotas"]:
        km = KM[rota_id]
        tarifa = round((0.20 + 0.0016 * km) * cfg["fator"], 4)
        minimo = round((60 + 0.12 * km) * cfg["fator"], 2)
        tarifas.append((nome, rota_id, date(2026, 1, 1), date(2026, 6, 30), tarifa, minimo))
        tarifas.append((nome, rota_id, INICIO_REAJUSTE, date(2026, 12, 31),
                        round(tarifa * (1 + REAJUSTE_CONTRATUAL), 4),
                        round(minimo * (1 + REAJUSTE_CONTRATUAL), 2)))


def valor_tabela(nome, rota_id, dia, peso):
    for t_nome, t_rota, ini, fim, tarifa, minimo in tarifas:
        if t_nome == nome and t_rota == rota_id and ini <= dia <= fim:
            return max(peso * tarifa, minimo)
    return None


# ----------------------------------------------------------------------------
# 3) Faturas "verdadeiras" (antes de sujar os dados)
# ----------------------------------------------------------------------------
nomes = list(TRANSPORTADORAS)
pesos_transp = [0.28, 0.24, 0.18, 0.16, 0.14]


def sortear_data():
    return date(2026, 1, 1) + timedelta(days=random.randint(0, 272))  # 01/01 a 30/09/2026


def sortear_peso():
    return round(min(max(random.lognormvariate(6.2, 0.9), 40), 8000), 1)


base = []
for _ in range(600):
    nome = random.choices(nomes, weights=pesos_transp)[0]
    cfg = TRANSPORTADORAS[nome]
    rota_id, dia, peso = random.choice(cfg["rotas"]), sortear_data(), sortear_peso()
    tabela = valor_tabela(nome, rota_id, dia, peso)
    valor = tabela + random.uniform(-0.40, 0.40)          # ruído de arredondamento
    tipo = "ok"
    if nome == "Atlântico Logística" and dia >= INICIO_REAJUSTE and random.random() < 0.85:
        valor, tipo = tabela * 1.095, "reajuste_indevido"   # cobrou ~9,5% ACIMA da tabela já reajustada
    elif random.random() < cfg["prob_excesso"]:
        valor, tipo = tabela * random.uniform(1.04, 1.20), "sobretaxa"
    elif random.random() < 0.03:
        valor, tipo = tabela * random.uniform(0.88, 0.96), "abaixo"
    base.append(dict(transportadora=nome, rota_id=rota_id, data=dia, peso=peso,
                     valor=round(valor, 2), tipo=tipo))

# Rotas que NÃO estão no contrato daquela transportadora
for _ in range(12):
    nome = random.choice(nomes)
    rota_id = random.choice([r[0] for r in ROTAS if r[0] not in TRANSPORTADORAS[nome]["rotas"]])
    peso = sortear_peso()
    valor = max(peso * (0.20 + 0.0016 * KM[rota_id]) * 1.25, 120)
    base.append(dict(transportadora=nome, rota_id=rota_id, data=sortear_data(), peso=peso,
                     valor=round(valor, 2), tipo="sem_tarifa"))

base.sort(key=lambda f: f["data"])
for i, f in enumerate(base, start=1):
    f["cte"] = f"CTE-{i:07d}"

# Cobranças em duplicidade: mesmo CT-e (conhecimento de transporte) cobrado em duas faturas
candidatas = [f for f in base if f["tipo"] == "ok" and f["data"].day <= 25]
duplicadas = []
for orig in random.sample(candidatas, 8):
    dup = dict(orig)
    dup["data"] = orig["data"] + timedelta(days=random.randint(1, 5))
    dup["tipo"] = "duplicidade"
    duplicadas.append(dup)

faturas = sorted(base + duplicadas, key=lambda f: (f["data"], f["cte"]))
for i, f in enumerate(faturas, start=1):
    f["numero_fatura"] = f"NF-{100000 + i}"

# ----------------------------------------------------------------------------
# 4) De-paras (usados no Power Query e aqui no Python)
# ----------------------------------------------------------------------------
de_para_transp = {}
for nome, cfg in TRANSPORTADORAS.items():
    for v in cfg["variacoes"]:
        de_para_transp[v.strip().upper()] = nome

de_para_cidade = {}
for _, origem, destino, _ in ROTAS:
    for cidade in (origem, destino):
        for v in variacoes_cidade(cidade):
            de_para_cidade[v.strip().upper()] = cidade


# ----------------------------------------------------------------------------
# 5) Sujar os dados (formato de planilha de transportadora)
# ----------------------------------------------------------------------------
def fmt_br(x, casas):
    s = f"{x:,.{casas}f}"
    return s.replace(",", "X").replace(".", ",").replace("X", ".")


def espacos(txt):
    return " " * random.choice([0, 0, 0, 1]) + txt + " " * random.choice([0, 0, 0, 1, 2])


def sujar(f):
    nome = f["transportadora"]
    _, origem, destino, _ = next(r for r in ROTAS if r[0] == f["rota_id"])
    d = f["data"]
    data_txt = d.strftime("%d/%m/%Y") if random.random() < 0.6 else d.strftime("%Y-%m-%d")
    r = random.random()
    peso_txt = fmt_br(f["peso"], 1) + ("" if r < 0.7 else (" kg" if r < 0.9 else " Kg"))
    valor_txt = ("R$ " if random.random() < 0.5 else "") + fmt_br(f["valor"], 2)
    return [espacos(f["numero_fatura"]), espacos(f["cte"]),
            espacos(random.choice(TRANSPORTADORAS[nome]["variacoes"])), data_txt,
            espacos(random.choice(variacoes_cidade(origem))),
            espacos(random.choice(variacoes_cidade(destino))), peso_txt, valor_txt]


COLUNAS_BRUTAS = ["numero_fatura", "cte", "transportadora", "data_emissao",
                  "origem", "destino", "peso_kg", "valor_cobrado"]
linhas = [sujar(f) for f in faturas]
for linha in random.sample(linhas, 10):                 # linhas repetidas por reenvio
    linhas.insert(random.randint(0, len(linhas)), list(linha))
for _ in range(3):                                       # linhas em branco
    linhas.insert(random.randint(0, len(linhas)), [""] * len(COLUNAS_BRUTAS))


def gravar(caminho, cabecalho, rows):
    with open(caminho, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(cabecalho)
        w.writerows(rows)


gravar(BRUTOS / "faturas_brutas.csv", COLUNAS_BRUTAS, linhas)
gravar(BRUTOS / "rotas.csv", ["rota_id", "origem", "destino", "distancia_km"], ROTAS)
gravar(BRUTOS / "tabela_contrato.csv",
       ["transportadora", "rota_id", "vigencia_inicio", "vigencia_fim", "tarifa_kg", "frete_minimo"],
       [(a, b, c.isoformat(), d.isoformat(), f"{e:.4f}", f"{g:.2f}") for a, b, c, d, e, g in tarifas])
gravar(BRUTOS / "de_para_transportadoras.csv", ["variacao", "nome_padrao"], sorted(de_para_transp.items()))
gravar(BRUTOS / "de_para_cidades.csv", ["variacao", "cidade_padrao"], sorted(de_para_cidade.items()))


# ----------------------------------------------------------------------------
# 6) Limpeza em Python = mesma lógica do Power Query (serve de gabarito)
# ----------------------------------------------------------------------------
def numero(txt):
    t = txt.lower().replace("kg", "").replace("r$", "").strip()
    return float(t.replace(".", "").replace(",", "."))


def limpar(linhas_brutas):
    vistos, saida = set(), []
    for lin in linhas_brutas:
        lin = [c.strip() for c in lin]
        if not lin[0]:
            continue
        num, cte, transp, data_txt, origem, destino, peso, valor = lin
        dia = (datetime.strptime(data_txt, "%d/%m/%Y") if "/" in data_txt
               else datetime.strptime(data_txt, "%Y-%m-%d")).date()
        origem, destino = de_para_cidade[origem.upper()], de_para_cidade[destino.upper()]
        reg = (num, cte, de_para_transp[transp.upper()], dia.isoformat(), origem, destino,
               ROTA_POR_PAR[(origem, destino)], f"{numero(peso):.1f}", f"{numero(valor):.2f}")
        if reg not in vistos:
            vistos.add(reg)
            saida.append(reg)
    return sorted(saida)


limpas = limpar(linhas)
gravar(TRATADOS / "faturas_limpas.csv",
       ["numero_fatura", "cte", "transportadora", "data_emissao", "origem", "destino",
        "rota_id", "peso_kg", "valor_cobrado"], limpas)

print("Linhas brutas (com sujeira):", len(linhas))
print("Faturas limpas:", len(limpas))
print("Anomalias plantadas (gabarito interno):", dict(Counter(f["tipo"] for f in faturas)))
