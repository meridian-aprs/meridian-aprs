/// Injectable wall-clock seam for time-dependent logic.
///
/// Default = `DateTime.now`. Tests pass a closure that returns a controllable
/// `DateTime`. UI date/time formatters intentionally do not use this — they
/// want render-time "now".
typedef Clock = DateTime Function();
