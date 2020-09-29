PACTICIPANT := "pactflow-example-provider"
GITHUB_REPO := "pactflow/example-provider"
PACT_CHANGED_WEBHOOK_UUID := "c76b601e-d66a-4eb1-88a4-6ebc50c0df8b"
PACT_CLI="docker run --rm -v ${PWD}:${PWD} -e PACT_BROKER_BASE_URL -e PACT_BROKER_TOKEN pactfoundation/pact-cli:latest"

# Only deploy from master
ifeq ($(TRAVIS_BRANCH),master)
	DEPLOY_TARGET=deploy
else
	DEPLOY_TARGET=no_deploy
endif

all: test

## ====================
## CI tasks
## ====================

ci: test can_i_deploy $(DEPLOY_TARGET)

# Run the ci target from a developer machine with the environment variables
# set as if it was on Github Actions.
# Use this for quick feedback when playing around with your workflows.
fake_ci: .env
	CI=true \
	TRAVIS_COMMIT=`git rev-parse --short HEAD`+`date +%s` \
	TRAVIS_BRANCH=`git rev-parse --abbrev-ref HEAD` \
	PACT_BROKER_PUBLISH_VERIFICATION_RESULTS=true \
	make ci

ci_webhook: .env
	npm run test:pact

fake_ci_webhook:
	CI=true \
	TRAVIS_COMMIT=`git rev-parse --short HEAD`+`date +%s` \
	TRAVIS_BRANCH=`git rev-parse --abbrev-ref HEAD` \
	PACT_BROKER_PUBLISH_VERIFICATION_RESULTS=true \
	make ci_webhook

## =====================
## Build/test tasks
## =====================

test: .env
	npm run test

## =====================
## Deploy tasks
## =====================

deploy: deploy_app tag_as_prod

no_deploy:
	@echo "Not deploying as not on master branch"

can_i_deploy: .env
	"${PACT_CLI}" broker can-i-deploy --pacticipant ${PACTICIPANT} --version ${TRAVIS_COMMIT} --to prod

deploy_app:
	@echo "Deploying to prod"

tag_as_prod:
	"${PACT_CLI}" broker create-version-tag \
	  --pacticipant ${PACTICIPANT} \
	  --version ${TRAVIS_COMMIT} \
	  --tag prod

## =====================
## Pactflow set up tasks
## =====================

# export the GITHUB_TOKEN environment variable before running this
create_github_token_secret:
	curl -v -X POST ${PACT_BROKER_BASE_URL}/secrets \
	-H "Authorization: Bearer ${PACT_BROKER_TOKEN}" \
	-H "Content-Type: application/json" \
	-H "Accept: application/hal+json" \
	-d  "{\"name\":\"githubToken\",\"description\":\"Github token\",\"value\":\"${GITHUB_TOKEN}\"}"

# NOTE: the github token secret must be created (either through the UI or using the
# `create_travis_token_secret` target) before the webhook is invoked.
create_or_update_pact_changed_webhook:
	"${PACT_CLI}" \
	  broker create-or-update-webhook \
	  "https://api.github.com/repos/${GITHUB_REPO}/dispatches" \
	  --header 'Content-Type: application/json' 'Accept: application/vnd.github.everest-preview+json' 'Authorization: Bearer $${user.githubToken}' \
	  --request POST \
	  --data '{ "event_type": "pact_changed", "client_payload": { "pact_url": "$${pactbroker.pactUrl}" } }' \
	  --uuid ${PACT_CHANGED_WEBHOOK_UUID} \
	  --consumer ${PACTICIPANT} \
	  --contract-content-changed \
	  --description "Pact content changed for ${PACTICIPANT}"

test_pact_changed_webhook:
	@curl -v -X POST ${PACT_BROKER_BASE_URL}/webhooks/${PACT_CHANGED_WEBHOOK_UUID}/execute -H "Authorization: Bearer ${PACT_BROKER_TOKEN}"


## ======================
## Travis CI set up tasks
## ======================

travis_login:
	@docker run --rm -v ${HOME}/.travis:/root/.travis -it lirantal/travis-cli login --pro

# Requires PACT_BROKER_TOKEN to be set
travis_encrypt_pact_broker_token:
	@docker run --rm -v ${HOME}/.travis:/root/.travis -v ${PWD}:${PWD} --workdir ${PWD} lirantal/travis-cli encrypt --pro PACT_BROKER_TOKEN="${PACT_BROKER_TOKEN}"


## ======================
## Misc
## ======================

.env:
	touch .env
