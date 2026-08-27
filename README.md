# Deploy-nano

Ubuntu workstation setup — configures the shell environment, installs essential software, and builds the latest [nano][4] with [syntax highlighting][1].

## Quick Install

Run [start-aio-min.sh][11] to start the setup:

```sh
curl -fsSL https://raw.githubusercontent.com/woznet/deploy-nano/main/ubuntu/v4/start-aio-min.sh | bash
```

## What it does

- Configures `.bashrc`, `.bash_aliases`, `inputrc`, and `sudoers`
- Installs apt packages plus [PowerShell (pwsh)][6], [GitHub CLI (gh)][7], and 1Password + CLI
- Generates an SSH key, imports GitHub public keys, and hardens sshd (pubkey-only)
- Builds [nano][4] from source (latest release) and adds [nanorc syntax highlighting][1]
- Sets up bash completions
- Syncs the standalone helper scripts to `~/dev/scripts`

## Standalone scripts

[`ubuntu/config/scripts/`][12] holds standalone installers (`install-docker.sh`, `install-vscode.sh`, `install-node.sh`, `install-nvm.sh`, and more) that can each be run on their own — the main script also copies them all to `~/dev/scripts`.

## Sources

- nanorc syntax highlighting - <https://github.com/galenguyer/nano-syntax-highlighting>
- nano - <https://git.savannah.gnu.org/git/nano.git>
- nvm - <https://github.com/nvm-sh/nvm>

## Other helpful links

- BLFS page for nano - <https://www.linuxfromscratch.org/blfs/view/svn/postlfs/nano.html>
- MS Docs PowerShell Install - <https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu>
- gh - <https://github.com/cli/cli/blob/trunk/docs/install_linux.md>

[1]: https://github.com/galenguyer/nano-syntax-highlighting
[4]: https://www.nano-editor.org/
[6]: https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu
[7]: https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian-ubuntu-linux-raspberry-pi-os-apt
[11]: https://github.com/woznet/deploy-nano/blob/main/ubuntu/v4/start-aio-min.sh
[12]: https://github.com/woznet/deploy-nano/tree/main/ubuntu/config/scripts
