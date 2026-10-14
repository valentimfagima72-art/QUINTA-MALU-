import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { createClient } from '@supabase/supabase-js';

// Função auxiliar para carregar .env sem dependência estrita
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const envPath = path.resolve(__dirname, '.env');

if (fs.existsSync(envPath)) {
  const envContent = fs.readFileSync(envPath, 'utf-8');
  for (const line of envContent.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const separatorIdx = trimmed.indexOf('=');
    if (separatorIdx !== -1) {
      const key = trimmed.substring(0, separatorIdx).trim();
      const value = trimmed.substring(separatorIdx + 1).trim();
      if (!process.env[key]) {
        process.env[key] = value;
      }
    }
  }
}

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ADMIN_EMAIL = process.env.ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;

if (!SUPABASE_URL || SUPABASE_URL.includes('your-project') || SUPABASE_URL.includes('xyzcompany')) {
  console.error('\x1b[31m[ERRO]\x1b[0m Por favor, preenche SUPABASE_URL e as chaves no ficheiro .env antes de executar o teste.');
  process.exit(1);
}

// Para scripts backend com RLS ativo para utilizadores autenticados:
// 1. Usa SERVICE_ROLE_KEY se disponível (recomendado para scripts de backend/manutenção)
// 2. Se não houver SERVICE_ROLE_KEY, usa ANON_KEY e autentica com login (se ADMIN_EMAIL/PASSWORD fornecidos)
const activeKey = SUPABASE_SERVICE_ROLE_KEY && !SUPABASE_SERVICE_ROLE_KEY.includes('exemplo_') 
  ? SUPABASE_SERVICE_ROLE_KEY 
  : SUPABASE_ANON_KEY;

const isServiceRole = activeKey === SUPABASE_SERVICE_ROLE_KEY && Boolean(SUPABASE_SERVICE_ROLE_KEY);

console.log('='.repeat(60));
console.log('  TESTE DE INTEGRAÇÃO SUPABASE - QUINTA MALU (PRODUTOS)');
console.log('='.repeat(60));
console.log(`URL do Supabase : ${SUPABASE_URL}`);
console.log(`Modo de Acesso  : ${isServiceRole ? 'service_role (Admin Backend)' : 'anon_key'}`);
console.log('='.repeat(60));

const supabase = createClient(SUPABASE_URL, activeKey, {
  auth: { persistSession: false }
});

async function runTest() {
  try {
    // Se estiver a usar anon key e tiver credenciais de utilizador admin, faz login
    if (!isServiceRole && ADMIN_EMAIL && ADMIN_PASSWORD && !ADMIN_PASSWORD.includes('senha_secreta')) {
      console.log(`\n[AUTH] A autenticar como utilizador ${ADMIN_EMAIL}...`);
      const { data: authData, error: authErr } = await supabase.auth.signInWithPassword({
        email: ADMIN_EMAIL,
        password: ADMIN_PASSWORD,
      });
      if (authErr) {
        console.warn(`[AVISO] Falha ao autenticar utilizador: ${authErr.message}`);
        console.warn('O teste continuará como anónimo (pode falhar no INSERT/UPDATE/DELETE devido ao RLS).');
      } else {
        console.log(`[AUTH] Autenticado com sucesso! Token de sessão ativo.`);
      }
    }

    // PASSO 1: INSERÇÃO DE 3 PRODUTOS DE EXEMPLO
    console.log('\n--- PASSO 1: Inserir 3 produtos de exemplo ---');
    const produtosExemplo = [
      {
        nome: 'Coca-Cola 500ml',
        categoria: 'bebida',
        preco: 50.00,
        apelidos: ['coca', 'cc'],
        ativo: true
      },
      {
        nome: 'Frango Grelhado',
        categoria: 'comida',
        preco: 350.00,
        apelidos: ['frango', 'frango grelhado'],
        ativo: true
      },
      {
        nome: 'Cerveja 2M',
        categoria: 'bebida',
        preco: 80.00,
        apelidos: ['2m', 'dois m'],
        ativo: true
      }
    ];

    const { data: produtosInseridos, error: insertError } = await supabase
      .from('produtos')
      .insert(produtosExemplo)
      .select();

    if (insertError) {
      throw new Error(`Erro no PASSO 1 (Inserção): ${insertError.message} (Código: ${insertError.code})`);
    }

    console.log(`[SUCESSO] ${produtosInseridos.length} produtos inseridos com sucesso:`);
    produtosInseridos.forEach(p => {
      console.log(`  + [${p.id}] ${p.nome} (${p.categoria}) - ${p.preco} MT | Apelidos: [${p.apelidos.join(', ')}]`);
    });

    // Guardar referências para os próximos passos
    const itemParaEditar = produtosInseridos.find(p => p.nome === 'Cerveja 2M') || produtosInseridos[0];
    const itemParaApagar = produtosInseridos.find(p => p.nome === 'Frango Grelhado') || produtosInseridos[1];

    // PASSO 2: LISTAR TODOS OS PRODUTOS
    console.log('\n--- PASSO 2: Listar todos os produtos ---');
    const { data: todosProdutos, error: listError } = await supabase
      .from('produtos')
      .select('*')
      .order('criado_em', { ascending: false });

    if (listError) {
      throw new Error(`Erro no PASSO 2 (Listagem): ${listError.message}`);
    }

    console.log(`[SUCESSO] Total de produtos encontrados na tabela: ${todosProdutos.length}`);
    todosProdutos.forEach((p, idx) => {
      console.log(`  ${idx + 1}. [${p.id}] ${p.nome} | ${p.categoria} | ${p.preco} MT | Ativo: ${p.ativo}`);
    });

    // PASSO 3: EDITAR O PREÇO DE UM PRODUTO
    const novoPreco = 85.00;
    console.log(`\n--- PASSO 3: Editar o preço de "${itemParaEditar.nome}" (${itemParaEditar.preco} MT -> ${novoPreco} MT) ---`);
    const { data: produtoAtualizado, error: updateError } = await supabase
      .from('produtos')
      .update({ preco: novoPreco })
      .eq('id', itemParaEditar.id)
      .select()
      .single();

    if (updateError) {
      throw new Error(`Erro no PASSO 3 (Atualização): ${updateError.message}`);
    }

    console.log(`[SUCESSO] Preço atualizado com sucesso:`);
    console.log(`  * [${produtoAtualizado.id}] ${produtoAtualizado.nome} novo preço: ${produtoAtualizado.preco} MT`);

    // PASSO 4: APAGAR UM PRODUTO
    console.log(`\n--- PASSO 4: Apagar produto "${itemParaApagar.nome}" [${itemParaApagar.id}] ---`);
    const { error: deleteError } = await supabase
      .from('produtos')
      .delete()
      .eq('id', itemParaApagar.id);

    if (deleteError) {
      throw new Error(`Erro no PASSO 4 (Remoção): ${deleteError.message}`);
    }

    console.log(`[SUCESSO] Produto "${itemParaApagar.nome}" apagado com sucesso.`);

    // VALIDAÇÃO FINAL
    console.log('\n--- VALIDAÇÃO FINAL: Conferir estado da tabela após remoção ---');
    const { data: estadoFinal, error: finalError } = await supabase
      .from('produtos')
      .select('id, nome, preco, categoria')
      .order('criado_em', { ascending: false });

    if (finalError) {
      throw new Error(`Erro na validação final: ${finalError.message}`);
    }

    console.log(`[SUCESSO] Total de produtos restantes: ${estadoFinal.length}`);
    estadoFinal.forEach(p => console.log(`  - ${p.nome}: ${p.preco} MT (${p.categoria})`));

    console.log('\n' + '='.repeat(60));
    console.log('  TESTES CONCLUÍDOS COM 100% DE SUCESSO! TABELA E API VALIDADAS.');
    console.log('='.repeat(60));

  } catch (err) {
    console.error(`\n\x1b[31m[FALHA NO TESTE]\x1b[0m ${err.message}`);
    if (err.message.includes('row-level security') || err.message.includes('permission denied')) {
      console.error('\n\x1b[33m[DICA DE CONFIGURAÇÃO RLS/PERMISSÕES]:\x1b[0m');
      console.error('Como o RLS foi ativado apenas para utilizadores autenticados, para correr o script de backend tens duas opções:');
      console.error('1. Adiciona a "SUPABASE_SERVICE_ROLE_KEY" ao ficheiro .env (acesso admin direto de backend).');
      console.error('2. Ou define ADMIN_EMAIL e ADMIN_PASSWORD no .env de um utilizador registado no Supabase Auth.');
    }
    process.exit(1);
  }
}

runTest();
