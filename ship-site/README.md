# ship-site

Build a web app, publish only its build folder to **Vercel** or **Firebase Hosting**, copy the link. Works with Vite (React, Vue, Svelte…), Create React App, Next.js static export, Eleventy, Jekyll: anything whose build script leaves an `index.html` in `dist/`, `build/`, `out/` or `_site/`. Several accounts on each, side by side, with no long commands to remember.

## Run it

Inside your Vite project:

```sh
ship-site
```

Or without installing:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/azharbinanwar/developer-tools/main/ship-site/ship-site)
```

Install options, and the `developer-tools` hub, are in the [main README](../README.md#2-install-it).

## Commands

```
ship-site              your Vercel projects and Firebase sites; pick one, it builds and publishes
ship-site --prod       straight to the main website, no question asked
ship-site --preview    a fresh test URL, the main website untouched
ship-site --dry-run    check everything and show what would happen; changes nothing (also -n)
ship-site ~/site       treat that folder as the current project
ship-site accounts     add or remove Vercel and Firebase accounts
ship-site -v           version
```

## What happens

### 1. Projects

```
▸ Projects
   you are in ~/Desktop/mine/rig-register-web
 ❯ rig-register-web       Vercel   Mohsin Dev     rig-register-web.vercel.app   ● this folder
   thoub.app              Firebase azhar@…        thoub-web.web.app
   advisor-app-a63c2      Firebase azhar@…        advisor-app-a63c2.web.app
   studiodesk             Vercel   Mohsin Dev     studiodesk-chi.vercel.app
   + new project
   label a project
   accounts
   refresh
   quit
```

Every Vercel project and Firebase site across all your accounts. The list opens from a local cache at once and is refreshed when it is older than 10 minutes, or with **refresh**. Each Firebase project shows its default hosting site; extra sites appear once you create them through **+ new project**. Projects you have built from this Mac come first. Inside a project folder, the one it publishes to is preselected; a folder set up with the Firebase CLI before gets its `.firebaserc` project preselected the first time, no searching. Expired Vercel sign-ins are renewed on their own.

For Firebase, nothing has to be set up in your repo: no `firebase init`, no `firebase.json`. Sign in once, pick or create a project, publish.

- **+ new project**: a Vercel project, or a Firebase site — inside one of your existing Firebase projects (`<name>.web.app`), or in a brand-new Firebase project made from just a name (free plan, Hosting only, no billing). With no account on that host yet, it signs you in first. It asks which account only when you have more than one.
- **label a project**: your own name for it, such as the domain it serves (`thoub.app`). Shown in the list and when publishing; it changes nothing on Vercel or Firebase.
- **accounts**: add or remove Vercel accounts (browser sign-in or a pasted token, then the team scope) and Firebase accounts (Google sign-in in the browser). With no account yet, it starts by adding one.

### Several accounts

Vercel accounts each keep their own sign-in under `~/.config/ship-site/accounts/`. Firebase accounts are the Firebase CLI's own Google logins: **+ add a Firebase account** runs `firebase login:add`, and any account you are already signed in with shows up on its own. Every command names its account (`--account you@x.com` for Firebase), so account A can publish domain A and account B domain B without switching anything.

### 2. Folder

Inside a project, that folder is built. Outside one, the folder the project was last built from is used, or it asks once and remembers.

### 3. Where

**main website** (production) or **test version**. `--prod` and `--preview` skip the question.

| | Vercel | Firebase |
| --- | --- | --- |
| main website | `vercel deploy --prod` | `firebase deploy --only hosting` → `<site>.web.app` |
| test version | a fresh preview URL | the `preview` channel, a URL that lasts 7 days |

### 4. Version (main website only)

```
▸ Version  1.0.0
 ❯ publish as 1.0.0
   bump                next is 1.0.1, or type your own
```

Enter publishes as is. **bump** asks `New version [1.0.1] ›`: Enter takes it, or type any version like `1.1.0`. It updates `package.json` with `npm version <new> --no-git-tag-version`, so nothing is committed or tagged. If this version is already live, the header says **live already** and **bump** is preselected. Test versions never ask.

### 5. Build and publish

The exact commands are shown, then run: `npm run build` (or pnpm, yarn or bun from the lockfile), then the deploy from a temporary copy of the build output (the first of `dist/`, `build/`, `out/`, `_site/` that holds an `index.html`) outside your git repo. No source, `node_modules`, `.env` or git commit info leaves your Mac, so Vercel's commit-author check never blocks it. For Firebase the copy gets its own `firebase.json`, keeping your project's redirects, headers and rewrites; nothing is added to your repo. The copy is deleted afterwards. If the build or deploy fails, the host's error is shown and it stops.

### 6. Done

The link is printed and copied. For the main website it is the project's domain.

## Dry run

`ship-site --dry-run` (or `-n`) walks the whole flow, checks everything, and changes nothing.

| Step | In a dry run |
| --- | --- |
| project list, refresh | ✅ runs (read-only) |
| add or remove an account | ✅ runs |
| new Vercel project | ⏭ says it would create it |
| version | ⏭ shows the new version, does not touch `package.json` |
| build script in `package.json` | ✅ checked |
| package manager installed | ✅ checked |
| Vercel login and project access | ✅ checked (read-only) |
| Firebase CLI, signed-in account, site reachable | ✅ checked (read-only) |
| build | ⏭ shows the command |
| deploy | ⏭ shows the exact command |
| "last published" record | ⏭ not saved |

It ends with **dry run passed** or a list of ✗ problems to fix.

## Keys

`Enter`, `↑` `↓`, `Esc` back and `q` quit work everywhere; apps and projects get `1`–`9`. Each option's own key is shown as `[x]` next to it. Change any of them in `~/.config/developer-tools/keys.json` (see the [main README](../README.md#keys)).

| Key | Option | Action name for keys.json |
| --- | --- | --- |
| `n` | new project | `project.new` |
| `l` | label a project | `project.label` |
| `a` | accounts | `accounts` |
| `r` | refresh | `refresh` |
| `q` | quit | `quit` |
| `m` | main website | `site.main` |
| `t` | test version | `site.test` |
| `p` | publish as | `version.keep` |
| `b` | bump | `version.bump` |
| `v` | vercel project | `new.vercel` |
| `f` | firebase site | `new.firebase` |
| `c` | create a new firebase project | `new.firebase_project` |
| `f` | add a firebase account | `account.add_firebase` |
| `v` | add a vercel account | `account.add_vercel` |
| `b` | sign in with vercel in the browser | `signin.browser` |
| `t` | paste a token | `signin.token` |
| `v` | vercel | `host.vercel` |
| `f` | firebase | `host.firebase` |
| `t` | this folder | `folder.this` |
| `l` | the folder it was built from last time | `folder.last` |
| `d` | remove it | `account.remove` |
| `d` | sign it out | `account.signout` |
| `p` | personal | `scope.personal` |
| `Esc` | back | `back` |

## Needs

bash, python3 and node on macOS, Linux or Windows (Git Bash or WSL), plus the CLI for each host you use: Vercel (`npm i -g vercel`) or Firebase (`npm i -g firebase-tools`). Each is offered the first time it is needed, never installed silently.

## Where things live

| What | Where |
| --- | --- |
| Accounts, scopes, project list, labels, which project each folder uses, last published version | `~/.config/ship-site/config.json` (mode 0600) |
| Each Vercel account's sign-in | `~/.config/ship-site/accounts/<name>/` (mode 0700) |
| Firebase sign-ins | the Firebase CLI's own store (`firebase login:list`) |
| Your normal `vercel login` | untouched |

A `vercel.json` in your project root is uploaded with the build. Without one, a single-page-app rewrite is added so deep links work; Firebase gets the same rewrite unless your `firebase.json` has its own. The only file it changes in your project is `package.json`'s version, and only when you pick **bump**.

## Left out on purpose

Listing, deleting, pausing or rolling back deployments. The Vercel dashboard and `vercel ls`, `vercel rm`, `vercel rollback` already do that well.
