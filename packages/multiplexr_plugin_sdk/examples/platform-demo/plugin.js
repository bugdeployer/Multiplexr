globalThis.multiplexrEntry = function(request) {
  const handlers={
    'metadata.provider':Multiplexr.contribution('metadata.provider',params=>Multiplexr.page([{id:'org.example.platform:synthetic',title:params.query+' (synthetic)',authors:['Example Author'],fields:{description:'Synthetic bibliographic example',language:'en',publisher:'Example Publisher',identifier:'EXAMPLE:1'}}]),'org.example.platform'),
    'artwork.provider':Multiplexr.contribution('artwork.provider',()=>Multiplexr.page([{id:'org.example.platform:cover',role:'cover',attribution:'Synthetic example',content:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='}]),'org.example.platform'),
    'source.provider':Multiplexr.contribution('source.provider',()=>Multiplexr.page([{id:'org.example.platform:listing',name:'Example.epub',mime:'application/epub+zip'}]),'org.example.platform'),
    'import.handler':Multiplexr.contribution('import.handler',(params,host)=>{const file=host.call('imports.read',{handle:params.input});return {proposals:(params.selection??[]).map(item=>({title:item.id,expectedRevision:item.revision,changes:{description:file.text.substring(0,512)}}))};},'org.example.platform'),
    'export.handler':Multiplexr.contribution('export.handler',params=>({name:'selection.txt',mime:'text/plain',text:'Selected items: '+params.selection.length}),'org.example.platform'),
    'library.tool':Multiplexr.contribution('library.tool',params=>({proposals:params.selection.map(item=>({title:item.id,expectedRevision:item.revision,changes:{description:'Synthetic proposed description'}}))}),'org.example.platform'),
    'library.rating':Multiplexr.contribution('library.tool',(params,host)=>{const item=params.selection[0];if(item)host.call('catalog.propose',{operation:'mergeFields',handle:item.id,revision:item.revision,fields:{'org.example.platform:rating':5},idempotencyKey:item.id.substring(0,32)});return {proposals:[]};},'org.example.platform'),
    'event.handler':Multiplexr.contribution('event.handler',()=>({acknowledged:true}),'org.example.platform'),
    'session.hook':Multiplexr.contribution('session.hook',()=>({commands:[{kind:'pause'}]}),'org.example.platform'),
    'ui.action':Multiplexr.contribution('ui.action',()=>({kind:'text',text:'A host-rendered example action'}),'org.example.platform'),
    'ui.section':Multiplexr.contribution('ui.section',()=>({kind:'group',children:[{kind:'text',text:'Synthetic details section'}]}),'org.example.platform'),
    'ui.destination':Multiplexr.contribution('ui.destination',()=>({kind:'group',children:[{kind:'text',text:'Synthetic extension destination'},{kind:'action',label:'Example action',action:'org.example.platform:ui_action'}]}),'org.example.platform'),
  };
  return Multiplexr.definePlugin(handlers)(request);
};
