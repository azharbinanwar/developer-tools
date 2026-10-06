import argparse
import getpass
import json
import re
import shutil
import subprocess
import sys
import tempfile
import webbrowser
from pathlib import Path
from datetime import datetime, timezone, timedelta
from .config import Config
from .project import LocalProject, detect
from .vercel import Vercel
from .ui import ask, choose, confirm, heading, row, loading


def show_local(local):
    heading('Valid React + Vite project')
    row('folder', local.root)
    row('build', local.build)
    row('output', local.output_path)


def add_account(config):
    name = ask('Account label — your name (e.g. Azhar Ali)').strip()
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9 _-]{0,63}', name):
        raise ValueError('Use an account label with letters, numbers, spaces, hyphens or underscores.')
    if name in config.data['accounts']:
        raise ValueError('That label already exists. Pick it from Accounts to sign in again.')
    config.data['accounts'][name] = {}
    config.save()
    authenticate(config, name)
    return name


def authenticate(config, name):
    if config.readonly:
        raise ValueError('Account setup is disabled in dry run. Run deploy-it accounts first.')
    client = Vercel(config, name)
    heading('Vercel token / ' + name)
    row('token page', 'https://vercel.com/account/tokens')
    choice = choose('Add the token for ' + name, ['Paste a Vercel token', 'Open token page in browser, then paste token', 'Sign in with Vercel instead'])
    if choice is None: return
    if choice == 1:
        if not webbrowser.open('https://vercel.com/account/tokens'):
            print('    Open https://vercel.com/account/tokens in your browser.')
        print('    Create and copy a token, then return here to paste it.')
    client.session.mkdir(parents=True, exist_ok=True, mode=0o700)
    client.session.chmod(0o700)
    token_file = client.session / 'token'
    if choice == 2:
        client.token = ''
        client.cli(['login'], scoped=False)
        if token_file.exists(): token_file.unlink()
    else:
        token = getpass.getpass('    Vercel token for ' + name + ' (paste hidden): ').strip()
        if not token: return
        client.token = token
        user = client.api('/v2/user', scoped=False)['user']
        token_file.write_text(token + '\n'); token_file.chmod(0o600)
        row('account label', name)
        row('signed in', user.get('username') or user.get('name', 'Vercel user'))
    select_scope(config, name)


def select_scope(config, name):
    client = Vercel(config, name)
    teams = client.pages('/v2/teams?limit=100', 'teams')
    user = client.api('/v2/user', scoped=False)['user']
    labels = [team.get('name', team['slug']) + ' / ' + team['slug'] for team in teams]
    if not teams:
        labels = ['Personal account / ' + user['username']]
    index = choose('Select the account/team scope', labels)
    if index is None: return
    if teams:
        selected = teams[index]
        config.data['accounts'][name].update(scope=selected['slug'], team_id=selected['id'], org_id=selected['id'])
    else:
        config.data['accounts'][name].update(scope=user['username'], org_id=user['id'])
        config.data['accounts'][name].pop('team_id', None)
    config.save()


def pick_account(config, preferred=None):
    accounts = list(config.data['accounts'])
    if preferred and preferred in accounts: return preferred
    if not accounts:
        if config.readonly: return None
        print('    No Vercel account is configured yet.')
        return add_account(config)
    labels = ['{} / {}'.format(name, config.data['accounts'][name].get('scope', 'not set up')) for name in accounts]
    if not config.readonly: labels.append('+ Add an account')
    index = choose('Vercel account', labels)
    if index is None: return None
    if index == len(accounts): return add_account(config)
    return accounts[index]


def client_for(config, name):
    client = Vercel(config, name, dry=config.readonly)
    try:
        client.api('/v2/user', scoped=False)
    except ValueError as error:
        print('    Authentication failed: {}'.format(error))
        if config.readonly: raise
        if not confirm('Set up this account now'): raise
        authenticate(config, name)
        client = Vercel(config, name)
        client.api('/v2/user', scoped=False)
    return client


def accounts_menu(config):
    while True:
        names = list(config.data['accounts'])
        index = choose('Accounts', names + ['+ Add account', 'Back'])
        if index is None or index == len(names) + 1: return
        if index == len(names): add_account(config); continue
        name = names[index]
        action = choose(name, ['Sign in / replace token', 'Change team scope', 'Show usage', 'Back'])
        if action == 0: authenticate(config, name)
        elif action == 1: select_scope(config, name)
        elif action == 2: client_for(config, name).cli(['usage'])


def pick_remote(client, create=False, local_name=None):
    with loading('Fetching Vercel projects'):
        projects = client.projects()
    options = [project['name'] for project in projects]
    if create: options.append('+ Create a Vercel project')
    options += ['Find by deployment/domain URL', 'Back']
    normalized = re.sub(r'[^a-z0-9]+', '-', (local_name or '').lower()).strip('-')
    default = next((i for i, project in enumerate(projects) if project['name'] == normalized), len(projects) if create else 0)
    index = choose('Vercel projects / ' + client.label, options, default=default)
    if index is None or index == len(options) - 1: return None
    if index < len(projects): return projects[index]
    if options[index].startswith('+'):
        while True:
            entered = ask('New Vercel project name (Enter uses this name; type to change)', normalized).strip()
            if not entered: return None
            name = re.sub(r'[^a-z0-9]+', '-', entered.lower()).strip('-')
            if not name or len(name) > 100:
                print('    Enter a name containing letters or numbers, up to 100 characters after formatting.')
                continue
            if name != entered:
                row('formatted name', name)
            try:
                with loading('Creating Vercel project ' + name):
                    return client.api('/v10/projects', 'POST', {'name': name, 'framework': None})
            except ValueError as error:
                print('    Could not create project: {}'.format(error))
                print('    Try another name, or leave the name empty to go back.')
    return client.from_url(ask('Paste the deployment or project domain URL'))


def show_domains(client, remote):
    domains = client.domains(remote['id'])
    for domain in domains:
        row('domain', 'https://' + domain['name'] + (' [unverified]' if domain.get('verified') is False else ''))
    return domains


def deploy(config, args, path=None, remote=None, account=None):
    path = path or args.path or detect(Path.cwd())
    if not path: raise ValueError('No project detected. Use --path or Add a local folder.')
    saved = config.data['projects'].get(str(Path(path).expanduser().resolve()), {})
    local = LocalProject(path, args.build_command or saved.get('build'), args.output or saved.get('output'))
    show_local(local)
    if not args.dry_run and not confirm('Deploy this project', default=True): return
    account = account or pick_account(config, args.account or saved.get('account'))
    client = None
    if account:
        with loading('Checking Vercel account access'):
            client = client_for(config, account)
    if not client:
        row('account', 'not configured — remote validation unavailable')
        if args.build: local.compile()
        print('    Dry run: local validation passed. No upload or remote changes. Configure an account for target/access checks.')
        return
    if remote is None and saved.get('id') and saved.get('account') == account:
        with loading('Loading saved Vercel project'):
            remote = client.project(saved['id'])
    if remote is None:
        # A local Vercel link is only a suggestion; confirm access in the chosen account.
        linked = local.root / '.vercel' / 'project.json'
        if linked.exists():
            suggestion = json.loads(linked.read_text()).get('projectId')
            if suggestion and confirm('Use the existing .vercel project link'):
                remote = client.project(suggestion)
    if remote is None: remote = pick_remote(client, create=not args.dry_run, local_name=local.root.name)
    if remote is None: return
    with loading('Fetching project domains'):
        domains = show_domains(client, remote)
    org = client.account.get('org_id') or remote.get('accountId')
    if not org: raise ValueError('Select an account/team scope before deploying.')
    production = args.production
    if not args.production and not args.preview:
        main_domains = [domain['name'] for domain in domains if not domain.get('gitBranch') and not domain.get('redirect')]
        destination = main_domains[0] if main_domains else remote['name'] + '.vercel.app'
        target = choose('Where do you want to publish?', ['Main website — update ' + destination, 'Test version — create a new preview URL'])
        if target is None: return
        production = target == 0
    row('account', account + ' / ' + client.account.get('scope', 'personal'))
    row('project', remote['name'])
    row('target', 'Production' if production else 'Preview')
    if production:
        print('    Production updates all production domains attached to this project.')
    if args.dry_run:
        if args.build: local.compile()
        print('    Dry run passed: project and account access checked. No upload, linking, deployment, deletion or settings changes.')
        return
    heading('1 / 2 — Building')
    log_dir = config.directory / 'logs'
    log_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    build_log = log_dir / (datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f') + '-build.log')
    try:
        local.compile(log_path=build_log)
    except ValueError:
        config.log({'action': 'build', 'status': 'failed', 'project': remote['name'], 'log': str(build_log)})
        row('build log', build_log)
        raise
    config.log({'action': 'build', 'status': 'success', 'project': remote['name'], 'log': str(build_log)})
    row('build log', build_log)
    heading('2 / 2 — Publishing to Vercel')
    with tempfile.TemporaryDirectory(prefix='deploy-it-') as directory:
        local.stage(directory, remote, org)
        command = ['deploy', '--yes'] + (['--prod'] if production else [])
        with loading('Uploading and deploying — waiting for Vercel'):
            output = client.cli(command, capture=True, cwd=directory, mutation=True)
    urls = re.findall(r'https://[^\s]+\.vercel\.app(?:[^\s]*)?', output)
    if not urls: raise ValueError('Deployment finished but no URL was returned. Check Vercel before retrying.')
    deployment_url = urls[-1].rstrip('/'); share_url = deployment_url
    if production:
        domains = client.domains(remote['id'])
        ready = [domain for domain in domains if domain.get('verified') is not False and not domain.get('gitBranch') and not domain.get('redirect')]
        if ready:
            primary = next((domain for domain in ready if domain['name'].endswith('.vercel.app')), ready[0])
            share_url = 'https://' + primary['name']
    print('\n  ✓ Published successfully')
    print('     Website: ' + share_url)
    if production and deployment_url != share_url:
        text = '     Build URL: ' + deployment_url
        print(('\033[2m' + text + '\033[0m') if sys.stdout.isatty() else text)
    if shutil.which('pbcopy'):
        subprocess.run(['pbcopy'], input=share_url, text=True, check=False)
        print('    Link copied.')
    config.remember(local, account, remote)
    config.log({'action': 'deploy', 'project': remote['name'], 'account': account, 'production': production, 'url': deployment_url})
    return completion_menu(share_url)


def completion_menu(share_url):
    while True:
        action = choose('What next?', ['Open website in browser', 'Deploy another project', 'Manage existing projects', 'Exit'])
        if action is None or action == 3: return
        if action == 0:
            if not webbrowser.open(share_url):
                print('    Open ' + share_url + ' in your browser.')
        else:
            return 'projects'



def timestamp(item):
    value = item.get('createdAt') or item.get('created') or 0
    return datetime.fromtimestamp(value / 1000, timezone.utc)


def deployment_label(item):
    date = timestamp(item).strftime('%Y-%m-%d %H:%M UTC')
    return '{} / {} / {} / {}'.format(date, item.get('target') or 'preview', item.get('state', item.get('readyState', '?')), item.get('url', item.get('uid', '?')))


def destructive(config, client, label, target, endpoint, method='DELETE', data=None):
    if config.readonly:
        row('dry run', '{} {}'.format(label, target))
        return
    heading(label)
    row('account', client.label + ' / ' + client.account.get('scope', ''))
    row('target', target)
    if ask('Type the exact target above to confirm') != target:
        print('    Cancelled.'); return
    client.api(endpoint, method, data)
    config.log({'action': label, 'target': target, 'account': client.label})
    print('    Done.')


def cleanup(config, client, remote):
    # Read every page; keep production, recent builds, and all aliased deployments.
    items = sorted(client.deployments(remote['id']), key=timestamp, reverse=True)
    candidates = [item for item in items[5:] if item.get('target') != 'production'
                  and item.get('state', item.get('readyState')) in ('READY', 'ERROR', 'CANCELED')
                  and timestamp(item) < datetime.now(timezone.utc) - timedelta(days=30)]
    safe = []
    for item in candidates:
        deployment_id = item.get('uid') or item['id']
        detail = client.deployment(deployment_id)
        aliases = client.pages('/v2/deployments/{}/aliases'.format(deployment_id), 'aliases')
        if detail.get('target') == 'production' or detail.get('alias') or detail.get('aliasAssigned') or aliases: continue
        safe.append(item)
    if not safe:
        print('    No unaliased previews older than 30 days outside the newest five deployments.'); return
    heading('Cleanup candidates — production and aliases preserved')
    for item in safe: row('remove', deployment_label(item))
    if config.readonly:
        print('    Dry run: nothing deleted.'); return
    expected = '{} / {}'.format(remote['name'], len(safe))
    if ask('Type {} to delete this selection'.format(expected)) != expected: return
    for item in safe:
        deployment_id = item.get('uid') or item['id']
        # Recheck immediately before deletion to avoid deleting a promoted version.
        detail = client.deployment(deployment_id)
        aliases = client.pages('/v2/deployments/{}/aliases'.format(deployment_id), 'aliases')
        if detail.get('target') == 'production' or detail.get('alias') or detail.get('aliasAssigned') or aliases:
            row('skipped', deployment_id); continue
        client.api('/v13/deployments/' + deployment_id, 'DELETE')
        config.log({'action': 'cleanup', 'target': deployment_id, 'account': client.label})
    print('    Cleanup finished.')


def remote_menu(config, args, client, remote):
    while True:
        heading(remote['name'] + ' / ' + client.label)
        index = choose('Manage project', ['Deploy from a local folder', 'Domains / URLs', 'Deployments / delete a version',
                    'Clean old previews', 'Pause production', 'Resume production', 'Roll back production', 'Delete entire project', 'Back'])
        if index is None or index == 8: return
        if index == 0: deploy(config, args, ask('Local React + Vite folder'), remote, client.label)
        elif index == 1: show_domains(client, remote)
        elif index == 2:
            items = client.deployments(remote['id'])
            if not items: print('    No deployments.'); continue
            selected = choose('Deployments', [deployment_label(item) for item in items] + ['Back'])
            if selected is None or selected == len(items): continue
            item = items[selected]; row('URL', 'https://' + item['url'])
            action = choose('This version', ['Show details', 'Delete deployment', 'Back'])
            deployment_id = item.get('uid') or item['id']
            if action == 0:
                detail = client.deployment(deployment_id)
                for key in ('id', 'url', 'readyState', 'target', 'createdAt'): row(key, detail.get(key, '—'))
            elif action == 1: destructive(config, client, 'Delete deployment', deployment_id, '/v13/deployments/' + deployment_id)
        elif index == 3: cleanup(config, client, remote)
        elif index in (4,5):
            verb = 'pause' if index == 4 else 'unpause'
            destructive(config, client, verb.title() + ' project', remote['name'], '/v1/projects/' + remote['id'] + '/' + verb, 'POST')
        elif index == 6:
            if config.readonly: print('    Dry run: would request rollback; nothing changed.'); continue
            if confirm('Roll back PRODUCTION for ' + remote['name']):
                latest = client.project(remote['id'])
                current = latest.get('targets', {}).get('production', {}).get('id')
                previous = [item for item in sorted(client.deployments(remote['id']), key=timestamp, reverse=True) if item.get('target') == 'production' and (item.get('uid') or item.get('id')) != current and item.get('state', item.get('readyState')) == 'READY']
                if not current or not previous: raise ValueError('Could not identify a previous production deployment.')
                client.cli(['rollback', previous[0].get('uid') or previous[0]['id']], mutation=True)
        elif index == 7:
            print('    This deletes the Vercel project and its deployments. Local source files remain.')
            destructive(config, client, 'Delete project', remote['name'], '/v9/projects/' + remote['id'])
            if not config.readonly: return


def dashboard(config, args):
    while True:
        saved = list(config.data['projects'].values())
        entries = ['{} / {} / {}'.format(project['name'], project['account'], project['path']) for project in saved]
        options = entries + ['+ Add a local folder', 'Fetch Vercel projects', 'Find by deployment/domain URL', 'Accounts', 'Quit']
        index = choose('deploy-it / projects', options)
        if index is None or index == len(options)-1: return
        try:
            if index < len(saved): deploy(config, args, saved[index]['path'])
            elif index == len(saved):
                path = ask('Paste the local React + Vite folder')
                deploy(config, args, path)
            elif index in (len(saved)+1, len(saved)+2):
                name = pick_account(config, args.account)
                if not name: continue
                client = client_for(config, name)
                remote = pick_remote(client) if index == len(saved)+1 else client.from_url(ask('Paste a deployment/domain URL'))
                if remote: remote_menu(config, args, client, remote)
            elif index == len(saved)+3: accounts_menu(config)
        except (ValueError, OSError) as error:
            print('\n    ! ' + str(error))


def main():
    parser = argparse.ArgumentParser(description='Build, publish and manage React + Vite sites on Vercel.')
    parser.add_argument('command', nargs='?', choices=['accounts', 'projects'], help='Open an explicit menu')
    parser.add_argument('--path', help='Local React + Vite project folder')
    parser.add_argument('--account', help='Saved account label')
    targets = parser.add_mutually_exclusive_group()
    targets.add_argument('--production', '--prod', action='store_true', help='Select the stable production target')
    targets.add_argument('--preview', action='store_true', help='Select a preview deployment')
    parser.add_argument('--dry-run', '-n', action='store_true', help='Validate without uploads or remote/config mutations')
    parser.add_argument('--build', action='store_true', help='Also run the local build during dry run (writes build output)')
    parser.add_argument('--build-command', help='Override build command; no shell expansion')
    parser.add_argument('--output', help='Build output subfolder, default dist')
    parser.add_argument('--version', action='version', version='deploy-it 1.0.0')
    args = parser.parse_args()
    try:
        config = Config(readonly=args.dry_run)
        if args.account and args.account not in config.data['accounts']:
            raise ValueError('Unknown account. Run deploy-it accounts to add it.')
        if args.command == 'accounts':
            if args.dry_run: raise ValueError('Account setup is disabled in dry run.')
            accounts_menu(config)
        elif args.command == 'projects': dashboard(config, args)
        elif args.path or detect(Path.cwd()):
            if deploy(config, args) == 'projects': dashboard(config, args)
        else: dashboard(config, args)
    except KeyboardInterrupt:
        print('\n    Cancelled.'); sys.exit(130)
    except (ValueError, OSError, KeyError) as error:
        print('\n    ! ' + str(error), file=sys.stderr); sys.exit(1)
