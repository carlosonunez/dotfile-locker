# dotfile-locker

A tool that makes it easy to track sensitive Bash/`zsh`/`fish`/etc. dotfiles in
a Git repository.

## Use cases

### Starting a new job

Let's say that you are configuring a laptop that was given to you by your new
job (congrats!).

You have a `.bash_profile` and other dot-files that you've
collected over the years in cloud storage or Google Drive
that you `ln -s` into your `$HOME` directory, but you don't like the idea of
logging into a personal account on a work machine for privacy reasons.

`dotfile-locker` enables you to encrypt those dotfiles in a Git repository and
restore them with one command:

```sh
./locker.sh --encrypt dotfiles --email [your-email]
```

### Juggling multiple clients

You're a consultant or someone that works with a lot of different companies. You
have multiple dotfiles or configs on your machine for each of these companies,
but you want to back them up somewhere safely with Git in case your computer
gets hosed.

`dotfile-locker` easily makes this possible:

```sh
./locker.sh --encrypt company-a --email [company-a-email]
./locker.sh --encrypt company-b --email [company-b-email]
```

## How to use

### Setting up

Install GPG, if you don't already have it:

```sh
brew install gnupg # Mac
choco install gnupg # Windows
apt -y install gnupg2 # Ubuntu/Debian
dnf install gnupg2 # Fedora/RHEL/Rocky
yum -y install gnupg2 # SuSE
```

Create a GPG key, if you don't already have one:

```sh
gpg --genereate-key # ...then follow the instructions
```

### Tracking your dotfiles

Create a Git repository for your dotfiles:

```sh
mkdir ~/src/dotfiles
git init
cd ~/src/dotfiles
git commit --allow-empty -m "Initial commit"
```

Add your dotfiles into it:

```sh
for file in .bash_profile .bash_dotfile \
    .bash_some_other_dotfile
do cp "$HOME/$file" "$HOME/src/dotfiles/my-dotfiles/$file"
done
```

### Encrypting

Finally, install `dotfile-locker` into the repo...

```sh
# Optional, but recommended: this .gitignore will prevent you from
# accidentally committing your dotfiles
curl -Lo .gitignore https://raw.githubusercontent.com/carlosonunez/dotfile-locker/refs/heads/main/.gitignore
curl -Lo locker.sh https://raw.githubusercontent.com/carlosonunez/dotfile-locker/refs/heads/main/locker.sh
chmod +x ./locker.sh
```

...and lock 'em up!

```sh
./locker.sh --encrypt my-dotfiles --email email@address
```

Commit and, if configured, push your changes as needed.

Run `./locker.sh --encrypt` every time your dotfiles change to keep the archive
in sync.

### Decrypting

When you're ready to decrypt your dotfiles, just do the opposite!

```sh
mkdir ~/src/dotfiles
cd ~/src/dotfiles
./locker.sh --decrypt my-dotfiles --email email@address
```

Your dotfiles will be in the `my-dotfiles` directory, and you can run
`./locker.sh --encrypt` to keep the archive in sync as described before.

## Ensure safety on every commit with `.githooks`

`dotfile-locker` comes with a few Git hooks to help you avoid accidentally
committing dotfiles into your Git history. To use them:

1. Download the `.githooks` directory in your dotfiles repository, and
2. Tell Git to use them: `git config core.hooksPath .githooks`

