#!/bin/bash
# Miniconda installation path
MINICONDA_PATH="$HOME/miniconda"
CONDA_EXECUTABLE="$MINICONDA_PATH/bin/conda"

# Check if the script is run as the root user
if [ "$(id -u)" != "0" ]; then
    echo "This script needs to be run as the root user."
    echo "Please try switching to the root user with 'sudo -i' and then re-run this script."
    exit 1
fi

# Ensure conda is properly initialized
ensure_conda_initialized() {
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    fi
    if [ -f "$CONDA_EXECUTABLE" ]; then
        eval "$("$CONDA_EXECUTABLE" shell.bash hook)"
    fi
}

# Check and install Conda
function install_conda() {
    if [ -f "$CONDA_EXECUTABLE" ]; then
        echo "Conda is already installed at $MINICONDA_PATH"
        ensure_conda_initialized
    else
        echo "Conda is not installed, proceeding with installation..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
        bash miniconda.sh -b -p $MINICONDA_PATH
        rm miniconda.sh
        
        # Initialize conda
        "$CONDA_EXECUTABLE" init
        ensure_conda_initialized
        
        echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.bashrc
        source ~/.bashrc
    fi
    
    # Verify if conda is available
    if command -v conda &> /dev/null; then
        echo "Conda installation successful, version: $(conda --version)"
    else
        echo "Conda may have been installed but is not available in the current session."
        echo "Please re-login or run 'source ~/.bashrc' to activate Conda."
    fi
}

# Check and install Node.js and npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js is already installed, version: $(node -v)"
    else
        echo "Node.js is not installed, proceeding with installation..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    if command -v npm > /dev/null 2>&1; then
        echo "npm is already installed, version: $(npm -v)"
    else
        echo "npm is not installed, proceeding with installation..."
        sudo apt-get install -y npm
    fi
}

# Check and install PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 is already installed, version: $(pm2 -v)"
    else
        echo "PM2 is not installed, proceeding with installation..."
        npm install pm2@latest -g
    fi
}

function install_node() {
    install_conda
    ensure_conda_initialized
    install_nodejs_and_npm
    install_pm2
    apt update && apt upgrade -y
    apt install curl sudo git python3-venv iptables build-essential wget jq make gcc nano npm -y
    read -p "Enter Hugging Face API Token: " HF_TOKEN
    read -p "Enter Flock API Key: " FLOCK_API_KEY
    read -p "Enter Task ID: " TASK_ID
    # Clone repository
    git clone https://github.com/FLock-io/llm-loss-validator.git
    # Enter project directory
    cd llm-loss-validator
    # Create and activate conda environment
    conda create -n llm-loss-validator python==3.10 -y
    source "$MINICONDA_PATH/bin/activate" llm-loss-validator
    # Install dependencies
    pip install -r requirements.txt
    # Get current directory's absolute path
    SCRIPT_DIR="$(pwd)"
    # Create startup script
    cat << EOF > run_validator.sh
#!/bin/bash
source "$MINICONDA_PATH/bin/activate" llm-loss-validator
cd $SCRIPT_DIR/src
CUDA_VISIBLE_DEVICES=0 \
bash start.sh \
--hf_token "$HF_TOKEN" \
--flock_api_key "$FLOCK_API_KEY" \
--task_id "$TASK_ID" \
--validation_args_file validation_config.json.example \
--auto_clean_cache True
EOF
    chmod +x run_validator.sh
    pm2 start run_validator.sh --name "llm-loss-validator" -- start && pm2 save && pm2 startup
    echo "Validator node has started."
}

function check_node() {
    pm2 logs llm-loss-validator
}

function uninstall_node() {
    pm2 delete llm-loss-validator && rm -rf llm-loss-validator
}

function install_train_node() {
    install_conda
    ensure_conda_initialized
    install_nodejs_and_npm
    install_pm2
    
    # Install necessary tools
    apt update && apt upgrade -y
    apt install curl sudo python3-venv iptables build-essential wget jq make gcc nano git -y
    
    # Clone QuickStart repository
    git clone https://github.com/FLock-io/testnet-training-node-quickstart.git
    cd testnet-training-node-quickstart
    
    # Create and activate conda environment
    conda create -n training-node python==3.10 -y
    source "$MINICONDA_PATH/bin/activate" training-node
    
    # Install dependencies
    pip install -r requirements.txt
    
    # Obtain necessary information
    read -p "Enter Task ID (TASK_ID): " TASK_ID
    read -p "Enter Flock API Key: " FLOCK_API_KEY
    read -p "Enter Hugging Face Token: " HF_TOKEN
    read -p "Enter Hugging Face Username: " HF_USERNAME
    
    # Create run script
    cat << EOF > run_training_node.sh
#!/bin/bash
source "$MINICONDA_PATH/bin/activate" training-node
TASK_ID=$TASK_ID FLOCK_API_KEY="$FLOCK_API_KEY" HF_TOKEN="$HF_TOKEN" CUDA_VISIBLE_DEVICES=0 HF_USERNAME="$HF_USERNAME" python full_automation.py
EOF
    
    chmod +x run_training_node.sh
    
    # Start training node with PM2
    pm2 start run_training_node.sh --name "flock-training-node" -- start && pm2 save && pm2 startup
    
    echo "Training node has started. You can view logs with 'pm2 logs flock-training-node'."
}

function update_task_id() {
    read -p "Enter new Task ID (TASK_ID): " NEW_TASK_ID
    
    # Update Task ID for validator node
    if [ -f "llm-loss-validator/run_validator.sh" ]; then
        sed -i "s/--task_id \".*\"/--task_id \"$NEW_TASK_ID\"/" llm-loss-validator/run_validator.sh
        pm2 restart llm-loss-validator
        echo "Validator node's Task ID has been updated and restarted."
    else
        echo "Validator node's run script not found."
    fi
    
    # Update Task ID for training node
    if [ -f "testnet-training-node-quickstart/run_training_node.sh" ]; then
        sed -i "s/TASK_ID=.*/TASK_ID=$NEW_TASK_ID/" testnet-training-node-quickstart/run_training_node.sh
        pm2 restart flock-training-node
        echo "Training node's Task ID has been updated and restarted."
    else
        echo "Training node's run script not found."
    fi
}

# Update node
function update_node() {
    # Update validator node
    if [ -d "llm-loss-validator" ]; then
        cd llm-loss-validator && git pull && pm2 restart llm-loss-validator
        echo "Validator node has been updated."
    else
        echo "Validator node directory not found."
    fi

    # Update training node
    if [ -d "testnet-training-node-quickstart" ]; then
        cd testnet-training-node-quickstart && git pull && pm2 restart flock-training-node
        echo "Training node has been updated."
    else
        echo "Training node directory not found."
    fi
}

# Main menu
function main_menu() {
    clear
    echo "Please choose an operation:"
    echo "1. Install Validator Node"
    echo "2. Install Training Node"
    echo "3. View Validator Node Logs"
    echo "4. View Training Node Logs"
    echo "5. Delete Validator Node"
    echo "6. Delete Training Node"
    echo "7. Update Task ID and Restart Node"
    echo "8. Update Node"
    read -p "Enter an option (1-8): " OPTION
    case $OPTION in
    1) install_node ;;
    2) install_train_node ;;
    3) check_node ;;
    4) pm2 logs flock-training-node ;;
    5) uninstall_node ;;
    6) pm2 delete flock-training-node && rm -rf testnet-training-node-quickstart ;;
    7) update_task_id ;;
    8) update_node ;;
    *) echo "Invalid option." ;;
    esac
}

# Display the main menu
main_menu
