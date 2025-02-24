clear

#!/bin/bash
# Define color variables

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

# Array of color codes excluding black and white
TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)

# Pick random colors
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

# Function to prompt user to check their progress
function check_progress {
    while true; do
        echo
        echo -n "${BOLD}${GREEN}Have you created hello-cloudbuild & hello-cloudbuild-deploy ($REGION) with ^candidate$ triggers ? (Y/N): ${RESET}"
        read -r user_input
        if [[ "$user_input" == "Y" || "$user_input" == "y" ]]; then
            echo
            echo "${BOLD}${WHITE}Great! Proceeding to the next steps...${RESET}"
            echo
            break
        elif [[ "$user_input" == "N" || "$user_input" == "n" ]]; then
            echo
            echo "${BOLD}${RED}Please create hello-cloudbuild & hello-cloudbuild-deploy ($REGION) with ^candidate$ triggers and then press Y to continue.${RESET}"
        else
            echo
            echo "${BOLD}${BLUE}Invalid input. Please enter Y or N.${RESET}"
        fi
    done
}

#----------------------------------------------------start--------------------------------------------------#

echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}Starting Execution${RESET}"

# Step 1: Set environment variables
echo "${BOLD}${YELLOW}Setting up environment variables${RESET}"
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")
gcloud config set compute/region $REGION

# Step 2: Enable required services
echo "${BOLD}${CYAN}Enabling necessary Google Cloud services${RESET}"
gcloud services enable container.googleapis.com \
    cloudbuild.googleapis.com \
    secretmanager.googleapis.com \
    containeranalysis.googleapis.com

# Step 3: Create Artifact Registry repository
echo "${BOLD}${GREEN}Creating Artifact Registry repository${RESET}"
gcloud artifacts repositories create my-repository \
  --repository-format=docker \
  --location=$REGION

# Step 4: Create GKE cluster
echo "${BOLD}${MAGENTA}Creating GKE Cluster${RESET}"
gcloud container clusters create hello-cloudbuild --num-nodes 1 --region $REGION

# Step 5: Install GitHub CLI
echo "${BOLD}${CYAN}Installing GitHub CLI${RESET}"
curl -sS https://webi.sh/gh | sh

# Step 6: Authenticate GitHub
echo "${BOLD}${BLUE} Authenticating with GitHub${RESET}"
gh auth login 
gh api user -q ".login"
GITHUB_USERNAME=$(gh api user -q ".login")
git config --global user.name "${GITHUB_USERNAME}"
git config --global user.email "${USER_EMAIL}"
echo ${GITHUB_USERNAME}
echo ${USER_EMAIL}

# Step 7: Create GitHub Repositories
echo "${BOLD}${GREEN}Creating GitHub repositories${RESET}"
gh repo create  hello-cloudbuild-app --private 

gh repo create  hello-cloudbuild-env --private

# Step 8: Clone Google Storage files
echo "${BOLD}${MAGENTA}Cloning source files${RESET}"
cd ~
mkdir hello-cloudbuild-app

gcloud storage cp -r gs://spls/gsp1077/gke-gitops-tutorial-cloudbuild/* hello-cloudbuild-app

cd ~/hello-cloudbuild-app

# Step 9: Update region values in files
echo "${BOLD}${CYAN}Updating region values in configuration files${RESET}"
sed -i "s/us-central1/$REGION/g" cloudbuild.yaml
sed -i "s/us-central1/$REGION/g" cloudbuild-delivery.yaml
sed -i "s/us-central1/$REGION/g" cloudbuild-trigger-cd.yaml
sed -i "s/us-central1/$REGION/g" kubernetes.yaml.tpl

# Step 10: Initialize git repository
echo "${BOLD}${YELLOW}Initializing Git repository${RESET}"
git init
git config credential.helper gcloud.sh
git remote add google https://github.com/${GITHUB_USERNAME}/hello-cloudbuild-app
git branch -m master
git add . && git commit -m "initial commit"

# Step 11: Submit build to Cloud Build
echo "${BOLD}${BLUE}Submitting build to Cloud Build${RESET}"
COMMIT_ID="$(git rev-parse --short=7 HEAD)"

gcloud builds submit --tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/my-repository/hello-cloudbuild:${COMMIT_ID}" .

echo

echo "${BOLD}${GREEN}Click here to set up triggers: ${RESET}""https://console.cloud.google.com/cloud-build/triggers;region=global/add?project=$PROJECT_ID"

# Call function to check progress before proceeding
check_progress

# Step 12: Commit and push changes
echo "${BOLD}${MAGENTA}Pushing changes to GitHub${RESET}"
git add .

git commit -m "Type Any Commit Message here"

git push google master

cd ~

# Step 13: Create SSH Key for GitHub authentication
echo "${BOLD}${CYAN}Generating SSH key for GitHub${RESET}"
mkdir workingdir
cd workingdir

ssh-keygen -t rsa -b 4096 -N '' -f id_github -C "${USER_EMAIL}"

# Step 14: Store SSH key in Secret Manager
echo "${BOLD}${BLUE}Storing SSH key in Secret Manager${RESET}"
gcloud secrets create ssh_key_secret --replication-policy="automatic"

gcloud secrets versions add ssh_key_secret --data-file=id_github

# Step 15: Add SSH key to GitHub
echo "${BOLD}${WHITE}Adding SSH key to GitHub${RESET}"
GITHUB_TOKEN=$(gh auth token)

SSH_KEY_CONTENT=$(cat ~/workingdir/id_github.pub)

gh api --method POST -H "Accept: application/vnd.github.v3+json" \
  /repos/${GITHUB_USERNAME}/hello-cloudbuild-env/keys \
  -f title="SSH_KEY" \
  -f key="$SSH_KEY_CONTENT" \
  -F read_only=false

rm id_github*

# Step 16: Grant permissions
echo "${BOLD}${BLUE}Granting IAM permissions${RESET}"
gcloud projects add-iam-policy-binding ${PROJECT_NUMBER} \
--member=serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
--role=roles/secretmanager.secretAccessor

cd ~

gcloud projects add-iam-policy-binding ${PROJECT_NUMBER} \
--member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
--role=roles/container.developer

# Step 17: Clone environment repository
echo "${BOLD}${MAGENTA}Cloning environment repository${RESET}"
mkdir hello-cloudbuild-env
gcloud storage cp -r gs://spls/gsp1077/gke-gitops-tutorial-cloudbuild/* hello-cloudbuild-env

# Step 18: Modify files and push
echo "${BOLD}${CYAN}Modifying files and pushing to GitHub${RESET}"
cd hello-cloudbuild-env
sed -i "s/us-central1/$REGION/g" cloudbuild.yaml
sed -i "s/us-central1/$REGION/g" cloudbuild-delivery.yaml
sed -i "s/us-central1/$REGION/g" cloudbuild-trigger-cd.yaml
sed -i "s/us-central1/$REGION/g" kubernetes.yaml.tpl

ssh-keyscan -t rsa github.com > known_hosts.github
chmod +x known_hosts.github

git init
git config credential.helper gcloud.sh
git remote add google https://github.com/${GITHUB_USERNAME}/hello-cloudbuild-env
git branch -m master
git add . && git commit -m "initial commit"
git push google master

# Step 19: Checkout and modify deployment branch
echo "${BOLD}${GREEN}Configuring deployment pipeline${RESET}"
git checkout -b production

rm cloudbuild.yaml

curl -LO raw.githubusercontent.com/Titash-shil/Google-Kubernetes-Engine-Pipeline-using-Cloud-Build-GSP1077/refs/heads/main/Qwiklab_Explorers_Env-cloudbuild.yaml

mv Qwiklab_Explorers_Env-cloudbuild.yaml cloudbuild.yaml

sed -i "s/REGION-/$REGION/g" cloudbuild.yaml
sed -i "s/GITHUB-USERNAME/${GITHUB_USERNAME}/g" cloudbuild.yaml

git add .

git commit -m "Create cloudbuild.yaml for deployment"

git checkout -b candidate

git push google production

git push google candidate

# Step 20: Trigger CD pipeline
echo "${BOLD}${WHITE}Triggering the CD pipeline${RESET}"
cd ~/hello-cloudbuild-app
ssh-keyscan -t rsa github.com > known_hosts.github
chmod +x known_hosts.github

git add .
git commit -m "Adding known_host file."
git push google master

rm cloudbuild.yaml

curl -LO raw.githubusercontent.com/QUICK-GCP-LAB/2-Minutes-Labs-Solutions/refs/heads/main/Google%20Kubernetes%20Engine%20Pipeline%20using%20Cloud%20Build/APP-cloudbuild.yaml

mv APP-cloudbuild.yaml cloudbuild.yaml

sed -i "s/REGION/$REGION/g" cloudbuild.yaml
sed -i "s/GITHUB-USERNAME/${GITHUB_USERNAME}/g" cloudbuild.yaml

git add cloudbuild.yaml

git commit -m "Trigger CD pipeline"

git push google master

echo

# Function to display a random congratulatory message
function random_congrats() {
    MESSAGES=(
        "${GREEN}Congratulations For Completing The Lab! Keep up the great work!${RESET}"
        "${BLUE}Well done! Your hard work and effort have paid off!${RESET}"
        "${WHITE}Bravo! You’ve completed the lab with excellence!${RESET}"
        "${CYAN}Amazing work! You’re making impressive progress!${RESET}"
        "${RED}You’ve made remarkable progress! Congratulations again!!${RESET}"
    )

    RANDOM_INDEX=$((RANDOM % ${#MESSAGES[@]}))
    echo -e "${BOLD}${MESSAGES[$RANDOM_INDEX]}"
}

# Display a random congratulatory message
random_congrats

echo -e "\n"  # Adding one blank line

cd

remove_files() {
    # Loop through all files in the current directory
    for file in *; do
        # Check if the file name starts with "gsp", "arc", or "shell"
        if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* ]]; then
            # Check if it's a regular file (not a directory)
            if [[ -f "$file" ]]; then
                # Remove the file and echo the file name
                rm "$file"
                echo "File removed: $file"
            fi
        fi
    done
}

remove_files
