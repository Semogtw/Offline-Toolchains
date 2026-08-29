# Estado de desenvolvimento — 2026-08-29

Checkpoint **público e sanitizado** do `Offline-Toolchains`.

Este repositório é infraestrutura reutilizável para reconstrução de ambientes, caches offline, manifests de integridade, empacotamento e validação. Este documento não contém inventário privado de consumidores, credenciais, nomes de secrets, run IDs operacionais, procedimentos de signing ou handoffs internos.

## Fonte de verdade

- `main` descreve os contratos públicos integrados.
- Pull requests abertas podem conter versões futuras dos formatos e ferramentas.
- Um artifact gerado por workflow só é utilizável quando o manifest, checksums, arquitetura, versão do schema e compatibilidade são validados.
- Um workflow verde que fabrica uma toolchain **não certifica o código de um projeto consumidor**. A toolchain prepara o ambiente; os gates do consumidor continuam separados.

## Objetivo atual

O projeto está evoluindo de um conjunto de caches/scripts úteis para uma plataforma mais explícita de artifacts reproduzíveis, com foco em:

- manifests versionados;
- perfis de ambiente declarativos;
- restauração determinística;
- composição de artifacts menores em vez de um único mega-artifact;
- doctors/compatibility guards;
- inventário e transporte uniformes;
- integridade verificável;
- operação segura em ambiente público.

## Linha Artifact Platform v2

A PR pública #7 (`feat: artifact platform v2`) continua sendo a referência para a evolução de schema v2 enquanto não for integrada.

Escopo documentado nessa linha:

- manifests schema v2;
- registry de perfis;
- builders capazes de representar locks/dependências exatas;
- restauração de workspace em um comando;
- catálogo de artifacts com identidade e expiração;
- reutilização de conjuntos equivalentes;
- cleanup seguro;
- perfis leves e agregados;
- doctors;
- compatibility guards;
- contratos uniformes de inventário/transporte.

A PR permanece draft enquanto os gates de segurança, build, restauração e compatibilidade não forem concluídos no escopo definido por ela.

## Modelo de perfis

Um perfil deve responder, sem depender de contexto implícito:

1. qual ambiente ele prepara?;
2. quais componentes inclui?;
3. qual schema de manifest usa?;
4. qual arquitetura/plataforma suporta?;
5. quais fingerprints/locks definem equivalência?;
6. como o consumidor restaura e ativa o ambiente?;
7. quais doctors precisam passar depois da restauração?;
8. quais artifacts adicionais podem ser compostos sobre ele?;
9. quando o artifact expira?;
10. como verificar que todas as partes pertencem ao mesmo conjunto compatível?

Perfis não devem depender de conhecimento privado do consumidor para serem interpretados.

## Manifest e integridade

Todo artifact relevante deve carregar metadata suficiente para impedir restauração ambígua.

Princípios:

- schema explicitamente versionado;
- checksum dos payloads;
- arquitetura/plataforma declaradas;
- identidade do builder/perfil;
- fingerprints dos locks relevantes;
- compatibilidade entre partes de artifact composto;
- falha fechada quando uma parte estiver ausente ou incompatível;
- nenhuma promoção silenciosa de artifact parcial para estado “pronto”.

Checksums verificam integridade; não substituem assinatura/autenticidade quando o threat model exigir algo mais forte.

## Restauração

O fluxo de restore deve ser:

- determinístico;
- idempotente quando repetido sobre o mesmo conjunto;
- explícito sobre diretórios criados/modificados;
- conservador com arquivos existentes;
- capaz de produzir um ambiente ativável sem esconder falhas;
- acompanhado por doctors pós-restauração.

A restauração não deve:

- inventar dependências ausentes;
- misturar partes de runs/conjuntos incompatíveis;
- baixar dependência inesperada quando o modo declarado é offline;
- ignorar checksum para “tentar continuar”;
- tratar cache corrompido como miss comum quando a integridade foi prometida.

## Artifacts compostos

A direção preferida é compor perfis em camadas quando isso reduz duplicação e custo operacional.

Exemplo conceitual:

```text
base de plataforma
  ↓
runtime/SDK
  ↓
cache de dependências do projeto
  ↓
ativação/doctor do consumidor
```

Isso é preferível a um mega-artifact quando:

- camadas têm cadências diferentes;
- uma base pode ser reutilizada;
- compatibilidade entre camadas pode ser verificada;
- a restauração continua simples.

Não fragmentar apenas por estética. Muitas partes sem contrato de composição tornam recuperação mais frágil.

## Cache offline

Um cache offline deve ser tratado como derivado reproduzível, não como fonte de verdade do projeto.

Documentar sempre que aplicável:

- gerador;
- versão do runtime/SDK;
- lockfile/fingerprint;
- plataforma;
- conteúdo esperado;
- estratégia de invalidação;
- forma de validar uso realmente offline.

A presença de arquivos em cache não prova que um build específico passará.

## Doctors e compatibility guards

Doctors devem falhar com mensagens acionáveis para problemas como:

- arquitetura errada;
- versão de schema não suportada;
- parte de artifact ausente;
- checksum divergente;
- lock/fingerprint incompatível;
- SDK/runtime não encontrado após ativação;
- permissões/diretórios inválidos;
- ferramenta esperada não executável.

Guardrails devem evitar “best effort” perigoso. Se o ambiente não corresponde ao contrato, o correto é recusar a ativação ou marcar estado degradado de forma explícita.

## Segurança de repositório público

Nunca versionar em documentação, fixtures, logs ou artifacts públicos:

- tokens;
- chaves privadas;
- signing material;
- credenciais de nuvem;
- source privado;
- configuração privada de produção;
- mapas de permissões internos;
- inventário de repositórios privados;
- handoff operacional de mantenedor;
- payload real de usuário;
- nomes/valores de secrets que não sejam necessários ao contrato público.

Workflows com credenciais devem usar mecanismos de secrets e least privilege. Logs precisam ser considerados públicos.

## Fronteira com projetos consumidores

Este repositório deve documentar:

- como construir/obter a toolchain;
- como verificar o artifact;
- como restaurar;
- como ativar;
- como diagnosticar incompatibilidade;
- como limpar artifacts gerados.

O consumidor deve documentar:

- quais testes do próprio projeto rodar;
- qual SHA/branch está sendo validado;
- critérios de release;
- signing/deploy específicos;
- estado funcional do produto.

Essa separação evita transformar Toolchains em um banco público de detalhes internos de outros projetos.

## Workflows operacionais

O repositório contém workflows usados tanto para fabricar artifacts quanto para executar verificações reproduzíveis.

Regras de interpretação:

- resultado do workflow vale para os inputs/commit declarados por ele;
- não extrapolar um focused gate para full suite;
- artifact expirado deve ser reconstruído, não tratado como cache eterno;
- logs/metadata públicos devem permanecer sanitizados;
- workflows temporários de diagnóstico devem ser removidos quando seu papel terminar;
- fixtures de trigger não devem se tornar uma segunda fonte de verdade de estado de projeto.

## Política para diagnósticos temporários

É aceitável criar tooling temporário para investigar um contrato do próprio repositório, desde que:

1. o objetivo seja explícito;
2. não exponha contexto privado;
3. o diagnóstico seja removido ou convertido em teste permanente depois;
4. o resultado útil seja incorporado no contrato/teste adequado;
5. não fique uma coleção indefinida de workflows de incidente.

## Validação de mudanças de formato

Ao mudar manifest/profile/restore:

1. adicionar/atualizar fixture de schema;
2. atualizar parser/validator;
3. testar manifest válido;
4. testar versões desconhecidas;
5. testar checksums divergentes;
6. testar parte ausente;
7. testar arquitetura incompatível;
8. testar restauração repetida;
9. testar cleanup;
10. atualizar documentação pública no mesmo conjunto de mudanças.

## Validação de builders

Builders devem ser exercitados em ambiente limpo quando possível.

Verificar:

- dependências declaradas;
- lock/fingerprint;
- tamanho e estrutura do artifact;
- ausência de secrets/source indevido;
- reproducibilidade suficiente para o contrato;
- manifest consistente com o payload;
- doctor pós-restauração.

## Estado de prontidão da v2

Enquanto a PR #7 permanecer draft, trate schema v2 como linha em evolução. Antes de um consumidor depender dele como contrato estável, confirmar no head da PR ou após merge:

- testes secret-free;
- hosted profile builds;
- builds que representem locks exatos no escopo suportado;
- download/restauração pelo fluxo de consumo real;
- reuse de artifact equivalente;
- cleanup seguro;
- compatibilidade de perfis compostos;
- ausência de caminhos temporários de bootstrap/export que não pertençam ao produto final.

## Próximos passos recomendados

1. concluir os gates da Artifact Platform v2;
2. remover mecanismos temporários que existam apenas para desenvolvimento da própria v2;
3. consolidar documentação de schema/profile/manifest;
4. manter doctors como interface principal de diagnóstico;
5. reduzir duplicação entre workflows sem esconder diferenças reais de plataforma;
6. garantir que artifacts compostos tenham identidade de conjunto verificável;
7. manter documentação pública livre de detalhes privados de consumidores;
8. depois do merge da v2, revisar documentos que ainda tratem schema anterior como padrão atual.

## Definition of Done para mudança de toolchain

Uma mudança de infraestrutura não está concluída apenas porque um workflow gerou arquivo. Exigir, conforme o escopo:

- builder verde;
- manifest válido;
- integridade verificada;
- artifact restaurado;
- doctor verde;
- consumo mínimo exercitado;
- cleanup validado;
- documentação atualizada;
- nenhum secret/source privado no payload ou logs;
- comportamento de incompatibilidade observado e fail-closed.

## Documentação relacionada

- `README.md` — apresentação pública e política de escopo;
- `docs/` — contratos técnicos reutilizáveis;
- `.github/workflows/` — automação observável;
- `scripts/` — build/restore/validation/maintenance;
- `manifests/` — metadata versionada;
- `tests/` e `fixtures/` — contratos executáveis;
- PR #7 — Artifact Platform v2 enquanto ainda não integrada.

Este snapshot é deliberadamente genérico onde o detalhe pertence a consumidores privados. Essa limitação é uma propriedade de segurança do repositório público, não falta de documentação.