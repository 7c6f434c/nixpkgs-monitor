# nixpkgs-monitor

NixPkgs package status, freshness and security status monitor

## updatetool.rb

(re)generates package caches using --list-{arch,deb,nix,gentoo}

Checks updates for a single package or all packages.

Generates coverage reports:
* what packages don't seem to be covered by updaters
* what packages are covered by updaters and how many updaters cover each given package

Coverage report is an estimate. More precise report can only be obtained during update.

Reports look somewhat ugly.

## comparepackages.rb

Matches packages in one distro to packages in another one.
To be used for experimentation only.
Probably you don't care that it exists.

## Debian watchfiles tools

Scripts and a writeup of an experiment to see just how useful Debian watchfiles are.