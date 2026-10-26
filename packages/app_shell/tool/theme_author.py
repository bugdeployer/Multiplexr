"""Validate/build a data-only theme with the real Flutter host compiler."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['validate', 'build'])
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path, nargs='?')
    args = parser.parse_args()
    if args.input.is_symlink():
        parser.error('Symlink inputs are not supported.')
    source = args.input.resolve(strict=True)
    if not source.is_file() or source.stat().st_size > 4194304:
        parser.error('A regular UTF-8 JSON file of at most 4 MiB is required.')
    if (args.command == 'build') != (args.output is not None):
        parser.error('build requires a new output path; validate takes no output.')
    flutter = shutil.which('flutter')
    if not flutter:
        parser.error('Flutter must be available on PATH. Run flutter pub get first.')
    with tempfile.TemporaryDirectory(prefix='app-shell-theme-') as temporary:
        result = Path(temporary) / 'validated.json'
        env = dict(os.environ, APP_SHELL_THEME_INPUT=str(source), APP_SHELL_THEME_RESULT=str(result))
        subprocess.run([flutter, 'test', 'test/theme_author_cli_test.dart', '--reporter', 'expanded'], cwd=ROOT, env=env, check=True)
        if args.output is not None:
            # Exclusive creation: author tools never overwrite an existing package.
            with args.output.open('x', encoding='utf-8') as target:
                target.write(result.read_text(encoding='utf-8'))
        print('Validated data-only theme package.' if args.output is None else 'Built data-only theme package.')

if __name__ == '__main__':
    main()
