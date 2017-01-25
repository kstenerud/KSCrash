Simple Backend
==============

A very basic Flask webapp for receiving a report from a KSCrash standard installation.

It will store each request in its on directory under the "posts" subdir.


Requirements
------------

- Python
- Flask (pip install flask)


Usage
-----

- run_internal.sh: Run in internal mode (only allow connections from the local machine)
- run_external.sh: Run in external mode (allow connections from anywhere)
- clean.sh: Delete all .pyc files and the posts directory.


### KSCrash Installation URL

The webapp listens on port 5000, and the post method resides at /crashreport

The URL you can use depends on your device and setup.

If you're using the simulator or Android emulator, you can connect to your local machine. The URLs are as follows:

- On iPhone Simulator, the URL is http://localhost:5000/crashreport
- On Android emulator, the URL is http://10.0.2.2:5000/crashreport

For all other setups, you must connect over a network in the usual way (e.g. example.com:5000/crashreport)
