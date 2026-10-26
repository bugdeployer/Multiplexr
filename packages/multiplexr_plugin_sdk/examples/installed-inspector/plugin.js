globalThis.multiplexrEntry = Multiplexr.definePlugin({
  'tool.inspect': (_, host) => host.call('runtime.ping', {}),
  'tool.read': (params, host) => host.call('catalog.titles', {handle: params.scopes[0].handle}),
  'tool.loop': () => { while (true) {} },
});
