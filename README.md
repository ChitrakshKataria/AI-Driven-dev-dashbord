# DevDash

DevDash opens a ready-to-use development workspace in tmux. Run it from a
project folder and it creates panes for Git, files, Codex, Claude Code, a spare
shell and your development server.

It works on macOS and Windows through WSL. Native Windows terminals are not
supported.

![DevDash running in a terminal](https://github.com/user-attachments/assets/7a05d17f-bc60-4484-bc68-b262dc3061f9)

## Install

Open Terminal on macOS, or your WSL terminal on Windows, then run:

```bash
git clone https://github.com/ChitrakshKataria/AI-Driven-vibecoding-dev-dashbord.git
cd AI-Driven-vibecoding-dev-dashbord
chmod +x install.sh
./install.sh
```

The installer adds Homebrew when it is missing, then installs Git, tmux,
lazygit, yazi, Codex CLI, Claude Code and the `devdash` command. It may ask for
your password while installing system packages. Restart the terminal when it
finishes so the updated PATH is loaded.

On Windows, keep the repository you want to work on inside the WSL filesystem,
such as `~/code/my-project`. File access is usually much faster there than under
`/mnt/c`.

You can check the installation at any time:

```bash
./install.sh --check
```

## Run

Go to a project and start DevDash:

```bash
cd ~/code/my-project
devdash
```

You can also pass the project folder directly:

```bash
devdash ~/code/my-project
```

DevDash starts the development command based on the lockfile it finds. It uses
`bun run dev`, `pnpm dev`, `yarn dev` or `npm run dev`. If there is no
`package.json`, that pane opens as a normal shell.

The first time Codex or Claude Code opens, follow its sign-in instructions. If
you do not use one of them, the rest of the dashboard still works.

Press `Ctrl+b`, then an arrow key to move between panes. Press `Ctrl+b`, then
`d` to leave the session running in the background.

## Change a pane command

Set an environment variable before starting DevDash. For example:

```bash
DEV_RUN="python3 -m http.server 8000" devdash .
```

Available overrides are `GIT_RUN`, `FILES_RUN`, `CODEX_RUN`, `CLAUDE_RUN`,
`SIDE_RUN` and `DEV_RUN`. Use `SESSION` to change the tmux session name. Run
`devdash --help` for the full list.

## Update or remove

To update, pull the latest changes and run the installer again:

```bash
git pull
./install.sh
```

To remove DevDash, delete the installed command:

```bash
rm "$HOME/.local/bin/devdash"
```

The other programs are normal Homebrew packages and are not removed
automatically.

## Test changes

The smoke test checks the shell syntax, tmux setup, installer flow and platform
detection without downloading packages:

```bash
./tests/smoke.sh
```

## License

DevDash is available under the MIT License.
