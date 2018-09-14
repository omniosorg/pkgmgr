<img src="http://www.omniosce.org/OmniOSce_logo.svg" height="128">

pkgmgr
=========

[![Build Status](https://travis-ci.org/omniosorg/pkgmgr.svg?branch=master)](https://travis-ci.org/omniosorg/pkgmgr)

Version: 0.2.7

Date: 2018-09-14

pkgmgr is an IPS package management and publishing tool.

Setup
-----

To build `pkgmgr` you require perl and gcc packages on your
system.

Get a copy of `pkgmgr` from https://github.com/omniosorg/pkgmgr/releases
and unpack it into your scratch directory and cd there.

    ./configure --prefix=$HOME/opt/pkgmgr
    make

Configure will check if all requirements are met and give
hints on how to fix the situation if something is missing.

Any missing perl modules will be built and installed into the prefix
directory. Your system perl will NOT be affected by this.

To install the application, just run

    make install

Configuration
-------------

Take a look at the `pkgmgr.conf.dist` file for inspiration.
