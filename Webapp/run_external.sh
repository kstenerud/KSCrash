#!/bin/sh

export FLASK_APP=listener.py
export FLASK_DEBUG=1

flask run --host=0.0.0.0
