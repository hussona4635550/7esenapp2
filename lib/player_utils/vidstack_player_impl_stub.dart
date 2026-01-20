import 'package:flutter/material.dart';

class VidstackPlayerImpl extends StatelessWidget {
  final String url;
  final List<Map<String, dynamic>> streamLinks;

  const VidstackPlayerImpl({
    required this.url,
    this.streamLinks = const [],
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
        child: Text("Vidstack Player is only supported on Web."));
  }
}
