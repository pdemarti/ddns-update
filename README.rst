======
ddns-update
======
Update a dynamic DNS IP Address record from a linux host.

The current version is specific to:
  - `DuckDNS <https://www.duckdns.org/>`_
  - Neatgear Nighthawk R7000 router

However it should be straightforward to adapt for any router (as long
as you can find a static status page showing the current WAN address),
and with some modification in the code, to any dynamic DNS service.


Installation
-------

.. code:: bash

    # 1. clone
    git clone git@github.com:pdemarti/ddns-update.git

    # 2. create default files
    cd ddns-update
    ./ddns-update.pl

    # 3. edit .config and .curl-pass

    # 4. run and check the output
    ./ddns-update.pl -v

    # 5. add to your crontab
    crontab -e

    # note: an example crontab entry is (adapt ad lib):
    # Update DuckDNS record
    # */10 * * * * (cd ~/contrib/ddns-update; ./ddns-update.pl >> ddns.log 2>&1)

Notes:
  - in ``.config``, typically the only values to change are your domain
    name (the one you registered on DuckDNS) and your token (provided
    by DuckDNS).
  - in ``.curl-pass``, update the ROUTER-ADDRESS, the router admin's
    USERNAME and PASSWORD.
