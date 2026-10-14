# Backend Quinta Malu - Fase 1 (Produtos)

Backend de gestão de vendas para a Quinta Malu no Supabase.

---

## 1. Estrutura de Ficheiros

- `supabase/migrations/20261013000001_create_produtos.sql`: Migration SQL contendo a tabela `produtos`, restrições, RLS, política e GRANTs explícitos para a Data API.
- `.env`: Ficheiro de variáveis de ambiente com placeholders do Supabase.
- `.env.example`: Exemplo de configuração.
- `test_produtos.ps1`: Script de teste nativo em PowerShell (funciona de imediato no Windows sem dependências).
- `test_produtos.js`: Script de teste em Node.js com `@supabase/supabase-js`.
- `test_produtos.py`: Script de teste em Python nativo (urllib/json).
- `package.json`: Manifesto de dependências Node.js.

---

## 2. Como Aplicar a Migration no Supabase

1. Acede ao painel do teu projeto no [Supabase Dashboard](https://supabase.com/dashboard).
2. No menu lateral, clica em **SQL Editor**.
3. Clica em **New query**.
4. Copia o conteúdo de `supabase/migrations/20261013000001_create_produtos.sql` e cola no editor.
5. Clica em **Run** (Executar).

---

## 3. Configurar Credenciais (.env)

Abre o ficheiro `.env` e substitui os valores pelos dados do teu projeto Supabase (**Project Settings** > **API**):

```env
SUPABASE_URL=https://teu-project-id.supabase.co
SUPABASE_ANON_KEY=tua-anon-key-aqui
SUPABASE_SERVICE_ROLE_KEY=tua-service-role-key-aqui
```

> **Nota sobre o RLS**: Como a política de segurança exige utilizador autenticado (`to authenticated`), para testes diretos de backend podes usar a `SUPABASE_SERVICE_ROLE_KEY` (chave de administração de backend) no `.env`, ou configurar `ADMIN_EMAIL` e `ADMIN_PASSWORD` se tiveres criado um utilizador no Supabase Auth.

---

## 4. Executar o Script de Teste

Podes correr o teste de 3 formas conforme a tua preferência:

### Opção A: PowerShell (Recomendado no Windows - sem instalar nada)
```powershell
.\test_produtos.ps1
```

### Opção B: Node.js
```bash
npm install
npm test
# ou: node test_produtos.js
```

### Opção C: Python
```bash
python test_produtos.py
```

### O que o teste faz:
1. **Insere 3 produtos**:
   - `Coca-Cola 500ml` (bebida, 50 MT, apelidos: `{"coca","cc"}`)
   - `Frango Grelhado` (comida, 350 MT, apelidos: `{"frango","frango grelhado"}`)
   - `Cerveja 2M` (bebida, 80 MT, apelidos: `{"2m","dois m"}`)
2. **Lista todos os produtos** registados.
3. **Edita o preço** da `Cerveja 2M` (de 80 para 85 MT).
4. **Apaga** o `Frango Grelhado`.
5. **Confirmação final** no log com validação de sucesso em cada etapa.
