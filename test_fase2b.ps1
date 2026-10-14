param(
    [string]$FotoPath = (Join-Path $PSScriptRoot "caderno.jpg..jpg")
)

$ErrorActionPreference = "Stop"

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

$SUPABASE_URL = [Environment]::GetEnvironmentVariable("SUPABASE_URL")
$SUPABASE_ANON_KEY = [Environment]::GetEnvironmentVariable("SUPABASE_ANON_KEY")
$ADMIN_EMAIL = [Environment]::GetEnvironmentVariable("ADMIN_EMAIL")
$ADMIN_PASSWORD = [Environment]::GetEnvironmentVariable("ADMIN_PASSWORD")

if (-not $SUPABASE_URL -or -not $SUPABASE_ANON_KEY) {
    throw "Preenche SUPABASE_URL e SUPABASE_ANON_KEY no .env."
}
if (-not $ADMIN_EMAIL -or -not $ADMIN_PASSWORD) {
    throw "Preenche ADMIN_EMAIL e ADMIN_PASSWORD no .env."
}
if (-not (Test-Path $FotoPath -PathType Leaf)) {
    throw "Foto nao encontrada: $FotoPath. Passa o caminho com -FotoPath."
}

$authHeaders = @{
    "apikey" = $SUPABASE_ANON_KEY
    "Content-Type" = "application/json"
}
$authBody = ConvertTo-Json -InputObject @{
    email = $ADMIN_EMAIL
    password = $ADMIN_PASSWORD
}
$auth = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/auth/v1/token?grant_type=password" `
    -Method Post -Headers $authHeaders -Body $authBody
if (-not $auth.access_token) {
    throw "O Supabase Auth nao devolveu um token de acesso."
}

$headers = @{
    "apikey" = $SUPABASE_ANON_KEY
    "Authorization" = "Bearer $($auth.access_token)"
    "Content-Type" = "application/json"
    "Prefer" = "return=representation"
}

$produtos = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/produtos?select=id,nome,preco,custo&ativo=eq.true&order=nome.asc" `
    -Method Get -Headers $headers
if (-not $produtos -or $produtos.Count -eq 0) {
    throw "Cria pelo menos um produto ativo antes de executar este teste."
}
$produtoCorrecao = $produtos[0]

$fotoBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $FotoPath))
$reqBody = ConvertTo-Json -Depth 8 -Compress -InputObject @{
    foto_base64 = [Convert]::ToBase64String($fotoBytes)
    data_venda = (Get-Date).ToString("yyyy-MM-dd")
}
$resultado = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/functions/v1/processar-caderno" `
    -Method Post -Headers $headers -Body $reqBody

if ($resultado.estado -ne "rascunho" -or -not $resultado.sessao_id) {
    throw "A Edge Function nao criou uma sessao em rascunho."
}
if (-not $resultado.itens -or $resultado.itens.Count -eq 0) {
    throw "A Edge Function nao devolveu itens para rever."
}

$sessaoId = $resultado.sessao_id
$itens = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/venda_sessao_itens?select=id,texto_original,produto_id,quantidade,confianca,estado&sessao_id=eq.$sessaoId&order=criado_em.asc" `
    -Method Get -Headers $headers
if (-not $itens -or $itens.Count -eq 0) {
    throw "Nao foram encontrados itens persistidos para o rascunho."
}

$item = $itens[0]
$quantidadeCorrigida = [int]$item.quantidade + 1
$correcao = ConvertTo-Json -Compress -InputObject @{
    p_item_id = $item.id
    p_produto_id = $produtoCorrecao.id
    p_quantidade = $quantidadeCorrigida
}
$null = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/rpc/corrigir_item_venda" `
    -Method Post -Headers $headers -Body $correcao

$itemCorrigido = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/venda_sessao_itens?select=id,produto_id,quantidade,estado&id=eq.$($item.id)" `
    -Method Get -Headers $headers
if (
    $itemCorrigido.Count -ne 1 -or
    $itemCorrigido[0].produto_id -ne $produtoCorrecao.id -or
    [int]$itemCorrigido[0].quantidade -ne $quantidadeCorrigida -or
    $itemCorrigido[0].estado -ne "reconhecido"
) {
    throw "A correcao do item nao foi persistida como esperado."
}

$itemManualBody = ConvertTo-Json -Compress -InputObject @{
    p_sessao_id = $sessaoId
    p_texto_original = "linha manual de teste"
    p_produto_id = $null
    p_quantidade = 1
}
$itemManualId = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/rpc/adicionar_item_venda" `
    -Method Post -Headers $headers -Body $itemManualBody

$confirmacaoBody = ConvertTo-Json -Compress -InputObject @{ p_sessao_id = $sessaoId }
$confirmacaoBloqueada = $false
try {
    $null = Invoke-RestMethod `
        -Uri "$SUPABASE_URL/rest/v1/rpc/confirmar_sessao_venda" `
        -Method Post -Headers $headers -Body $confirmacaoBody
} catch {
    if ($_.ErrorDetails.Message -notmatch "existem itens por rever") {
        throw "A confirmacao falhou por um motivo inesperado."
    }
    $confirmacaoBloqueada = $true
}
if (-not $confirmacaoBloqueada) {
    throw "A sessao foi confirmada apesar de ter um item por rever."
}

$manualCorrecao = ConvertTo-Json -Compress -InputObject @{
    p_item_id = $itemManualId
    p_produto_id = $produtoCorrecao.id
    p_quantidade = 1
}
$null = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/rpc/corrigir_item_venda" `
    -Method Post -Headers $headers -Body $manualCorrecao

$itensPorRever = $itens | Where-Object { $_.estado -eq "por_rever" }
foreach ($itemPendente in $itensPorRever) {
    if ($itemPendente.id -eq $item.id) { continue }
    $pendenteBody = ConvertTo-Json -Compress -InputObject @{
        p_item_id = $itemPendente.id
        p_produto_id = $produtoCorrecao.id
        p_quantidade = [int]$itemPendente.quantidade
    }
    $null = Invoke-RestMethod `
        -Uri "$SUPABASE_URL/rest/v1/rpc/corrigir_item_venda" `
        -Method Post -Headers $headers -Body $pendenteBody
}

$confirmacao = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/rpc/confirmar_sessao_venda" `
    -Method Post -Headers $headers -Body $confirmacaoBody
if ($confirmacao.estado -ne "confirmada") {
    throw "A sessao nao foi confirmada."
}

$sessoes = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/venda_sessoes?select=id,estado,total_bruto&id=eq.$sessaoId" `
    -Method Get -Headers $headers
$vendas = Invoke-RestMethod `
    -Uri "$SUPABASE_URL/rest/v1/vendas?select=id,produto_id,quantidade,preco_unit,custo_unit,subtotal,produtos(nome)&sessao_id=eq.$sessaoId&order=criado_em.asc" `
    -Method Get -Headers $headers

if ($sessoes.Count -ne 1 -or $sessoes[0].estado -ne "confirmada") {
    throw "O estado confirmado da sessao nao foi persistido."
}
if ($vendas.Count -ne ($itens.Count + 1)) {
    throw "Esperadas $($itens.Count + 1) vendas, mas foram gravadas $($vendas.Count)."
}

$totalVendas = [decimal]0
$totalCustos = [decimal]0
Write-Host "Sessao confirmada: $sessaoId"
foreach ($venda in $vendas) {
    if ($null -eq $venda.preco_unit -or $null -eq $venda.custo_unit) {
        throw "Venda $($venda.id) nao tem snapshot de preco e custo."
    }
    $precoLinha = [decimal]$venda.preco_unit * [int]$venda.quantidade
    $custoLinha = [decimal]$venda.custo_unit * [int]$venda.quantidade
    $lucroLinha = $precoLinha - $custoLinha
    $totalVendas += $precoLinha
    $totalCustos += $custoLinha
    Write-Host (
        "{0} x{1} | Preco unit.: {2:N2} MT | Custo unit.: {3:N2} MT | Lucro: {4:N2} MT" -f
        $venda.produtos.nome, $venda.quantidade, $venda.preco_unit, $venda.custo_unit, $lucroLinha
    )
}

if ([math]::Abs($totalVendas - [decimal]$sessoes[0].total_bruto) -gt [decimal]0.01) {
    throw "O total da sessao nao corresponde ao total das vendas."
}

Write-Host ("Total de vendas: {0:N2} MT | Custo: {1:N2} MT | Lucro bruto: {2:N2} MT" -f `
    $totalVendas, $totalCustos, ($totalVendas - $totalCustos))
Write-Host "FASE 2B: teste concluido com sucesso."
