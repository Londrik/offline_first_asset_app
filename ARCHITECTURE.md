# Arquitetura de Software — Projeto B (Offline-First Asset Engine)

Documento baseado no padrão **Arc42** e alinhado com as diretrizes de qualidade de software **ISO/IEC 25010**.

---

## 1. Visão Geral e Requisitos de Qualidade (ISO/IEC 25010)

1. **Confiabilidade (Reliability - Fault Tolerance & Recoverability)**: Tolerância estrita a quedas abruptas de rede (*Flapping Networks*), preservando atomicamente toda intenção de escrita na tabela `PendingMutations` via SQLite ACID.
2. **Eficiência de Desempenho (Performance Efficiency - Time Behaviour)**: Carga nula de I/O e criptografia na Main UI Thread, preservando a taxa de 120 FPS via Dart Isolates.
3. **Segurança e Integridade (Security & Data Integrity)**: Garantia de idempotência com identificadores universais UUIDv4 e integridade de payload com hash SHA-256 e compressão Gzip.
4. **Manutenibilidade (Maintainability - Modularity & Testability)**: Estrutura desacoplada em camadas limpas com separação estrita de contratos.

---
```mermaid
flowchart TD
    classDef boundary fill:#161b22,stroke:#30363d,stroke-width:2px,stroke-dasharray: 5 5,color:#8b949e;
    classDef comp fill:#1f6feb,stroke:#388bfd,stroke-width:1.5px,color:#ffffff;
    classDef db fill:#238636,stroke:#2ea043,stroke-width:1.5px,color:#ffffff;
    classDef worker fill:#8957e5,stroke:#a371f7,stroke-width:1.5px,color:#ffffff;
    classDef rel stroke:#8b949e,stroke-width:1.5px,color:#c9d1d9;

    subgraph app_boundary ["Offline-First Engine Core"]
        direction TB

        subgraph PresentationLayer ["Camada de Apresentação e Estado"]
            view["<b>AssetListScreen / Form</b><br/><i>[Flutter Widgets]</i><br/>Interface com badges reativos"]:::comp
            controller["<b>AssetController</b><br/><i>[ChangeNotifier / State]</i><br/>Orquestra estado da UI"]:::comp
        end

        subgraph DataLayer ["Camada de Dados & Persistência Local"]
            facade["<b>LocalRepositoryFacade</b><br/><i>[Data Facade]</i><br/>Atomicidade (Asset + Outbox)"]:::comp
            drift_db[("<b>AppDatabase</b><br/><i>[Drift SQLite]</i><br/>Índices B-Tree locais")]:::db
        end

        subgraph SyncLayer ["Engine de Sincronização & Resolução"]
            sync_engine["<b>SyncEngine</b><br/><i>[Core Orchestrator]</i><br/>Consumo FIFO e orquestração"]:::comp
            conflict_res["<b>ConflictResolver</b><br/><i>[LWW / Field-Level]</i><br/>Fusão semântica (HTTP 409)"]:::comp
        end

        subgraph NetworkLayer ["Concorrência & Transporte de Rede"]
            isolate_mgr["<b>SyncIsolateManager</b><br/><i>[Concurrency Layer]</i><br/>Isolate worker via Portas"]:::worker
            dio_client["<b>Dio Client</b><br/><i>[HTTP / Interceptors]</i><br/>Backoff, Full Jitter, Chaos"]:::comp
        end
    end

    view -->|"1. Observa / Despacha eventos"| controller
    controller -->|"2. Invoca mutações locais"| facade
    facade -->|"3. Transação atômica"| drift_db
    sync_engine -->|"4. Drena FIFO / Atualiza status"| drift_db
    sync_engine -->|"5. Resolve conflitos de versão"| conflict_res
    sync_engine -->|"6. Despacha tarefas de rede"| isolate_mgr
    isolate_mgr -->|"7. Executa requests isolados"| dio_client
```



## 3. Modelo de Memória e Concorrência de Dart Isolates

Diferente de threads tradicionais com memória compartilhada, Dart Isolates operam sobre heaps isolados de memória sem locks (*Share-nothing memory architecture*), comunicando-se exclusivamente por cópia de dados primitivos via portas de mensagens.

```mermaid
graph TD
    subgraph Main_Thread["Main UI Thread (Event Loop)"]
        direction TB
        UI["Widgets & UI State (120 FPS)"]
        SIM["SyncIsolateManager"]
        RP1["ReceivePort (Main)"]
        SP1["SendPort (Worker Reference)"]
    end

    subgraph Background_Isolate["Dedicated Background Isolate Heap"]
        direction TB
        Worker["BackgroundSyncWorkerEntryPoint"]
        RP2["ReceivePort (Worker)"]
        SP2["SendPort (Main Reference)"]
        HeavyOps["Gzip Encode + SHA-256<br/>JSON Serialization + Dio I/O"]
    end

    SIM -->|"1. spawn(mainSendPort)"| Worker
    Worker -->|"2. Handshake(workerSendPort)"| RP1
    SIM -->|"3. dispatch(SyncTaskMessage)"| RP2
    RP2 --> HeavyOps
    HeavyOps -->|"4. send(SyncTaskResult)"| RP1
    SIM -->|"5. ShutdownCommand / kill"| RP2

```

---

## 4. Diagrama de Sequência de Sincronização & Reconciliação (HTTP 409 Conflict)

```mermaid
sequenceDiagram
    autonumber
    participant UI as Main UI Thread
    participant DB as SQLite (Drift DB)
    participant Engine as SyncEngine
    participant Resolver as ConflictResolver (LWW)
    participant Worker as Background Isolate
    participant Server as Remote API

    UI->>DB: optimisticUpsertAsset() [Asset: DIRTY, Outbox: INSERT]
    DB-->>UI: Confirmacao atomica imediata (Zero Latencia)
    Engine->>DB: getPendingMutationsFifo() [Ordenado por timestamp ASC]
    DB-->>Engine: Retorna lote K de mutacoes pendentes
    Engine->>Worker: dispatch(SyncTaskMessage)
    Note over Worker: Compacta Payload Gzip e calcula SHA-256
    Worker->>Server: POST /sync (Payload, baseVersion: 1)
    Server-->>Worker: HTTP 409 Conflict (serverVersion: 3, serverPayload)
    Worker-->>Engine: Retorna SyncTaskResult (isConflict: true)
    Engine->>Resolver: resolve(localPayload, serverPayload, localTime, serverTime)
    Note over Resolver: LWW: Compara timestamps e determina vencedor
    Resolver-->>Engine: ConflictResolutionResult (resolvedPayload, version: 4)
    Engine->>DB: db.transaction() [DELETE mutation, UPDATE asset: SYNCED]
    DB-->>UI: Stream reativo emite novo estado consolidado

```

---

## 5. Modelo Entidade-Relacionamento do Drift SQLite (ERD)

```mermaid
erDiagram
    ASSETS {
        text id PK "UUIDv4 chave primaria"
        text assetTag UK "Codigo patrimonial unico"
        text name "Descricao do ativo"
        text status "OPERATIONAL | MAINTENANCE | DECOMMISSIONED"
        integer serverVersion "Versao logica do servidor"
        datetime localUpdatedAt "Timestamp UTC da alteracao local"
        text syncStatus "SYNCED | DIRTY | CONFLICT [Indexado]"
    }

    PENDING_MUTATIONS {
        text id PK "UUIDv4 chave primaria da mutacao"
        text aggregateId "Referencia ao ID do ativo"
        text aggregateType "Entidade afetada (ASSET)"
        text action "CREATE | UPDATE | DELETE"
        text payload "Delta serializado em formato JSON"
        integer baseVersion "Versao em que a alteracao foi baseada"
        datetime clientTimestamp "Timestamp UTC do dispositivo [Indexado]"
        integer retryCount "Contador incremental de retentativas [Indexado]"
        text lastError "Mensagem ou stack da ultima falha de rede"
        datetime createdAt "Timestamp UTC da criacao do registro"
    }

    ASSETS ||--o{ PENDING_MUTATIONS : "gera mutacoes na outbox"

```

---

## 6. Fluxograma de Decisão do Motor de Reconciliação

```mermaid
flowchart TD
    Start(["Inicio: Drenagem FIFO da Mutacao"]) --> PushRequest["Despacha requisicao ao Servidor Remoto"]
    PushRequest --> EvaluateStatus{"Codigo HTTP retornado?"}

    EvaluateStatus -- "200 OK" --> ApplySuccess["Transacao SQLite:<br/>1. DELETE mutacao da outbox<br/>2. UPDATE asset: serverVersion++, syncStatus='SYNCED'"]
    ApplySuccess --> EndSuccess(["Fim: Estado Sincronizado"])

    EvaluateStatus -- "5xx / Network Error" --> CheckRetry{"retryCount < MaxRetries?"}
    CheckRetry -- "Sim" --> IncRetry["Calcula Backoff Full Jitter<br/>UPDATE pending_mutations: retryCount++, lastError"]
    IncRetry --> EndFail(["Aguarda proxima janela FIFO"])
    CheckRetry -- "Nao" --> MarkPermanent["Mantem na outbox para inspecao ou alerta operacional"]

    EvaluateStatus -- "409 Conflict" --> CheckStrategy{"Estrategia Configurada?"}
    CheckStrategy -- "Last-Write-Wins" --> CompareTime{"clientTimestamp >= serverTimestamp?"}
    CompareTime -- "Sim (Local Vence)" --> WinLocal["payload Local prevalece<br/>serverVersion = serverVersion + 1"]
    CompareTime -- "Nao (Servidor Vence)" --> WinServer["Payload Remoto prevalece<br/>serverVersion = serverVersion"]

    CheckStrategy -- "Field-Level Merge" --> MergeFields["Mescla campos sem colisao direta<br/>Desempate LWW em campos concorrentes"]

    WinLocal --> TransactionConflict["Transacao SQLite:<br/>1. DELETE mutacao colidida<br/>2. UPDATE asset com dados mesclados<br/>3. syncStatus = 'SYNCED'"]
    WinServer --> TransactionConflict
    MergeFields --> TransactionConflict
    TransactionConflict --> EndResolved(["Fim: Conflito Reconciliado Deterministicamente"])

```

---

## 7. Registros de Decisão de Arquitetura (ADRs)

### ADR-001: Adoção do SQLite via Drift com Padrão Outbox Transacional

* **Contexto**: O aplicativo necessita de persistência relacional local, com capacidade reativa e suporte a transações ACID para garantir consistência entre dados de negócios e fila de envio.
* **Decisão**: Utilizar o ORM Drift com SQLite nativo, criando uma tabela de ativos (`Assets`) e uma outbox relacional (`PendingMutations`) vinculadas por transação atômica.
* **Consequências**: Elimina estados de inconsistência onde a UI reflete alterações que não foram gravadas na fila de envio ou vice-versa.

### ADR-002: Isolamento Concorrente de I/O e Criptografia com Dart Isolates

* **Contexto**: Serialização JSON volumosa, compressão Gzip e cálculo SHA-256 consomem mais tempo do que a janela de 8.33 ms permitida a 120 FPS.
* **Decisão**: Isolar todo o processamento de background no `BackgroundSyncWorkerIsolate`, mantendo a UI Thread livre de bloqueios.
* **Consequências**: Renderização com latência estável e zero jank garantido sob qualquer carga de lote.

### ADR-003: Reconciliação Híbrida de Conflitos (LWW e Field-Level Merge) em HTTP 409

* **Contexto**: Atualizações concorrentes entre múltiplos técnicos e o servidor geram divergências de versão lógica (*Lost Update Problem*).
* **Decisão**: Implementar `ConflictResolver` extensível, provendo `LastWriteWinsResolver` como padrão temporal e `FieldLevelMergeResolver` para fusão de campos não sobrepostos.
* **Consequências**: Resolução determinística e auditável sem intervenção humana obrigatória em operações rotineiras.

### ADR-004: Mitigação de Thundering Herd via Exponential Backoff com Full Jitter

* **Contexto**: Reabertura de conexões em lote por milhares de dispositivos móveis sobrecarrega os gateways de API centrais.
* **Decisão**: Adotar a fórmula RFC 8900 / AWS Full Jitter no cálculo de intervalos de retry com teto em 60 segundos e máscara de bitwise shift de 30 bits.
* **Consequências**: Distribuição contínua da carga de rede no tempo, estabilizando os servidores em momentos de reinicialização.

### ADR-005: Injeção de Falhas Controlada (Chaos Testing) no Pipeline HTTP do Dio

* **Contexto**: Validar a estabilidade do banco de dados e dos interceptadores sob falhas de conexão de borda em ambiente automatizado de CI/CD.
* **Decisão**: Criar o `FaultInjectionInterceptor` com suporte a HTTP 503, quedas de socket, timeouts e corrupção de payload com encadeamento explícito de erros.
* **Consequências**: Testes automatizados executam cenários de degradação sem depender de infraestrutura física de rede instável.
