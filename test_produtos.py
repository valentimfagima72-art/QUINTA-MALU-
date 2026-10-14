import os
import json
import urllib.request
import urllib.error
from pathlib import Path

# Carregar variáveis do .env manualmente para evitar dependências externas
env_path = Path(__file__).parent / ".env"
if env_path.exists():
    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or "your-project" in SUPABASE_URL or "xyzcompany" in SUPABASE_URL:
    print("\033[91m[ERRO] Preenche o SUPABASE_URL e as chaves no ficheiro .env antes de executar.\033[0m")
    exit(1)

# Escolhe a chave para o teste (preferência service_role se existir, senão anon_key)
api_key = SUPABASE_SERVICE_ROLE_KEY if SUPABASE_SERVICE_ROLE_KEY and "exemplo_" not in SUPABASE_SERVICE_ROLE_KEY else SUPABASE_ANON_KEY

headers = {
    "apikey": api_key,
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json",
    "Prefer": "return=representation"
}

def request(endpoint, method="GET", data=None):
    url = f"{SUPABASE_URL}/rest/v1/{endpoint}"
    req = urllib.request.Request(url, method=method, headers=headers)
    if data is not None:
        req.data = json.dumps(data).encode("utf-8")
    with urllib.request.urlopen(req) as resp:
        content = resp.read().decode("utf-8")
        return json.loads(content) if content else None

def main():
    print("=" * 60)
    print("  TESTE SUPABASE REST API - QUINTA MALU (PRODUTOS) [PYTHON]")
    print("=" * 60)
    print(f"URL: {SUPABASE_URL}")
    print("=" * 60)

    try:
        # PASSO 1: INSERIR 3 PRODUTOS
        print("\n--- PASSO 1: Inserir 3 produtos de exemplo ---")
        novos = [
            {"nome": "Coca-Cola 500ml", "categoria": "bebida", "preco": 50.00, "apelidos": ["coca", "cc"], "ativo": True},
            {"nome": "Frango Grelhado", "categoria": "comida", "preco": 350.00, "apelidos": ["frango", "frango grelhado"], "ativo": True},
            {"nome": "Cerveja 2M", "categoria": "bebida", "preco": 80.00, "apelidos": ["2m", "dois m"], "ativo": True}
        ]
        inserted = request("produtos", method="POST", data=novos)
        print(f"[SUCESSO] {len(inserted)} produtos inseridos:")
        for p in inserted:
            print(f"  + [{p['id']}] {p['nome']} ({p['categoria']}) - {p['preco']} MT | Apelidos: {p['apelidos']}")

        item_editar = next((p for p in inserted if p["nome"] == "Cerveja 2M"), inserted[0])
        item_apagar = next((p for p in inserted if p["nome"] == "Frango Grelhado"), inserted[1])

        # PASSO 2: LISTAR TODOS OS PRODUTOS
        print("\n--- PASSO 2: Listar todos os produtos ---")
        todos = request("produtos?select=*&order=criado_em.desc")
        print(f"[SUCESSO] Total de produtos na tabela: {len(todos)}")
        for idx, p in enumerate(todos, 1):
            print(f"  {idx}. [{p['id']}] {p['nome']} | {p['categoria']} | {p['preco']} MT | Ativo: {p['ativo']}")

        # PASSO 3: EDITAR PREÇO
        print(f"\n--- PASSO 3: Editar preço de '{item_editar['nome']}' ({item_editar['preco']} MT -> 85.00 MT) ---")
        updated = request(f"produtos?id=eq.{item_editar['id']}", method="PATCH", data={"preco": 85.00})
        print(f"[SUCESSO] Preço atualizado: [{updated[0]['id']}] {updated[0]['nome']} -> {updated[0]['preco']} MT")

        # PASSO 4: APAGAR PRODUTO
        print(f"\n--- PASSO 4: Apagar produto '{item_apagar['nome']}' [{item_apagar['id']}] ---")
        request(f"produtos?id=eq.{item_apagar['id']}", method="DELETE")
        print(f"[SUCESSO] Produto '{item_apagar['nome']}' apagado com sucesso.")

        # VALIDAÇÃO FINAL
        print("\n--- VALIDAÇÃO FINAL: Conferir produtos restantes ---")
        restantes = request("produtos?select=id,nome,preco,categoria&order=criado_em.desc")
        print(f"[SUCESSO] Total restante: {len(restantes)}")
        for p in restantes:
            print(f"  - {p['nome']}: {p['preco']} MT ({p['categoria']})")

        print("\n" + "=" * 60)
        print("  TESTES CONCLUÍDOS COM 100% DE SUCESSO!")
        print("=" * 60)

    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8")
        print(f"\n\033[91m[FALHA HTTP {e.code}]\033[0m {err_msg}")
        exit(1)
    except Exception as e:
        print(f"\n\033[91m[ERRO]\033[0m {e}")
        exit(1)

if __name__ == "__main__":
    main()
