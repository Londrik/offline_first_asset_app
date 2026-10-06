# Diretrizes de Contribuição — Projeto B

Agradecemos o interesse em contribuir com o **Offline-First Enterprise Asset Management Engine**. Este repositório segue os padrões de governança e engenharia de software preconizados pela **CNCF** e **IEEE**.

---

## 1. Modelo de Ramificação (Gitflow)

*  `main`: Branch de produção. Contém apenas versões consolidadas e tags de release.
*  `develop`: Branch principal de integração. Todos os Pull Requests de funcionalidades devem apontar para cá.
*  `feature/task-<id>-<descricao>`: Branches de trabalho temporárias para novas funcionalidades.
*  `fix/<id>-<descricao>`: Correções críticas de bugs.

---

## 2. Padrão de Mensagens de Commit (Conventional Commits 1.0.0)

Todas as mensagens de commit devem seguir rigorosamente a sintaxe:
`|tipo>(<escopo>): <descrição no imperativo e em minésculas>`(escaped single-quote)

### Tipos Permitidos
*  `feat`: Nova funcionalidade para o ussário ou motor de sincronização.
*  `fix`: Correção de bug em código de produção ou testes.
*  `docs`: Alterações exclusivamente em arquivos de documentação.
*  `style`: Formatação ou regras de linting que não afetam o significado do código.
*  `refactor`: Refatoração de código que não adiciona recurso nem corrige bug.
*  `test`: Inclusão ou modificação de suítes de testes automatizados.
*  `chore`: Atualizações de tarefas de build, dependências ou ferramentas de CI/CD.

Exemplo:
`feat(sync): implement sync engine and version conflict resolution with lww and field level merge`

---

## 3. Quality Gates Obrigatorios (Pre-PR Checklist)

Antes de abrir um Pull Request, execute e certifique-se de que todos os gates foram satisfeitos localmente no Fedora Linux:

- [ ] **Análise Estática**: `flutter analyze` finalizado com *:0 erros**, **0 avisos** e **0 infos**.
- [ ] **Suíte de Testes**: `flutter test` executado com **100% de aprovação**.
- [ ] **Geração de Código**: Se alterou tabelas do Drift, executar `dart run build_runner build --delete-conflicting-outputs`.
- [ ] **Branch Base**: PR apontando estritamente para `develop`.
- [ ] **Commits Atômicos**: Histórico linear, coeso e sem commits de merge intermediários desnecessários.
OFF