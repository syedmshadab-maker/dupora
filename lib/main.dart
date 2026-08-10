import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ui/app.dart';
import 'ui/state/app_controller.dart';

void main() {
  runApp(const DuporaBootstrap());
}

/// Owns the [AppController] and waits for its async [AppController.init]
/// (settings load, cache DB open, storage enumeration) before handing off
/// to [DuporaApp], showing a minimal splash rather than a flash of empty
/// state.
class DuporaBootstrap extends StatefulWidget {
  const DuporaBootstrap({super.key});

  @override
  State<DuporaBootstrap> createState() => _DuporaBootstrapState();
}

class _DuporaBootstrapState extends State<DuporaBootstrap> {
  late final AppController _controller;
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _initFuture = _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(body: Center(child: CircularProgressIndicator())),
            );
          }
          return const DuporaApp();
        },
      ),
    );
  }
}
