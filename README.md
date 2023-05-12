- [**magit-remote-link.el** &#x2014; Actions with remote git hub links.](#orgf7118ff)
- [Installation](#org20e9bb4)
  - [use-package](#orge033b4b)
- [Usage](#org221dcbf)
  - [Commands](#org29733e3)
  - [Bindings](#orgfc26e0c)
- [Future stuff aka TODO](#orgd59bcd1)
- [License](#orgdd8232a)


<a id="orgf7118ff"></a>

# **magit-remote-link.el** &#x2014; Actions with remote git hub links.

This package provides functions for copying and opening URLs to specific lines in a Git repository on various hosting services.


<a id="org20e9bb4"></a>

# Installation

This package requires `magit` and `project` and relies heavily on magit's ability to extract remote repository information from local Git repositories.


<a id="orge033b4b"></a>

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


<a id="org221dcbf"></a>

# Usage


<a id="org29733e3"></a>

## Commands

Once installed, you can use the following interactive commands (`M-x`):

-   `magit-remote-link-copy-at-point`: Copy the URL of the remote repository and the line at the point or in the active region to the clipboard.
-   `magit-remote-link-browse-at-point`: Open the URL of the remote repository and the line at the point or in the active region in a browser.

To use these functions, navigate to a file in a Git repository in magit and place the cursor on a line or select a region to specify the line number or range. Then use the key binding you configured or run the function directly to copy or open the URL. The URL will be copied or opened with the line number specified in the URL.


<a id="orgfc26e0c"></a>

## Bindings

I have [my magit stuff](https://github.com/pkulev/.emacs.d#git-things) binded on the `C-C m` prefix, and for these commands my mnemonics are: Copy a URL pointing to a line or a region in a file to the clipboard is more like `kill-ring-save` (`M-w`) function, so `C-c m w` makes sense for me. Opening the same URL in Web browser is `C-c m W` because of W in the "Web", huh. Obviously `m` stands for `magit`.


<a id="orgd59bcd1"></a>

# Future stuff aka TODO

-   [ ] Unit tests! I can check all of this by hands.
-   [ ] Other Git repository providers support. For now the URLs are generated only in compliance with Github scheme.
-   [ ] Copy link to a repository remote (not a particular file).
-   [ ] Build correct links for lightweight markups like .md, .rst and so on.
-   [ ] Browse a repository remote (maybe `forge.el` can do this already?).
-   [ ] Run unit tests via GHA.


<a id="orgdd8232a"></a>

# License

This package is distributed under the GNU General Public License, version 3 or later. See the file LICENSE for details.