# Shrikebyte Open Source HDL Library

This repository holds Shrikebyte's public, open source, VHDL library of
generic and reusable HDL building blocks.

## Getting Started

### Get the Source Code

This repository is hosted on [GitHub](https://github.com/shrikebyte/sblib)
and can be directly cloned using this command:

`git clone https://github.com/shrikebyte/sblib-open.git`

### Install Project Tools

- HDL Registers 8.0.0
- VHDL Style Guide 3.30.0
- VUnit 5.0.0.dev6
- GHDL latest

#### Install Python Tools

Assuming a relatively recent version of python3 and pip3 are already available
on the system, run the following command to install the python tools.
Optionally, you may want to use a python virtual environment.

`python -m pip install hdl_registers==8.0.0 vsg==3.30.0 vunit_hdl==5.0.0.dev6`

#### Install GHDL

GHDL is an open-source VHDL simulator.

The latest version can be compiled from source and manually installed by
cloning, building, and installing the open-source repo (recommended):

`git clone https://github.com/ghdl/ghdl.git`

Alternatively, if using a Debian-based distro, an older version of GHDL can be
installed with:

`apt install ghdl`

### Test

> [!WARNING]
> Development happens on the main branch. As a consequence, main is not guaranteed to be stable or to build properly every time, as it is always in a state of progress. Use tagged releases for the most stable experience.

Walk through the following steps to run the simulations.

1. Ensure the required build tools have been properly installed and made
   available on the system's command line.

   `make tool-check`

2. Run the simulations. By default, this will use all CPU cores to run multiple
   sims in parallel.

   `make sim`

## Release Process

This project uses Github actions to manage releases. Once a new version of the
code is ready to be deployed:

1. Run `make style-fix` from the repo's root to run the code style tool over
   the new code. This ensures style consistency across the codebase without
   the need for manual code reviews.
2. Update the version number at the top of the [Makefile](Makefile), following
   Semantic Versioning.
3. Update the [changelog](CHANGELOG.md) with a summary the changes for the
   release.
4. Add, commit, and push the changes using git.
5. Run the following command, which triggers a Github action to create a new git
   tag and Github release.

   `make release`

### Versioning

This project uses [Semantic Versioning](http://semver.org/).
For a list of available versions and the design change history see the
[changelog](CHANGELOG.md).

Semantic versioning shall be used with respect to the module's HDL interfaces.
A major changes breaks at least one module interface. A minor change can add
a new interface and/or feature to a module without breaking compatibility.
A patch change fixes a bug without breaking compatibility.
