// Author source: no Multiplexr app, Dart, Android or Node imports.
function multiplexrEntry(request) {
  return Multiplexr.definePlugin({
    'metadata.search': Multiplexr.contribution('metadata.provider', (params, host) => {
      host.call('runtime.ping');
      return Multiplexr.page([{
        id: Multiplexr.namespacedId('org.example.synthetic', 'moon'),
        title: `${String(params.query).slice(0, 100)} — synthetic`,
        authors: ['Example Author'],
      }]);
    }, 'org.example.synthetic'),
  })(request);
}
