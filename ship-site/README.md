# ship-site

Build a web app, publish only its build folder to **Vercel** or **Firebase Hosting**, copy the link. Works with Vite (React, Vue, Svelte…), Create React App, Next.js static export, Eleventy, Jekyll: anything whose build script leaves an `index.html` in `dist/`, `build/`, `out/` or `_site/`. Plain static sites too: no build, the folder holding `index.html` goes up as it is. Several accounts on each, side by side, with no long commands to remember.

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
   you are in ~/Desktop/mine/SukunGardenAdmin
   Mohsin Dev · Vercel
 ❯ [1]  rig-register-web     rig-register-web.vercel.app   12× · 3d ago
   [2]  studiodesk           studiodesk.com                 2× · 2mo ago
        + new project here
   mohsin@… · Firebase
        Sukun Garden  sukun-garden · 2 sites
   [3]    admin              admin.sukungarden.com          5× · today   ● this folder
   [4]    landing            sukun-garden.web.app           1× · 1w ago
   [5]  advisor-app-a63c2    advisor-app-a63c2.web.app
        + new project here

   [n]  + new project
   [l]  label a project
   [d]  custom domain
   [a]  accounts
   [r]  refresh
   [q]  quit
```

Every Vercel project and Firebase site across all your accounts, grouped by account. A Firebase project with several sites shows them under its own line. Each row shows the address it serves (your own domain once it is connected, else the host's), how many times you published it from this Mac and when last. The list opens from a local cache at once and is refreshed when it is older than 10 minutes, or with **refresh**. Each Firebase project shows its default hosting site; extra sites appear once you create them through **+ new project**. Projects you have built from this Mac come first. Inside a project folder, the one it publishes to is preselected; a folder set up with the Firebase CLI before gets its `.firebaserc` project preselected the first time, and a site named like the folder (`SukunGardenWeb` → `sukun-garden`) is preselected too, no searching. Expired Vercel sign-ins are renewed on their own.

For Firebase, nothing has to be set up in your repo: no `firebase init`, no `firebase.json`. Sign in once, pick or create a project, publish.

- **+ new project**: a Vercel project, or a Firebase site — inside one of your existing Firebase projects (`<name>.web.app`), or in a brand-new Firebase project made from just a name (free plan, Hosting only, no billing). The name you type is cleaned to what the host allows (`Admin.Sukun Garden` → `admin-sukun-garden`) and shown back as **create admin-sukun-garden.web.app** before anything is made; **change the name** asks again. With no account on that host yet, it signs you in first. It asks which account only when you have more than one. One Firebase project can hold several sites on the free plan: a landing page on `sukun-garden.web.app` and the admin on `sukun-garden-admin.web.app`, say.
- **label a project**: your own name for it: `admin`, `landing`, the domain it serves. Shown in the list and when publishing; it changes nothing on Vercel or Firebase. It is never asked in the flow: set it from the list, or after publishing on the done screen, where one is suggested from the folder name (`SukunGardenAdmin` → `admin`).
- **custom domain**: your own domain or subdomain (`example.com`, `admin.example.com`, with its ending) for a project, saved at once as a reminder and shown on its row. On Firebase you can also **connect it now**: it prints the DNS records the way a registrar wants them (host `admin`, or `@` for the domain itself) and copies them. After every publish one line says where it stands (`live`, or `waiting for DNS` with what Firebase has not seen yet), and the done screen gets **check the domain again** until it is live; the full table comes back from **custom domain › connect it now** any time; the row says **DNS pending** until Firebase sees the records, then shows the domain in place of `<site>.web.app` and the published link uses it. The `.web.app` address keeps working either way. Or **just keep it as a reminder** and connect it another time. Vercel domains are added on vercel.com, which shows its records there; the reminder is kept here all the same.
- **accounts**: add or remove Vercel accounts (browser sign-in or a pasted token, then the team scope) and Firebase accounts (Google sign-in in the browser). With no account yet, it starts by adding one.

### Several accounts

Vercel accounts each keep their own sign-in under `~/.config/ship-site/accounts/`. Firebase accounts are the Firebase CLI's own Google logins: **+ add a Firebase account** runs `firebase login:add`, and any account you are already signed in with shows up on its own. Every command names its account (`--account you@x.com` for Firebase), so account A can publish domain A and account B domain B without switching anything.

### 2. Folder

Inside a project, that folder is built, no question asked. Outside one, the folder the project was last built from is used, or it asks once and remembers.

### 3. Where

```
▸ sukun-garden
   host        Firebase  mohsin@…
   project     sukun-garden
   folder      /Users/azharali/Desktop/mine/SukunGardenWeb
   domain      admin.sukungarden.com  DNS pending  also sukun-garden.web.app, which stays as is
 ❯ [m]  main website    updates sukun-garden.web.app and admin.sukungarden.com once live
   [t]  test version    a preview URL for 7 days, the main website untouched
   [s]  new site here   another <name>.web.app in sukun-garden; this folder publishes there instead
   [d]  custom domain   admin.sukungarden.com, saved as a reminder; connect it now or later
        ← back          another project or site
```

**main website** (production) or **test version**. `--prod` and `--preview` skip the question. **new site here** (Firebase) makes one more `<name>.web.app` site in the same project, suggested from the folder name (`SukunGardenAdmin` → `admin-sukun-garden`), confirmed before it is created; this folder then publishes there. **custom domain** saves your domain for this project right here (see [Projects](#1-projects)); the screen redraws with it.

If another folder already publishes to this project, you are told which one and asked `y` before anything is built; any other key goes back to the list with nothing changed. A folder moving to a different project is not asked: that is the normal way to give the admin its own site.

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

The exact commands are shown, then run: `npm run build` (or pnpm, yarn or bun from the lockfile), then the deploy from a temporary copy of the build output (the first of `dist/`, `build/`, `out/`, `_site/` that holds an `index.html`) outside your git repo.

**Static sites** have no build step. With no `build` script in `package.json` (or no `package.json` at all), the folder holding `index.html` is the site: the project folder itself, or `site/`, `public/`, `www/`, `docs/`, `static/`, in that order. It goes up whole, with `.well-known/`, `og-image.png`, `robots.txt`, `llms.txt`, fonts and `privacy/index.html` all at the root, minus `.git`, `node_modules`, `.idea`, `.env*` and `.DS_Store`. Real pages are served as such: `/privacy` opens `privacy/index.html`, and there is no single-page rewrite. The Publishing step says so:

```
▸ Files
   folder      /Users/azharali/Desktop/mine/SukunGardenWeb/site  no build — published as they are, 47 files
``` No source, `node_modules`, `.env` or git commit info leaves your Mac, so Vercel's commit-author check never blocks it. For Firebase the copy gets its own `firebase.json`, keeping your project's redirects, headers and rewrites; nothing is added to your repo. The copy is deleted afterwards. If the build or deploy fails, the host's error is shown and it stops.

### 6. Done

```
▸ Published
   link        https://admin.sukungarden.com  copied
   also        https://sukun-garden-admin.web.app  stays as is
   console     https://console.firebase.google.com/project/sukun-garden/hosting/sites/sukun-garden-admin
 ❯ [o]  open the link in the browser
   [l]  label this project       none yet — admin, landing, the domain it serves
   [d]  custom domain            admin.sukungarden.com
   [p]  back to projects
   [q]  quit
```

The link is printed and copied; for the main website it is your own domain once one is connected, with the host's address shown too, since it keeps working. Everything you may want to keep is here: label it, connect a domain, open it, or go back and publish another.

## Dry run

`ship-site --dry-run` (or `-n`) walks the whole flow, checks everything, and changes nothing.

| Step | In a dry run |
| --- | --- |
| project list, refresh | ✅ runs (read-only) |
| new project or site name | ✅ asked and shown back; ⏭ not created |
| custom domain | ⏭ says what it would connect |
| add or remove an account | ✅ runs |
| new Vercel project | ⏭ says it would create it |
| version | ⏭ shows the new version, does not touch `package.json` |
| build script in `package.json`, or the static folder and its file count | ✅ checked |
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
| `d` | custom domain | `project.domain` |
| `s` | new site here (Firebase, on Publish to) | `site.new` |
| `c` | connect it now (a Firebase custom domain) | `domain.connect` |
| `r` | just keep it as a reminder | `domain.remember` |
| `o` | open the link in the browser (after publishing) | `done.link` |
| `c` | check the domain again (after publishing, while pending) | `domain.check` |
| `l` | label this project (after publishing) | `done.label` |
| `p` | back to projects (after publishing) | `projects` |
| `Esc` | back, on Publish to: another project or site | `back` |
| `c` | create (a new project or site, after its name is shown) | `new.create` |
| `e` | change the name | `new.rename` |
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
| `d` | remove it | `account.remove` |
| `d` | sign it out | `account.signout` |
| `p` | personal | `scope.personal` |
| `Esc` | back | `back` |

## Needs

bash, python3 and node on macOS, Linux or Windows (Git Bash or WSL), plus the CLI for each host you use: Vercel (`npm i -g vercel`) or Firebase (`npm i -g firebase-tools`). Each is offered the first time it is needed, never installed silently.

## Where things live

| What | Where |
| --- | --- |
| Accounts, scopes, project list, labels, which project each folder uses, publish counts and dates, last published version | `~/.config/ship-site/config.json` (mode 0600) |
| Each Vercel account's sign-in | `~/.config/ship-site/accounts/<name>/` (mode 0700) |
| Firebase sign-ins | the Firebase CLI's own store (`firebase login:list`) |
| Your normal `vercel login` | untouched |

A `vercel.json` in your project root is uploaded with the build. Without one, an app gets a single-page rewrite so deep links work, and a static site gets `cleanUrls` instead; Firebase gets the same unless your `firebase.json` has its own. The only file it changes in your project is `package.json`'s version, and only when you pick **bump**.

## Left out on purpose

Listing, deleting, pausing or rolling back deployments. The Vercel dashboard and `vercel ls`, `vercel rm`, `vercel rollback` already do that well.
