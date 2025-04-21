#!/bin/bash
# Horde Model Loader with Tmux Wrapper
# -----------------------------------
# Selects a GGUF model, configures parameters, and runs it 
# in a tmux session for AI Horde integration

# Configuration - Edit these values
MODEL_DIR=""                # Directory containing your GGUF files
HORDE_KEY=""                # Your Horde API key
HORDE_WORKER_NAME=""        # Your Horde worker name
HORDE_DB=""                 # Path to db.json from AI-Horde-text-model-reference
KOBOLDCPP_PATH=""           # Path to koboldcpp.py

# Default values
DEFAULT_CONTEXT="8192"
DEFAULT_HORDE_CTX="4096"
DEFAULT_HORDE_GEN_LEN="256"
DEFAULT_GPU_LAYERS="999"
PORT="5001"

# Check for required configuration
if [ -z "$MODEL_DIR" ]; then
    echo "ERROR: MODEL_DIR not set. Please edit the script to set your models directory."
    exit 1
fi

if [ -z "$HORDE_KEY" ]; then
    echo "ERROR: HORDE_KEY not set. Please edit the script to set your Horde API key."
    exit 1
fi

if [ -z "$HORDE_WORKER_NAME" ]; then
    echo "ERROR: HORDE_WORKER_NAME not set. Please edit the script to set your worker name."
    exit 1
fi

if [ -z "$HORDE_DB" ] || [ ! -f "$HORDE_DB" ]; then
    echo "ERROR: HORDE_DB not set or file not found."
    echo "Please clone https://github.com/Haidra-Org/AI-Horde-text-model-reference/"
    echo "and set the path to db.json in the script."
    exit 1
fi

if [ -z "$KOBOLDCPP_PATH" ] || [ ! -f "$KOBOLDCPP_PATH" ]; then
    echo "ERROR: KOBOLDCPP_PATH not set or file not found."
    echo "Please set the path to koboldcpp.py in the script."
    exit 1
fi

# Get model files
model_files=("$MODEL_DIR"/*.gguf)

# Check if models exist
if [ ${#model_files[@]} -eq 0 ]; then
    echo "No .gguf files found in $MODEL_DIR."
    exit 1
fi

# Model selection
echo "Select a model file:"
select model_file in "${model_files[@]}"; do
    if [ -n "$model_file" ]; then
        echo "Selected model: $model_file"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

# Get Horde model name from metadata
horde_model=$(python find_hordename.py "$model_file" "$HORDE_DB")
echo "Horde model name: $horde_model"
if [ -z "$horde_model" ]; then
    echo "WARNING: Could not determine Horde model name. The model may not be recognized by the Horde."
fi

# Available context sizes
context_options=("256" "512" "1024" "2048" "3072" "4096" "6144" "8192" "12288" "16384" "24576" "32768" "49152" "65536" "131072")

# Local context size selection
echo "Select LOCAL context size:"
PS3="Context: "
select opt in "${context_options[@]}" ""; do
    case $REPLY in
        "")
            context="$DEFAULT_CONTEXT"
            echo "No context size selected. Using default: $context"
            break
            ;;
        *[0-9]*)
            if [[ $REPLY -ge 1 && $REPLY -le ${#context_options[@]} ]]; then
                context=${context_options[$REPLY-1]}
                echo "Selected context size: $context"
                break
            else
                echo "Invalid option. Please try again."
            fi
            ;;
        *)
            echo "Invalid input. Please enter a number."
            ;;
    esac
done

# Horde context size selection
echo "Select HORDE context size:"
PS3="Context: "
select opt in "${context_options[@]}" ""; do
    case $REPLY in
        "")
            hordemaxctx="$DEFAULT_HORDE_CTX"
            echo "No context size selected. Using default: $hordemaxctx"
            break
            ;;
        *[0-9]*)
            if [[ $REPLY -ge 1 && $REPLY -le ${#context_options[@]} ]]; then
                hordemaxctx=${context_options[$REPLY-1]}
                echo "Selected Horde context size: $hordemaxctx"
                break
            else
                echo "Invalid option. Please try again."
            fi
            ;;
        *)
            echo "Invalid input. Please enter a number."
            ;;
    esac
done

# Generation length
read -p "Horde gen length? [$DEFAULT_HORDE_GEN_LEN]: " hordegenlen_response 
hordegenlen=${hordegenlen_response:-$DEFAULT_HORDE_GEN_LEN}

# Advanced options
read -p "Do you want to change advanced parameters? (y/[n]): " change_params
if [[ "$change_params" == "y" ]]; then
    # Tensor split
    while true; do
        read -p "Enter tensor split [disabled]: " tensor_response
        if [[ "$tensor_response" == "" ]]; then
            tensor_split=""
            break
        elif [[ "$tensor_response" =~ ^[0-9]+(\.[0-9]+)?(\ [0-9]+(\.[0-9]+)?)*$ ]]; then
            tensor_split="--tensor_split $tensor_response"
            break
        else
            echo "Invalid response. Please enter valid numbers separated by spaces."
        fi
    done

    # GPU layers
    read -p "Enter GPU layers [$DEFAULT_GPU_LAYERS]: " layers_response
    layers=${layers_response:-$DEFAULT_GPU_LAYERS}

    # Row split
    read -p "Disable rowsplit? (y/[n]): " rowsplit_response
    if [[ "$rowsplit_response" == "y" ]]; then
        rowsplit=""
    else
        rowsplit="--rowsplit"
    fi

    # Flash attention
    read -p "Disable flash attention? (y/[n]): " flash_response
    if [[ "$flash_response" == "y" ]]; then
        flashattention=""
    else
        flashattention="--flashattention"
    fi

    # Quant KV
    read -p "Enable quant KV? (y/[n]): " kv_response
    if [[ "$kv_response" == "y" ]]; then
        quantkv="--quantkv"
    else
        quantkv=""
    fi

    # Preload
    read -p "Enable preload? (y/[n]): " preload_response
    if [[ "$preload_response" == "y" ]]; then
        preload="--preload"
    else
        preload=""
    fi
    
    # Port
    read -p "Server port? [$PORT]: " port_response
    PORT=${port_response:-$PORT}
else
    # Default advanced settings
    tensor_split=""
    layers="$DEFAULT_GPU_LAYERS"
    rowsplit="--rowsplit"
    flashattention="--flashattention"
    quantkv=""
    preload=""
fi

# Capture any additional flags passed to the script
additional_flags=("$@")

# Build the command
CMD="python $KOBOLDCPP_PATH --usecublas $rowsplit --port $PORT --contextsize $context \
    --gpulayers $layers --multiuser --model \"$model_file\" \
    --hordemodelname \"$horde_model\" --hordegenlen $hordegenlen \
    --hordemaxctx $hordemaxctx --hordekey \"$HORDE_KEY\" \
    --hordeworkername \"$HORDE_WORKER_NAME\" $tensor_split $flashattention \
    $quantkv $preload ${additional_flags[@]}"

# Function to start in tmux
start_in_tmux() {
    # Check if there's already a koboldcpp session
    if tmux has-session -t koboldcpp 2>/dev/null; then
        echo "A koboldcpp tmux session is already running."
        read -p "Do you want to kill it and start a new one? (y/n): " kill_session
        if [[ "$kill_session" == "y" ]]; then
            tmux kill-session -t koboldcpp
        else
            echo "Attaching to existing session..."
            tmux attach -t koboldcpp
            return
        fi
    fi
    
    # Create a new session
    tmux new-session -d -s koboldcpp "$1; echo ''; echo 'Process exited. Press enter to close window.'; read"
    echo "Started koboldcpp in tmux session. Attaching to session..."
    sleep 1
    tmux attach -t koboldcpp
}

# Show the command
echo
echo "Running command:"
echo "$CMD"
echo

# Start the script in tmux
start_in_tmux "$CMD"