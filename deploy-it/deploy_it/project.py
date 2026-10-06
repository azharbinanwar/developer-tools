import json
import shlex
import shutil
import subprocess
from pathlib import Path


class LocalProject:
    def __init__(self, path, build=None, output=None):
        self.root = Path(path).expanduser().resolve()
        try:
            package = json.loads((self.root / 'package.json').read_text())
        except (OSError, ValueError):
            raise ValueError('This folder does not contain a valid package.json.')
        dependencies = dict(package.get('dependencies', {}), **package.get('devDependencies', {}))
        if 'vite' not in dependencies or 'react' not in dependencies:
            raise ValueError('This version supports React + Vite static websites. This is not one.')
        if not package.get('scripts', {}).get('build'):
            raise ValueError('package.json needs a build script.')
        if (self.root / 'api').exists():
            raise ValueError('An api/ directory was found. This static-only version will not upload functions.')
        self.name = package.get('name') or self.root.name
        self.manager = next((manager for filename, manager in (
            ('pnpm-lock.yaml', 'pnpm'), ('yarn.lock', 'yarn'),
            ('bun.lock', 'bun'), ('bun.lockb', 'bun')) if (self.root / filename).exists()), 'npm')
        self.build = build or '{} run build'.format(self.manager)
        self.output = output or 'dist'
        self.output_path = (self.root / self.output).resolve()
        if self.output_path == self.root or self.root not in self.output_path.parents:
            raise ValueError('The output must be a subfolder inside the project.')

    def compile(self, log_path=None):
        command = shlex.split(self.build)
        if not command or not shutil.which(command[0]):
            raise ValueError('Build command executable is unavailable: {}'.format(self.build))
        # No shell interpolation; build scripts belong to the selected project.
        if log_path is None:
            result = subprocess.run(command, cwd=str(self.root))
            returncode = result.returncode
        else:
            with open(log_path, 'w') as log:
                Path(log_path).chmod(0o600)
                log.write('Project: {}\nCommand: {}\n\n'.format(self.root, self.build))
                process = subprocess.Popen(command, cwd=str(self.root), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                try:
                    for line in process.stdout:
                        print(line, end='', flush=True)
                        log.write(line)
                        log.flush()
                    returncode = process.wait()
                finally:
                    process.stdout.close()
                    if process.poll() is None:
                        process.terminate()
                        process.wait()
        if returncode:
            raise ValueError('Build failed. Nothing was deployed.')
        if not (self.output_path / 'index.html').is_file():
            raise ValueError('No index.html in {}. Set the correct output folder.'.format(self.output_path))

    def stage(self, destination, remote, org_id):
        if not (self.output_path / 'index.html').is_file():
            raise ValueError('Build output is missing.')
        shutil.copytree(self.output_path, destination, dirs_exist_ok=True, symlinks=True)
        stage = Path(destination)
        for item in stage.rglob('*'):
            if item.is_symlink():
                raise ValueError('Build output contains a symlink; deployment stopped.')
        if (stage / '.vercel').exists() or (stage / '.env').exists():
            raise ValueError('Unexpected credential/config files in build output.')
        settings = {}
        config_path = self.root / 'vercel.json'
        if config_path.exists():
            settings = json.loads(config_path.read_text())
            if 'builds' in settings or 'functions' in settings:
                raise ValueError('Legacy builds/functions require source deployment, which is outside static Vite support.')
        settings.update({'version': 2, 'framework': None, 'buildCommand': None,
                         'installCommand': None, 'outputDirectory': '.'})
        settings.setdefault('rewrites', [{'source': '/(.*)', 'destination': '/index.html'}])
        (stage / 'vercel.json').write_text(json.dumps(settings, indent=2))
        (stage / '.vercel').mkdir()
        (stage / '.vercel' / 'project.json').write_text(json.dumps({
            'projectId': remote['id'], 'orgId': org_id, 'projectName': remote['name']}))
        return stage


def detect(path):
    path = Path(path).expanduser().resolve()
    for candidate in [path] + list(path.parents):
        if (candidate / 'package.json').is_file():
            return candidate
    return None
