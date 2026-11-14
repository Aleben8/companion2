#!/bin/sh
# Prepara il progetto: genera le cartelle android/ios (se mancano) e scarica le dipendenze.
# Non sovrascrive lib/, assets/ o web/.
set -e
flutter create . --project-name companion2 --platforms=web,android,ios
rm -f test/widget_test.dart
flutter pub get
echo "Fatto. Prova con: flutter run -d chrome"
