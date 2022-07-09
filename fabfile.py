from __future__ import with_statement
from fabric.api import env, local, settings, abort, run, cd, sudo
from fabric.contrib.console import confirm
import os
from dotenv import load_dotenv

load_dotenv()

def dev():
    env.user = os.getenv("DEV_SERVER_USER")
    env.hosts = [ os.getenv("DEV_SERVRER_HOST") ]
    global code_dir
    code_dir = os.getenv("DEV_CODE_DIR")
    with cd(code_dir):
        run('git checkout main')
        run('git reset --hard HEAD')
        run('git pull')
        run('docker-compose build')
        run('docker-compose down')
        run('docker-compose up -d')

def deploy():
    with cd(code_dir):
        # reset any local changes & grab the latest version
        run('git checkout main')
        run('git reset --hard HEAD')
        run('git pull')
        run('docker-compose build')
        run('docker-compose down')
        run('docker-compose up -d')
        # run('docker-compose scale app=8 worker=1')
