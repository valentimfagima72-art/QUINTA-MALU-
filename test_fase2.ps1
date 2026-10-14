# ==============================================================================
# Quinta Malu — Fase 2: Teste da Edge Function processar-caderno
# Envia uma foto de um caderno de vendas e verifica os lançamentos criados
# ==============================================================================

$ErrorActionPreference = "Stop"

# ── Carregar .env ─────────────────────────────────────────────────────────────
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line.Split("=", 2)
            if ($parts.Length -eq 2) {
                [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), "Process")
            }
        }
    }
}

$SUPABASE_URL        = [Environment]::GetEnvironmentVariable("SUPABASE_URL")
$SUPABASE_ANON_KEY   = [Environment]::GetEnvironmentVariable("SUPABASE_ANON_KEY")
$ADMIN_EMAIL         = [Environment]::GetEnvironmentVariable("ADMIN_EMAIL")
$ADMIN_PASSWORD      = [Environment]::GetEnvironmentVariable("ADMIN_PASSWORD")

# ── Validações ────────────────────────────────────────────────────────────────
if (-not $SUPABASE_URL -or $SUPABASE_URL -match "xyzcompany") {
    Write-Host "[ERRO] Preenche SUPABASE_URL no ficheiro .env" -ForegroundColor Red; exit 1
}
if (-not $ADMIN_EMAIL -or $ADMIN_PASSWORD -match "senha_secreta") {
    Write-Host "[ERRO] Preenche ADMIN_EMAIL e ADMIN_PASSWORD no ficheiro .env" -ForegroundColor Red; exit 1
}

# ── Configuração do ficheiro de imagem ────────────────────────────────────────
# Podes mudar este caminho para a foto real do caderno
$FOTO_PATH = Join-Path $PSScriptRoot "teste_caderno.jpg"

if (-not (Test-Path $FOTO_PATH)) {
    Write-Host "[INFO] Ficheiro '$FOTO_PATH' não encontrado." -ForegroundColor Yellow
    Write-Host "[INFO] A criar imagem de teste simulada (PNG com texto)..." -ForegroundColor Yellow

    # Criar imagem PNG mínima válida (1x1 pixel branco) como placeholder
    # Em produção, usa uma foto real do caderno
    $pngBytes = [byte[]](
        0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,  # PNG signature
        0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,  # IHDR chunk
        0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,  # 1x1
        0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,  # bit depth, color type
        0xDE,0x00,0x00,0x00,0x0C,0x49,0x44,0x41,  # IDAT chunk
        0x54,0x08,0xD7,0x63,0xF8,0xFF,0xFF,0x3F,
        0x00,0x05,0xFE,0x02,0xFE,0xA7,0x35,0x81,
        0x84,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,  # IEND chunk
        0x44,0xAE,0x42,0x60,0x82
    )
    [System.IO.File]::WriteAllBytes($FOTO_PATH, $pngBytes)
    Write-Host "[INFO] Imagem placeholder criada em: $FOTO_PATH" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ⚠️  ATENÇÃO: Para teste real, substitui 'teste_caderno.jpg'" -ForegroundColor Magenta
    Write-Host "  pelo caminho da tua foto real do caderno de vendas." -ForegroundColor Magenta
    Write-Host ""
}

Write-Host ("=" * 65) -ForegroundColor Cyan
Write-Host "  FASE 2 — TESTE: PROCESSAR CADERNO DE VENDAS (GEMINI VISION)" -ForegroundColor Cyan
Write-Host ("=" * 65) -ForegroundColor Cyan
Write-Host "URL Supabase : $SUPABASE_URL"
Write-Host "Foto         : $FOTO_PATH"
Write-Host ("=" * 65) -ForegroundColor Cyan

# ── PASSO 1: Autenticação ─────────────────────────────────────────────────────
Write-Host "`n[AUTH] A autenticar utilizador '$ADMIN_EMAIL'..." -ForegroundColor Yellow

$authBody = ConvertTo-Json -InputObject @{ email = $ADMIN_EMAIL; password = $ADMIN_PASSWORD }
$authHeaders = @{ "apikey" = $SUPABASE_ANON_KEY; "Content-Type" = "application/json" }

try {
    $authResp = Invoke-RestMethod -Uri "$SUPABASE_URL/auth/v1/token?grant_type=password" `
        -Method Post -Headers $authHeaders -Body $authBody
    $accessToken = $authResp.access_token
    Write-Host "[AUTH] Login efetuado com sucesso!" -ForegroundColor Green
} catch {
    Write-Host "[ERRO] Falha no login: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host "Detalhes: $($_.ErrorDetails.Message)" -ForegroundColor Red }
    exit 1
}

$apiHeaders = @{
    "apikey"        = $SUPABASE_ANON_KEY
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

# ── PASSO 2: Converter foto em base64 ────────────────────────────────────────
Write-Host "`n[PASSO 2] A converter foto em base64..." -ForegroundColor Yellow
$fotoBytes   = [System.IO.File]::ReadAllBytes($FOTO_PATH)
$fotoBase64  = [Convert]::ToBase64String($fotoBytes)
$tamanhoKB   = [math]::Round($fotoBytes.Length / 1024, 1)
Write-Host "[SUCESSO] Foto convertida: $tamanhoKB KB ($($fotoBytes.Length) bytes)" -ForegroundColor Green

# ── PASSO 3: Chamar a Edge Function processar-caderno ────────────────────────
Write-Host "`n[PASSO 3] A chamar a Edge Function 'processar-caderno'..." -ForegroundColor Yellow

$dataHoje = (Get-Date).ToString("yyyy-MM-dd")
$reqBody  = ConvertTo-Json -InputObject @{
    foto_base64 = $fotoBase64
    data_venda  = $dataHoje
} -Compress

$edgeFunctionUrl = "$SUPABASE_URL/functions/v1/processar-caderno"

try {
    $resultado = Invoke-RestMethod -Uri $edgeFunctionUrl `
        -Method Post -Headers $apiHeaders -Body $reqBody

    Write-Host "[SUCESSO] Edge Function respondeu com sucesso!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  📋 Sessão criada    : $($resultado.sessao_id)"
    Write-Host "  📅 Data da venda    : $($resultado.data_venda)"
    Write-Host "  ✅ Reconhecidos     : $($resultado.produtos_reconhecidos) produto(s)"
    Write-Host "  ❌ Não reconhecidos : $($resultado.produtos_nao_reconhecidos.Count) produto(s)"
    Write-Host "  💰 Total bruto      : $($resultado.total_bruto) MT"

    if ($resultado.produtos_nao_reconhecidos.Count -gt 0) {
        Write-Host ""
        Write-Host "  Palavras não reconhecidas (adiciona aos apelidos da tabela produtos):" -ForegroundColor Magenta
        foreach ($nr in $resultado.produtos_nao_reconhecidos) {
            Write-Host "    - $nr" -ForegroundColor Magenta
        }
    }

    if ($resultado.linhas.Count -gt 0) {
        Write-Host ""
        Write-Host "  Linhas lançadas:" -ForegroundColor Cyan
        foreach ($linha in $resultado.linhas) {
            Write-Host "    + $($linha.produto_nome) x$($linha.quantidade) @ $($linha.preco_unit) MT = $($linha.subtotal) MT"
        }
    }

} catch {
    Write-Host "[ERRO] Edge Function falhou: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "Detalhes: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Verifica:" -ForegroundColor Yellow
    Write-Host "  1. A Edge Function foi publicada no Supabase? (ver README_FASE2.md)" -ForegroundColor Yellow
    Write-Host "  2. O secret GEMINI_API_KEY foi configurado no Supabase Dashboard?" -ForegroundColor Yellow
    Write-Host "  3. A migration 20261013000003_create_vendas.sql foi executada?" -ForegroundColor Yellow
    exit 1
}

# ── PASSO 4: Verificar registos criados na base de dados ─────────────────────
Write-Host "`n[PASSO 4] A verificar registos criados na base de dados..." -ForegroundColor Yellow

$sessoes = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/venda_sessoes?order=criado_em.desc&limit=3" `
    -Method Get -Headers $apiHeaders

Write-Host "[SUCESSO] Últimas sessões de venda na base de dados:" -ForegroundColor Green
foreach ($s in $sessoes) {
    Write-Host "  📋 [$($s.id)] $($s.data_venda) | $($s.produtos_reconhecidos) produto(s) | $($s.total_bruto) MT"
}

$sessaoId = $resultado.sessao_id
$linhasDb = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/vendas?sessao_id=eq.$sessaoId&select=*,produtos(nome,preco)" `
    -Method Get -Headers $apiHeaders

Write-Host ""
Write-Host "[SUCESSO] Linhas de venda desta sessão:" -ForegroundColor Green
foreach ($v in $linhasDb) {
    $nome = if ($v.produtos) { $v.produtos.nome } else { "produto_id: $($v.produto_id)" }
    Write-Host "  + $nome x$($v.quantidade) @ $($v.preco_unit) MT = $($v.subtotal) MT"
}

Write-Host ""
Write-Host ("=" * 65) -ForegroundColor Cyan
Write-Host "  FASE 2 CONCLUÍDA COM SUCESSO!" -ForegroundColor Cyan
Write-Host ("=" * 65) -ForegroundColor Cyan
