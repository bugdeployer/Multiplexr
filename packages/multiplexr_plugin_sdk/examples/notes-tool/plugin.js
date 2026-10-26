// Protocol 1 retains its historical entrypoint; the API is app-neutral.
function multiplexrEntry(request) {
  return AppShell.definePlugin({
    'notes.welcome': AppShell.contribution('ui.destination', () => ({
      kind: 'text', text: 'A reusable extension for a Notes host.'
    }), 'org.example.notes')
  })(request);
}
