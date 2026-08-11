## Resumo

<!-- Descreva o que foi feito e por que. Seja direto. -->

## Tipo de mudanca

- [ ] feat: nova funcionalidade
- [ ] fix: correcao de bug
- [ ] refactor: refatoracao sem mudanca de comportamento
- [ ] tests: adicao ou ajuste de testes
- [ ] docs: documentacao
- [ ] infra: infraestrutura (Terraform, K8s, Docker, CI/CD)

## Camadas afetadas

- [ ] API (Controllers, Requests, Responses, Mappers, Validators, Bootstrap)
- [ ] Application (Commands, Queries, Handlers, Results, Services, Validators)
- [ ] Domain (Entities, Value Objects, Enums, Repositories)
- [ ] Infrastructure (Repositories, Migrations, Data, Security, Health Checks)
- [ ] Shared (Helpers, Logging)
- [ ] Infra (Terraform, K8s, Docker)
- [ ] Testes

## Checklist

- [ ] Branch segue o padrao `tipo/AAAA-MM-DD-descricao`
- [ ] Commits seguem Conventional Commits (`feat:`, `fix:`, `refactor:`, `tests:`, `docs:`)
- [ ] Novos endpoints seguem o padrao `Controller -> IMediator -> Handler`
- [ ] Commands/Queries possuem validators na Application
- [ ] Testes unitarios cobrem handlers novos ou alterados
- [ ] Testes de integracao cobrem endpoints novos ou alterados
- [ ] Migrations foram incluidas se houve mudanca no modelo de dados
- [ ] Documentacao foi atualizada (`docs/API_REFERENCE.md`, `docs/ARCHITECTURE.md`) se aplicavel
- [ ] Nenhum secret ou credencial foi commitado

## Como testar

<!-- Passos para validar a mudanca. Inclua comandos, payloads ou cenarios relevantes. -->

1.

## Observacoes

<!-- Informacoes adicionais, decisoes tomadas, debitos tecnicos conhecidos. Remova se nao aplicavel. -->
