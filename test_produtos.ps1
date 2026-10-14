# ==============================================================================
# Quinta Malu - Teste de Integração Supabase (PowerShell Nativo)
# Não necessita de Node.js nem Python instalados!
# ==============================================================================

$ErrorActionPreference = "Stop"

# Carregar variáveis do .env
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line.Split("=", 2)
            if ($parts.Length -eq 2) {
                $key = $parts[0].Trim()
                $val = $parts[1].Trim()
                [Environment]::SetEnvironmentVariable($key, $val, "Process")
            }
        }
    }
}

$SUPABASE_URL = [Environment]::GetEnvironmentVariable("SUPABASE_URL")
$SUPABASE_ANON_KEY = [Environment]::GetEnvironmentVariable("SUPABASE_ANON_KEY")
$ADMIN_EMAIL = [Environment]::GetEnvironmentVariable("ADMIN_EMAIL")
$ADMIN_PASSWORD = [Environment]::GetEnvironmentVariable("ADMIN_PASSWORD")

if (-not $SUPABASE_URL -or $SUPABASE_URL -match "your-project" -or $SUPABASE_URL -match "xyzcompany") {
    Write-Host "[ERRO] Por favor, preenche SUPABASE_URL e SUPABASE_ANON_KEY no ficheiro .env antes de executar." -ForegroundColor Red
    exit 1
}

if (-not $SUPABASE_ANON_KEY) {
    Write-Host "[ERRO] SUPABASE_ANON_KEY deve estar preenchida no ficheiro .env." -ForegroundColor Red
    exit 1
}

if (-not $ADMIN_EMAIL -or -not $ADMIN_PASSWORD -or $ADMIN_PASSWORD -match "senha_secreta") {
    Write-Host "[ERRO] Por favor, preenche ADMIN_EMAIL e ADMIN_PASSWORD no ficheiro .env para autenticar." -ForegroundColor Red
    exit 1
}

Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  TESTE SUPABASE REST API - QUINTA MALU (PRODUTOS)" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "URL Supabase : $SUPABASE_URL"
Write-Host "Utilizador   : $ADMIN_EMAIL"
Write-Host ("=" * 60) -ForegroundColor Cyan

# Autenticação no Supabase Auth para obter access_token
Write-Host "`n[AUTH] A autenticar utilizador '$ADMIN_EMAIL'..." -ForegroundColor Yellow

$authHeaders = @{
    "apikey"       = $SUPABASE_ANON_KEY
    "Content-Type" = "application/json"
}

$authBody = ConvertTo-Json -InputObject @{
    email    = $ADMIN_EMAIL
    password = $ADMIN_PASSWORD
}

$accessToken = $null

try {
    $authResponse = Invoke-RestMethod -Uri "$SUPABASE_URL/auth/v1/token?grant_type=password" -Method Post -Headers $authHeaders -Body $authBody
    $accessToken = $authResponse.access_token
    if (-not $accessToken) {
        throw "Token de acesso não foi devolvido pelo Supabase Auth."
    }
    Write-Host "[AUTH] Login efetuado com sucesso! Access token obtido." -ForegroundColor Green
} catch {
    Write-Host "[ERRO] Falha ao autenticar utilizador '$ADMIN_EMAIL': $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "Detalhes: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
    exit 1
}

$headers = @{
    "apikey"        = $SUPABASE_ANON_KEY
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
    "Prefer"        = "return=representation"
}

try {
    # PASSO 1: INSERÇÃO DE 3 PRODUTOS
    Write-Host "`n--- PASSO 1: Inserir 3 produtos de exemplo ---" -ForegroundColor Yellow
    $novosProdutos = @(
        @{
            nome      = "Coca-Cola 500ml"
            categoria = "bebida"
            preco     = 50.00
            custo     = 30.00
            apelidos  = @("coca", "cc")
            ativo     = $true
        },
        @{
            nome      = "Frango Grelhado ¼"
            categoria = "comida"
            preco     = 250.00
            custo     = 120.00
            apelidos  = @("frango", "frango 1/4", "frango grelhado")
            ativo     = $true
        },
        @{
            nome      = "Cerveja 2M"
            categoria = "bebida"
            preco     = 80.00
            custo     = 55.00
            apelidos  = @("2m", "dois m")
            ativo     = $true
        }
    )

    $bodyJson = ConvertTo-Json -InputObject $novosProdutos -Depth 5
    $inserted = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/produtos" -Method Post -Headers $headers -Body $bodyJson

    Write-Host "[SUCESSO] $($inserted.Count) produtos inseridos com sucesso:" -ForegroundColor Green
    foreach ($p in $inserted) {
        $apelidosStr = ($p.apelidos -join ", ")
        $lucro = [decimal]$p.preco - [decimal]$p.custo
        Write-Host "  + [$($p.id)] $($p.nome) ($($p.categoria)) - Preço: $($p.preco) MT | Custo: $($p.custo) MT | Lucro: $lucro MT | Apelidos: [$apelidosStr]"
    }

    $itemParaEditar = $inserted | Where-Object { $_.nome -eq "Cerveja 2M" } | Select-Object -First 1
    if (-not $itemParaEditar) { $itemParaEditar = $inserted[0] }

    $itemParaApagar = $inserted | Where-Object { $_.nome -like "*Frango*" } | Select-Object -First 1
    if (-not $itemParaApagar) { $itemParaApagar = $inserted[1] }

    # PASSO 2: LISTAR TODOS OS PRODUTOS
    Write-Host "`n--- PASSO 2: Listar todos os produtos ---" -ForegroundColor Yellow
    $todos = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/produtos?select=*&order=criado_em.desc" -Method Get -Headers $headers

    Write-Host "[SUCESSO] Total de produtos na tabela: $($todos.Count)" -ForegroundColor Green
    $i = 1
    foreach ($p in $todos) {
        $lucro = [decimal]$p.preco - [decimal]$p.custo
        Write-Host "  $i. [$($p.id)] $($p.nome) | $($p.categoria) | Preço: $($p.preco) MT | Custo: $($p.custo) MT | Lucro: $lucro MT | Ativo: $($p.ativo)"
        $i++
    }

    # PASSO 3: EDITAR PREÇO DE UM PRODUTO
    Write-Host "`n--- PASSO 3: Editar o preço de '$($itemParaEditar.nome)' ($($itemParaEditar.preco) MT -> 85.00 MT) ---" -ForegroundColor Yellow
    $updateBody = ConvertTo-Json -InputObject @{ preco = 85.00 }
    $updated = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/produtos?id=eq.$($itemParaEditar.id)" -Method Patch -Headers $headers -Body $updateBody

    $novoLucro = [decimal]$updated[0].preco - [decimal]$updated[0].custo
    Write-Host "[SUCESSO] Preço atualizado com sucesso:" -ForegroundColor Green
    Write-Host "  * [$($updated[0].id)] $($updated[0].nome) novo preço: $($updated[0].preco) MT | Custo: $($updated[0].custo) MT | Novo Lucro: $novoLucro MT"

    # PASSO 4: APAGAR UM PRODUTO
    Write-Host "`n--- PASSO 4: Apagar produto '$($itemParaApagar.nome)' [$($itemParaApagar.id)] ---" -ForegroundColor Yellow
    $null = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/produtos?id=eq.$($itemParaApagar.id)" -Method Delete -Headers $headers

    Write-Host "[SUCESSO] Produto '$($itemParaApagar.nome)' apagado com sucesso." -ForegroundColor Green

    # VALIDAÇÃO FINAL
    Write-Host "`n--- VALIDAÇÃO FINAL: Conferir produtos restantes ---" -ForegroundColor Yellow
    $finais = Invoke-RestMethod -Uri "$SUPABASE_URL/rest/v1/produtos?select=id,nome,preco,custo,categoria&order=criado_em.desc" -Method Get -Headers $headers
    Write-Host "[SUCESSO] Total restante: $($finais.Count)" -ForegroundColor Green
    foreach ($p in $finais) {
        $lucro = [decimal]$p.preco - [decimal]$p.custo
        Write-Host "  - $($p.nome): Preço $($p.preco) MT | Custo $($p.custo) MT | Lucro $lucro MT ($($p.categoria))"
    }

    Write-Host "`n$('=' * 60)" -ForegroundColor Cyan
    Write-Host "  TESTES CONCLUÍDOS COM 100% DE SUCESSO!" -ForegroundColor Cyan
    Write-Host "$('=' * 60)" -ForegroundColor Cyan

} catch {
    Write-Host "`n[FALHA NO TESTE] $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "Detalhes: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
    exit 1
}
