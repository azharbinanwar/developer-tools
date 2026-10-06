import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from deploy_it.config import Config
from deploy_it.project import LocalProject, detect
from deploy_it.vercel import Vercel, hostname
from deploy_it.app import main


class DeployItTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.project = self.root / 'site'; self.project.mkdir()
        (self.project / 'package.json').write_text(json.dumps({'name': 'test-site', 'scripts': {'build': 'vite build'}, 'dependencies': {'react': '19'}, 'devDependencies': {'vite': '8'}}))

    def tearDown(self): self.temp.cleanup()

    def test_detect_nested_folder(self):
        nested = self.project / 'src' / 'components'; nested.mkdir(parents=True)
        self.assertEqual(detect(nested), self.project.resolve())

    def test_reject_non_vite_and_output_outside_project(self):
        with self.assertRaises(ValueError): LocalProject(self.project, output='../outside')
        (self.project / 'package.json').write_text('{}')
        with self.assertRaises(ValueError): LocalProject(self.project)

    def test_dry_run_cannot_mutate_api_or_cli(self):
        config = Config(self.root / 'state', readonly=True)
        client = Vercel(config, 'test', {}, dry=True)
        with patch('deploy_it.vercel.subprocess.run') as process:
            with self.assertRaises(ValueError): client.cli(['deploy'], mutation=True)
            with self.assertRaises(ValueError): client.api('/v9/projects/test', 'DELETE')
            process.assert_not_called()
        config.save(); config.log({'action': 'test'})
        self.assertFalse(config.directory.exists())

    def test_offline_dry_run_never_builds_or_saves(self):
        state = self.root / 'empty-state'
        with patch.dict('os.environ', {'DEPLOY_IT_HOME': str(state)}), patch('sys.argv', ['deploy-it', '--dry-run', '--path', str(self.project)]), patch('deploy_it.project.subprocess.run') as run:
            main()
            run.assert_not_called()
        self.assertFalse(state.exists())
        self.assertFalse((self.project / 'dist').exists())

    def test_only_build_output_is_staged(self):
        dist = self.project / 'dist'; dist.mkdir()
        (dist / 'index.html').write_text('<html/>')
        (self.project / '.env').write_text('SECRET=should-not-upload')
        local = LocalProject(self.project)
        destination = self.root / 'stage'
        local.stage(destination, {'id': 'prj_test', 'name': 'test-site'}, 'team_test')
        self.assertFalse((destination / '.env').exists())
        self.assertFalse((destination / 'package.json').exists())
        link = json.loads((destination / '.vercel' / 'project.json').read_text())
        self.assertEqual(link['projectId'], 'prj_test')
        self.assertEqual(link['orgId'], 'team_test')
        self.assertEqual(json.loads((destination / 'vercel.json').read_text())['outputDirectory'], '.')

    def test_output_symlinks_are_rejected(self):
        dist = self.project / 'dist'; dist.mkdir()
        (dist / 'index.html').write_text('<html/>')
        secret = self.root / 'secret'; secret.write_text('secret')
        (dist / 'file').symlink_to(secret)
        with self.assertRaises(ValueError):
            LocalProject(self.project).stage(self.root / 'stage', {'id':'prj_test','name':'test'}, 'team_test')

    def test_hostnames_never_accept_credentials_or_paths(self):
        self.assertEqual(hostname('https://test.vercel.app/'), 'test.vercel.app')
        for value in ('https://user:pass@test.vercel.app', 'http://test.vercel.app', 'https://test.vercel.app/file', 'https://test.vercel.app?secret=x'):
            with self.assertRaises(ValueError): hostname(value)

    def test_pagination_fetches_every_page(self):
        client = Vercel(Config(self.root/'state'), 'test', {})
        with patch.object(client, 'api', side_effect=[{'projects':[{'id':'a'}], 'pagination':{'next':123}}, {'projects':[{'id':'b'}], 'pagination':{}}]) as api:
            self.assertEqual([p['id'] for p in client.projects()], ['a','b'])
            self.assertIn('until=123', api.call_args_list[1].args[0])

    def test_config_credentials_permissions_and_log_bound(self):
        config = Config(self.root/'state'); config.save()
        self.assertEqual(config.path.stat().st_mode & 0o777, 0o600)
        for i in range(205): config.log({'index':i})
        self.assertEqual(len((config.directory/'history.jsonl').read_text().splitlines()), 200)

if __name__ == '__main__': unittest.main()
