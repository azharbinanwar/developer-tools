import json
import os
import shutil
import subprocess
from urllib.parse import urlencode, quote, urlsplit
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from pathlib import Path
from .config import HOME_DIR


def hostname(value):
    value = value.strip()
    parsed = urlsplit(value if '://' in value else 'https://' + value)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.port or parsed.path not in ('', '/') or parsed.query or parsed.fragment:
        raise ValueError('Paste a plain HTTPS deployment/domain URL, without a path or query.')
    return parsed.hostname.lower()


class Vercel:
    def __init__(self, config, label, account=None, dry=False):
        self.config = config
        self.label = label
        self.account = account if account is not None else config.data['accounts'][label]
        self.dry = dry
        self.session = config.directory / 'accounts' / label
        self.executable = os.environ.get('DEPLOY_IT_VERCEL') or shutil.which('vercel') or str(HOME_DIR / 'runtime' / 'node_modules' / '.bin' / 'vercel')
        self.token = ''
        token_file = self.session / 'token'
        if token_file.exists(): self.token = token_file.read_text().strip()

    def cli(self, args, capture=False, cwd=None, mutation=False, scoped=True):
        if mutation and self.dry:
            raise ValueError('Dry run blocked a remote mutation.')
        if not Path(self.executable).is_file() and not shutil.which(self.executable):
            raise ValueError('Vercel CLI is not installed. See deploy-it/README.md.')
        command = [self.executable] + list(args) + ['--global-config', str(self.session)]
        if self.token: command += ['--token', self.token]
        if scoped and self.account.get('scope'): command += ['--scope', self.account['scope']]
        env = dict(os.environ, VERCEL_TELEMETRY_DISABLED='1', NO_COLOR='1')
        # Never inherit a different account or project through environment variables.
        for name in ('VERCEL_TOKEN', 'VERCEL_PROJECT_ID', 'VERCEL_ORG_ID'):
            env.pop(name, None)
        result = subprocess.run(command, cwd=str(cwd) if cwd else None, env=env,
                                stdout=subprocess.PIPE if capture else None,
                                stderr=subprocess.PIPE if capture else None, text=True)
        if result.returncode:
            detail = (result.stderr or result.stdout or 'Vercel command failed.').strip()
            if self.token: detail = detail.replace(self.token, '[redacted]')
            raise ValueError(detail)
        return result.stdout or ''

    def api(self, endpoint, method='GET', data=None, scoped=True):
        if self.dry and method != 'GET':
            raise ValueError('Dry run blocked {} {}'.format(method, endpoint))
        if scoped and self.account.get('team_id'):
            endpoint += ('&' if '?' in endpoint else '?') + urlencode({'teamId': self.account['team_id']})
        if not self.token:
            args = ['api', endpoint, '--raw', '--method', method]
            if data is not None:
                import tempfile
                with tempfile.NamedTemporaryFile(mode='w', suffix='.json') as stream:
                    json.dump(data, stream); stream.flush()
                    return json.loads(self.cli(args + ['--input', stream.name], capture=True, mutation=method != 'GET', scoped=scoped) or '{}')
            return json.loads(self.cli(args, capture=True, mutation=method != 'GET', scoped=scoped) or '{}')
        body = json.dumps(data).encode() if data is not None else None
        request = Request('https://api.vercel.com' + endpoint, data=body, method=method,
                          headers={'Authorization': 'Bearer ' + self.token, 'Content-Type': 'application/json'})
        try:
            with urlopen(request, timeout=30) as response:
                payload = response.read()
                return json.loads(payload) if payload else {}
        except HTTPError as error:
            try: detail = json.loads(error.read()).get('error', {}).get('message', str(error))
            except ValueError: detail = str(error)
            raise ValueError('Vercel: {}'.format(detail))
        except URLError as error:
            raise ValueError('Cannot reach Vercel: {}'.format(error.reason))

    def pages(self, endpoint, key):
        items, cursor, seen = [], None, set()
        while True:
            url = endpoint + (('&' if '?' in endpoint else '?') + urlencode({'until': cursor}) if cursor else '')
            response = self.api(url)
            items.extend(response.get(key, []))
            cursor = response.get('pagination', {}).get('next')
            if not cursor: return items
            if cursor in seen: raise ValueError('Vercel repeated a pagination cursor; stopped.')
            seen.add(cursor)

    def projects(self): return self.pages('/v9/projects?limit=100', 'projects')
    def project(self, project_id): return self.api('/v9/projects/' + quote(project_id, safe=''))
    def domains(self, project_id): return self.pages('/v9/projects/{}/domains?limit=100'.format(quote(project_id, safe='')), 'domains')
    def deployments(self, project_id): return self.pages('/v6/deployments?' + urlencode({'projectId': project_id, 'limit': 100}), 'deployments')
    def deployment(self, deployment_id): return self.api('/v13/deployments/' + quote(deployment_id, safe=''))

    def from_url(self, value):
        host = hostname(value)
        try:
            deployment = self.deployment(host)
            project_id = deployment.get('projectId') or deployment.get('project', {}).get('id')
            if project_id: return self.project(project_id)
        except ValueError:
            pass
        for project in self.projects():
            if any(domain.get('name') == host for domain in self.domains(project['id'])):
                return project
        raise ValueError('That URL was not found in this account/scope. Try another account.')
