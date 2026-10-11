# Auren_Wipe 1.0.6

Resource de administração para FiveM, com interface preta, branca e cinza, animações,
wipe seletivo, revisão de impacto, backup transacional e histórico persistente.

## Instalação na MRI QBOX padrão

1. Copie a pasta **Auren_Wipe** para `resources/[standalone]/Auren_Wipe`.
2. Acrescente `ensure Auren_Wipe` ao `server.cfg`, depois do `ensure oxmysql` e dos resources da base.
3. Entre com um administrador já autorizado na base e use **/apexwipe**.

Não é necessário importar SQL, editar tabelas ou montar consultas para cada wipe.
As três tabelas próprias são criadas e a auditoria é migrada automaticamente.
O usuário do MySQL precisa de permissões de leitura de schema, CREATE/ALTER nas tabelas
próprias e SELECT/INSERT/UPDATE/DELETE nas tabelas atendidas.

Na base padrão, as permissões ACE `admin`, `god` ou `command` e a integração opcional
do core reconhecem administradores existentes. Se a base usa uma política de acesso
diferente, conceda apenas aos administradores responsáveis:

```cfg
add_ace group.admin apex.wipe.admin allow
```

Esse ajuste é opcional na MRI padrão. A ACE `apex.wipe.admin` é também a opção direta
para usar o painel sem framework. Não conceda essa permissão a jogadores comuns.
Permissões são verificadas no servidor em todas as ações, inclusive buscas e histórico.
`Config.ExecuteAce` permite separar administradores de revisão e execução, se desejado.

## Uso

Escolha o alcance, encontre o alvo pela busca, selecione as categorias e informe o motivo.
**Simular e revisar** somente consulta o banco. A revisão mostra tabelas, campos,
quantidade de registros, tamanho estimado do backup e eventuais impedimentos.
Para executar, digite a frase apresentada e confirme a manutenção. O plano expira em
180 segundos, pertence ao administrador que o criou e só pode ser usado uma vez.

| Alcance | Comportamento |
| --- | --- |
| Personagem | Busca por nome/citizenid. Reinicia inventário, dinheiro ou compartimentos; pode remover veículos ou o personagem e seus vínculos conhecidos. Também atende personagens offline. |
| Baú | Limpa o conteúdo pelo nome e proprietário exatos. Proprietário vazio identifica o baú compartilhado. Mantém o cadastro do baú. |
| Garagem | Limpa compartimentos ou remove veículos vinculados à garagem escolhida. Mantém a definição da garagem. |
| Servidor inteiro | Aplica somente as categorias selecionadas em todos os registros das tabelas atendidas. |

Dinheiro significa o JSON `players.money`. As moedas declaradas no core são zeradas,
incluindo `coin` na configuração MRI reconhecida. Contas de scripts bancários externos
não são alteradas. Remover um personagem inclui veículos, grupos e conteúdo dos baús
pessoais que usam o citizenid como proprietário; aparência e dados pessoais NPWD
conhecidos são incluídos quando detectados.

Ao remover perfis NPWD, o plano também inclui visualizações/curtidas do Match e
publicações, curtidas e denúncias do Twitter vinculadas aos perfis/publicações atingidos.
Isso inclui referências feitas por outros personagens ao perfil removido; dados sem
vínculo com o alvo permanecem. Todos esses registros entram no backup antes da exclusão.
As relações são conhecidas e revisadas; tabelas externas desconhecidas continuam bloqueadas.

Imóveis ps-housing e qbx_properties são detectados pelo schema: o proprietário é
desvinculado e as chaves pessoais são limpas antes da remoção do personagem.
Cadastros, preços, interiores, decoração e coordenadas permanecem. Casas ps-housing
liberadas voltam à venda; apartamentos permanecem sem dono. Os baús ps-housing
identificados pelo imóvel/mobília são esvaziados. Acessos `characters` das portas
ox_doorlock são limpos, preservando o restante do JSON original. As linhas anteriores
inteiras entram no backup. Nenhuma dessas integrações exige configuração adicional.
Esses dois formatos são reconhecidos pela estrutura de colunas, sem edição de SQL.

As comparações entre tabelas detectam automaticamente charset e collation das
colunas. Quando os formatos diferem, a consulta adapta a comparação ao identificador
de destino; charsets legados usam uma comparação Unicode sem conversão com perda.
Isso cobre NPWD, baús, pátio, financiamentos e as guardas de foreign keys, sem alterar
collations das tabelas ou seus dados. A simulação também salva o diagnóstico de
estrutura automaticamente quando uma consulta não consegue ser concluída.

**A execução inicia uma manutenção em toda a cidade, inclusive para um alvo único.**
O sistema salva jogadores/inventários pelas integrações disponíveis, avisa e desconecta
os outros jogadores, pausa resources com scripts de servidor ou compartilhados e aguarda
os dados estabilizarem. Infraestrutura e mapas exclusivamente de cliente permanecem ativos.
Depois, faz backup e alteração na mesma transação. O operador recebe o resultado e é
desconectado após 15 segundos, antes da retomada automática dos resources anteriormente
ativos. A reconexão carrega os dados atualizados sem reutilizar as sessões anteriores.

A ordem de pausa/retomada respeita dependências declaradas e includes `@resource/arquivo`.
As integrações opcionais ZSX Garages/Dealership com ZSX_UIV2 são reconhecidas também
quando faltam no manifest: garagem e concessionária param antes da interface e retomam
depois dela. VehicleDeformation permanece disponível até o fechamento da garagem.
Isso não altera arquivos dos scripts ZSX. Chamadas NUI já em andamento em outros
resources ainda podem ser canceladas durante uma parada; erros de cliente não substituem
o resultado da operação no histórico e no console do Apex.

Ao remover veículos, o sistema identifica as entidades correspondentes por vehicleid
ou placa antes da transação e as remove do mundo somente após o commit. Veículos fora
do alvo ficam preservados. Se a identidade mudar, a remoção falhar ou essa limpeza for
interrompida, o banco continua com o resultado registrado, mas a manutenção permanece
ativa para revisão pelo console; não retoma gameplay com veículos antigos sem confirmação.

Se uma execução falhar, consulte o histórico e o console pelo ID mostrado antes de tentar
novamente. Nunca interprete timeout ou ausência de resposta como confirmação de sucesso.

## Proteção de configurações e backup

O navegador envia opções e alvos; ele não pode escolher SQL, tabelas ou predicados.
O servidor usa parâmetros para os valores e uma lista explícita de operações conhecidas.
Não executa DROP, TRUNCATE, reset de IDs nem desativa foreign keys.

Tabelas desconhecidas, bans, contas mistas de terceiros e tabelas cujo nome contenha
`config` ou `setting` ficam fora do wipe. Os arquivos de outros resources não são editados.
Baús mantêm os registros; somente o conteúdo é zerado. Configurações de imóveis,
garagens e outros scripts ficam preservadas pelo escopo conservador dos adaptadores.

Tabelas afetadas precisam ser InnoDB, sem efeitos ativos desconhecidos ou colunas que o
backup JSON não suporta. Triggers de outro evento não bloqueiam a operação. Os três
triggers padrão do RHD Garage são detectados pela definição completa, com seus efeitos
incluídos no backup automaticamente. Foreign keys não cobertas, ciclos e relações externas visíveis bloqueiam a
remoção. Uma alteração de alcance durante a manutenção também bloqueia a operação.
A transação verifica novamente o conteúdo e salva todos os registros atingidos antes
das alterações; erro SQL reverte backup, auditoria de sucesso e wipe juntos.

O backup inclui a linha completa anterior de cada alvo, inclusive campos que não serão
alterados. Ele fica em `apex_wipe_snapshots`; a operação fica em `apex_wipe_jobs`.
`apex_wipe_guards` é uma tabela interna de controle. Essas tabelas nunca entram no wipe.
O backup cobre os alvos do plano, não é um dump de todo o banco nem de arquivos do servidor.

Limites padrão: 50.000 linhas e 64 MiB estimados por plano. Planos maiores são recusados.
Processos externos ao FXServer que escrevem no banco não podem ser pausados por este
resource; interrompa esses escritores antes de usar o sistema.

## Integrações automáticas da garagem

O plano detecta `police_impound` e `vehicle_financing` quando aplicáveis. Remover veículos
inclui os registros correspondentes do pátio e os financiamentos, com backup e exclusão
antes dos veículos. Cadastros/configurações de garagens ficam preservados.

No wipe de porta-malas/porta-luvas, o backup também cobre os registros do pátio que os
triggers da garagem podem afetar. Os triggers originais permanecem ativos e mantêm seu
comportamento: o trigger padrão remove do pátio os veículos cujo estado é diferente de 2,
mesmo quando a alteração principal é nos compartimentos. Essa consequência aparece na
revisão como **backup e efeitos automáticos da garagem**. Estado 2 ou NULL é preservado.

Não é necessário editar SQL, apagar triggers ou cadastrar manualmente essas dependências.
O sistema compara corpo, evento e momento do trigger; um nome conhecido com corpo
modificado não é aceito automaticamente. Definições, colunas e relações são verificadas
novamente antes de executar. Triggers personalizados ativos que ainda não são reconhecidos
continuam bloqueados, pois podem afetar dados/configurações fora do plano.

Quando há triggers personalizados, a simulação lista os impedimentos encontrados juntos
e salva automaticamente `diagnostics/latest.json` na pasta do resource para suporte.
Esse relatório contém estrutura/definições, sem linhas de jogadores; não é enviado completo
à interface. A gravação depende de acesso de escrita à pasta diagnostics.

## Histórico e recuperação

O histórico persiste no banco entre reinícios e registra:

- nome do administrador no servidor e licença;
- license2, Discord, FiveM e Steam, quando disponíveis;
- ID de sessão, citizenid e nome do personagem do administrador, quando disponíveis;
- data do banco, motivo, alvo, alcance, categorias, quantidades e resultado;
- ID que vincula a operação aos snapshots de backup.

O IP não é coletado. A interface apresenta as 30 operações mais recentes, com filtro,
detalhes e exportação CSV. Todos os registros anteriores continuam no banco. O CSV da
NUI contém o histórico carregado, não os inventários ou dados dos snapshots.

Para exportar um backup completo, use **somente no console do servidor**:

```text
apex_wipe_export <id-da-operacao>
```

O JSON será salvo em `Auren_Wipe/backups/<id>.json`. A NUI nunca recebe os snapshots.
O arquivo contém dados dos jogadores: mantenha-o no armazenamento administrativo.
Para restaurar, faça uma cópia do estado atual, mantenha os escritores parados e use as
linhas originais do JSON ou da tabela de snapshots com o plano registrado. Restaure os
campos reiniciados por suas chaves originais; para exclusões, restaure pais antes dos
filhos. Não use REPLACE nem importação indiscriminada sobre dados criados após o wipe.
Não há botão de restauração automática nesta versão.

O estado de manutenção é salvo em KVP antes de pausar os resources. Em reinício do
Auren_Wipe, o sistema tenta retomar a lista original. Se o resultado de uma transação
interrompida for incerto, conserva a manutenção e exige verificar o ID no banco/console.
Depois dessa verificação, o console dispõe de:

```text
apex_wipe_resume
```

Se um resource não reiniciar, a cidade continua bloqueada e o console informa seu nome.
Resolva o erro do resource e execute a retomada pelo console. Esse comando não refaz o wipe.

## Interface invisível e DEV.HTML

A NUI de produção inicia com a página inteira oculta e fundo transparente. A trava do
`body` fica embutida no HTML e não depende de carregar o CSS ou o aplicativo principal.
Não há tema escuro aplicado ao canvas da página nem desfoque de fundo do CEF.
O cliente limpa o foco imediatamente ao carregar e ao iniciar/parar o resource. A abertura
exige resposta autorizada do servidor; o foco só é ativado depois que a NUI confirma a
renderização dessa abertura. Eventos locais e confirmações atrasadas são recusados.
Mensagens sem o canal próprio não abrem a página. Esc fecha a revisão e depois o painel.

Abra **DEV.HTML** com dois cliques para testar o visual e as animações fora do FiveM.
Todos os dados, backups e operações dessa prévia são fictícios e ficam somente na memória.
Recarregar restaura a demonstração. Ela exige a marca explícita de prévia do DEV.HTML,
um arquivo local ou HTTP localhost e ausência da API NUI do FiveM. A página de produção
não ativa a demonstração por parâmetros da URL. O arquivo demo.js não é distribuído
como arquivo da NUI pelo manifest.

Opcionalmente, para servir a prévia local com Python:

```text
python -m http.server 8788 --bind 127.0.0.1
```

Execute na pasta Auren_Wipe e abra `http://127.0.0.1:8788/DEV.HTML`.
O servidor de prévia não conecta ao banco; encerre-o com Ctrl+C após visualizar.

Ao atualizar de uma versão anterior, substitua o pacote completo, incluindo client, web e
fxmanifest.lua, e execute `restart Auren_Wipe` no console do servidor. Preserve quaisquer
arquivos próprios de backup e ajustes administrativos de config.server.lua.

## Compatibilidade real

**Dependência obrigatória: oxmysql.** O painel, notificações, comunicação, permissões ACE,
auditoria e manutenção não dependem de ox_lib, QBOX, QBCore ou ESX.

| Ambiente | Atendimento nesta versão |
| --- | --- |
| MRI QBOX / QBOX com ox_inventory | Adaptadores padrão para players, player_groups, player_vehicles e ox_inventory; integração opcional de salvamento/permissões/cadastro do core. |
| QBCore | Integração opcional de permissões, personagem e salvamento. Categorias funcionam quando as tabelas/colunas são compatíveis; baús de qb-inventory não possuem adaptador nesta versão. |
| Sem framework | Painel e administração por ACE; wipe apenas sobre o schema conhecido presente no banco. |
| ESX, vRP, inventários e scripts personalizados | Não há mapeamento automático desses schemas. Categorias incompatíveis são bloqueadas; não são convertidas por suposição. |

Standalone não significa apagar corretamente qualquer estrutura de banco existente.
Scripts de terceiros podem misturar dados pessoais e configurações. Para cobrir tabelas
adicionais de personagem, um desenvolvedor pode registrar adaptadores revisados em
`Config.CharacterAdapters`; tabelas protegidas continuam proibidas. Isso é opcional e
não é necessário para os adaptadores da base padrão. Dados desconhecidos sem relações
detectáveis permanecem no banco; o painel não promete apagar todos os dados de todo plugin.

## Verificação e referências

Os testes incluídos nesta correção cobrem a visibilidade inicial, mensagens de abertura,
fechamento, reinício, respostas atrasadas e foco. São 12 regressões JavaScript e 7 testes
de cliente Lua com natives simuladas. Há também 9 testes de relações NPWD usando os
planos e transações Lua em SQLite isolado, com FKs, backup e rollback ativos. Eles cobrem
alvos individuais/globais, preservação de configurações e bloqueio de relações desconhecidas.
SQLite valida esses cenários sem substituir um teste da implementação em MySQL/oxmysql.
Os testes não conectam ao servidor do usuário. A transparência
foi verificada no navegador sobre um fundo quadriculado, também sem CSS e sem app.js.
O DEV.HTML foi verificado separadamente com dados fictícios.
Há mais 17 regressões de garagem e preflight, incluindo os três corpos de trigger
encontrados no SQL da RHD Garage, preservação de outros alvos, backup de efeitos,
rollback, alterações de schema, diagnóstico e permissões. Mais 20 regressões cobrem
imóveis nos dois formatos, acessos, portas, baús, backups e mudanças de dados/alvos.
As 65 regressões anteriores passaram novamente. A versão 1.0.5 também foi validada
em uma instância MariaDB nativa separada, com dados fictícios: o erro de collations
da captura foi reproduzido e os planos corrigidos foram medidos/executados com
backup, rollback, imóveis, NPWD e triggers RHD. Nenhum banco da cidade foi acessado.
Os testes de desenvolvimento ficam separados do pacote de produção.
Na versão 1.0.6, oito simulações adicionais verificam parada/retomada, dependências
ZSX, includes externos, recursos opcionais ausentes, recuperação da ordem antiga
e bloqueio de ciclos antes de qualquer salvamento ou desconexão.
Não houve teste em um FXServer/MRI QBOX ativo; valide a instalação em uma cópia da sua
base antes da primeira operação real, especialmente se houver scripts personalizados.

As integrações usam as APIs e schemas dos projetos:
[QBOX](https://docs.qbox.re/resources/qbx_core/exports/server),
[MRI QBOX](https://www.mriqbox.com.br/docs/mri/resources/qbx_core),
[QBCore](https://github.com/qbcore-framework/qb-core/blob/main/server/functions.lua),
[ox_inventory](https://github.com/overextended/ox_inventory/blob/main/modules/inventory/server.lua),
[oxmysql](https://overextended.dev/docs/oxmysql/Functions/transaction) e
[segurança de eventos Cfx.re](https://docs.fivem.net/docs/developers/server-security/).
