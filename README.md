# Minhas Rondas — protótipo

Protótipo Flutter Android, offline, para testes.

Funções:
- Rondas de hora em hora.
- Horário inicial e final configuráveis.
- Botão para registrar a passagem.
- O horário registrado é capturado automaticamente do relógio do aparelho.
- Não existe edição do horário registrado na interface.
- Histórico local usando SharedPreferences.
- Rondas não registradas ficam como "Ronda perdida — sem registro".

## Abrir no Android Studio

1. Instale o Flutter SDK e o Android Studio.
2. No Android Studio, abra a pasta deste projeto.
3. Execute `flutter pub get`.
4. Conecte um celular Android com depuração USB ou use um emulador.
5. Execute `flutter run`.
6. Para gerar APK: `flutter build apk --release`.
7. O APK ficará em `build/app/outputs/flutter-apk/app-release.apk`.

Observação:
Este é um protótipo simples. A lógica de "perdida" usa uma tolerância de 30 minutos após o horário previsto. Para uma versão de uso real, essa regra pode ser alterada (por exemplo, permitir registrar 10:12 para a ronda das 10:00 sem marcar como perdida, dependendo da regra desejada).
