# ship-site

Build a Vite site on your Mac, publish only the `dist/` folder to Vercel, copy the link.

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

## What happens

1. **Account**: pick a saved Vercel account or add one. Adding asks for a name, then how to sign in: the Vercel browser login, or a token pasted from vercel.com/account/tokens. If the account belongs to teams you pick which scope it deploys to.
2. **Project**: the projects in that account are listed. Pick one, or create one by typing a name. Nothing is created unless you ask.
3. **Where**: main website (production) or a test version (a fresh preview URL). Skip the question with `--prod` or `--preview`.
4. **Build**: the exact command is shown, then run. `npm run build`, or pnpm, yarn or bun if their lockfile is present.
5. **Publish**: the exact `vercel deploy` command is shown, then run from a temporary copy of `dist/` outside your git repo. No source, `node_modules`, `.env` or commit info leaves your Mac. The copy is deleted afterwards.
6. **Done**: the link is printed and copied. For the main website that is the project's domain.

The account and project are remembered per folder. Next time they show at the top with a "change account or project" option.

## Commands

```
ship-site             build this Vite project and publish dist/ to Vercel
ship-site --prod      straight to the main website, no question asked
ship-site --preview   a fresh preview URL
ship-site ~/site      a project folder other than the current one
ship-site accounts    add or remove Vercel accounts
ship-site --version
```

## Needs

macOS, python3 (built in), node and the Vercel CLI. Missing node or the CLI? It asks before installing either.

## Where things live

| What | Where |
| --- | --- |
| Accounts, scopes, which project each folder uses | `~/.config/ship-site/config.json` (mode 0600) |
| Each account's sign-in | `~/.config/ship-site/accounts/<name>/` (mode 0700): the CLI session for browser logins, a `token` file for pasted tokens |
| Your normal `vercel login` | untouched, ship-site never uses it |

A `vercel.json` in your project root is uploaded along with `dist/`. Without one, a single-page-app rewrite is added so deep links work.

## Left out on purpose

Listing, deleting, pausing or rolling back deployments. The Vercel dashboard and `vercel ls`, `vercel rm`, `vercel rollback` already do that well.
