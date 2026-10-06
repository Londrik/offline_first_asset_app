# Registro de Alteraç��es (Changelog)

Todas as alterações relevantes deste projeto estão documentadas neste arquivo, seguindo o padrão [Keep a Changelog 1.0.0](https://keepachangelog.com/pt-BR/1.0.0/) e versionamento semantico [SemVer 2.0.0](https://semver.org/).

---

## [Unreleased]

---

## [0.5.0] - 2026-10-06
### Adicionado
- **Task 5 (Resilience & Chaos Testing)**: Motor de cálculo estocástico de `BackoffCalculator` com algoritmo RFC 8900 Full Jitter.
- `ResilienceInterceptor` para o cliente Dio com gestão inteligente de retentativas em falhas transitórias (Timeouts, SocketException, HTTP 500-504).
- `FaultInjectionInterceptor` para engenharia de caos em testes automatizados.
- Suíte de testes de borda e resiliência cobrindo dispersão uniforme de jitter e consistência atômica do SQLite sob falha sustentada.

## [0.4.0] - 2026-10-06
### Adicionado
- **Task 4 (Conflict Resolution & Sync Engine)**: `SyncEngine` reativo com drenagem FIFO de mutações pendentes.
- Classes de estratégia de reconciliação de concorrência: `LastWriteWinsResolver` e `FieldLevelMergeResolver`.
- Tratamento determinístico de respostas HTTP 409 Conflict sem perda de dados locais ou corrupção de versão.
- Suíte de testes unitários integrados com Drift in-memory (`sync_engine_conflict_test.dart`).

## [0.3.0] - 2026-10-06
### Adicionado
- **Task 3 (Background Concurrency & Isolates)**: `SyncIsolateManager` operando com ciclo de vida isolado via `Isolate.spawn`.
- Protocolo de mensageria tipado com primitivos seguros (`SyncTaskMessage`, `SyncTaskResult`, `IsolateInitHandshake`, `IsolateShutdownCommand`).
- Offloading de serialização JSON, compactação Gzip e hash SHA-256 fora da Main UI Thread (Zero UI Jank / 120 FPS).
- Suíte de testes de concorrência e descarte de memoria (`sync_isolate_test.dart`).

## [0.2.0] - 2026-10-06
### Adicionado
- **Task 2 (Optimistic UI & State Management)**: Camada de apresentação reativa com controle de estado para mutaç��es otimistas.
- `AssetController`, componentes visuais `SyncStatusBadge`, `AssetFormWidget` e telas de listagem e detalhe.
- Suíte de testes de widgets validando renderização imediata de estados `DIRTY` e `SyNCED`.

## [0.1.0] - 2026-10-05
### Adicionado
- **Task 1 (Database Core & Outbox Pattern)**: Esquema relacional local com Drift SQLite (`Assets` e `PendingMutations`).
- Índices de borda B-Tree `idx_mutations_fifo` e `idx_assets_sync_status`.
- Implementação do `LocalRepositoryFacade` provendo transações ACID atômicas entre entidade e outbox.
- Configuração do pipeline inicial de CI/CD via GitHub Actions e pré-push gates.
