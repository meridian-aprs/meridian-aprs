/// Compile-time app configuration.
///
/// Values are injected via `--dart-define` at build time. See the
/// "Local Development" section in CLAUDE.md for setup instructions.
class AppConfig {
  static const stadiaMapsApiKey = String.fromEnvironment(
    'STADIA_MAPS_API_KEY',
    defaultValue: '',
  );
}
