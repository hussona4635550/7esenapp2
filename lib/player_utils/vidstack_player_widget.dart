import 'package:flutter/material.dart';
import 'vidstack_player_impl_stub.dart'
    if (dart.library.html) 'vidstack_player_impl_web.dart' as impl;

class VidstackPlayerWidget extends StatelessWidget {
  final String url;
  final List<Map<String, dynamic>> streamLinks;

  const VidstackPlayerWidget({
    required this.url,
    this.streamLinks = const [],
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return impl.VidstackPlayerImpl(
      url: url,
      streamLinks: streamLinks,
    );
  }
}
