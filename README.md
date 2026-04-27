# Egzakta Task

To create the GitLab environment:

```bash
./create_gitlab.sh
```

To clean up the environment for GitLab deployment:

```bash
./clean_up.sh
```

The output will show the default root and user passwords, as well as the
hostname.

The Ansible host values must be defined in `ansible/host_vars/us2604.yml`. Then
Ansible can be run with:

```bash
ansible-playbook site.yml
```
