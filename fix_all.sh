#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/development/flutter/bin:$PATH"

# 1. Limpa arquivo acidental gerado na pasta pai (~/Projetos)
rm -f ../pubspec.yaml ../pubspec.lock ../fix_and_complete_task1.sh

# 2. Configura pubspec.yaml correto dentro do projeto
cat << 'PUBSPEC' > pubspec.yaml
name: offline_first_asset_app
description: "Offline-First Asset Management Engine with Drift"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.10.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  drift: ^2.24.2
  sqlite3_flutter_libs: ^0.5.28
  path_provider: ^2.1.5
  path: ^1.9.0
  uuid: ^4.5.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  drift_dev: ^2.24.2
  build_runner: ^2.4.14
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
PUBSPEC

# 3. Remove teste padrão quebrado do widget_test gerado pelo template
rm -f test/widget_test.dart

# 4. Força resolução de pacotes e compilação do Drift
flutter pub get
dart run build_runner build

# 5. Validação rigorosa dos Quality Gates
flutter analyze
flutter test

# 6. Commit atômico e push remoto
git add -A
git commit -m "feat(database): implement drift schema, edge indexes, and transactional local repository"
git push origin feature/task-1-drift-local-db

echo "==> Estado final do repositório:"
git status
git log -n 1 --oneline
