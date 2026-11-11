import 'app_state.dart';

/// What a screen reader hears about the helper, such as "helper downloading, 42 percent".
String helperStatusWords(HelperState helper) => switch (helper) {
  HelperNotInstalled() => 'helper not downloaded',
  HelperDownloading(waitingForWifi: true) => 'helper waiting for Wi-Fi',
  HelperDownloading(waitingForNetwork: true) => 'helper waiting for a connection',
  // A paused download starts again from the beginning, so it usually has nothing to count.
  HelperDownloading(paused: true, :final percent) =>
    percent == 0 ? 'helper download paused' : 'helper download paused, $percent percent',
  HelperDownloading(:final percent) => 'helper downloading, $percent percent',
  HelperChecking() => 'helper starting',
  HelperLoading() => 'helper loading',
  HelperReady() => 'helper ready',
  HelperResting() => 'helper resting while a deep dive is recorded',
  HelperFailed() => 'helper needs a look',
};

String studySemanticsLabel(HelperState helper, {required bool writing}) =>
    'Study, ask Berea, ${writing ? 'writing an answer' : helperStatusWords(helper)}';
