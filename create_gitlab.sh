#!/bin/bash
#
# Host a GitLab instance locally:
# - host it with Docker
# - set some default settings
# - create a non-root user
# - create a repository for the non-root user
# - clone the repository locally
# note that ${gitlab_password} is set in .envrc

# quit on error
set -euo pipefail

# start the containers
docker compose -f ./gitlab-compose.yml up -d

# wait for gitlab to come up
while [ "$(docker inspect -f '{{.State.Health.Status}}' gitlab)" != "healthy" ]; do
  echo "> GitLab still initializing, waiting 30 seconds..."
  sleep 30
done
echo "> GitLab healthy"

# variables
gitlab_domain="gitlab.hometask.xyz"
gitlab_username="me"
gitlab_name="me"
gitlab_email="me@example.com"
# ${gitlab_password} is set in .envrc

if ! grep -q "127.0.0.1 gitlab.hometask.xyz" /etc/hosts; then
  echo -e "\n127.0.0.1 gitlab.hometask.xyz" | sudo tee -a /etc/hosts > /dev/null
  echo "> /etc/hosts entry added"
else
  echo "> /etc/hosts entry exists"
fi

# generate root access token, assign it to 'gitlab_private_token':
# - https://docs.gitlab.com/user/profile/personal_access_tokens/#create-a-personal-access-token-programmatically
# it is later revoked
gitlab_private_token=$(docker exec -i gitlab \
  gitlab-rails runner "
    script_token = User.find_by_username('root').personal_access_tokens.create(
      name: 'root_automation_token', 
      scopes: [:api],
      expires_at: 1.days.from_now
    ); 
    puts script_token.token " \
    | tail -1)
echo "> Private access token generated"

# set default settings
# - disable sign up
# - disable vscode setting gitlab recommends to disable
curl -fsS -X PUT \
  --url "http://${gitlab_domain}/api/v4/application/settings" \
  -H "PRIVATE-TOKEN: ${gitlab_private_token}" \
  -d "vscode_extension_marketplace_single_origin_fallback_enabled=false" \
  -d "signup_enabled=false" > /dev/null
echo "> Default settings changed"

# add non-root user
curl -fsS -X POST \
  --url "http://${gitlab_domain}/api/v4/users" \
  -H "PRIVATE-TOKEN: ${gitlab_private_token}" \
  -d "username=${gitlab_username}" \
  -d "name=${gitlab_name}" \
  -d "email=${gitlab_email}" \
  -d "password=${gitlab_password}" \
  -d "skip_confirmation=true" > /dev/null
echo "> Non-root user added"

# generate ssh key, force overwrite
if [[ ! -f "${HOME}/.ssh/glab-task" ]]; then
  ssh-keygen -t ed25519 -f "${HOME}/.ssh/glab-task" -N "" -C "${USER}" > /dev/null
  chown "${USER}:${USER}" "${HOME}/.ssh/glab-task"*
  echo "> SSH key generated"
else
  echo "> SSH key exists"
fi

# get UID
gitlab_uid=$(curl -fsS -X GET \
  --url "http://${gitlab_domain}/api/v4/users?username=${gitlab_username}" \
  -H "PRIVATE-TOKEN: ${gitlab_private_token}" \
  | jq '.[0].id')

# add SSH key to user
curl -fsS -X POST \
  --url "http://${gitlab_domain}/api/v4/users/${gitlab_uid}/keys" \
  -H "PRIVATE-TOKEN: ${gitlab_private_token}" \
  -d "title=automation" \
  -d "expires_at=$(date -d "+1 year" +%F)" \
  --data-urlencode "key=$(cat ${HOME}/.ssh/glab-task.pub)"  > /dev/null
  # encoding issues w/o --data-urlencode
echo "> SSH key added to the non-root user"

# add repo
curl -fsS -X POST \
  --url "http://${gitlab_domain}/api/v4/projects/user/${gitlab_uid}" \
  -H "PRIVATE-TOKEN: ${gitlab_private_token}" \
  -d "name=hometask" \
  -d "visibility=private" > /dev/null
echo "> GitLab repository created"

# add runner
runner_token="$(curl -fsS -X POST \
  --url "${gitlab_domain}/api/v4/user/runners" \
  -H "PRIVATE-TOKEN: ${gitlab_private_token}" \
  -d "runner_type=instance_type" \
  -d "tag_list=deploy" \
  | jq -r '.token')"
sed -i "s|token: '.*'|token: '${runner_token}'|" \
  ./ansible/roles/gitlab_runner/vars/main.yml
echo "> GitLab runner created"

# revoke the token
docker exec -i gitlab gitlab-rails runner \
  "PersonalAccessToken.find_by_name('root_automation_token').revoke!"
echo "> Token revoked"

# add ssh config entry, disable fingerprinting (it's totally local anyway)
if ! grep -q "Host ${gitlab_domain}" "${HOME}/.ssh/config"; then
  cat << EOF >> "${HOME}/.ssh/config"

Host ${gitlab_domain}
  Hostname ${gitlab_domain}
  Port 2222
  User git
  StrictHostKeyChecking no
  IdentityFile ~/.ssh/glab-task
EOF
  echo "> SSH config entry added"
else
  echo "> SSH config entry exists"
fi

# clone the repo
git clone "git@${gitlab_domain}:${gitlab_username}/hometask.git" > /dev/null
echo "> GitLab repo cloned locally"

# open gitlab in firefox
echo ">>> All done! Test by opening: http://${gitlab_domain}"
# print root password
docker exec -i gitlab grep 'Password:' /etc/gitlab/initial_root_password
echo "User Password: ${gitlab_password}"
