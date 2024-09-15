#!/bin/bash

#script for installing gitpmoji. oneliner
# to run it as one liner you can use this command:
# curl -s https://raw.githubusercontent.com/Fl0p/gitpmoji/main/install.sh | bash

CURRENT_DIR=$(pwd)

#check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found, installing it"
    brew install jq
fi

echo "Current dir: $CURRENT_DIR"

TOP_LEVEL_GIT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

echo "Top level project dir: $TOP_LEVEL_GIT_DIR"
ls -la $TOP_LEVEL_GIT_DIR

echo "Enter dir name where gitkobemoji scripts will be installed. use '.' for current dir. just press enter for default 'gitkobemoji'"
read -p "GITKOBEMOJI_DIR=" GITKOBEMOJI_DIR

if [ -z "$GITKOBEMOJI_DIR" ]; then
    GITKOBEMOJI_DIR="gitkobemoji"
fi

GITKOBEMOJI_INSTALL_DIR="$TOP_LEVEL_GIT_DIR/$GITKOBEMOJI_DIR"
echo "gitkobemoji will be installed in $GITKOBEMOJI_INSTALL_DIR"

mkdir -p $GITKOBEMOJI_INSTALL_DIR
cd $GITKOBEMOJI_INSTALL_DIR
pwd

#download from github
curl -o prepare-commit-msg.sh https://raw.githubusercontent.com/Fl0p/gitpmoji/main/prepare-commit-msg.sh
curl -o gpt.sh https://raw.githubusercontent.com/Fl0p/gitpmoji/main/gpt.sh

#make executable
chmod +x prepare-commit-msg.sh
chmod +x gpt.sh

echo "Do you want to add '$GITKOBEMOJI_DIR' directory to gitignore?  (y/n)"
read GITKOBEMOJI_ADD_TO_GITIGNORE

if [ "$GITKOBEMOJI_ADD_TO_GITIGNORE" = "y" ]; then
    echo "" >> $TOP_LEVEL_GIT_DIR/.gitignore
    echo "# ignore gitkobemoji directory" >> $TOP_LEVEL_GIT_DIR/.gitignore
    echo "$GITKOBEMOJI_DIR" >> $TOP_LEVEL_GIT_DIR/.gitignore
fi

# Удалить запрос API ключа OpenAI
# Заменить на проверку наличия Ollama
if ! command -v ollama &> /dev/null
then
    echo "Ollama не найдена. Пожалуйста, установите Ollama: https://ollama.ai/"
    exit 1
fi

#check if .gitkobemoji.env exists
if [ -f .gitkobemoji.env ]; then
    echo "$GITKOBEMOJI_DIR/.gitkobemoji.env уже существует, пропускаем настройку переменных окружения"
    echo "--- начало .gitkobemoji.env ---"
    cat .gitkobemoji.env
    echo "--- конец .gitkobemoji.env ---"
else
    echo ".gitkobemoji.env не существует, создаем его"
    
    cat << EOF > .gitkobemoji.env
# Базовый URL для локального API Ollama
export GITKOBEMOJI_API_BASE_URL="http://localhost:11434/api"
export GITKOBEMOJI_API_MODEL="llama3.1"
EOF

    echo "Файл .gitkobemoji.env создан с базовым URL для Ollama API и моделью API"
fi

if [ "$GITKOBEMOJI_ADD_TO_GITIGNORE" != "y" ]; then
    echo -e "\033[0;31m Do you want to add environment file '$GITKOBEMOJI_DIR/.gitkobemoji.env' to .gitignore to keep your API key secret? (y/n)\033[0m"    
    read GITKOBEMOJI_ADD_ENV_TO_GITIGNORE
    if [ "$GITKOBEMOJI_ADD_ENV_TO_GITIGNORE" = "y" ]; then
        echo "" >> $TOP_LEVEL_GIT_DIR/.gitignore
        echo "# ignore environment file for gitkobemoji" >> $TOP_LEVEL_GIT_DIR/.gitignore
        echo "$GITKOBEMOJI_DIR/.gitkobemoji.env" >> $TOP_LEVEL_GIT_DIR/.gitignore
    fi
fi

cd $TOP_LEVEL_GIT_DIR

echo "Gitkobemoji files installed in: $GITKOBEMOJI_INSTALL_DIR"


HOOKS_DIR="$TOP_LEVEL_GIT_DIR/.git/hooks"
echo "git hooks dir: $HOOKS_DIR"

echo "Going to install git hook for prepare-commit-msg"

relative_path() {
    local common_part="$1" # for now
    local result="." # for now

    while [[ "${2#"$common_part"}" == "${2}" ]]; do
        # no match, means that candidate common part is not correct
        common_part="$(dirname "$common_part")"
        result="${result}/.." # move to parent dir in relative path
    done

    if [[ "$common_part" == "/" ]]; then
        # special case for root (no common path)
        result="$result/"
    fi

    # since we now have identified the common part,
    # compute the non-common part
    local forward_part="${2#"$common_part"}"
    # and now stick all parts together
    result="${result}${forward_part}"
    echo "$result"
}

echo "Looking for relative path between:"
# Get absolute path of gitpmoji install dir
TARGET="$(cd "$GITKOBEMOJI_INSTALL_DIR"; pwd)"
# Get absolute path of the hooks directory
SOURCE="$(cd "$HOOKS_DIR"; pwd)"

echo "TARGET: $TARGET"
echo "SOURCE: $SOURCE"

RELATIVE_PATH=$(relative_path "$SOURCE" "$TARGET")

echo "RELATIVE_PATH: $RELATIVE_PATH"

cd $HOOKS_DIR

echo "Creating symlink for prepare-commit-msg"
echo "ln -sf $RELATIVE_PATH/prepare-commit-msg.sh prepare-commit-msg"

ln -sf $RELATIVE_PATH/prepare-commit-msg.sh prepare-commit-msg

cd $TOP_LEVEL_GIT_DIR

echo "Git hooks successfully installed"
echo "You can now commit with gitkobemoji. 🚀"
echo "To uninstall just remove $HOOKS_DIR/prepare-commit-msg and $GITKOBEMOJI_INSTALL_DIR"

exit 0
