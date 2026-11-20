- [**magit-remote-link.el** &mdash; Actions with remote git hub links.](#org28a35ed)
- [Installation](#org55528f1)
  - [use-package](#org52f216c)
- [Usage](#org96edd82)
  - [Commands](#org335d068)
  - [Hosting providers](#orgc0c0613)
  - [Bindings](#org641a969)
  - [Tests](#org80877d3)
- [Future stuff aka TODO](#org3080837)
- [License](#org1a42d20)


<a id="org28a35ed"></a>

# **magit-remote-link.el** &mdash; Actions with remote git hub links.

This package provides functions for copying and opening URLs to specific lines in a Git repository on various hosting services.


<a id="org55528f1"></a>

# Installation

This package requires `magit` and relies heavily on magit's ability to extract remote repository information from local Git repositories.


<a id="org52f216c"></a>

## use-package

```elisp
(use-package magit-remote-link
  :ensure nil
  :quelpa
  (magit-remote-link :repo "pkulev/magit-remote-link.el"
                     :fetcher github :upgrade t)
  :commands (magit-remote-link-copy-at-point magit-remote-link-browse-at-point)
  :bind (("C-c m w" . magit-remote-link-copy-at-point)
         ("C-c m W" . magit-remote-link-browse-at-point)))
```


<a id="org96edd82"></a>

# Usage


<a id="org335d068"></a>

## Commands

Once installed, you can use the following interactive commands (`M-x`):

-   `magit-remote-link-copy-at-point`: Copy the URL of the remote repository and the line at the point or in the active region to the clipboard.
-   `magit-remote-link-browse-at-point`: Open the URL of the remote repository and the line at the point or in the active region in a browser.

Both commands prompt for the remote to link to.

To use these functions, navigate to a file in a Git repository in magit and place the cursor on a line or select a region to specify the line number or range. Then use the key binding you configured or run the function directly to copy or open the URL. The URL will be copied or opened with the line number specified in the URL.


<a id="orgc0c0613"></a>

## Hosting providers

The web layout of a repository can't be derived from its clone URL in general (for example, GNU Savannah clones from `git.savannah.nongnu.org/git/` but serves cgit from `cgit.git.savannah.nongnu.org/cgit/`), so remotes are matched against rules:

-   `magit-remote-link-hosts` maps a regexp on the remote's `HOST/PATH` to a provider and, optionally, a template for the web URL of the repository. Templates may use `%s` (scheme), `%h` (host), `%p` (path) and `\1` to `\9` (groups of the regexp). GitHub, GitLab, Bitbucket, Codeberg, SourceHut, NotABug and GNU Savannah (cgit) are built in; any other host is assumed to use the GitHub layout.
-   `magit-remote-link-git-hosting-providers` defines the URL layout of each provider: GitHub, GitLab, Bitbucket, Gitea, Codeberg, SourceHut, NotABug and cgit. cgit has no line ranges, so a region links to its first line.

For example, to link a self-hosted cgit:

```elisp
(add-to-list 'magit-remote-link-hosts
             '("\\`git\\.example\\.com/\\(.*\\)\\'" cgit "https://web.example.com/cgit/\\1"))
```

A single remote can also be configured without touching Emacs settings, using git config:

```sh
git config remote.savannah.magit-remote-link-provider cgit
git config remote.savannah.magit-remote-link-url https://cgit.git.savannah.nongnu.org/cgit/org-mode.git
```

Gitea has no built-in host rule, since its servers are self-hosted; select it with a `magit-remote-link-hosts` entry (``("\\`git\\.example\\.com/" gitea)``) or the `magit-remote-link-provider` git config key.

Remote URLs may be `https://`, `ssh://`, `git+ssh://` or scp-style (`user@host:path`).


<a id="org641a969"></a>

## Bindings

I have [my magit stuff](https://github.com/pkulev/.emacs.d#git-things) binded on the `C-C m` prefix, and for these commands my mnemonics are: Copy a URL pointing to a line or a region in a file to the clipboard is more like `kill-ring-save` (`M-w`) function, so `C-c m w` makes sense for me. Opening the same URL in Web browser is `C-c m W` because of W in the "Web", huh. Obviously `m` stands for `magit`.


<a id="org80877d3"></a>

## Tests

Tests use ERT and need `magit` on the load path:

```sh
emacs -Q --batch -L . -L /path/to/magit/deps -l test/magit-remote-link-test.el \
      -f ert-run-tests-batch-and-exit
```


<a id="org3080837"></a>

# Future stuff aka TODO

-   [X] Unit tests! I can check all of this by hands.
-   [X] Other Git repository providers support. For now the URLs are generated only in compliance with Github scheme.
-   [ ] Copy link to a repository remote (not a particular file).
-   [ ] Build correct links for lightweight markups like .md, .rst and so on.
-   [ ] Browse a repository remote (maybe `forge.el` can do this already?).
-   [ ] Run unit tests via GHA.


<a id="org1a42d20"></a>

# License

This package is distributed under the GNU General Public License, version 3 or later. See the file LICENSE for details.
