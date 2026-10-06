import json
import os
import tempfile
from pathlib import Path
from datetime import datetime, timezone

HOME_DIR = Path(__file__).resolve().parent.parent


class Config:
    def __init__(self, directory=None, readonly=False):
        self.directory = Path(directory or os.environ.get('DEPLOY_IT_HOME', HOME_DIR))
        self.path = self.directory / 'config.json'
        self.readonly = readonly
        if self.path.exists():
            try:
                self.data = json.loads(self.path.read_text())
            except (ValueError, OSError) as error:
                raise ValueError('Cannot read config.json; fix it before continuing: {}'.format(error))
        else:
            self.data = {'version': 1, 'accounts': {}, 'projects': {}}

    def save(self):
        if self.readonly:
            return
        self.directory.mkdir(parents=True, exist_ok=True)
        fd, filename = tempfile.mkstemp(dir=str(self.directory), prefix='.config-')
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, 'w') as stream:
                json.dump(self.data, stream, indent=2)
                stream.write('\n')
            os.replace(filename, self.path)
        finally:
            if os.path.exists(filename): os.unlink(filename)

    def remember(self, local, account, remote):
        key = str(local.root)
        self.data['projects'][key] = {
            'path': key, 'name': remote['name'], 'id': remote['id'],
            'account': account, 'build': local.build, 'output': local.output,
        }
        self.save()

    def log(self, event):
        if self.readonly: return
        self.directory.mkdir(parents=True, exist_ok=True)
        path = self.directory / 'history.jsonl'
        previous = path.read_text().splitlines()[-199:] if path.exists() else []
        event = dict(event, at=datetime.now(timezone.utc).isoformat())
        previous.append(json.dumps(event))
        path.write_text('\n'.join(previous) + '\n')
        path.chmod(0o600)
