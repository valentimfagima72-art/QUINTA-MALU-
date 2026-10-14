# Fase 2 — Publicar a Edge Function `processar-caderno` no Supabase

## O que esta Edge Function faz

1. Recebe uma foto do caderno de vendas em **base64**
2. Envia para o **Gemini 1.5 Flash** que lê o texto manuscrito
3. Para cada linha extraída, procura o produto na tabela `produtos` pelos **apelidos**
4. Cria um registo em `venda_sessoes` e os registos em `vendas`
5. Devolve o resumo: produtos reconhecidos, não reconhecidos e total bruto

---

## Passo 1 — Aplicar a Migration SQL

No **Supabase Dashboard > SQL Editor**, executa o conteúdo de:

```
supabase/migrations/20261013000003_create_vendas.sql
```

---

## Passo 2 — Publicar a Edge Function

Tens **duas formas** de publicar a Edge Function:

### Opção A: Via Supabase Dashboard (sem instalar nada)

1. Vai ao [Supabase Dashboard](https://supabase.com/dashboard) → o teu projeto
2. No menu lateral clica em **Edge Functions**
3. Clica em **Deploy a new function**
4. Nome da função: `processar-caderno`
5. Cola o conteúdo completo do ficheiro `supabase/functions/processar-caderno/index.ts`
6. Clica em **Deploy**

### Opção B: Via Supabase CLI (PowerShell)

```powershell
# Instalar a CLI (só uma vez)
npm install -g supabase

# Login
supabase login

# Ligar ao teu projeto (substitui pelo teu project-id)
supabase link --project-ref SEU_PROJECT_ID

# Publicar a função
supabase functions deploy processar-caderno
```

---

## Passo 3 — Configurar o Secret GEMINI_API_KEY

A Edge Function precisa da tua chave Gemini configurada como **secret** no Supabase.

### Via Dashboard:
1. **Edge Functions** → clica na função `processar-caderno`
2. Clica em **Secrets** (ou vai a **Project Settings > Edge Functions > Secrets**)
3. Adiciona: `GEMINI_API_KEY` = `(a tua chave do Google AI Studio)`

### Via CLI:
```powershell
supabase secrets set GEMINI_API_KEY=a_tua_chave_aqui
```

---

## Passo 4 — Executar o Teste

```powershell
# Opcional: coloca a tua foto do caderno na pasta do projeto com o nome:
# teste_caderno.jpg

# Executar o script de teste
powershell -ExecutionPolicy Bypass -File .\test_fase2.ps1
```

> **Nota:** Se não tiveres uma foto do caderno, o script cria uma imagem placeholder. O Gemini não vai conseguir ler nada útil nela, mas o fluxo completo (autenticação → Edge Function → base de dados) será validado.

---

## Estrutura do JSON enviado para a Edge Function

```json
{
  "foto_base64": "iVBORw0KGgoAAAANSUhEUgAA...",
  "data_venda": "2026-10-13"
}
```

## Estrutura da resposta

```json
{
  "sessao_id": "uuid-da-sessao",
  "data_venda": "2026-10-13",
  "total_bruto": 210.00,
  "produtos_reconhecidos": 3,
  "produtos_nao_reconhecidos": ["fgao x2"],
  "linhas": [
    { "produto_nome": "Coca-Cola 500ml", "quantidade": 2, "preco_unit": 50.00, "subtotal": 100.00 },
    { "produto_nome": "Cerveja 2M",      "quantidade": 1, "preco_unit": 80.00, "subtotal": 80.00  },
    { "produto_nome": "Coca-Cola 500ml", "quantidade": 1, "preco_unit": 30.00, "subtotal": 30.00  }
  ]
}
```

---

## Dica: Melhorar o reconhecimento de produtos

Se o Gemini reconhecer um produto com um nome que não está nos `apelidos`, basta adicionar esse apelido na tabela `produtos`. Por exemplo, se o caderno usa "fgao" para Frango:

```sql
UPDATE public.produtos
SET apelidos = array_append(apelidos, 'fgao')
WHERE nome LIKE '%Frango%';
```
