// Historical credential form fixture, not shipped.
import 'legacy_provider_credentials.dart';
export 'legacy_video_details.dart';
export 'package:multiplexr/src/features/metadata/application/video_metadata_policy.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:app_shell/app_shell.dart';

/// Shared credential interaction for movie/TV and audiobook metadata.
class MetadataCredentialCard extends StatefulWidget {
  const MetadataCredentialCard({
    super.key,
    required this.name,
    required this.label,
    required this.configured,
    required this.save,
    required this.footer,
  });
  final String name, label, footer;
  final Future<bool> Function() configured;
  final Future<void> Function(String) save;
  @override
  State<MetadataCredentialCard> createState() => _MetadataCredentialCardState();
}

class _MetadataCredentialCardState extends State<MetadataCredentialCard> {
  final input = TextEditingController();
  bool connected = false, loading = true, busy = false, visible = false;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.configured();
      if (mounted) {
        setState(() {
          connected = value;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not read provider status. Tap Retry.';
        });
      }
    }
  }

  Future<void> save(String credential) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(credential.trim());
      input.clear();
      if (!mounted) return;
      setState(() {
        connected = credential.trim().isNotEmpty;
        visible = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            connected
                ? '${widget.name} verified and saved.'
                : '${widget.name} disconnected.',
          ),
        ),
      );
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => error = e.message ?? 'Could not update ${widget.name}.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not update ${widget.name}. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            loading
                ? 'Checking connection…'
                : connected
                ? 'Connected · credential stored securely on this device.'
                : 'Not connected',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: input,
            enabled: !loading && !busy,
            obscureText: !visible,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: connected ? 'Replace ${widget.label}' : widget.label,
              suffixIcon: IconButton(
                tooltip: visible ? 'Hide credential' : 'Show credential',
                onPressed: loading || busy
                    ? null
                    : () => setState(() => visible = !visible),
                // ignore: deprecated_member_use
                icon: InterfaceIcon(
                  visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (error != null && !busy)
            TextButton(onPressed: refresh, child: const Text('Retry status')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: loading || busy || input.text.trim().isEmpty
                ? null
                : () => save(input.text),
            child: Text(busy ? 'Saving…' : 'Verify and save'),
          ),
          if (connected)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: busy ? null : () => save(''),
                child: Text('Disconnect ${widget.name}'),
              ),
            ),
          const SizedBox(height: 20),
          SelectableText(widget.footer),
        ],
      ),
    ),
  );
}

class MetadataSettings extends StatelessWidget {
  const MetadataSettings({super.key, required this.service});
  final ProviderCredentialsHost service;
  @override
  Widget build(BuildContext context) => MetadataCredentialCard(
    name: 'TMDB',
    label: 'API key or read token',
    configured: service.metadataCredentials.configured,
    save: service.metadataCredentials.save,
    footer: 'Movie and TV matching uses parsed titles. Ambiguous matches can be reviewed from each video.\n\nThis product uses the TMDB API but is not endorsed or certified by TMDB.',
  );
}

class AudiobookMetadataSettings extends StatelessWidget {
  const AudiobookMetadataSettings({super.key, required this.credentials});
  final ProviderCredentials credentials;
  @override
  Widget build(BuildContext context) => MetadataCredentialCard(
    name: 'AudiobookDB',
    label: 'API key',
    configured: credentials.configured,
    save: credentials.save,
    footer: 'Use your personal AudiobookDB API key. Find metadata and review matches from your audiobook collection.\n\nMetadata provided by AudiobookDB · https://audiobookdb.org',
  );
}
