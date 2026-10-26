import test from 'node:test';
import assert from 'node:assert/strict';
import {httpJson} from '../src/sdk.js';

test('JSON requests use mediated credentials and bounded POST contract', () => {
  const calls = [];
  const host = {call(method, params) { calls.push({method, params}); return {status:200, body:'{"items":[]}'}; }};
  assert.deepEqual(httpJson(host, 'https://example.com', true), {items:[]});
  httpJson(host, 'https://example.com/search', 'apiKey', {q:'Moon'});
  assert.deepEqual(calls, [
    {method:'http.get', params:{url:'https://example.com', credential:true}},
    {method:'http.post', params:{url:'https://example.com/search', credential:'apiKey', body:'{"q":"Moon"}'}},
  ]);
});

test('HTTP failures and invalid JSON retain stable non-secret errors', () => {
  for (const [status, body, code] of [[401,'private','permission_denied'],[403,'private','permission_denied'],[429,'private','resource_limit'],[503,'private','runtime_failure'],[200,'<html>private</html>','invalid_response'],[200,'{"__proto__":{}}','invalid_response']]) {
    assert.throws(() => httpJson({call:()=>({status,body})}, 'https://example.com'), error => error.code === code && !error.message.includes('private'));
  }
});
