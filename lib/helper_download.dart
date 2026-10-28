import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether [links] is mobile data alone, with no Wi-Fi or cable beside it. A device with no
/// connection is not held for Wi-Fi: the download fails and says to check the connection.
bool mobileOnly(List<ConnectivityResult> links) =>
    links.contains(ConnectivityResult.mobile) &&
    !links.contains(ConnectivityResult.wifi) &&
    !links.contains(ConnectivityResult.ethernet);

/// The Wi-Fi rule: with Wi-Fi only on, a download waits while the device is on mobile data,
/// unless the reader chose mobile data for this one.
bool holdForWifi({required bool wifiOnly, required bool mobileOnly, required bool mobileAllowed}) =>
    wifiOnly && mobileOnly && !mobileAllowed;

/// Reads the connection type from the system; nothing is sent anywhere.
Future<bool> mobileDataNow() async => mobileOnly(await Connectivity().checkConnectivity());

Stream<bool> mobileDataChanges() => Connectivity().onConnectivityChanged.map(mobileOnly);
