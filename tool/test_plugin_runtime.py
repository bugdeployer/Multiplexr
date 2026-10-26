"""Host/SDK boundary checks; actual interpreter containment needs Android tests."""
import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
ANDROID = '{http://schemas.android.com/apk/res/android}'

class PluginRuntimeBoundaryTest(unittest.TestCase):
    def test_release_service_is_disabled_nonexported_and_os_isolated(self):
        manifest = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml')
        service = next(s for s in manifest.findall('.//service')
                       if s.get(ANDROID + 'name') == '.plugins.PluginSandboxService')
        self.assertEqual(service.get(ANDROID + 'enabled'), 'false')
        self.assertEqual(service.get(ANDROID + 'exported'), 'false')
        self.assertEqual(service.get(ANDROID + 'isolatedProcess'), 'true')
        for file in (ROOT / 'lib').rglob('*.dart'):
            self.assertNotIn('PluginSandboxService', file.read_text(encoding='utf-8'), str(file))

    def test_sdk_has_no_app_dependencies_and_notice_matches_engine_license(self):
        sdk = ROOT / 'packages/multiplexr_plugin_sdk'
        package = json.loads((sdk / 'package.json').read_text())
        self.assertFalse(package.get('dependencies'))
        for file in (sdk / 'src').glob('*'):
            content = file.read_text(encoding='utf-8')
            for forbidden in ['package:multiplexr/', 'package:flutter/', '../lib/src/', '../../lib/src/']:
                self.assertNotIn(forbidden, content, str(file))
        license_file = ROOT / 'android/app/src/main/cpp/quickjs/LICENSE'
        notice = ROOT / 'android/app/src/main/assets/licenses/quickjs.txt'
        self.assertEqual(license_file.read_bytes(), notice.read_bytes())

    def test_sdk_types_cover_every_shipped_host_method(self):
        gateway = (ROOT / 'lib/src/features/plugins/application/plugin_platform.dart').read_text(encoding='utf-8')
        declarations = (ROOT / 'packages/multiplexr_plugin_sdk/src/index.d.ts').read_text(encoding='utf-8')
        offered = set(re.findall(r"case '([a-z]+\.[A-Za-z]+)':", gateway))
        interface = declarations.split('export interface HostMethods {', 1)[1].split('\n}', 1)[0]
        typed = set(re.findall(r"'([^']+)':", interface))
        self.assertEqual(offered, typed)

    def test_bundled_provider_implementations_and_network_endpoints_are_absent(self):
        forbidden = ['class Tmdb', 'class AudiobookMetadataService',
                     'image.tmdb.org', 'api.themoviedb.org', 'api.audiobookdb.org']
        roots = [ROOT / 'lib', ROOT / 'android/app/src/main/kotlin']
        for root in roots:
            for file in root.rglob('*'):
                if file.suffix not in ('.dart', '.kt'):
                    continue
                value = file.read_text(encoding='utf-8')
                for marker in forbidden:
                    self.assertNotIn(marker, value, str(file))
        plugins = ROOT / 'android/app/src/main/kotlin/com/bugdeployer/multiplexr/plugins'
        for file in plugins.glob('*.kt'):
            self.assertNotIn('java.util.Base64', file.read_text(encoding='utf-8').replace(
                '/** Standard base64 without API-26 java.util.Base64 dependencies. */', ''), str(file))

    def test_sdk_fixtures_match_native_installation_proofs(self):
        pairs = [('test/fixtures/installed-v1.signed.json', 'src/test/resources/plugins/installed-v1.json'),
                 ('test/fixtures/installed-inspector.signed.json', 'src/androidTest/assets/installed-signed.plugin.json')]
        for sdk, native in pairs:
            self.assertEqual(json.loads((ROOT / 'packages/multiplexr_plugin_sdk' / sdk).read_text(encoding='utf-8')),
                             json.loads((ROOT / 'android/app' / native).read_text(encoding='utf-8')))

    def test_android_fixture_is_the_current_independently_built_sdk(self):
        sdk = ROOT / 'packages/multiplexr_plugin_sdk'
        with tempfile.TemporaryDirectory() as folder:
            artifact = Path(folder) / 'synthetic.json'
            subprocess.run(['node', str(sdk / 'bin/plugin.js'), 'build',
                            str(sdk / 'examples/synthetic'), str(artifact)],
                           check=True, capture_output=True, timeout=30)
            expected = json.loads(artifact.read_text(encoding='utf-8'))
        fixture = ROOT / 'android/app/src/androidTest/assets/synthetic.plugin.json'
        self.assertEqual(json.loads(fixture.read_text(encoding='utf-8')), expected,
                         'Regenerate the Android fixture before running the isolation proof')

if __name__ == '__main__':
    unittest.main()
