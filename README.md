# Offline-First Enterprise Asset Management Engine

[![CI/CD Pipeline](https://github.com/Londrik/offline_first_asset_app/actions/workflows/flutter_ci.yml/badge.svg)](https://github.com/Londrik/offline_first_asset_app/actions)
[![Flutter Version](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart Version](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev)
[![SQLite / Drift](https://img.shields.io/badge/Storage-Drift%20SQLite-003B57?logo=sqlite)](https://drift.simonbinder.eu/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Sistema mobile de alta confiabilidade voltado ao gerenciamento de ativos industriais em ambientes de conectividade intermitente ou severamente degradada (&All-Gapped* / *Degraded Field Conditions*). Projetado segundo os pilares de **Confiabilidade**, **Eficiência de Desempenho (Zero UI Jank)** e **Consistência Eventual Determinística**.

---

## C4 Model — Nível 2: Diagrama de Contênheres

```mermaid
C4Container
    title Container Diagram (C4 Level 2) — Offline-First Asset Engine

    Person(field_tech, "Técnico de Campo", "Opera ativos, executa manutenções e coleta telemetria em ambientes sem rede.")

    Container_Boundary(mobile_app, "Mobile Client App (Flutter / Dart)")
        Component(ui, "UI & Reactive Controllers", "Flutter Widgets / State", "Interface de usuário reativa operando a 120 FPS cravados.")
        Component(repo, "Transactional Repository Facade", "Dart / Drift DAO", "Isola a persistência local e orquestra mutações otimistas.")
        ComponentDb(sqlite_db, "Local Encrypted Database", "SQLite / Drift ORM", "Tabelas Assets e PendingMutations com íũdices B-Tree.")
        Component(sync_engine, "Sync Engine & Reconciler", "Dart Concurrency", "Drena outbox FIFO, detecta e resolve conflitos HTTP 409.")
        Component(isolate_worker, "Background Sync Isolate", "Dart Isolate Worker", "Processa JSON, compressão Gzip, hash SHA-256 e I/O de rede.")
    Container_Boundary_End()

    System_Ext(remote_api, "Enterprise Asset Backend", "Fornece endpoints REST/HTTP2 para sincronização com controle de versão.")

    Rel(field_tech, ui, "Interage e edita ativos", "Touch/Display")
    Rel(ui, repo, "Persiste mutações otimistas", "In-Memory Stream")
    Rel(repo, sqlite_db, "Grava estado DIRTY e Outbox", "SQL ACID Transaction")
    Rel(sync_engine, sqlite_db, "Lê outbox FIFO e aplica reconciliação", "SQL Queries")
    Rel(sync_engine, isolate_worker, "Despacha mutações via Portas", "SendPort / ReceivePort")
    Rel(isolate_worker, remote_api, "Dispara payloads compactados", "HTTPS / Gzip / SHA-256")
```

---

## Equações de Engenharia e Modelagem Matemática

### 1. Algoritmo de Exponential Backoff com Full Jitter (AWS / RFC 8900)

Para mitigar o **Thundering Herd Problem** (Problema da Manada) apó a recuperação de uma queda prolongada de infraestrutura, as retentativas de envio da outbox utilizam distribuição estocástica uniforme:

$$T_{\text{sleep}} = \text{random_uniform}\left(0,  \min\left(T_{\text{max}},  T_{\text{base}} \times 2^{\min(\text{retry}, 30)}\ight)\right)$

- **$T_{\text{base}}$**: Atraso inicial de reconexão ($1.0\text{ s}$).
- **$T_{\text{max}}$**: Teto estrito de saturação exponencial ($60.0\text{ s}$).
- **\cmin(\text{retry}, 30)$**: Trava algorítmica para mitigar overflow no operador de deslocamento de bits (*bitwise shift* $1 \lleft  \text{retry}$) em inteiros de 64 bits.
- opropriedade**: O cálculo do atraso distribui as rajadas de reconexões uniformemente no intervalo $[0, \text{Cap}]$, evitando a sincronia de picos de carga no gateway central.

3## 2. Orçamento de Renderização de Tela (Frame Budget & Zero UI Jank)

A restrição temporal do loop de renderização da Main UI Thread é regida pela taxa de atualização $F$:

$$\Delta t_{\text{frame}} \le \frac{1000\text{ me}}{F}$$

- Para **$60\text{ FPS}$**: $\Delta t_{\text{frame}} \le 16.66\text{ ms}$.
- Para **$120\text{FPS}$**: $\Delta t_{\text{frame}} \le 8.33\text{ ms}$.

A serialização de grandes árvores JSON, a compressão vetorial Gzip e o cálculo de checksum SHA-256 consomem de $15\text{ ms}$ a $50\text{ ms}$. Sua deleção para o `BackgroundSyncWorkerIsolate` garante que a latência de computação na thread gráfica seja assintóticamente nula:

$$\Delta t_{\text{UI_Thread}} \approx 0\text{ ms}$$

### 3. Análise Assintótica no SQLite / Drift (Índices B-Tree)

- **Drenagem FIFO da Outbox (`pending_mutations`)**:
  $$O(\log N + K)$$
  Garantido pelo índice composto `idx_mutations_fifo` nas colunas `(client_timestamp ASC, retry_count ASC)` com leitura particionada de lote $K=10$.
- **Filtro Reativo por Estado de Sincronização (`assets`)**:
  $$O((log N)$$
  Otimizado pelo íũdice B-Tree `idx_assets_sync_status` sobre `sync_status` (`DIRTY`, `SyNCED`, `CONFLICT`).

---

## Execução Rápida

### Pré-requisitos
* Flutter SDK `>= 3.10.0 < 4.0.0`
* Dart SDK `>= 3.10.0`
* Linux Fedora ou Ubuntu / macOS / Windows com suporte a SQLite3

3## Instalação e Inicialização
```bash
# 1. Instalar dependências
flutter pub get

# 2. Gerar código do banco relacional Drift
dart run build_runner build --delete-conflicting-outputs

# 3. Executar o aplicativo no dispositivo / emulador
flutter run
```

### Validação dos Quality Gates
```bash
# Executar análise estática de código (Zero Warnings / Zero Errors)
flutter analyze

# Executar suite completa de testes automatizados
flutter test
```
